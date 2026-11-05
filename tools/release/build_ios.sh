#!/usr/bin/env bash
# Builds the signed iOS .ipa that goes to App Store Connect (TestFlight and the
# App Store). app/ios/README-mac.md section 6 is the click-by-click guide around
# this script; tools/release/build_android.ps1 is its Android twin.
#
#   tools/release/build_ios.sh            -> app/build/ios/ipa/*.ipa for App Store Connect
#   tools/release/build_ios.sh --ad-hoc   -> an ad-hoc .ipa for cable installs on registered iPhones
#
# Build number = number of commits on this branch, the same rule as Android, so
# one commit has one number on both stores. App Store Connect refuses a build
# number it has already seen for this version, so commit before you build.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
app="$root/app"

if [ ! -f "$root/.env" ]; then
  echo "$root/.env is missing. docs/11-owner-setup.md Part 1 creates it; copy it from Windows (README-mac.md section 2)." >&2
  exit 1
fi
if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter is not on PATH. README-mac.md section 1 installs 3.44.6." >&2
  exit 1
fi

method=app-store
if [ "${1:-}" = "--ad-hoc" ]; then method=ad-hoc; fi

cd "$app"
code="$(git rev-list --count HEAD)"
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "warning: uncommitted changes. The build carries number $code but will not match a commit." >&2
fi
name="$(sed -nE 's/^version:[[:space:]]*([0-9.]+).*/\1/p' pubspec.yaml)"
echo "Building Drivalry $name (build $code) as $method ..."

flutter build ipa --release --dart-define-from-file=../.env --build-name="$name" --build-number="$code" --export-method="$method"

ipa="$(ls -t build/ios/ipa/*.ipa | head -n 1)"
echo
echo "Done: $app/$ipa ($(du -h "$ipa" | cut -f1)), version $name ($code)"
if [ "$method" = app-store ]; then
  echo "Upload it: open Transporter, drag the .ipa in, Deliver. Then App Store Connect > TestFlight > iOS Builds. README-mac.md section 6."
else
  echo "Install it: Finder > the iPhone > drag the .ipa onto the device, or Xcode > Window > Devices and Simulators > +."
fi
