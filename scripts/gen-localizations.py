#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Generate .lproj/Localizable.strings from String Catalogs (.xcstrings).

The .xcstrings files are the single source of truth (editable in Xcode).
SwiftPM builds without full Xcode cannot compile .xcstrings, so the
generated .strings files are checked in as the bundled resources.
CI runs this with --check to fail when they drift out of sync.

Usage: gen-localizations.py [--check]
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOGS = [
    (ROOT / "App/Localizable.xcstrings", ROOT / "App/Resources"),
    (ROOT / "Sources/Core/Localizable.xcstrings", ROOT / "Sources/Core/Resources"),
]
LANGUAGES = ["en", "zh-Hans"]


def escape(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def render(catalog: dict, lang: str) -> str:
    source_lang = catalog.get("sourceLanguage", "en")
    lines = []
    untranslated = []
    for key in sorted(catalog.get("strings", {})):
        entry = catalog["strings"][key]
        locs = entry.get("localizations", {})
        unit = locs.get(lang, {}).get("stringUnit")
        if unit is None and lang == source_lang:
            unit = {"value": key}
        if unit is None:
            untranslated.append(key)
            unit = locs.get(source_lang, {}).get("stringUnit", {"value": key})
        lines.append(f'"{escape(key)}" = "{escape(unit["value"])}";')
    body = "\n".join(lines) + "\n"
    return body, untranslated


def main() -> int:
    check = "--check" in sys.argv
    drift = False
    for catalog_path, res_dir in CATALOGS:
        catalog = json.loads(catalog_path.read_text())
        for lang in LANGUAGES:
            body, untranslated = render(catalog, lang)
            out = res_dir / f"{lang}.lproj" / "Localizable.strings"
            if untranslated and lang != catalog.get("sourceLanguage", "en"):
                # Report-only per SPEC §8.5(6): English fallback is allowed to ship.
                rel = catalog_path.relative_to(ROOT)
                print(f"note: {rel} [{lang}] {len(untranslated)} untranslated key(s): {', '.join(untranslated[:5])}")
            if check:
                if not out.exists() or out.read_text() != body:
                    print(f"OUT OF SYNC: {out.relative_to(ROOT)} — run scripts/gen-localizations.py")
                    drift = True
            else:
                out.parent.mkdir(parents=True, exist_ok=True)
                out.write_text(body)
                print(f"wrote {out.relative_to(ROOT)} ({body.count(chr(10))} keys)")
    return 1 if drift else 0


if __name__ == "__main__":
    sys.exit(main())
