$ErrorActionPreference = "Stop"

$xBuildRoot = "X:\fireplace-build"
$xFrontendBuild = Join-Path $xBuildRoot "frontend-build"
$projectBuildPath = Join-Path $PSScriptRoot "build"

$env:GRADLE_USER_HOME = "X:\gradle-home"
$env:TEMP = "X:\temp"
$env:TMP = "X:\temp"

foreach ($path in @($xBuildRoot, $xFrontendBuild, $env:GRADLE_USER_HOME, $env:TEMP)) {
    if (-not (Test-Path $path)) {
        New-Item -Path $path -ItemType Directory | Out-Null
    }
}

if (Test-Path $projectBuildPath) {
    $item = Get-Item $projectBuildPath -Force
    if (-not $item.Attributes.ToString().Contains("ReparsePoint")) {
        Remove-Item -Recurse -Force $projectBuildPath
    }
}
if (-not (Test-Path $projectBuildPath)) {
    cmd /c "mklink /J `"$projectBuildPath`" `"$xFrontendBuild`""
}

& (Join-Path $PSScriptRoot "patch_webcrypto_16k.ps1")
. (Join-Path $PSScriptRoot "scripts\version_dart_defines.ps1")
$versionDefines = Get-VersionDartDefineArgs
flutter run --dart-define=BASE_URL=http://10.0.2.2:3000 @versionDefines
