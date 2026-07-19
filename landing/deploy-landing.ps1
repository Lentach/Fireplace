# Deploy the landing page (https://fireplace.ignorelist.com/welcome/).
# Runs on the dev PC, mirrors deploy-web.ps1: build here, stage on the VM,
# guarded atomic swap into ~/fireplace/landing-build/ (nginx alias target).
# One-time server prerequisite: the /welcome nginx block — see README.md.
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$VM = 'ubuntu@51.68.138.13'
$stamp = Get-Date -Format yyyyMMddHHmmss
$staging = "~/fireplace/landing-staging-$stamp"

Write-Host '== build =='
npm ci
npm run build
if (-not (Test-Path 'dist/index.html')) { throw 'build produced no dist/index.html' }

Write-Host '== upload to staging =='
ssh $VM "mkdir -p $staging"
scp -r dist/* "${VM}:$staging/"

Write-Host '== guarded atomic swap =='
ssh $VM "test -f $staging/index.html && rm -rf ~/fireplace/landing-build.old && (test -d ~/fireplace/landing-build && mv ~/fireplace/landing-build ~/fireplace/landing-build.old || true) && mv $staging ~/fireplace/landing-build && echo PUBLISHED_OK"

Write-Host '== verify =='
$resp = Invoke-WebRequest -Uri 'https://fireplace.ignorelist.com/welcome/' -UseBasicParsing
if ($resp.StatusCode -eq 200 -and $resp.Content -match 'Fireplace') {
  Write-Host 'VERIFIED: /welcome/ serves the landing page.'
} else {
  throw "verification failed: HTTP $($resp.StatusCode)"
}
