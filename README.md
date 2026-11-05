# MohiView

MohiView is a remote desktop app for Windows. It is [RustDesk](https://github.com/rustdesk/rustdesk)
with a new name and logo, pointed at our own server (`remote.brandivolabs.com`), so it works as soon
as it is installed, with no settings to change.

MohiView is not affiliated with or endorsed by RustDesk or Purslane Ltd. "RustDesk" is their trademark.

## What is changed

RustDesk's behaviour is not changed. `patches/apply_branding.py` changes only:

- the app name, `MohiView` (window titles, install folder, service name, every text in the app)
- the built-in ID/relay server, `remote.brandivolabs.com`, and its public key
- the Windows file properties (product name, company, copyright)
- the links on the About page
- the home-screen credit line under the logo: "Proudly Improved by Mohibullah Mehedi" (the RustDesk
  credit and license stay on the About page)
- the icons and logos in `overlay/`, made from `branding/*.svg` by `tools/make-icons.ps1`

Every edit says how many times it must match, so the build stops if upstream code moves instead of
shipping a half-branded app.

## Building

The GitHub Actions workflow `.github/workflows/build-windows.yml` checks out RustDesk at
`RUSTDESK_VERSION`, applies the branding and builds the Windows x64 installer
`MohiView-<version>-x64.exe`. Run it from the Actions tab and tick *publish* to make a release.

To move to a newer RustDesk: change `RUSTDESK_VERSION` (and the tool versions, copied from upstream's
`flutter-build.yml`), run the workflow, and fix `apply_branding.py` if it reports a mismatch.

## Source code and license

MohiView is licensed under the **GNU AGPL-3.0**, the same as RustDesk (see `LICENSE`). Its complete
source code is RustDesk's source at the tag named in the workflow plus the files in this repository.
