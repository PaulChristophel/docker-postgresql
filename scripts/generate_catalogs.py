#!/usr/bin/env python3
"""Generate digest-pinned CloudNativePG image catalogs from build results."""

from __future__ import annotations

import argparse
import datetime
import json
import re
from pathlib import Path
from typing import Any

DIGEST_RE = re.compile(r"^sha256:[0-9a-f]{64}$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=Path("images.json"))
    parser.add_argument("--results", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path("image-catalogs"))
    parser.add_argument(
        "--date",
        default=datetime.datetime.now(datetime.UTC).strftime("%Y%m%d"),
        help="Catalog label date in YYYYMMDD form (default: today in UTC)",
    )
    return parser.parse_args()


def load_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as stream:
        return json.load(stream)


def load_results(results_dir: Path) -> dict[tuple[int, str], dict[str, Any]]:
    results: dict[tuple[int, str], dict[str, Any]] = {}
    for path in sorted(results_dir.glob("*.json")):
        result = load_json(path)
        key = (int(result["major"]), result["variant"])
        if key in results:
            raise ValueError(f"duplicate build result for PostgreSQL {key[0]} {key[1]}")
        if not DIGEST_RE.fullmatch(result["digest"]):
            raise ValueError(f"invalid digest in {path}: {result['digest']!r}")
        results[key] = result
    return results


def render_catalog(
    *,
    image: str,
    variant: dict[str, Any],
    channel: str,
    versions: list[dict[str, Any]],
    results: dict[tuple[int, str], dict[str, Any]],
    date: str,
) -> str:
    variant_tag = variant["tag"]
    suffix = "" if channel == "stable" else f"-{channel}"
    catalog_name = f"postgresql-{variant_tag}{suffix}"
    lines = [
        "apiVersion: postgresql.cnpg.io/v1",
        "kind: ClusterImageCatalog",
        "metadata:",
        f"  name: {catalog_name}",
        "  labels:",
        "    images.cnpg.io/family: postgresql",
        "    images.cnpg.io/type: standard",
        f"    images.cnpg.io/os: {variant['os']}",
        f'    images.cnpg.io/date: "{date}"',
        "    images.cnpg.io/publisher: docker.io",
    ]
    if variant["untrusted"]:
        lines.append("    images.cnpg.io/languages: untrusted")
    if channel != "stable":
        lines.append(f"    images.cnpg.io/channel: {channel}")
    lines.extend(["spec:", "  images:"])

    for version in sorted(versions, key=lambda item: item["major"]):
        major = int(version["major"])
        key = (major, variant_tag)
        if key not in results:
            raise ValueError(
                f"missing build result for PostgreSQL {major} {variant_tag}"
            )
        result = results[key]
        if result["image"] != image:
            raise ValueError(
                f"unexpected image for PostgreSQL {major} {variant_tag}: "
                f"{result['image']!r}"
            )
        lines.extend(
            [
                f"    - major: {major}",
                f"      image: {image}@{result['digest']}",
            ]
        )

    return "\n".join(lines) + "\n"


def main() -> None:
    args = parse_args()
    if not re.fullmatch(r"[0-9]{8}", args.date):
        raise ValueError("--date must use YYYYMMDD format")

    config = load_json(args.config)
    results = load_results(args.results)
    args.output.mkdir(parents=True, exist_ok=True)

    expected_keys: set[tuple[int, str]] = set()
    for version in config["postgresql"]:
        for variant in config["variants"]:
            expected_keys.add((int(version["major"]), variant["tag"]))
    unexpected_keys = set(results) - expected_keys
    if unexpected_keys:
        raise ValueError(f"unexpected build results: {sorted(unexpected_keys)}")

    channels = sorted({version["channel"] for version in config["postgresql"]})
    for variant in config["variants"]:
        for channel in channels:
            versions = [
                version
                for version in config["postgresql"]
                if version["channel"] == channel
            ]
            if not versions:
                continue
            suffix = "" if channel == "stable" else f"-{channel}"
            output_path = args.output / f"catalog-{variant['tag']}{suffix}.yaml"
            output_path.write_text(
                render_catalog(
                    image=config["image"],
                    variant=variant,
                    channel=channel,
                    versions=versions,
                    results=results,
                    date=args.date,
                ),
                encoding="utf-8",
            )
            print(output_path)


if __name__ == "__main__":
    main()
