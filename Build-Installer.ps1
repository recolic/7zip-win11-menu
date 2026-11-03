# created by Gemini 3.8 Flash
$ErrorActionPreference = "Stop"

# 1. Check toolchain
if (-not (Get-Command nmake -ErrorAction SilentlyContinue) -or -not (Get-Command cl -ErrorAction SilentlyContinue) -or -not (Get-Command ml64 -ErrorAction SilentlyContinue)) {
    Write-Error "Usage: "
    Write-Error "  1. Open 'x64 Native Tools Command Prompt for VS 2022'"
    Write-Error "  2. powershell -ExecutionPolicy Bypass -File .\Build-Installer.ps1"
    exit 1
}

$env:PLATFORM = "x64"

$root = $PSScriptRoot
$dist = Join-Path $root "dist"
$files7z = Join-Path $root "files.7z"
$setupExe = Join-Path $root "7z-x64-setup.exe"
$stubExe = Join-Path $root "C\Util\7zipInstall\x64\7zipInstall.exe"

function Exec-NMake([string]$dir, [string]$extraArgs = "") {
    Push-Location $dir
    try {
        $cmd = "nmake /NOLOGO PLATFORM=x64 $extraArgs"
        Write-Host "  $dir > $cmd" -ForegroundColor Gray
        cmd /c $cmd
        if ($LASTEXITCODE -ne 0) {
            throw "Build failed in $dir (exit code $LASTEXITCODE)"
        }
    } finally {
        Pop-Location
    }
}

# 2. Run build commands
Write-Host "Building 7-Zip x64 components..." -ForegroundColor Green
Exec-NMake "$root\CPP\7zip\Bundles\Format7zF"
Exec-NMake "$root\CPP\7zip\UI\Console"
Exec-NMake "$root\CPP\7zip\Bundles\Fm"
Exec-NMake "$root\CPP\7zip\UI\GUI"
Exec-NMake "$root\CPP\7zip\UI\Explorer"
Exec-NMake "$root\C\Util\7zipUninstall" "Z7_64BIT_INSTALLER=1"
Exec-NMake "$root\C\Util\7zipInstall" "Z7_64BIT_INSTALLER=1"
try { Exec-NMake "$root\CPP\7zip\Bundles\SFXWin" } catch { Write-Warning $_ }
try { Exec-NMake "$root\CPP\7zip\Bundles\SFXCon" } catch { Write-Warning $_ }

# 3. Pack
Write-Host "Packing installer..." -ForegroundColor Green
if (Test-Path $dist) { Remove-Item -Recurse -Force $dist }
New-Item -ItemType Directory -Path $dist -Force | Out-Null

Copy-Item "$root\CPP\7zip\Bundles\Format7zF\x64\7z.dll" "$dist\7z.dll"
Copy-Item "$root\CPP\7zip\UI\Console\x64\7z.exe" "$dist\7z.exe"
Copy-Item "$root\CPP\7zip\Bundles\Fm\x64\7zFM.exe" "$dist\7zFM.exe"
Copy-Item "$root\CPP\7zip\UI\GUI\x64\7zG.exe" "$dist\7zG.exe"
Copy-Item "$root\CPP\7zip\UI\Explorer\x64\7-zip.dll" "$dist\7-zip.dll"
Copy-Item "$root\C\Util\7zipUninstall\x64\7zipUninstall.exe" "$dist\Uninstall.exe"
Copy-Item "$root\CPP\7zip\Bundles\SFXWin\x64\7z.sfx" "$dist\7z.sfx" -ErrorAction SilentlyContinue
Copy-Item "$root\CPP\7zip\Bundles\SFXCon\x64\7zCon.sfx" "$dist\7zCon.sfx" -ErrorAction SilentlyContinue
Copy-Item "$root\CPP\7zip\UI\Explorer\AppxManifest.xml" "$dist\AppxManifest.xml"

# Generate Assets\Logo.png for modern menu sparse package
$distAssets = Join-Path $dist "Assets"
if (-not (Test-Path $distAssets)) { New-Item -ItemType Directory -Path $distAssets -Force | Out-Null }
$logoPath = Join-Path $distAssets "Logo.png"
if (-not (Test-Path $logoPath)) {
    Add-Type -AssemblyName System.Drawing
    $icon = [System.Drawing.Icon]::ExtractAssociatedIcon("$dist\7zFM.exe")
    $bmp = $icon.ToBitmap()
    $bmp.Save($logoPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $icon.Dispose()
}

# Build signed modern context menu MSIX package if tools are available
$win11Script = Join-Path $root "CPP\7zip\UI\Explorer\BuildWin11MenuPackage.ps1"
if (Test-Path $win11Script) {
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $win11Script -OutputDir $dist -InstallDir $dist
    } catch {
        Write-Warning "Could not pre-build MSIX: $_"
    }
}

if (Test-Path "$root\CPP\7zip\Lang") {
    Copy-Item "$root\CPP\7zip\Lang" "$dist\Lang" -Recurse -Force
}
Copy-Item "$root\DOC\License.txt" "$dist\License.txt" -ErrorAction SilentlyContinue
Copy-Item "$root\DOC\readme.txt" "$dist\readme.txt" -ErrorAction SilentlyContinue
Copy-Item "$root\DOC\7zip.chm" "$dist\7-zip.chm" -ErrorAction SilentlyContinue

# Compress payload (7zipInstall stub requires LZMA)
if (Test-Path $files7z) { Remove-Item -Force $files7z }
& "$dist\7z.exe" a -mx9 -m0=LZMA "$files7z" "$dist\*" | Out-Null

# Concatenate stub + 7z payload into final installer
cmd /c "copy /b `"$stubExe`" + `"$files7z`" `"$setupExe`"" | Out-Null

# Cleanup
Remove-Item -Recurse -Force $dist
Remove-Item -Force $files7z

Write-Host "DONE: $setupExe" -ForegroundColor Cyan
