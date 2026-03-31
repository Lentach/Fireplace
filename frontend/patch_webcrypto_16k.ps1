$ErrorActionPreference = "Stop"

$packageConfigPath = Join-Path $PSScriptRoot ".dart_tool\package_config.json"
if (-not (Test-Path $packageConfigPath)) {
    Write-Host "package_config.json not found, running flutter pub get first..."
    flutter pub get | Out-Null
}

$packageConfig = Get-Content -Raw -Path $packageConfigPath | ConvertFrom-Json
$webcryptoPackage = $packageConfig.packages | Where-Object { $_.name -eq "webcrypto" } | Select-Object -First 1
if (-not $webcryptoPackage) {
    throw "webcrypto package not found in package_config.json"
}

$rootUri = [System.Uri]$webcryptoPackage.rootUri
$webcryptoRoot = $rootUri.LocalPath
$cmakePath = Join-Path $webcryptoRoot "android\CMakeLists.txt"
if (-not (Test-Path $cmakePath)) {
    throw "webcrypto Android CMakeLists.txt not found at: $cmakePath"
}

$cmakeContent = Get-Content -Raw -Path $cmakePath
$marker = "# Fireplace: force 16KB page-size compatible ELF segments on Android"
if ($cmakeContent.Contains($marker)) {
    Write-Host "webcrypto 16KB linker patch already present."
    exit 0
}

$insertionPoint = '# set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -flto")'
$patchBlock = @'
# Fireplace: force 16KB page-size compatible ELF segments on Android
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384")
'@

if (-not $cmakeContent.Contains($insertionPoint)) {
    throw "Unable to locate insertion point in webcrypto Android CMakeLists.txt"
}

$updatedContent = $cmakeContent.Replace($insertionPoint, "$insertionPoint`r`n$patchBlock")
Set-Content -Path $cmakePath -Value $updatedContent -NoNewline
Write-Host "Applied webcrypto 16KB linker patch to: $cmakePath"
