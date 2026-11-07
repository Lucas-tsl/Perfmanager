<#
    PerfUpdate - mise à jour automatique de PerfManager depuis GitHub
    ------------------------------------------------------------------
    PerfUpdate.bat         : enregistre ta clé GitHub (une seule fois) puis installe la dernière version.
    PerfUpdate.bat -Setup  : change la clé GitHub.

    La clé (fine-grained, droit « Contents : lecture » sur le dépôt) est chiffrée avec Windows (DPAPI) :
    elle n'est lisible que par ta session Windows, sur ce PC. Elle ne sert qu'à l'en-tête des requêtes
    de mise à jour vers GitHub.

    Ce fichier est aussi chargé par PerfManager.ps1 et PerfRemote.ps1 (fonctions Test-Update / Install-Update).
#>
param([switch]$Setup)

$UpdRoot        = $PSScriptRoot
$UpdCfgPath     = Join-Path $UpdRoot 'update.json'
$UpdVerPath     = Join-Path $UpdRoot 'version.json'
$UpdApi         = 'https://api.github.com'
$UpdDefaultRepo = 'Lucas-tsl/Perfmanager'
# Fichiers personnels jamais écrasés par une mise à jour (s'ils existent déjà)
$UpdKeep        = @('profiles.json', 'remote.json', 'update.json', 'version.json', 'state.json', 'perfmanager.log')

function Write-UpdLog([string]$Msg, [string]$Level = 'OK') {
    try { Add-Content -Path (Join-Path $UpdRoot 'perfmanager.log') -Value ("{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}" -f (Get-Date), $Level, $Msg) -Encoding UTF8 } catch {}
}

