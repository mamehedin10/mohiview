#!/usr/bin/env python3
"""Apply MohiView branding to a RustDesk source tree.

Usage:  python apply_branding.py <rustdesk-root> <mohiview-root>

Every edit says how many times its pattern must match. A mismatch stops the
build, so an upstream change can never ship a half-branded client.
Then overlay/ (icons and logos) is copied over the tree.
Keep this file ASCII.
"""
import re
import shutil
import sys
from pathlib import Path

APP = "MohiView"
APP_LOWER = "mohiview"
COMPANY = "Brandivo Labs"
SERVER = "remote.brandivolabs.com"
KEY = "6SnjPxxIqKEigkVh5oyLOdybN985sLKctewuicFufxg="
WEBSITE = "https://github.com/mamehedin10/mohiview"
PORTAL = "https://remote.brandivolabs.com"
CREDIT = "Proudly Improved by Mohibullah Mehedi"
COPYRIGHT = "Copyright " + chr(0xA9) + " 2026 " + COMPANY + ". Based on RustDesk (AGPL-3.0)."

CONFIG_RS = "libs/hbb_common/src/config.rs"
RUNNER_RC = "flutter/windows/runner/Runner.rc"
SETTINGS_DART = "flutter/lib/desktop/pages/desktop_setting_page.dart"
COMMON_DART = "flutter/lib/common.dart"
HOME_DART = "flutter/lib/desktop/pages/desktop_home_page.dart"

# (file, kind, pattern, replacement, expected matches); kind is "lit" or "re"
EDITS = [
    # Built-in server, key and app name: no --config step needed on any PC.
    (CONFIG_RS, "lit",
     'PROD_RENDEZVOUS_SERVER: RwLock<String> = RwLock::new("".to_owned());',
     'PROD_RENDEZVOUS_SERVER: RwLock<String> = RwLock::new("%s".to_owned());' % SERVER, 1),
    (CONFIG_RS, "lit",
     'APP_NAME: RwLock<String> = RwLock::new("RustDesk".to_owned());',
     'APP_NAME: RwLock<String> = RwLock::new("%s".to_owned());' % APP, 1),
    (CONFIG_RS, "lit",
     'pub const RENDEZVOUS_SERVERS: &[&str] = &["rs-ny.rustdesk.com"];',
     'pub const RENDEZVOUS_SERVERS: &[&str] = &["%s"];' % SERVER, 1),
    (CONFIG_RS, "re",
     r'pub const RS_PUB_KEY: &str = "[^"]*";',
     'pub const RS_PUB_KEY: &str = "%s";' % KEY, 1),

    # File properties of the main exe.
    ("Cargo.toml", "lit", 'description = "RustDesk Remote Desktop"',
     'description = "%s Remote Desktop"' % APP, 1),
    ("Cargo.toml", "re", r'LegalCopyright = "[^"]*"', 'LegalCopyright = "%s"' % COPYRIGHT, 1),
    ("Cargo.toml", "lit", 'ProductName = "RustDesk"', 'ProductName = "%s"' % APP, 1),
    ("Cargo.toml", "lit", 'FileDescription = "RustDesk Remote Desktop"',
     'FileDescription = "%s Remote Desktop"' % APP, 1),
    ("Cargo.toml", "lit", 'OriginalFilename = "rustdesk.exe"',
     'OriginalFilename = "%s.exe"' % APP, 1),

    # File properties of the self-extracting installer.
    ("libs/portable/Cargo.toml", "lit", 'description = "RustDesk Remote Desktop"',
     'description = "%s Remote Desktop"' % APP, 1),
    ("libs/portable/Cargo.toml", "re", r'LegalCopyright = "[^"]*"',
     'LegalCopyright = "%s"' % COPYRIGHT, 1),
    ("libs/portable/Cargo.toml", "lit", 'ProductName = "RustDesk"', 'ProductName = "%s"' % APP, 1),
    ("libs/portable/Cargo.toml", "lit", 'OriginalFilename = "rustdesk.exe"',
     'OriginalFilename = "%s.exe"' % APP, 1),
    ("libs/portable/Cargo.toml", "lit", 'FileDescription = "RustDesk Remote Desktop"',
     'FileDescription = "%s Remote Desktop"' % APP, 1),
    ("libs/portable/src/main.rs", "lit", 'const APP_PREFIX: &str = "rustdesk";',
     'const APP_PREFIX: &str = "%s";' % APP_LOWER, 1),

    # Flutter runner resources (what Explorer shows for MohiView.exe).
    (RUNNER_RC, "re", r'VALUE "CompanyName", "[^"]*"', 'VALUE "CompanyName", "%s"' % COMPANY, 1),
    (RUNNER_RC, "re", r'VALUE "FileDescription", "[^"]*"',
     'VALUE "FileDescription", "%s Remote Desktop"' % APP, 1),
    (RUNNER_RC, "re", r'VALUE "InternalName", "[^"]*"', 'VALUE "InternalName", "%s"' % APP_LOWER, 1),
    (RUNNER_RC, "re", r'VALUE "LegalCopyright", "[^"]*"', 'VALUE "LegalCopyright", "%s"' % COPYRIGHT, 1),
    (RUNNER_RC, "re", r'VALUE "OriginalFilename", "[^"]*"',
     'VALUE "OriginalFilename", "%s.exe"' % APP, 1),
    (RUNNER_RC, "re", r'VALUE "ProductName", "[^"]*"', 'VALUE "ProductName", "%s"' % APP, 1),

    # About page and install page: our links and company, keeping the RustDesk credit.
    (SETTINGS_DART, "lit", "launchUrlString('https://rustdesk.com/privacy.html');",
     "launchUrlString('%s');" % WEBSITE, 1),
    (SETTINGS_DART, "lit", "launchUrlString('https://rustdesk.com');",
     "launchUrlString('%s');" % WEBSITE, 1),
    (SETTINGS_DART, "lit", "} Purslane Tech Pte. Ltd.",
     "} %s. Based on RustDesk (AGPL-3.0)." % COMPANY, 1),
    ("flutter/lib/desktop/pages/install_page.dart", "lit", "'https://rustdesk.com/privacy.html'",
     "'%s'" % WEBSITE, 2),

    # Home screen credit line (custom clients show it in place of "Powered by RustDesk";
    # the RustDesk credit stays on the About page). Larger and clearer than upstream,
    # links to our portal, and sits under the logo instead of above it.
    (COMMON_DART, "lit", 'translate("powered_by_me"),', "'%s'," % CREDIT, 1),
    (COMMON_DART, "lit", "launchUrl(Uri.parse('https://rustdesk.com'));",
     "launchUrl(Uri.parse('%s'));" % PORTAL, 1),
    (COMMON_DART, "lit", "opacity: 0.5,", "opacity: 0.85,", 1),
    (COMMON_DART, "lit", "?.copyWith(fontSize: 9, decoration: TextDecoration.underline),",
     "?.copyWith(fontSize: 11, fontWeight: FontWeight.w600),", 1),
    (HOME_DART, "re",
     r"(      if \(bind\.isCustomClient\(\)\)\r?\n"
     r"        Align\(\r?\n"
     r"          alignment: Alignment\.center,\r?\n"
     r"          child: loadPowered\(context\),\r?\n"
     r"        \),\r?\n)"
     r"(      Align\(\r?\n"
     r"        alignment: Alignment\.center,\r?\n"
     r"        child: loadLogo\(\),\r?\n"
     r"      \),\r?\n)",
     lambda m: m.group(2) + m.group(1), 1),
]


