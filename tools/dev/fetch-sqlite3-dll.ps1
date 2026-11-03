# Downloads the official 64-bit Windows sqlite3.dll into <repo>/.tools/sqlite3/.
#
# Normally NOT needed: package:sqlite3 3.x fetches its own SQLite build through
# Dart hooks the first time `dart test` / `flutter test` runs, so the Dart and
# Flutter tests in this repo work on Windows with no setup. Keep this script for
# the cases where a plain sqlite3.dll on disk is handy: inspecting a .pack file
# with a SQLite shell or GUI, or a tool that cannot use hooks.
#
#   powershell -ExecutionPolicy Bypass -File tools/dev/fetch-sqlite3-dll.ps1
#
# .tools/ is gitignored.
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$dest = Join-Path $repoRoot '.tools\sqlite3'
New-Item -ItemType Directory -Force -Path $dest | Out-Null

Write-Host 'Resolving the current sqlite-dll-win-x64 archive from sqlite.org...'
$page = Invoke-WebRequest -Uri 'https://www.sqlite.org/download.html' -UseBasicParsing
$match = [regex]::Match($page.Content, '(\d{4}/sqlite-dll-win-x64-\d+\.zip)')
if (-not $match.Success) {
    throw 'Could not find a sqlite-dll-win-x64 archive on https://www.sqlite.org/download.html'
}
$relative = $match.Groups[1].Value
$url = "https://www.sqlite.org/$relative"
$zip = Join-Path $dest 'sqlite-dll-win-x64.zip'

Write-Host "Downloading $url"
Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
Expand-Archive -Path $zip -DestinationPath $dest -Force
Remove-Item $zip

$dll = Join-Path $dest 'sqlite3.dll'
if (-not (Test-Path $dll)) {
    throw "Archive did not contain sqlite3.dll (looked in $dest)"
}
$size = (Get-Item $dll).Length
Write-Host "sqlite3.dll ($size bytes) -> $dll"
