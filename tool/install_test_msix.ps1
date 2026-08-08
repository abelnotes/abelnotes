# Installs the locally-built MSIX for manual testing: trusts the self-signed
# cert and sideloads the package. Re-run after each `dart run msix:create`.
#
#   powershell -ExecutionPolicy Bypass -File tool\install_test_msix.ps1
#
# Elevates itself: writing to LocalMachine\Root and deploying a package both
# need admin. Not used for Store builds, which Microsoft signs.
#
# ASCII only on purpose - Windows PowerShell 5.1 reads .ps1 as ANSI, so a
# stray non-ASCII character breaks parsing on someone else's codepage.

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$cer  = Join-Path $repo 'certs\abelnotes_test.cer'
$msix = Join-Path $repo 'build\windows\x64\runner\Release\abelnotes.msix'

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
  ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
  Write-Host 'Servono privilegi di amministratore, chiedo elevazione...'
  Start-Process powershell -Verb RunAs -ArgumentList @(
    '-NoExit', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`""
  )
  return
}

if (-not (Test-Path $cer)) {
  throw "Certificato mancante: $cer"
}
if (-not (Test-Path $msix)) {
  throw "Pacchetto mancante: $msix - lancia prima: dart run msix:create"
}

$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $cer
Write-Host "Certificato : $($cert.Subject)  [$($cert.Thumbprint)]"

if (Get-ChildItem Cert:\LocalMachine\Root |
      Where-Object Thumbprint -eq $cert.Thumbprint) {
  Write-Host 'Root        : gia presente'
} else {
  Import-Certificate -FilePath $cer -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
  Write-Host 'Root        : importato'
}

# A same-version package already installed makes Add-AppxPackage fail; the
# flag replaces it instead, including downgrades during testing.
Add-AppxPackage -Path $msix -ForceUpdateFromAnyVersion
$pkg = Get-AppxPackage -Name '*AbelNotes*'
Write-Host "Installato  : $($pkg.PackageFullName)"
Write-Host ''
Write-Host 'Per rimuovere tutto:'
Write-Host "  Get-AppxPackage -Name '*AbelNotes*' | Remove-AppxPackage"
Write-Host "  Get-ChildItem Cert:\LocalMachine\Root | Where-Object Subject -eq '$($cert.Subject)' | Remove-Item"
