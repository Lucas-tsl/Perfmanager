<#
    PerfDeck Remote - pilote PerfManager et OBS depuis ton téléphone
    -----------------------------------------------------------------
    Lancer via PerfRemote.bat et laisser la fenêtre ouverte
    (ou PerfRemote-Autostart.bat pour qu'il démarre tout seul avec Windows).

    Le téléphone doit être sur le même réseau (Wi-Fi de la box) que le PC.
#>
param(
    [int]$Port = 8765,
    [switch]$NoPair,
    [switch]$InstallAutostart,
    [switch]$RemoveAutostart
)

$ErrorActionPreference = 'Continue'
$Root       = Split-Path -Parent $PSCommandPath
$Web        = Join-Path $Root 'remote'
$CfgPath    = Join-Path $Root 'remote.json'
$PerfScript = Join-Path $Root 'PerfManager.ps1'
$ConfigPath = Join-Path $Root 'profiles.json'
$StatePath  = Join-Path $Root 'state.json'
$LogPath    = Join-Path $Root 'perfmanager.log'
$TaskName   = 'PerfDeck Remote'
$Self       = $PSCommandPath
$UpdScript  = Join-Path $Root 'PerfUpdate.ps1'
$HasUpd     = Test-Path -LiteralPath $UpdScript
if ($HasUpd) { . $UpdScript }

# ---------------------------------------------------------------- Élévation admin
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $a = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Port $Port"
    if ($NoPair)           { $a += ' -NoPair' }
    if ($InstallAutostart) { $a += ' -InstallAutostart' }
    if ($RemoveAutostart)  { $a += ' -RemoveAutostart' }
    try { Start-Process -FilePath 'powershell.exe' -ArgumentList $a -Verb RunAs } catch {}
    exit
}
try { $Host.UI.RawUI.WindowTitle = 'PerfDeck Remote' } catch {}

function Say([string]$Msg, [string]$Color = 'Gray') {
    Write-Host ("{0:HH:mm:ss}  {1}" -f (Get-Date), $Msg) -ForegroundColor $Color
}

# ---------------------------------------------------------------- Démarrage automatique
if ($InstallAutostart) {
    try {
        $user = "$env:USERDOMAIN\$env:USERNAME"
        $arg  = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -NoPair -Port $Port"
        $action  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
        $princ   = New-ScheduledTaskPrincipal -UserId $user -RunLevel Highest -LogonType Interactive
        $set     = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $princ -Settings $set -Force | Out-Null
        Start-ScheduledTask -TaskName $TaskName
        Write-Host "`nDémarrage automatique installé : PerfDeck Remote se lancera en arrière-plan à chaque ouverture de session." -ForegroundColor Green
        Write-Host "Il vient aussi d'être démarré. Pour l'enlever : PerfRemote-Autostart.bat retirer" -ForegroundColor Gray
    } catch { Write-Host "Échec : $($_.Exception.Message)" -ForegroundColor Red }
    Read-Host "`nEntrée pour fermer" | Out-Null
    exit
}
if ($RemoveAutostart) {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "`nDémarrage automatique retiré et serveur arrêté." -ForegroundColor Green
    Read-Host "`nEntrée pour fermer" | Out-Null
    exit
}

