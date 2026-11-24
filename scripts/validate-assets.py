#!/usr/bin/env python3
"""Validate the APLite local asset library.

Runs on CI (and locally) so a filtered or edited library can never silently drift from the
native AssetRegistry. Checks:

  * registry.json parses
  * every family's original LICENSE file exists
  * every registry glyph exists in every declared library path
  * the Swift enum's raw values exactly match the JSON concepts
  * the library stays outside APLite/ so XcodeGen never bundles it

Usage: python3 scripts/validate-assets.py
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def fail(message):
    print(f"asset validation FAILED: {message}", file=sys.stderr)
    raise SystemExit(1)


def main():
    manifest = json.loads((ROOT / "Assets/registry.json").read_text(encoding="utf-8"))
    concepts = [c["concept"] for c in manifest["concepts"]]
    if not concepts:
        fail("registry has no concepts")

    for family in manifest["families"]:
        licence = ROOT / family["licenseFile"]
        if not licence.is_file():
            fail(f"missing licence: {family['licenseFile']}")
        for key in ("outlinePath", "iconPath"):
            if key not in family:
                continue
            directory = ROOT / family[key]
            for concept in concepts:
                if not (directory / f"{concept}.svg").is_file():
                    fail(f"{family['name']}: missing {concept}.svg in {family[key]}")

    swift = (ROOT / "APLite/System/AssetRegistry.swift").read_text(encoding="utf-8")
    if "enum Icon: String, CaseIterable" not in swift:
        fail("AssetRegistry.swift has no Icon enum")
    block = swift.split("enum Icon: String, CaseIterable {", 1)[1].split("/// The SF Symbol", 1)[0]
    cases = []
    for line in re.findall(r"case ([^\n]+)", block):
        for token in line.split(","):
            token = token.strip()
            if not token:
                continue
            raw = token.split("=", 1)[1].strip() if "=" in token else token
            cases.append(raw.strip('"'))
    if set(cases) != set(concepts):
        fail(f"registry/Swift mismatch: only in Swift={set(cases)-set(concepts)}, "
             f"only in JSON={set(concepts)-set(cases)}")

    library = ROOT / "Assets/Icons"
    if (ROOT / "APLite/Assets/Icons").exists():
        fail("asset library must stay outside APLite/ so it is not bundled")
    if not library.is_dir():
        fail("Assets/Icons is missing")

    # Xcode derives an asset's type from its folder extension. A folder named "ZaloIcon" that
    # contains an imageset Contents.json is silently ignored, so UIImage(named:) returns nil.
    catalog = ROOT / "APLite/Assets.xcassets"
    kinds = (".appiconset", ".imageset", ".colorset")
    names = set()
    for child in catalog.iterdir():
        if not child.is_dir():
            continue
        if not child.name.endswith(kinds):
            fail(f"asset folder '{child.name}' has no recognised extension; Xcode ignores it")
        names.add(child.name.split(".", 1)[0])
    for swift_file in (ROOT / "APLite").rglob("*.swift"):
        for name in re.findall(r'UIImage\(named:\s*"([^"]+)"\)', swift_file.read_text(encoding="utf-8")):
            if name not in names:
                fail(f"{swift_file.relative_to(ROOT)} references missing asset '{name}'")

    print(f"asset validation OK: {len(concepts)} concepts, "
          f"{len(manifest['families'])} licensed families, library outside app bundle, "
          f"{len(names)} compiled assets")


if __name__ == "__main__":
    main()
