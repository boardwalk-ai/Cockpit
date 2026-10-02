# Build standalone Doc Oct (Flutter web) + stamp a unique cleanup service
# worker + publish to https://octopilotai.app/doc-oct/
#
# From repo (Windows):
#   cd H:\Cockpit\apps\cockpit
#   .\deploy\Deploy-DocOct.ps1              # build + stamp + upload
#   .\deploy\Deploy-DocOct.ps1 -SkipUpload  # build + stamp only
#   .\deploy\Deploy-DocOct.ps1 -SkipBuild   # re-stamp + upload existing build/web
#
# Requires the same SSH secret as Deploy-Web.ps1 (COCKPIT_SSH_PASSWORD or
# repo-root .deploy-ssh-password).

param(
    [string]$Flutter = "C:\Users\USER\sdk\flutter\bin\flutter.bat",
    [string]$RemoteDir = "/var/www/octopilotai-app",
    [string]$BuildId = (Get-Date -Format "yyyyMMddHHmmss"),
    [switch]$SkipBuild,
    [switch]$SkipUpload
)

$ErrorActionPreference = "Stop"

$AppRoot = Split-Path $PSScriptRoot -Parent
$WebDir = Join-Path $AppRoot "build\web"
$Defines = Join-Path $AppRoot "dococt-defines.json"

Push-Location $AppRoot
try {
    if (-not $SkipBuild) {
        if (-not (Test-Path $Flutter)) {
            throw "Flutter not found at $Flutter - pass -Flutter path\to\flutter.bat"
        }
        if (-not (Test-Path $Defines)) {
            throw "Missing dart-defines file: $Defines"
        }
        Write-Host ">> flutter build web --release (doc-oct, build-number=$BuildId)"
        & $Flutter build web --release --no-wasm-dry-run `
            -t lib/main_dococt.dart `
            --base-href /doc-oct/ `
            --dart-define-from-file=$Defines `
            --build-number=$BuildId
        if ($LASTEXITCODE -ne 0) { throw "flutter build web failed ($LASTEXITCODE)" }
    }
    elseif (-not (Test-Path $WebDir)) {
        throw "No build/web and -SkipBuild set. Run a full build first."
    }

    Write-Host ">> Stamping cleanup SW + cache-bust ($BuildId)"
    & (Join-Path $PSScriptRoot "Stamp-Build.ps1") -BuildId $BuildId -WebDir $WebDir -AppName "doc-oct"

    if (-not $SkipUpload) {
        $PublishArgs = @(
            (Join-Path $PSScriptRoot "publish_web.py"),
            "--web-dir", $WebDir,
            "--remote-dir", $RemoteDir,
            "--skip-nginx"
        )
        Write-Host ">> Publishing via publish_web.py -> $RemoteDir"
        & py -3 @PublishArgs
        if ($LASTEXITCODE -ne 0) { throw "publish_web.py failed ($LASTEXITCODE)" }
    }
}
finally {
    Pop-Location
}

Write-Host ""
Write-Host ">> Done. Open https://octopilotai.app/doc-oct/ (one reload after first deploy)."
Write-Host "   Each deploy ships a new flutter_service_worker.js (build_id=$BuildId) that"
Write-Host "   clears Cache Storage, unregisters, and reloads open tabs."