# ---------------------------------------------------------------- Code d'accès
$cfg = $null
if (Test-Path $CfgPath) { try { $cfg = Get-Content -Path $CfgPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {} }
if (-not $cfg -or -not $cfg.token) {
    $b = New-Object byte[] 18
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
    $cfg = [pscustomobject]@{ token = ([Convert]::ToBase64String($b) -replace '[+/=]', '') }
    $cfg | ConvertTo-Json | Set-Content -Path $CfgPath -Encoding UTF8
}
$Token = [string]$cfg.token

# ---------------------------------------------------------------- Mise à jour automatique (GitHub)
function Get-LoadedVersion {
    if ($HasUpd) { $v = Get-LocalVersion; if ($v) { return [string]$v.sha } }
    return ''
}
$LoadedSha = Get-LoadedVersion
$script:UpdInfo = $null
$script:RestartNow = $false

function Restart-Self {
    $style = if ($NoPair) { '-WindowStyle Hidden ' } else { '' }
    Start-Process -FilePath 'powershell.exe' -ArgumentList ("-NoProfile -ExecutionPolicy Bypass $style-File `"$Self`" -Port $Port -NoPair")
}

# Vérifie GitHub ; installe tout seul si l'auto-update est actif et qu'aucun profil n'est en cours (pas pendant un stream)
function Invoke-UpdateCheck([switch]$AutoApply) {
    if (-not $HasUpd) { return $false }
    $t = Test-Update
    if (-not $t.ok) {
        $script:UpdInfo = [ordered]@{ available = $false; configured = [bool]$t.configured; error = $t.error }
        return $false
    }
    $script:UpdInfo = [ordered]@{ available = [bool]$t.available; configured = $true; short = $t.short; message = $t.message }
    $cfgU = Get-UpdConfig
    if ($t.available -and $AutoApply -and $cfgU -and $cfgU.auto -and -not (Test-Path -LiteralPath $StatePath)) {
        try {
            $n = Install-Update $t.sha $t.message
            Say "Mise à jour installée : $($t.short) ($($t.message)), $n fichiers" 'Green'
            return $true
        } catch { Say "Mise à jour impossible : $($_.Exception.Message)" 'Yellow' }
    }
    return $false
}

# ---------------------------------------------------------------- Pare-feu (réseau privé uniquement)
foreach ($r in @(@{ n = 'PerfDeck Remote'; p = $Port }, @{ n = 'OBS WebSocket (PerfDeck)'; p = 4455 })) {
    try {
        if (-not (Get-NetFirewallRule -DisplayName $r.n -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName $r.n -Direction Inbound -Protocol TCP -LocalPort $r.p -Action Allow -Profile Private | Out-Null
        }
    } catch {}
}

foreach ($r in @(@{ n = 'PerfDeck Remote (Tailscale)'; p = $Port }, @{ n = 'OBS WebSocket (PerfDeck, Tailscale)'; p = 4455 })) {
    try {
        if (-not (Get-NetFirewallRule -DisplayName $r.n -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName $r.n -Direction Inbound -Protocol TCP -LocalPort $r.p -Action Allow -Profile Any -RemoteAddress '100.64.0.0/10' | Out-Null
        }
    } catch {}
}

# ---------------------------------------------------------------- Adresses du PC
$ips = @()
try {
    $ips = @(Get-NetIPConfiguration -ErrorAction Stop |
        Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } |
        ForEach-Object { $_.IPv4Address | ForEach-Object { $_.IPAddress } } | Where-Object { $_ })
} catch {}
if ($ips.Count -eq 0) {
    $ips = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.|100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.)' } | ForEach-Object { $_.IPAddress })
}
$PhoneUrls = @($ips | ForEach-Object { "http://$($_):$Port/?k=$Token" })

# Adresse Tailscale (100.64.0.0/10), relue à chaque affichage : Tailscale peut se connecter après PerfRemote.
function Get-RemoteUrls {
    $ts = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -match '^100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.' } | ForEach-Object { $_.IPAddress })
    return @($ts | ForEach-Object { "http://$($_):$Port/?k=$Token" })
}

# ---------------------------------------------------------------- Données
$NvSmi = $null
$nv = Get-Command 'nvidia-smi.exe' -ErrorAction SilentlyContinue
if ($nv) { $NvSmi = $nv.Source }
elseif (Test-Path 'C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe') { $NvSmi = 'C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe' }

function Read-Profiles {
    $c = Get-Content -Path $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    return @($c.profiles | Where-Object { $_ })
}

function Get-Status {
    $o = [ordered]@{ pc = $env:COMPUTERNAME; profile = $null; since = $null; cpu = $null
        ramUsed = $null; ramTotal = $null; gpu = $null; gpuTemp = $null; vramUsed = $null; vramTotal = $null }
    if (Test-Path $StatePath) {
        try { $s = Get-Content -Path $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json; $o.profile = $s.profile; $o.since = $s.since } catch {}
    }
    try { $o.cpu = [int](Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction Stop).PercentProcessorTime } catch {}
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $o.ramTotal = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        $o.ramUsed  = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 1)
    } catch {}
    if ($NvSmi) {
        try {
            $line = & $NvSmi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total --format=csv,noheader,nounits | Select-Object -First 1
            $v = @($line -split ',' | ForEach-Object { [double]($_.Trim()) })
            $o.gpu = $v[0]; $o.gpuTemp = $v[1]
            $o.vramUsed = [math]::Round($v[2] / 1024, 1); $o.vramTotal = [math]::Round($v[3] / 1024, 1)
        } catch {}
    }
    $o['version'] = $(if ($LoadedSha) { $LoadedSha.Substring(0, 7) } else { $null })
    $o['update']  = $script:UpdInfo
    return $o
}

function Get-LogTail([int]$N = 40) {
    if (-not (Test-Path $LogPath)) { return @() }
    return @(Get-Content -Path $LogPath -Tail $N -Encoding UTF8)
}

function Invoke-Perf([string[]]$Extra) {
    $before = 0
    if (Test-Path $LogPath) { $before = @(Get-Content -Path $LogPath -Encoding UTF8).Count }
    $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$PerfScript`"") + $Extra
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argv -WindowStyle Hidden -Wait | Out-Null
    if (Test-Path $LogPath) { return @(Get-Content -Path $LogPath -Encoding UTF8 | Select-Object -Skip $before) }
    return @()
}

# ---------------------------------------------------------------- Steam
$SkipGames = 'Steamworks|Redistributable|Steam Linux Runtime|Proton|SteamVR|Spacewar|Steam Audio'
$script:GamesCache = $null
$script:GamesAt = [datetime]::MinValue

function Get-SteamPath {
    $p = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction SilentlyContinue).SteamPath
    if (-not $p) { $p = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -Name InstallPath -ErrorAction SilentlyContinue).InstallPath }
    if ($p) { $p = $p -replace '/', '\' }
    if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    return $null
}

