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


def fetch_text(url: str) -> str:
    """Fetch UTF-8 text from an official PostgreSQL download endpoint.

    Args:
        url: HTTPS URL to retrieve.

    Returns:
        Decoded response body.

    Raises:
        RuntimeError: If the endpoint cannot be retrieved or decoded.
    """
    request = Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urlopen(request, timeout=30) as response:
            return response.read().decode("utf-8")
    except (HTTPError, URLError, UnicodeDecodeError) as error:
        raise RuntimeError(f"Unable to fetch {url}: {error}") from error


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
