#!/usr/bin/env python3
"""Update stable PostgreSQL source releases and checksum pins in images.json."""

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

SOURCE_INDEX_URL = "https://ftp.postgresql.org/pub/source/"
USER_AGENT = "docker-postgresql-images-updater/1.0"
MANIFEST_ACCEPT = (
    "application/vnd.oci.image.index.v1+json,"
    "application/vnd.docker.distribution.manifest.list.v2+json,"
    "application/vnd.oci.image.manifest.v1+json,"
    "application/vnd.docker.distribution.manifest.v2+json"
)


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments.

    Returns:
        Parsed command-line arguments.
    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=Path("images.json"))
    parser.add_argument(
        "--check",
        action="store_true",
        help="Exit nonzero when an update is available without writing the file.",
    )
    return parser.parse_args()


def fetch_text(url: str, headers: dict[str, str] | None = None) -> str:
    """Fetch UTF-8 text from an official PostgreSQL download endpoint.

    Args:
        url: HTTPS URL to retrieve.
        headers: Optional HTTP headers to include in the request.

    Returns:
        Decoded response body.

    Raises:
        RuntimeError: If the endpoint cannot be retrieved or decoded.
    """
    request_headers = {"User-Agent": USER_AGENT, **(headers or {})}
    request = Request(url, headers=request_headers)
    try:
        with urlopen(request, timeout=30) as response:
            return response.read().decode("utf-8")
    except (HTTPError, URLError, UnicodeDecodeError) as error:
        raise RuntimeError(f"Unable to fetch {url}: {error}") from error


def fetch_response(
    url: str, headers: dict[str, str] | None = None
) -> tuple[str, dict[str, str]]:
    """Fetch a response body and normalized headers.

    Args:
        url: HTTPS URL to retrieve.
        headers: Optional HTTP headers to include in the request.

    Returns:
        The decoded response body and lowercase response headers.

    Raises:
        RuntimeError: If the endpoint cannot be retrieved or decoded.
    """
    request_headers = {"User-Agent": USER_AGENT, **(headers or {})}
    request = Request(url, headers=request_headers)
    try:
        with urlopen(request, timeout=30) as response:
            return (
                response.read().decode("utf-8"),
                {key.lower(): value for key, value in response.headers.items()},
            )
    except (HTTPError, URLError, UnicodeDecodeError) as error:
        raise RuntimeError(f"Unable to fetch {url}: {error}") from error


def parse_image_reference(reference: str) -> tuple[str, str, str]:
    """Split a digest-pinned image reference into registry, repository, and tag.

    Args:
        reference: An OCI reference containing a tag and SHA-256 digest.

    Returns:
        Registry host, repository path, and tag.

    Raises:
        RuntimeError: If the reference is not safely digest-pinned.
    """
    name, separator, digest = reference.partition("@sha256:")
    if not separator or not re.fullmatch(r"[0-9a-f]{64}", digest):
        raise RuntimeError(f"Base image is not SHA-256 pinned: {reference}")
    registry, _, repository_and_tag = name.partition("/")
    if not repository_and_tag or ":" not in repository_and_tag:
        raise RuntimeError(
            f"Base image is missing a registry, repository, or tag: {reference}"
        )
    repository, tag = repository_and_tag.rsplit(":", 1)
    if registry == "docker.io":
        registry = "registry-1.docker.io"
        if "/" not in repository:
            repository = f"library/{repository}"
    return registry, repository, tag


def bearer_token(challenge: str) -> str:
    """Exchange an OCI bearer-auth challenge for a pull token.

    Args:
        challenge: A ``WWW-Authenticate`` header from an OCI registry.

    Returns:
        Bearer token suitable for the challenged manifest request.

    Raises:
        RuntimeError: If the challenge cannot be parsed or lacks a token.
    """
    match = re.fullmatch(
        r'Bearer\s+realm="([^"]+)"(?:,service="([^"]+)")?(?:,scope="([^"]+)")?',
        challenge,
    )
    if not match:
        raise RuntimeError(f"Unsupported OCI authentication challenge: {challenge}")
    realm, service, scope = match.groups()
    query = []
    if service:
        query.append(f"service={service}")
    if scope:
        query.append(f"scope={scope}")
    payload = json.loads(fetch_text(f"{realm}?{'&'.join(query)}"))
    token = payload.get("token") or payload.get("access_token")
    if not token:
        raise RuntimeError("OCI authentication response did not contain a bearer token")
    return token