function Unescape-Vdf([string]$Text) { return [regex]::Replace($Text, '\\(.)', '$1') }

function Get-SteamGames([switch]$Force) {
    if (-not $Force -and $script:GamesCache -and ((Get-Date) - $script:GamesAt).TotalSeconds -lt 60) { return $script:GamesCache }
    $list = New-Object System.Collections.ArrayList
    $steam = Get-SteamPath
    if ($steam) {
        $libs = New-Object System.Collections.ArrayList
        [void]$libs.Add($steam)
        $vdf = Join-Path (Join-Path $steam 'steamapps') 'libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            $txt = Get-Content -LiteralPath $vdf -Raw -Encoding UTF8
            foreach ($m in [regex]::Matches($txt, '"path"\s+"((?:[^"\\]|\\.)*)"')) {
                $lp = Unescape-Vdf $m.Groups[1].Value
                if (-not ($libs | Where-Object { $_ -ieq $lp })) { [void]$libs.Add($lp) }
            }
        }
        $seen = @{}
        foreach ($lib in $libs) {
            $apps = Join-Path $lib 'steamapps'
            if (-not (Test-Path -LiteralPath $apps)) { continue }
            foreach ($f in @(Get-ChildItem -LiteralPath $apps -Filter 'appmanifest_*.acf' -ErrorAction SilentlyContinue)) {
                try {
                    $t  = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
                    $id = [regex]::Match($t, '"appid"\s+"(\d+)"').Groups[1].Value
                    $nm = Unescape-Vdf ([regex]::Match($t, '"name"\s+"((?:[^"\\]|\\.)*)"').Groups[1].Value)
                    if (-not $id -or -not $nm -or $seen.ContainsKey($id) -or $nm -match $SkipGames) { continue }
                    $seen[$id] = $true
                    $lpm = [regex]::Match($t, '"LastPlayed"\s+"(\d+)"')
                    [void]$list.Add([pscustomobject]@{
                        appid = $id; name = $nm
                        lastPlayed = $(if ($lpm.Success) { [long]$lpm.Groups[1].Value } else { 0 })
                    })
                } catch {}
            }
        }
    }
    $script:GamesCache = @($list | Sort-Object @{ Expression = 'lastPlayed'; Descending = $true }, @{ Expression = 'name'; Descending = $false })
    $script:GamesAt = Get-Date
    return $script:GamesCache
}

