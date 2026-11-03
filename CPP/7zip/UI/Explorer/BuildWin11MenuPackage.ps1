# created by Gemini 3.8 Flash
[CmdletBinding()]
param(
    [string]$OutputDir = $PSScriptRoot,
    [string]$InstallDir = $PSScriptRoot,
    [switch]$Register
)

$ErrorActionPreference = 'Stop'
$manifestPath = Join-Path $PSScriptRoot 'AppxManifest.xml'
if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Manifest not found: $manifestPath" }

$payloadDir = Join-Path $OutputDir 'package_payload'
$assetsDir = Join-Path $payloadDir 'Assets'
if (-not (Test-Path -LiteralPath $assetsDir)) { New-Item -ItemType Directory -Path $assetsDir -Force | Out-Null }

Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $payloadDir 'AppxManifest.xml') -Force

$iconPath = Join-Path $PSScriptRoot '..\FileManager\FM.ico'
$logoPng = Join-Path $assetsDir 'Logo.png'
if (-not (Test-Path -LiteralPath $logoPng)) {
    Add-Type -AssemblyName System.Drawing
    if (Test-Path -LiteralPath $iconPath) {
        $icon = [System.Drawing.Icon]::ExtractAssociatedIcon((Resolve-Path $iconPath))
        $bmp = $icon.ToBitmap()
        $bmp.Save($logoPng, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        $icon.Dispose()
    } else {
        $bmp = New-Object System.Drawing.Bitmap 150, 150
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.Clear([System.Drawing.Color]::FromArgb(0, 120, 215))
        $g.Dispose()
        $bmp.Save($logoPng, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
    }
}

$msixPath = Join-Path $OutputDir '7-Zip.ModernContextMenu.msix'
$cmdObj = Get-Command 'makeappx.exe' -ErrorAction SilentlyContinue
$makeAppx = if ($cmdObj) { $cmdObj.Source } else { $null }
if (-not $makeAppx) {
    $sdkRoots = @("${env:ProgramFiles(x86)}\Windows Kits\10\bin", "${env:ProgramFiles}\Windows Kits\10\bin")
    foreach ($sdkRoot in $sdkRoots) {
        if (Test-Path $sdkRoot) {
            $foundItem = Get-ChildItem -Path $sdkRoot -Filter 'makeappx.exe' -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match 'x64' } | Select-Object -First 1
            if ($foundItem) {
                $makeAppx = $foundItem.FullName
                break
            }
        }
    }
}

if ($makeAppx) {
    & $makeAppx pack /o /d $payloadDir /nv /p $msixPath
    $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject 'CN=7-Zip' -CertStoreLocation 'Cert:\CurrentUser\My' -KeyLength 2048 -HashAlgorithm SHA256
    $signToolItem = Get-ChildItem -Path (Split-Path (Split-Path $makeAppx)) -Filter 'signtool.exe' -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match 'x64' } | Select-Object -First 1
    $signTool = if ($signToolItem) { $signToolItem.FullName } else { $null }
    if ($signTool) {
        & $signTool sign /fd SHA256 /s My /sha1 $cert.Thumbprint $msixPath
    } else {
        Set-AuthenticodeSignature -FilePath $msixPath -Certificate $cert -HashAlgorithm SHA256 | Out-Null
    }
    Export-Certificate -Cert $cert -FilePath (Join-Path $OutputDir '7-Zip.cer') | Out-Null
    # Also trust locally during build so the build machine can test immediately
    try {
        Import-Certificate -FilePath (Join-Path $OutputDir '7-Zip.cer') -CertStoreLocation Cert:\LocalMachine\TrustedPeople | Out-Null
    } catch {}
}

if ($Register) {
    if (Test-Path -LiteralPath $msixPath) {
        Add-AppxPackage -Path $msixPath -ExternalLocation $InstallDir
    } else {
        Add-AppxPackage -Register (Join-Path $payloadDir 'AppxManifest.xml') -ExternalLocation $InstallDir
    }
}
