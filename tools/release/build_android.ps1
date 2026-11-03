# Builds the signed Android App Bundle that goes to Google Play (internal
# testing and every track above it). docs/11-owner-setup.md Part 15 is the
# click-by-click guide around this script.
#
#   .\tools\release\build_android.ps1          -> app\build\app\outputs\bundle\release\app-release.aab
#   .\tools\release\build_android.ps1 -Apk     -> a release APK for adb install (same signing)
#
# Version code = number of commits on this branch. It only ever grows, and
# Play refuses a code it has already seen, so commit before you build.
param([switch]$Apk)

# Flutter and git print ordinary warnings on stderr; under "Stop" Windows
# PowerShell 5.1 would turn the first of those into a fatal error, so this
# script checks exit codes itself instead.
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$app = Join-Path $root "app"

if (-not (Test-Path (Join-Path $root ".env"))) {
    throw "C:\Drivalry\.env is missing. docs/11-owner-setup.md Part 1 creates it."
}
if (-not (Test-Path (Join-Path $app "android\key.properties"))) {
    throw "app\android\key.properties is missing. docs/11-owner-setup.md Part 15a explains the upload key."
}

$flutter = "flutter"
$local = Join-Path $env:USERPROFILE "dev\flutter\bin\flutter.bat"
if (Test-Path $local) { $flutter = $local }

Push-Location $app
try {
    $code = [int](git rev-list --count HEAD)
    $dirty = (git status --porcelain | Measure-Object -Line).Lines
    if ($dirty -gt 0) {
        Write-Warning "There are uncommitted changes. The bundle will carry version code $code but not match a commit."
    }
    $match = Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9.]+)'
    $name = $match.Matches[0].Groups[1].Value
    $target = if ($Apk) { "apk" } else { "appbundle" }
    Write-Host "Building Drivalry $name (version code $code) as $target ..."

    & $flutter build $target --release --dart-define-from-file=../.env --build-number=$code --build-name=$name
    if ($LASTEXITCODE -ne 0) { throw "flutter build $target failed (exit $LASTEXITCODE)" }

    $out = if ($Apk) { "build\app\outputs\flutter-apk\app-release.apk" } else { "build\app\outputs\bundle\release\app-release.aab" }
    $file = Get-Item $out
    $mb = [math]::Round($file.Length / 1MB)
    Write-Host ""
    Write-Host "Done: $($file.FullName) ($mb MB), version $name ($code)"
    if ($Apk) {
        Write-Host "Install on the connected phone:  adb install -r `"$($file.FullName)`""
    } else {
        Write-Host "Upload it: Play Console > Testing > Internal testing > Create new release. docs/11 Part 15c."
    }
} finally {
    Pop-Location
}