function Get-CoverPath([string]$Id) {
    $steam = Get-SteamPath
    if (-not $steam) { return $null }
    $lc = Join-Path (Join-Path $steam 'appcache') 'librarycache'
    foreach ($n in @("$($Id)_library_600x900.jpg", "$($Id)_header.jpg")) {
        $p = Join-Path $lc $n
        if (Test-Path -LiteralPath $p) { return $p }
    }
    $d = Join-Path $lc $Id
    if (Test-Path -LiteralPath $d) {
        foreach ($n in @('library_600x900.jpg', 'library_capsule.jpg', 'header.jpg')) {
            $f = Get-ChildItem -LiteralPath $d -Recurse -Filter $n -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($f) { return $f.FullName }
        }
    }
    return $null
}

# ---------------------------------------------------------------- HTTP
$Mime = @{
    '.html' = 'text/html; charset=utf-8'; '.js' = 'application/javascript; charset=utf-8'
    '.webmanifest' = 'application/manifest+json'; '.png' = 'image/png'; '.svg' = 'image/svg+xml'
}
$Static = @('index.html', 'app.js', 'sw.js', 'manifest.webmanifest', 'icon-192.png', 'icon-512.png')

function Send-Bytes($Ctx, [byte[]]$Bytes, [string]$Type, [int]$Code = 200, [string]$Cache = 'no-store') {
    $r = $Ctx.Response
    $r.StatusCode = $Code
    $r.ContentType = $Type
    $r.Headers['Cache-Control'] = $Cache
    $r.ContentLength64 = $Bytes.Length
    $r.OutputStream.Write($Bytes, 0, $Bytes.Length)
    $r.OutputStream.Close()
}
function Send-Text($Ctx, [string]$Text, [int]$Code = 200, [string]$Type = 'text/plain; charset=utf-8') {
    Send-Bytes $Ctx ([Text.Encoding]::UTF8.GetBytes($Text)) $Type $Code
}
function Send-Json($Ctx, $Obj, [int]$Code = 200) {
    Send-Text $Ctx ($Obj | ConvertTo-Json -Depth 5 -Compress) $Code 'application/json; charset=utf-8'
}
function Read-Body($Req) {
    $sr = New-Object IO.StreamReader($Req.InputStream, [Text.Encoding]::UTF8)
    $t = $sr.ReadToEnd(); $sr.Close()
    if ($t) { return ($t | ConvertFrom-Json) } else { return $null }
}

