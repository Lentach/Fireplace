# Shared GIT_COMMIT / BUILD_TIME dart-defines for local flutter run (matches deploy.sh).
function Get-VersionDartDefineArgs {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
    $gitCommit = "dev"
    try {
        Push-Location $repoRoot
        $hash = git rev-parse --short HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $hash) {
            $gitCommit = $hash.Trim()
        }
    } finally {
        Pop-Location
    }
    $buildTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    return @(
        "--dart-define=GIT_COMMIT=$gitCommit",
        "--dart-define=BUILD_TIME=$buildTime"
    )
}
