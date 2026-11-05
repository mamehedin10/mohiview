#!/usr/bin/env python3
"""macOS-only MohiView branding. Run AFTER patches/apply_branding.py.

Usage:  python3 apply_branding_macos.py <rustdesk-root> <mohiview-root>

- App bundle name and bundle id (MohiView.app, com.brandivolabs.mohiview).
- build.py copies the `service` helper into the renamed bundle.
- flutter/assets/icon.png is removed: macOS draws the menu-bar icon as a
  template (shape only) and would turn the coloured square into a blob;
  without it the tray falls back to res/mac-tray-dark-x2.png (an "M" shape).
- mac/overlay/ (mac-icon.png, tray templates) is copied over the tree.
ORG stays "com.carriez": several plist labels hardcode it, so changing it
would break the service install.
Keep this file ASCII.
"""
import re
import shutil
import sys
from pathlib import Path

APP = "MohiView"
BUNDLE_ID = "com.brandivolabs.mohiview"
COPYRIGHT = "Copyright " + chr(0xA9) + " 2026 Brandivo Labs. Based on RustDesk (AGPL-3.0)."

XCCONFIG = "flutter/macos/Runner/Configs/AppInfo.xcconfig"
PBXPROJ = "flutter/macos/Runner.xcodeproj/project.pbxproj"

# (file, kind, pattern, replacement, expected matches)
EDITS = [
    (XCCONFIG, "re", r"PRODUCT_NAME = [^\r\n]*", "PRODUCT_NAME = " + APP, 1),
    (XCCONFIG, "re", r"PRODUCT_BUNDLE_IDENTIFIER = [^\r\n]*", "PRODUCT_BUNDLE_IDENTIFIER = " + BUNDLE_ID, 1),
    (XCCONFIG, "re", r"PRODUCT_COPYRIGHT = [^\r\n]*", "PRODUCT_COPYRIGHT = " + COPYRIGHT, 1),
    (PBXPROJ, "lit", "PRODUCT_BUNDLE_IDENTIFIER = com.carriez.rustdesk;",
     "PRODUCT_BUNDLE_IDENTIFIER = %s;" % BUNDLE_ID, 3),
    ("build.py", "lit", "./build/macos/Build/Products/Release/RustDesk.app/Contents/MacOS/",
     "./build/macos/Build/Products/Release/%s.app/Contents/MacOS/" % APP, 1),
]


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    root = Path(sys.argv[1]).resolve()
    mohiview = Path(sys.argv[2]).resolve()

    texts = {}
    errors = []
    for rel, kind, pattern, replacement, expected in EDITS:
        if rel not in texts:
            with open(root / rel, encoding="utf-8", newline="") as fh:
                texts[rel] = fh.read()
        text = texts[rel]
        if kind == "lit":
            found = text.count(pattern)
            new_text = text.replace(pattern, replacement)
        else:
            new_text, found = re.subn(pattern, lambda _m: replacement, text)
        if found != expected:
            errors.append("%s: expected %d match(es) of %r, found %d" % (rel, expected, pattern, found))
            continue
        texts[rel] = new_text
        print("ok    %s  <-  %s" % (rel, pattern[:72]))
    if errors:
        print("\nMAC BRANDING FAILED - upstream changed, update mac/apply_branding_macos.py:")
        for e in errors:
            print("  " + e)
        sys.exit(1)
    for rel, text in texts.items():
        with open(root / rel, "w", encoding="utf-8", newline="") as fh:
            fh.write(text)

    colour_icon = root / "flutter/assets/icon.png"
    if colour_icon.exists():
        colour_icon.unlink()
        print("removed flutter/assets/icon.png (menu bar uses the template icon)")

    overlay = mohiview / "mac/overlay"
    count = 0
    for src in sorted(overlay.rglob("*")):
        if src.is_file():
            dst = root / src.relative_to(overlay)
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, dst)
            count += 1
    if count == 0:
        print("MAC BRANDING FAILED - mac/overlay is empty; run tools/make-icons.ps1 -Target mac")
        sys.exit(1)
    print("copied %d mac overlay files" % count)
    print("MohiView macOS branding applied: %s.app (%s)" % (APP, BUNDLE_ID))


if __name__ == "__main__":
    main()