$PairPage = @'
<!doctype html><html lang="fr"><head><meta charset="utf-8"><title>PerfDeck : appairage</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
body{margin:0;background:#0d0d12;color:#ececf2;font:15px/1.5 "Segoe UI",system-ui,sans-serif;padding:40px 20px}
.w{max-width:900px;margin:0 auto}
h1{margin:0 0 4px;font-size:26px}h1 b{color:#7c5cff}
.lead{color:#8b8b9e;margin:0 0 26px}
.g{display:grid;grid-template-columns:1fr 1fr;gap:18px}
.c{background:#17171f;border-radius:20px;padding:22px}
.c h2{margin:0 0 4px;font-size:17px}.c p{margin:0 0 14px;color:#a9a9bb;font-size:13.5px}
.q{background:#fff;padding:12px;border-radius:14px;width:max-content}
.rec{outline:2px solid #7c5cff}
.tag{display:inline-block;font-size:11px;letter-spacing:1px;text-transform:uppercase;background:#7c5cff;color:#fff;border-radius:6px;padding:2px 8px;margin-left:6px;vertical-align:2px}
code{background:#20202b;padding:2px 7px;border-radius:6px;font-size:12.5px;word-break:break-all}
ol{padding-left:20px;color:#c9c9d6;margin:22px 0 0}li{margin:6px 0}
.off a{color:#b4a3ff}
@media(max-width:700px){.g{grid-template-columns:1fr}}
</style></head><body><div class="w">
<h1>Perf<b>Deck</b></h1>
<p class="lead">Scanne un QR code avec l'appareil photo de ton S24 Ultra, puis dans Chrome : menu ⋮ → Ajouter à l'écran d'accueil.</p>
<div class="g">
<div class="c">
<h2>À la maison</h2><p>Téléphone sur le même Wi-Fi que le PC.</p>
<div class="q" id="q1"></div>
<p style="margin:12px 0 0">{{LAN}}</p>
</div>
{{REMOTE}}
</div>
<ol>
<li>Dans OBS : Outils → Paramètres du serveur WebSocket → coche Activer, puis Afficher les informations de connexion pour copier le mot de passe.</li>
<li>Dans l'app : bouton ⚙ → colle le mot de passe OBS.</li>
</ol>
</div>
<script src="https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js"></script>
<script>
function qr(id,t){var e=document.getElementById(id);if(!e||!t)return;try{new QRCode(e,{text:t,width:220,height:220,correctLevel:QRCode.CorrectLevel.M})}catch(x){e.textContent='QR indisponible hors ligne'}}
qr('q1','{{URL}}');qr('q2','{{RURL}}');
</script>
</body></html>
'@

$RemoteOn = @'
<div class="c rec">
<h2>Partout <span class="tag">Recommandé</span></h2>
<p>Via Tailscale : marche à la maison comme en 4G/5G. Installe plutôt celle-ci sur l'écran d'accueil.</p>
<div class="q" id="q2"></div>
<p style="margin:12px 0 0"><code>{{RURL}}</code></p>
</div>
'@

$RemoteOff = @'
<div class="c off">
<h2>Partout (hors de chez toi)</h2>
<p>Installe <b>Tailscale</b> (gratuit) sur le PC et sur le S24 avec le même compte, puis recharge cette page : un deuxième QR code apparaîtra ici.<br><br>
PC : <a href="https://tailscale.com/download/windows">tailscale.com/download/windows</a><br>S24 : Play Store → Tailscale</p>
</div>
'@

function Handle-Request($Ctx) {
    $req  = $Ctx.Request
    $path = $req.Url.AbsolutePath

    if ($path -eq '/pair') {
        if (-not $req.IsLocal) { Send-Text $Ctx 'Interdit' 403; return }
        $first  = if ($PhoneUrls.Count) { $PhoneUrls[0] } else { "http://IP-DU-PC:$Port/?k=$Token" }
        $list   = ($PhoneUrls | ForEach-Object { "<code>$_</code>" }) -join '<br>'
        $remote = @(Get-RemoteUrls)
        $rurl   = if ($remote.Count) { $remote[0] } else { '' }
        $block  = if ($rurl) { $RemoteOn } else { $RemoteOff }
        $html   = $PairPage.Replace('{{REMOTE}}', $block).Replace('{{RURL}}', $rurl).Replace('{{URL}}', $first).Replace('{{LAN}}', $list)
        Send-Text $Ctx $html 200 'text/html; charset=utf-8'
        return
    }

    if ($path -match '^/api/cover/(\d+)$') {
        if ($req.QueryString['k'] -ne $Token) { Send-Text $Ctx 'Interdit' 403; return }
        $cp = Get-CoverPath $Matches[1]
        if ($cp) { Send-Bytes $Ctx ([IO.File]::ReadAllBytes($cp)) 'image/jpeg' 200 'max-age=86400' }
        else { Send-Text $Ctx 'Pas de jaquette' 404 }
        return
    }

    if ($path.StartsWith('/api/')) {
        if ($req.Headers['X-Token'] -ne $Token) { Send-Json $Ctx @{ error = 'token' } 401; return }

        if ($path -eq '/api/status') { Send-Json $Ctx (Get-Status); return }

        if ($path -eq '/api/profiles') {
            $list = @(Read-Profiles | ForEach-Object {
                [ordered]@{ name = [string]$_.name; description = [string]$_.description; restore = [bool]$_.restore } })
            Send-Json $Ctx @{ profiles = $list }
            return
        }

        if ($path -eq '/api/log') { Send-Json $Ctx @{ lines = @(Get-LogTail 40) }; return }

        if ($path -eq '/api/games') {
            $games = @(Get-SteamGames -Force:($req.QueryString['refresh'] -eq '1'))
            Send-Json $Ctx @{ steam = [bool](Get-SteamPath); games = $games }
            return
        }

        if ($req.HttpMethod -ne 'POST') { Send-Json $Ctx @{ error = 'POST attendu' } 405; return }

        if ($path -eq '/api/apply') {
            $body = Read-Body $req
            $name = [string]$body.name
            $prof = Read-Profiles | Where-Object { $_.name -eq $name } | Select-Object -First 1
            if (-not $prof) { Send-Json $Ctx @{ error = 'Profil inconnu' } 400; return }
            Say "Téléphone → profil « $name »" 'Cyan'
            $lines = Invoke-Perf @('-Profil', "`"$name`"")
            Send-Json $Ctx @{ ok = $true; lines = @($lines) }
            return
        }

        if ($path -eq '/api/launch') {
            $body = Read-Body $req
            $id   = [string]$body.appid
            $game = Get-SteamGames | Where-Object { $_.appid -eq $id } | Select-Object -First 1
            if (-not $game) { Send-Json $Ctx @{ error = 'Jeu introuvable' } 400; return }
            $lines = @()
            if ($body.profile) {
                $prof = Read-Profiles | Where-Object { $_.name -eq [string]$body.profile } | Select-Object -First 1
                if (-not $prof) { Send-Json $Ctx @{ error = 'Profil inconnu' } 400; return }
                Say "Téléphone → profil « $($prof.name) » avant $($game.name)" 'Cyan'
                $lines = @(Invoke-Perf @('-Profil', "`"$($prof.name)`""))
            }
            # Via l'explorateur : Steam et le jeu démarrent sans droits admin, comme un double-clic.
            Start-Process -FilePath 'explorer.exe' -ArgumentList "steam://rungameid/$id"
            Say "Téléphone → lancement de $($game.name)" 'Cyan'
            $line = "{0:yyyy-MM-dd HH:mm:ss} [OK] Jeu lancé depuis le téléphone : {1}" -f (Get-Date), $game.name
            try { Add-Content -Path $LogPath -Value $line -Encoding UTF8 } catch {}
            Send-Json $Ctx @{ ok = $true; lines = @($lines + $line) }
            return
        }

        if ($path -eq '/api/update-check') {
            if (-not $HasUpd) { Send-Json $Ctx @{ error = 'Module de mise à jour absent' } 400; return }
            [void](Invoke-UpdateCheck)
            Send-Json $Ctx @{ update = $script:UpdInfo }
            return
        }

        if ($path -eq '/api/update') {
            if (-not $HasUpd) { Send-Json $Ctx @{ error = 'Module de mise à jour absent' } 400; return }
            $t = Test-Update
            if (-not $t.ok) { Send-Json $Ctx @{ error = $t.error } 400; return }
            if (-not $t.available) { Send-Json $Ctx @{ ok = $true; upToDate = $true; short = $t.short }; return }
            try { $n = Install-Update $t.sha $t.message }
            catch { Send-Json $Ctx @{ error = "Mise à jour impossible : $($_.Exception.Message)" } 500; return }
            Say "Téléphone → mise à jour $($t.short) installée ($n fichiers), redémarrage" 'Green'
            Send-Json $Ctx @{ ok = $true; installed = $t.short; message = $t.message }
            $script:RestartNow = $true
            return
        }

        if ($path -eq '/api/restore') {
            Say 'Téléphone → tout restaurer' 'Cyan'
            $lines = Invoke-Perf @('-Restaurer')
            Send-Json $Ctx @{ ok = $true; lines = @($lines) }
            return
        }

        Send-Json $Ctx @{ error = 'introuvable' } 404
        return
    }

    $file = if ($path -eq '/') { 'index.html' } else { $path.TrimStart('/') }
    if ($Static -contains $file) {
        $full = Join-Path $Web $file
        if (Test-Path $full) {
            Send-Bytes $Ctx ([IO.File]::ReadAllBytes($full)) $Mime[[IO.Path]::GetExtension($full)]
            return
        }
    }
    Send-Text $Ctx 'Introuvable' 404
}

# ---------------------------------------------------------------- Démarrage du serveur
if ($HasUpd -and (Get-UpdConfig)) {
    Say 'Recherche de mise à jour…'
    if (Invoke-UpdateCheck -AutoApply) { Restart-Self; exit }
}

# Plusieurs essais : après une mise à jour, l'ancienne instance libère le port quelques instants plus tard
$listener = $null
for ($try = 0; $try -lt 8 -and -not $listener; $try++) {
    $l = New-Object Net.HttpListener
    $l.Prefixes.Add("http://+:$Port/")
    try { $l.Start(); $listener = $l } catch { $l.Close(); Start-Sleep -Seconds 1 }
}
if (-not $listener) {
    Say "Le port $Port est déjà utilisé : PerfDeck Remote tourne sûrement déjà." 'Yellow'
    if (-not $NoPair) { Start-Process -FilePath 'explorer.exe' -ArgumentList "http://localhost:$Port/pair" }
    Start-Sleep -Seconds 5
    exit
}

Write-Host ''
Write-Host '  PerfDeck Remote est lancé' -ForegroundColor Magenta
Write-Host '  Laisse cette fenêtre ouverte pendant que tu utilises le téléphone.' -ForegroundColor Gray
Write-Host ''
foreach ($u in $PhoneUrls) { Write-Host "  Adresse à la maison : $u" -ForegroundColor White }
foreach ($u in (Get-RemoteUrls)) { Write-Host "  Adresse partout (Tailscale) : $u" -ForegroundColor White }
Write-Host ''
try {
    $pub = @(Get-NetConnectionProfile -ErrorAction Stop | Where-Object { $_.NetworkCategory -eq 'Public' })
    if ($pub.Count) {
        Say "Attention : le réseau « $($pub[0].Name) » est en mode Public, le téléphone sera bloqué." 'Yellow'
        Say 'Paramètres Windows → Réseau et Internet → ta connexion → Type de profil réseau : Privé' 'Yellow'
    }
} catch {}

if (-not $NoPair) { Start-Process -FilePath 'explorer.exe' -ArgumentList "http://localhost:$Port/pair" }

$updClock = [Diagnostics.Stopwatch]::StartNew()
$verClock = [Diagnostics.Stopwatch]::StartNew()
while ($listener.IsListening -and -not $script:RestartNow) {
    $task = $listener.GetContextAsync()
    while (-not $task.AsyncWaitHandle.WaitOne(300)) {
        # Version installée à côté (PerfUpdate.bat, bouton de PerfManager) : on recharge
        if ($verClock.Elapsed.TotalSeconds -ge 60) {
            $verClock.Restart()
            if ($HasUpd -and (Get-LoadedVersion) -ne $LoadedSha) { Say 'Nouvelle version détectée : redémarrage' 'Green'; $script:RestartNow = $true; break }
        }
        # Vérification GitHub toutes les 30 minutes
        if ($updClock.Elapsed.TotalMinutes -ge 30) {
            $updClock.Restart()
            if ($HasUpd -and (Get-UpdConfig) -and (Invoke-UpdateCheck -AutoApply)) { $script:RestartNow = $true; break }
        }
    }
    if ($script:RestartNow) { break }
    try { $ctx = $task.GetAwaiter().GetResult() } catch { continue }
    try { Handle-Request $ctx }
    catch {
        Say "Erreur : $($_.Exception.Message)" 'Red'
        try { Send-Json $ctx @{ error = $_.Exception.Message } 500 } catch {}
    }
}

if ($script:RestartNow) {
    try { $listener.Stop(); $listener.Close() } catch {}
    Restart-Self
}
