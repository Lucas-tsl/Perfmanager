<#
    Construit PerfManager.exe puis l'installateur PerfManager-Setup.exe dans le dossier dist\.
    Utilisé par GitHub Actions ; marche aussi sur ton PC (le compilateur C# est fourni avec Windows).
        powershell -ExecutionPolicy Bypass -File windows\build.ps1 -Version 1.0.5
#>
param([string]$Version = '1.0.0')
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path -Parent $here
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null

$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { throw "Compilateur C# introuvable : $csc" }
& $csc /nologo /target:winexe /optimize+ /codepage:65001 `
    "/out:$dist\PerfManager.exe" "/win32icon:$here\perfmanager.ico" "/win32manifest:$here\app.manifest" `
    /r:System.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll /r:System.Web.Extensions.dll `
    "$here\PerfManagerApp.cs"
if ($LASTEXITCODE -ne 0) { throw 'Compilation de PerfManager.exe échouée' }
Write-Host "PerfManager.exe compilé"

$iscc = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'
if (-not (Test-Path $iscc)) {
    Write-Host 'Installation d''Inno Setup…'
    choco install innosetup -y --no-progress | Out-Null
}
& $iscc /Qp "/DAppVersion=$Version" "$here\installer.iss"
if ($LASTEXITCODE -ne 0) { throw 'Création de l''installateur échouée' }
Write-Host "Installateur prêt : $dist\PerfManager-Setup.exe"