def apply_edits(root):
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
            repl = replacement if callable(replacement) else (lambda _m, r=replacement: r)
            new_text, found = re.subn(pattern, repl, text)
        if found != expected:
            errors.append("%s: expected %d match(es) of %r, found %d" % (rel, expected, pattern, found))
            continue
        texts[rel] = new_text
        print("ok    %s  <-  %s" % (rel, pattern[:72]))
    if errors:
        print("\nBRANDING FAILED - upstream changed, update patches/apply_branding.py:")
        for e in errors:
            print("  " + e)
        sys.exit(1)
    for rel, text in texts.items():
        with open(root / rel, "w", encoding="utf-8", newline="") as fh:
            fh.write(text)


def copy_overlay(root, mohiview):
    overlay = mohiview / "overlay"
    count = 0
    for src in sorted(overlay.rglob("*")):
        if src.is_file():
            dst = root / src.relative_to(overlay)
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, dst)
            count += 1
    if count == 0:
        print("BRANDING FAILED - overlay/ is empty; run tools/make-icons.ps1 first")
        sys.exit(1)
    print("copied %d overlay files (icons, logos)" % count)


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    root = Path(sys.argv[1]).resolve()
    mohiview = Path(sys.argv[2]).resolve()
    if not (root / CONFIG_RS).is_file():
        print("not a RustDesk tree (submodules checked out?): %s" % root)
        sys.exit(2)
    apply_edits(root)
    copy_overlay(root, mohiview)
    print("MohiView branding applied: app=%s server=%s" % (APP, SERVER))


if __name__ == "__main__":
    main()
