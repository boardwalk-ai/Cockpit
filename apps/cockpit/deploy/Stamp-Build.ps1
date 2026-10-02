# Post-process apps/cockpit/build/web after `flutter build web`.
# - Writes a unique cleanup service worker (forces browser SW update)
# - Cache-busts flutter_bootstrap.js in index.html
# - Stamps version.json with build_id
#
# Usage:
#   .\deploy\Stamp-Build.ps1 -BuildId 20260807231500
#   .\deploy\Stamp-Build.ps1   # auto timestamp

param(
    [string]$BuildId = (Get-Date -Format "yyyyMMddHHmmss"),
    [string]$WebDir = "",
    [string]$AppName = "cockpit"
)

$ErrorActionPreference = "Stop"

$AppRoot = Split-Path $PSScriptRoot -Parent
if (-not $WebDir) {
    $WebDir = Join-Path $AppRoot "build\web"
}

if (-not (Test-Path $WebDir)) {
    throw "Build output not found: $WebDir - run flutter build web first."
}

$Template = Join-Path $PSScriptRoot "flutter_service_worker.js.template"
if (-not (Test-Path $Template)) {
    throw "Missing SW template: $Template"
}

# 1) Fresh cleanup SW with unique build_id (byte-different every deploy).
$Sw = (Get-Content -Raw -Encoding utf8 $Template).Replace('__BUILD_ID__', $BuildId)
$SwPath = Join-Path $WebDir "flutter_service_worker.js"
[System.IO.File]::WriteAllText($SwPath, $Sw)
Write-Host ">> SW stamped build_id=$BuildId -> $SwPath"

# 2) Cache-bust bootstrap script tag in index.html.
$IndexPath = Join-Path $WebDir "index.html"
$Index = [System.IO.File]::ReadAllText($IndexPath)
$Pattern = 'src="flutter_bootstrap\.js(\?v=[^"]*)?"'
$Replacement = "src=`"flutter_bootstrap.js?v=$BuildId`""
$NewIndex = [regex]::Replace($Index, $Pattern, $Replacement)
if ($NewIndex -notmatch [regex]::Escape("flutter_bootstrap.js?v=$BuildId")) {
    throw "Failed to inject cache-bust query into index.html"
}
[System.IO.File]::WriteAllText($IndexPath, $NewIndex)
Write-Host ">> index.html bootstrap ?v=$BuildId"

# 3) Stamp version.json (handy for debugging which build is live).
$VersionPath = Join-Path $WebDir "version.json"
$VersionObj = [ordered]@{
    app_name     = $AppName
    version      = "1.0.0"
    build_number = $BuildId
    build_id     = $BuildId
    package_name = $AppName
    stamped_at   = (Get-Date).ToUniversalTime().ToString("o")
}
$VersionJson = ($VersionObj | ConvertTo-Json -Compress)
[System.IO.File]::WriteAllText($VersionPath, $VersionJson)
Write-Host ">> version.json build_id=$BuildId"

# 4) Marker file for ops.
[System.IO.File]::WriteAllText((Join-Path $WebDir "BUILD_ID"), $BuildId)

Write-Host ">> Stamp complete."