function Get-UpdConfig {
    if (-not (Test-Path -LiteralPath $UpdCfgPath)) { return $null }
    try {
        $c   = Get-Content -LiteralPath $UpdCfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $sec = ConvertTo-SecureString -String ([string]$c.token)
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        try { $tok = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
        return [pscustomobject]@{
            repo   = $(if ($c.repo) { [string]$c.repo } else { $UpdDefaultRepo })
            branch = $(if ($c.branch) { [string]$c.branch } else { 'main' })
            auto   = ($c.auto -ne $false)
            token  = $tok
        }
    } catch { return $null }
}

function Save-UpdConfig([string]$Token, [string]$Repo = $UpdDefaultRepo, [string]$Branch = 'main') {
    $enc = ConvertFrom-SecureString -SecureString (ConvertTo-SecureString -String $Token -AsPlainText -Force)
    [ordered]@{ repo = $Repo; branch = $Branch; auto = $true; token = $enc } | ConvertTo-Json | Set-Content -LiteralPath $UpdCfgPath -Encoding UTF8
}

function Get-LocalVersion {
    if (-not (Test-Path -LiteralPath $UpdVerPath)) { return $null }
    try { return (Get-Content -LiteralPath $UpdVerPath -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Get-UpdHeaders($Cfg) {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
    return @{
        Authorization          = "Bearer $($Cfg.token)"
        Accept                 = 'application/vnd.github+json'
        'User-Agent'           = 'PerfManager-Updater'
        'X-GitHub-Api-Version' = '2022-11-28'
    }
}

function Get-UpdError($Err) {
    $code = $null
    try { $code = [int]$Err.Exception.Response.StatusCode } catch {}
    switch ($code) {
        401 { return 'Clé GitHub refusée ou expirée : relance PerfUpdate.bat -Setup' }
        403 { return "Accès refusé : la clé doit avoir le droit « Contents : lecture » sur le dépôt" }
        404 { return "Dépôt introuvable : ajoute le dépôt Perfmanager à ta clé GitHub" }
        default { return "GitHub injoignable : $($Err.Exception.Message)" }
    }
}

# Compare le dernier commit de la branche à la version installée
function Test-Update {
    $cfg = Get-UpdConfig
    if (-not $cfg) {
        return [pscustomobject]@{ ok = $false; configured = $false; available = $false; error = 'Clé GitHub non configurée : lance PerfUpdate.bat' }
    }
    try {
        $c     = Invoke-RestMethod -Uri "$UpdApi/repos/$($cfg.repo)/commits/$($cfg.branch)" -Headers (Get-UpdHeaders $cfg) -TimeoutSec 15
        $sha   = [string]$c.sha
        $local = Get-LocalVersion
        return [pscustomobject]@{
            ok         = $true
            configured = $true
            available  = (-not $local -or [string]$local.sha -ne $sha)
            sha        = $sha
            short      = $sha.Substring(0, [Math]::Min(7, $sha.Length))
            message    = ([string]$c.commit.message -split "`n")[0].Trim()
            date       = [string]$c.commit.committer.date
            current    = $(if ($local) { [string]$local.short } else { $null })
        }
    } catch {
        return [pscustomobject]@{ ok = $false; configured = $true; available = $false; error = (Get-UpdError $_) }
    }
}

# Télécharge la version $Sha et remplace les fichiers de l'appli (profils et réglages conservés)
function Install-Update([string]$Sha, [string]$Message) {
    $cfg = Get-UpdConfig
    if (-not $cfg) { throw 'Clé GitHub non configurée : lance PerfUpdate.bat' }
    if (-not $Sha) {
        $t = Test-Update
        if (-not $t.ok) { throw $t.error }
        $Sha = $t.sha; $Message = $t.message
    }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('perfmanager-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        $zip = Join-Path $tmp 'update.zip'
        try {
            Invoke-WebRequest -Uri "$UpdApi/repos/$($cfg.repo)/zipball/$Sha" -Headers (Get-UpdHeaders $cfg) -OutFile $zip -UseBasicParsing -TimeoutSec 180
        } catch { throw (Get-UpdError $_) }
        $out = Join-Path $tmp 'x'
        Expand-Archive -LiteralPath $zip -DestinationPath $out -Force
        $src = Get-ChildItem -LiteralPath $out -Directory | Select-Object -First 1
        if (-not $src -or -not (Test-Path -LiteralPath (Join-Path $src.FullName 'PerfManager.ps1'))) {
            throw "Archive inattendue : PerfManager.ps1 absent de la version $Sha"
        }
        $n = 0
        foreach ($f in @(Get-ChildItem -LiteralPath $src.FullName -Recurse -File)) {
            $rel = $f.FullName.Substring($src.FullName.Length).TrimStart('\', '/')
            if ($rel -match '^(\.git|android[\\/]|windows[\\/]|dist[\\/])') { continue }   # sources des applis : inutiles sur le PC
            $dest = Join-Path $UpdRoot $rel
            if (($UpdKeep -contains $rel) -and (Test-Path -LiteralPath $dest)) { continue }
            $dir = Split-Path -Parent $dest
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
            $n++
        }
        $short = $Sha.Substring(0, [Math]::Min(7, $Sha.Length))
        [ordered]@{ sha = $Sha; short = $short; message = $Message; installed = (Get-Date).ToString('yyyy-MM-dd HH:mm') } |
            ConvertTo-Json | Set-Content -LiteralPath $UpdVerPath -Encoding UTF8
        Write-UpdLog "Mise à jour installée : $short $(if ($Message) { "($Message)" }) - $n fichiers"
        return $n
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------- Lancement direct (PerfUpdate.bat)
if ($MyInvocation.InvocationName -ne '.') {
    try { $Host.UI.RawUI.WindowTitle = 'PerfManager : mise à jour' } catch {}
    Write-Host ''
    Write-Host '  PerfManager : mise à jour depuis GitHub' -ForegroundColor Magenta
    Write-Host ''

    function Ask-Token {
        Write-Host "  Colle ta clé GitHub (droit « Contents : lecture » sur $UpdDefaultRepo)." -ForegroundColor Gray
        Write-Host '  Clic droit pour coller. Rien ne s''affiche pendant la saisie, c''est normal.' -ForegroundColor Gray
        $sec = Read-Host '  Clé GitHub' -AsSecureString
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        try { $tok = ([Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)).Trim() }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
        if (-not $tok) { return $false }
        Save-UpdConfig $tok
        Write-Host '  Clé enregistrée (chiffrée pour ta session Windows).' -ForegroundColor Green
        return $true
    }

    if ($Setup -or -not (Get-UpdConfig)) {
        if (-not (Ask-Token)) { Write-Host '  Aucune clé saisie.' -ForegroundColor Yellow; Read-Host "`n  Entrée pour fermer" | Out-Null; exit }
    }

    for ($try = 0; $try -lt 2; $try++) {
        $t = Test-Update
        if ($t.ok) { break }
        Write-Host "  $($t.error)" -ForegroundColor Red
        if ($try -eq 0 -and (Read-Host '  Saisir une autre clé ? (o/N)') -match '^[oOyY]') { [void](Ask-Token) } else { break }
    }

    if ($t.ok) {
        if (-not $t.available) {
            Write-Host "  Déjà à jour (version $($t.short))." -ForegroundColor Green
        } else {
            Write-Host "  Nouvelle version $($t.short) : $($t.message)" -ForegroundColor White
            try {
                $n = Install-Update $t.sha $t.message
                Write-Host "  Installée : $n fichiers mis à jour. Tes profils et réglages sont conservés." -ForegroundColor Green
                Write-Host '  PerfDeck Remote redémarre tout seul dans la minute s''il est lancé.' -ForegroundColor Gray
            } catch { Write-Host "  Échec : $($_.Exception.Message)" -ForegroundColor Red }
        }
    }
    Read-Host "`n  Entrée pour fermer" | Out-Null
}
