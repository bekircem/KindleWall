#!/usr/bin/env python3
"""Rebuild Localizable.xcstrings from what the compiler actually found.

    swift build once, then:  python3 scripts/sync-catalog.py [--check]

Xcode's IDE merges the .stringsdata the compiler emits into the String Catalog. From the
command line it does not: `xcstringstool sync` marks stale entries and removes them, but it
adds nothing — verified against an empty catalog, which stayed empty. So this script does the
adding.

It reads every .stringsdata under DerivedData, keeps the translations already in the catalog,
adds keys that are new, drops keys no longer in source, and reports what has no Turkish value
yet. `--check` makes it report without writing, which is what CI and the test suite want.

Requires a build with SWIFT_EMIT_LOC_STRINGS=YES (set in project.yml).
"""

import argparse
import glob
import json
import os
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG = ROOT / "KindleWall/Resources/Localizable.xcstrings"
TRANSLATION_LANGUAGE = "tr"

DERIVED = (
    "~/Library/Developer/Xcode/DerivedData/KindleWall-*/Build/Intermediates.noindex"
    "/KindleWall.build/Debug/KindleWall.build/Objects-normal/*/*.stringsdata"
)


def stringsdata_files() -> list[str]:
    found = [p for p in glob.glob(os.path.expanduser(DERIVED)) if "AppShortcuts" not in p]
    if not found:
        sys.exit(
            "no .stringsdata found — build first:\n"
            "  xcodebuild build-for-testing -project KindleWall.xcodeproj -scheme KindleWall "
            "-destination 'platform=macOS,arch=arm64'"
        )
    return found


def keys_from_source() -> dict[str, str]:
    """Every localizable key the compiler saw, mapped to the file it came from."""
    keys: dict[str, str] = {}
    for path in stringsdata_files():
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
        source = pathlib.Path(data.get("source", path)).name
        for entries in data.get("tables", {}).values():
            for entry in entries:
                key = entry.get("key")
                if key is not None:
                    keys.setdefault(key, source)
    return keys


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true",
                        help="report without writing; exit 1 if anything is untranslated")
    args = parser.parse_args()

    source_keys = keys_from_source()
    existing = json.loads(CATALOG.read_text(encoding="utf-8")) if CATALOG.exists() else {}
    previous = existing.get("strings", {})

    merged: dict[str, dict] = {}
    for key in sorted(source_keys):
        merged[key] = previous.get(key, {})
        # A key that came back from source is not stale, whatever it was before.
        merged[key].pop("extractionState", None)

    dropped = sorted(set(previous) - set(source_keys))
    added = sorted(set(source_keys) - set(previous))

    untranslated = []
    for key, value in merged.items():
        # Placeholders and punctuation are marked not-for-translation; they are not missing.
        if value.get("shouldTranslate") is False:
            continue
        localizations = value.get("localizations", {})
        entry = localizations.get(TRANSLATION_LANGUAGE)
        has_unit = bool((entry or {}).get("stringUnit", {}).get("value"))
        has_variations = bool((entry or {}).get("variations"))
        if not (has_unit or has_variations):
            untranslated.append(key)

    print(f"{len(source_keys)} keys in source · {len(added)} new · {len(dropped)} dropped")
    print(f"{len(untranslated)} without a {TRANSLATION_LANGUAGE} value")

    if args.check:
        for key in untranslated[:20]:
            print(f"  untranslated: {key!r}  ({source_keys[key]})")
        if len(untranslated) > 20:
            print(f"  … and {len(untranslated) - 20} more")
        return 1 if untranslated else 0

    CATALOG.write_text(
        json.dumps({"sourceLanguage": "en", "strings": merged, "version": "1.0"},
                   ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"wrote {CATALOG.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