def current_base_digest(reference: str) -> str:
    """Resolve an OCI tag to the registry's current manifest SHA-256 digest.

    Args:
        reference: Existing digest-pinned OCI reference in ``images.json``.

    Returns:
        Replacement digest-pinned reference for the same registry, tag, and repository.

    Raises:
        RuntimeError: If the registry does not return a valid manifest digest.
    """
    registry, repository, tag = parse_image_reference(reference)
    url = f"https://{registry}/v2/{repository}/manifests/{tag}"
    headers = {"Accept": MANIFEST_ACCEPT}
    try:
        _, response_headers = fetch_response(url, headers)
    except RuntimeError as error:
        if not isinstance(error.__cause__, HTTPError) or error.__cause__.code != 401:
            raise
        challenge = error.__cause__.headers.get("WWW-Authenticate", "")
        _, response_headers = fetch_response(
            url, {**headers, "Authorization": f"Bearer {bearer_token(challenge)}"}
        )
    digest = response_headers.get("docker-content-digest", "")
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
        raise RuntimeError(
            f"Registry did not return a SHA-256 manifest digest for {reference}"
        )
    original_name = reference.partition("@sha256:")[0]
    return f"{original_name}@{digest}"


def available_versions(index: str) -> dict[int, str]:
    """Return the newest minor release for every PostgreSQL major in an index.

    Args:
        index: HTML directory index from ftp.postgresql.org.

    Returns:
        A mapping from PostgreSQL major version to its newest release string.
    """
    versions: dict[int, tuple[int, str]] = {}
    for major_text, minor_text in re.findall(r'href="v(\d+)\.(\d+)/"', index):
        major = int(major_text)
        minor = int(minor_text)
        if major not in versions or minor > versions[major][0]:
            versions[major] = (minor, f"{major}.{minor}")
    return {major: version for major, (_, version) in versions.items()}


def release_sha256(version: str) -> str:
    """Retrieve and validate a PostgreSQL release archive SHA-256 checksum.

    Args:
        version: PostgreSQL release version, such as ``18.6``.

    Returns:
        The validated lowercase SHA-256 digest.

    Raises:
        RuntimeError: If the official checksum file lacks the expected entry.
    """
    filename = f"postgresql-{version}.tar.bz2"
    checksum_url = f"{SOURCE_INDEX_URL}v{version}/{filename}.sha256"
    checksum_file = fetch_text(checksum_url)
    match = re.search(
        rf"^([0-9a-fA-F]{{64}})\s+\*?{re.escape(filename)}$",
        checksum_file,
        re.MULTILINE,
    )
    if not match:
        raise RuntimeError(f"No SHA-256 entry for {filename} in {checksum_url}")
    digest = match.group(1).lower()
    if len(bytes.fromhex(digest)) != hashlib.sha256().digest_size:
        raise RuntimeError(f"Invalid SHA-256 entry for {filename}")
    return digest


def update_releases(config: dict[str, Any], versions: dict[int, str]) -> list[str]:
    """Update configured stable releases to the newest available minor versions.

    Args:
        config: Parsed images configuration.
        versions: Newest upstream version by PostgreSQL major.

    Returns:
        Human-readable descriptions of modified release records.

    Raises:
        RuntimeError: If a configured stable major is absent upstream.
    """
    changes: list[str] = []
    for release in config["postgresql"]:
        if release["channel"] != "stable":
            continue
        major = release["major"]
        if major not in versions:
            raise RuntimeError(
                f"PostgreSQL {major} is not present in the upstream source index"
            )
        version = versions[major]
        if version == release["version"]:
            continue
        old_version = release["version"]
        release["version"] = version
        release["sha256"] = release_sha256(version)
        changes.append(f"PostgreSQL {major}: {old_version} -> {version}")
    return changes


def update_base_images(config: dict[str, Any]) -> list[str]:
    """Update every configured base-image digest to its current tagged manifest.

    Args:
        config: Parsed images configuration.

    Returns:
        Human-readable descriptions of modified distribution records.
    """
    changes: list[str] = []
    for distribution_key, distribution in config["distributions"].items():
        old_reference = distribution["base"]
        new_reference = current_base_digest(old_reference)
        if old_reference == new_reference:
            continue
        distribution["base"] = new_reference
        changes.append(f"{distribution_key}: updated base-image digest")
    return changes


def main() -> int:
    """Run the PostgreSQL release updater.

    Returns:
        Process exit status.

    Raises:
        RuntimeError: If the configuration cannot be processed safely.
    """
    args = parse_args()
    config = json.loads(args.config.read_text(encoding="utf-8"))
    changes = update_releases(config, available_versions(fetch_text(SOURCE_INDEX_URL)))
    changes.extend(update_base_images(config))
    if not changes:
        print("images.json already contains the latest stable PostgreSQL releases")
        return 0

    print("\n".join(changes))
    if args.check:
        return 1
    args.config.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except RuntimeError as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(2)
