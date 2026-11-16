"""Build the installable Spatial Plates ZIP with the required addon folder name.

Run from any directory with: python3 scripts/package_release.py
"""
from __future__ import annotations

import argparse
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ADDON_DIR = ROOT / "SpatialPlates"
ADDON_FILES = (
    "SpatialPlates.toc",
    "Config.lua",
    "Presets.lua",
    "Appearance.lua",
    "Range.lua",
    "Core.lua",
    "Minimap.lua",
    "Media/Icon.tga",
)
PACKAGE_FILES = ADDON_FILES + ("LICENSE",)


def get_version() -> str:
    toc = (ADDON_DIR / "SpatialPlates.toc").read_text(encoding="utf-8")
    config = (ADDON_DIR / "Config.lua").read_text(encoding="utf-8")
    toc_match = re.search(r"^## Version: ([0-9]+\.[0-9]+\.[0-9]+)$", toc, re.MULTILINE)
    config_match = re.search(r'^SP\._VERSION = "([0-9]+\.[0-9]+\.[0-9]+)"$', config, re.MULTILINE)
    if not toc_match or not config_match or toc_match.group(1) != config_match.group(1):
        raise ValueError("TOC and Config.lua must declare the same semantic version")
    for filename in ADDON_FILES:
        if not (ADDON_DIR / filename).is_file():
            raise FileNotFoundError(ADDON_DIR / filename)
    if not (ROOT / "LICENSE").is_file():
        raise FileNotFoundError(ROOT / "LICENSE")
    return toc_match.group(1)


def build(output: Path) -> Path:
    version = get_version()
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for filename in ADDON_FILES:
            archive.write(ADDON_DIR / filename, f"SpatialPlates/{filename}")
        archive.write(ROOT / "LICENSE", "SpatialPlates/LICENSE")
    return output


def main() -> None:
    version = get_version()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=ROOT / "build" / f"SpatialPlates-{version}.zip",
        help="output ZIP path (default: build/SpatialPlates-<version>.zip)",
    )
    args = parser.parse_args()
    result = build(args.output)
    print(f"Built installable addon archive: {result}")


if __name__ == "__main__":
    main()
