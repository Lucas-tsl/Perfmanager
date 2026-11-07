<#
    PerfManager - profils de performance pour PC gaming / stream
    ------------------------------------------------------------
    Lancer via PerfManager.bat (double-clic). Les droits admin sont demandés
    (nécessaires pour arrêter des services Windows).

    Ligne de commande (raccourcis, Stream Deck...) :
        PerfManager.ps1 -Profil "Stream + Jeu"   applique un profil sans interface
        PerfManager.ps1 -Restaurer               remet tout comme avant
#>
param(
    [string]$Profil,
    [switch]$Restaurer
)

$ErrorActionPreference = 'Continue'
$Root       = Split-Path -Parent $PSCommandPath
$ConfigPath = Join-Path $Root 'profiles.json'
$StatePath  = Join-Path $Root 'state.json'
$LogPath    = Join-Path $Root 'perfmanager.log'
$Headless   = ([bool]$Profil) -or $Restaurer
$Self       = $PSCommandPath

# ---------------------------------------------------------------- Élévation admin
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $argList = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
    if ($Profil)    { $argList += " -Profil `"$Profil`"" }
    if ($Restaurer) { $argList += " -Restaurer" }
    try { Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs } catch {}
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---------------------------------------------------------------- Configuration
function Read-Config {
    if (-not (Test-Path $ConfigPath)) { throw "profiles.json introuvable à côté du script." }
    return (Get-Content -Path $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json)
}

try { $script:Config = Read-Config }
catch {
    [System.Windows.Forms.MessageBox]::Show(
        "Erreur de lecture de profiles.json :`n$($_.Exception.Message)", 'PerfManager',
        [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    exit 1
}
$script:Protected = @($script:Config.protectedProcesses | Where-Object { $_ })

$UpdScript = Join-Path $Root 'PerfUpdate.ps1'
$HasUpd    = Test-Path -LiteralPath $UpdScript
if ($HasUpd) { . $UpdScript }

# ---------------------------------------------------------------- Journal
$script:LogBox = $null
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $stamp = Get-Date
    try { Add-Content -Path $LogPath -Value ("{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}" -f $stamp, $Level, $Message) -Encoding UTF8 } catch {}
    if ($script:LogBox) {
        $color = switch ($Level) {
            'OK'    { [Drawing.Color]::FromArgb(120, 220, 150) }
            'WARN'  { [Drawing.Color]::FromArgb(255, 190, 90) }
            'ERR'   { [Drawing.Color]::FromArgb(255, 110, 110) }
            'TITLE' { [Drawing.Color]::FromArgb(170, 150, 255) }
            default { [Drawing.Color]::FromArgb(150, 150, 160) }
        }
        $box = $script:LogBox
        $box.SelectionStart  = $box.TextLength
        $box.SelectionLength = 0
        $box.SelectionColor  = $color
        $box.AppendText(("{0:HH:mm:ss}  {1}" -f $stamp, $Message) + [Environment]::NewLine)
        $box.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    }
}

# ---------------------------------------------------------------- État (pour restaurer)
function Get-State {
    $s = @{ exists = $false; profile = ''; since = ''; powerPlan = $null; toast = $null; services = @(); processes = @() }
    if (Test-Path $StatePath) {
        try {
            $j = Get-Content -Path $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
            $s.exists    = $true
            $s.profile   = $j.profile
            $s.since     = $j.since
            $s.powerPlan = $j.powerPlan
            $s.toast     = $j.toast
            $s.services  = @($j.services  | Where-Object { $_ })
            $s.processes = @($j.processes | Where-Object { $_ })
        } catch {}
    }
    return $s
}

function Save-State($s) {
    $o = [ordered]@{
        profile   = $s.profile
        since     = $s.since
        powerPlan = $s.powerPlan
        toast     = $s.toast
        services  = @($s.services)
        processes = @($s.processes)
    }
    $o | ConvertTo-Json -Depth 4 | Set-Content -Path $StatePath -Encoding UTF8
}

# ---------------------------------------------------------------- Plan d'alimentation
$GuidRx = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
# Les motifs utilisent "." à la place des accents : la sortie de powercfg est en page de code OEM.
$PowerPlans = @{
    high     = @{ guid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'; label = 'Performances élevées';   pattern = 'High performance|Performances .lev' }
    ultimate = @{ guid = 'e9a42b02-d5df-448d-aa00-03f14749eb61'; label = 'Performances optimales'; pattern = 'Ultimate Performance|Performances optimales' }
    balanced = @{ guid = '381b4222-f694-41f0-9685-ff5bb260df2e'; label = 'Utilisation équilibrée'; pattern = 'Balanced|quilibr' }
}

function Get-ActivePlanGuid {
    $out = (powercfg /getactivescheme) -join ' '
    if ($out -match "($GuidRx)") { return $Matches[1] }
    return $null
}

function Set-PowerPlan([string]$Key) {
    $plan = $PowerPlans[$Key]
    if (-not $plan) { Write-Log "Plan d'alimentation inconnu : $Key" 'WARN'; return }
    $lines = @(powercfg /list)
    $guid = $null
    if (($lines -join "`n") -match [regex]::Escape($plan.guid)) { $guid = $plan.guid }
    else {
        # Plan déjà dupliqué auparavant ? On le retrouve par son nom.
        $line = $lines | Where-Object { $_ -match $plan.pattern } | Select-Object -First 1
        if ($line -and ($line -match "($GuidRx)")) { $guid = $Matches[1] }
    }
    if (-not $guid) {
        $dup = (powercfg -duplicatescheme $plan.guid) -join ' '
        if ($dup -match "($GuidRx)") { $guid = $Matches[1] }
    }
    if (-not $guid) { Write-Log "Plan « $($plan.label) » indisponible sur ce PC" 'WARN'; return }
    powercfg /setactive $guid | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Log "Alimentation : $($plan.label)" 'OK' }
    else { Write-Log "Impossible d'activer « $($plan.label) »" 'WARN' }
}

# ---------------------------------------------------------------- Mode Jeu / notifications
function Set-GameMode([bool]$On) {
    $k = 'HKCU:\Software\Microsoft\GameBar'
    try {
        if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
        Set-ItemProperty -Path $k -Name AutoGameModeEnabled -Value ([int]$On) -Type DWord
        Set-ItemProperty -Path $k -Name AllowAutoGameMode   -Value ([int]$On) -Type DWord
        Write-Log ("Mode Jeu Windows : " + $(if ($On) { 'activé' } else { 'désactivé' })) 'OK'
    } catch { Write-Log "Mode Jeu : $($_.Exception.Message)" 'WARN' }
}

$ToastKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications'
function Get-Toast {
    $v = (Get-ItemProperty -Path $ToastKey -Name ToastEnabled -ErrorAction SilentlyContinue).ToastEnabled
    if ($null -eq $v) { return 1 } else { return [int]$v }
}
function Set-Toast([bool]$On) {
    try {
        if (-not (Test-Path $ToastKey)) { New-Item -Path $ToastKey -Force | Out-Null }
        Set-ItemProperty -Path $ToastKey -Name ToastEnabled -Value ([int]$On) -Type DWord
        Write-Log ("Notifications Windows : " + $(if ($On) { 'activées' } else { 'coupées' })) 'OK'
    } catch { Write-Log "Notifications : $($_.Exception.Message)" 'WARN' }
}

# ---------------------------------------------------------------- Services / processus
function Stop-Svc([string]$Name, $State) {
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { Write-Log "Service $Name introuvable (ignoré)"; return }
    if ($svc.Status -ne 'Running') { Write-Log "$($svc.DisplayName) : déjà arrêté"; return }
    try {
        Stop-Service -Name $Name -NoWait -ErrorAction Stop
        if ($State.services -notcontains $Name) { $State.services += $Name }
        Write-Log "Service arrêté : $($svc.DisplayName)" 'OK'
    } catch { Write-Log "Impossible d'arrêter $Name : $($_.Exception.Message)" 'WARN' }
}

function Stop-AppProcess([string]$Name, $State) {
    if ($script:Protected -contains $Name) { Write-Log "$Name est protégé, ignoré" 'WARN'; return }
    $procs = @(Get-Process -Name $Name -ErrorAction SilentlyContinue)
    if ($procs.Count -eq 0) { Write-Log "$Name : pas lancé"; return }
    $path = $procs | Where-Object { $_.Path } | Select-Object -First 1 -ExpandProperty Path
    if ($path -and ($State.processes -notcontains $path)) { $State.processes += $path }
    $procs | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Log "Fermé : $Name ($($procs.Count) processus)" 'OK'
}

function Start-App($App) {
    $path = [Environment]::ExpandEnvironmentVariables([string]$App.path)
    if (-not (Test-Path $path)) { Write-Log "$($App.name) introuvable ($path) : corrige le chemin dans profiles.json" 'WARN'; return }
    $pn = [IO.Path]::GetFileNameWithoutExtension($path)
    if (Get-Process -Name $pn -ErrorAction SilentlyContinue) { Write-Log "$($App.name) : déjà lancé"; return }
    try {
        if ($App.elevated) {
            $p = @{ FilePath = $path; WorkingDirectory = (Split-Path $path -Parent) }
            if ($App.args) { $p.ArgumentList = [string]$App.args }
            Start-Process @p
        } else {
            # Lancé via l'explorateur = sans droits admin (comme un double-clic)
            Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$path`""
        }
        Write-Log "Lancé : $($App.name)" 'OK'
    } catch { Write-Log "Lancement de $($App.name) impossible : $($_.Exception.Message)" 'WARN' }
}

$PriorityLabels = @{ Idle = 'basse'; BelowNormal = 'inférieure'; Normal = 'normale'; AboveNormal = 'supérieure'; High = 'haute' }
function Set-Prio([string]$Name, [string]$Value) {
    if (-not $PriorityLabels.ContainsKey($Value)) { Write-Log "Priorité « $Value » refusée pour $Name" 'WARN'; return }
    $procs = @(Get-Process -Name $Name -ErrorAction SilentlyContinue)
    if ($procs.Count -eq 0) { Write-Log "$Name : pas lancé, priorité non changée"; return }
    foreach ($pr in $procs) { try { $pr.PriorityClass = $Value } catch {} }
    Write-Log "Priorité $($PriorityLabels[$Value]) : $Name" 'OK'
}

# ---------------------------------------------------------------- Profils
function Get-Default($o) { if ($null -ne $o.default) { return [bool]$o.default } else { return $true } }

function Get-Items($Prof) {
    $items = New-Object System.Collections.ArrayList
    if ($Prof.restore) {
        [void]$items.Add(@{ type = 'restore'; label = 'Restaurer tout ce que PerfManager a arrêté'; on = $true; relaunch = [bool]$Prof.relaunchApps })
    }
    if ($Prof.powerPlan -and $PowerPlans[$Prof.powerPlan]) {
        [void]$items.Add(@{ type = 'power'; name = $Prof.powerPlan; label = "Alimentation : $($PowerPlans[$Prof.powerPlan].label)"; on = $true })
    }
    if ($null -ne $Prof.gameMode) {
        [void]$items.Add(@{ type = 'gamemode'; value = [bool]$Prof.gameMode; on = $true
            label = $(if ($Prof.gameMode) { 'Activer le Mode Jeu Windows' } else { 'Désactiver le Mode Jeu Windows' }) })
    }
    if ($null -ne $Prof.notifications) {
        [void]$items.Add(@{ type = 'toast'; value = [bool]$Prof.notifications; on = $true
            label = $(if ($Prof.notifications) { 'Réactiver les notifications Windows' } else { 'Couper les notifications Windows' }) })
    }
    foreach ($p in @($Prof.killProcesses)) {
        if ($p) { [void]$items.Add(@{ type = 'process'; name = $p.name; label = "Fermer : $($p.label)"; on = (Get-Default $p) }) }
    }
    foreach ($s in @($Prof.stopServices)) {
        if ($s) { [void]$items.Add(@{ type = 'service'; name = $s.name; label = "Service : $($s.label)"; on = (Get-Default $s) }) }
    }
    foreach ($a in @($Prof.launch)) {
        if ($a) { [void]$items.Add(@{ type = 'launch'; app = $a; label = "Lancer : $($a.name)"; on = (Get-Default $a) }) }
    }
    if ($Prof.priorities) {
        foreach ($pp in $Prof.priorities.PSObject.Properties) {
            [void]$items.Add(@{ type = 'priority'; name = $pp.Name; value = [string]$pp.Value; on = $true
                label = "Priorité $($PriorityLabels[[string]$pp.Value]) : $($pp.Name)" })
        }
    }
    return ,$items
}

function Restore-All([switch]$Relaunch) {
    $s = Get-State
    if (-not $s.exists) { Write-Log 'Rien à restaurer : aucun profil actif.'; return }
    Write-Log "Restauration (profil « $($s.profile) »)" 'TITLE'
    foreach ($n in $s.services) {
        try { Start-Service -Name $n -ErrorAction Stop; Write-Log "Service relancé : $n" 'OK' }
        catch { Write-Log "Service $n non relancé : $($_.Exception.Message)" 'WARN' }
    }
    if ($s.powerPlan) {
        powercfg /setactive $s.powerPlan | Out-Null
        Write-Log "Plan d'alimentation d'origine rétabli" 'OK'
    }
    if ($null -ne $s.toast) { Set-Toast ([bool][int]$s.toast) }
    if ($Relaunch) {
        foreach ($p in $s.processes) {
            if ($p -match '\\WindowsApps\\') { Write-Log "À relancer à la main : $(Split-Path $p -Leaf)" 'WARN'; continue }
            if (Test-Path $p) {
                try { Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$p`""; Write-Log "Relancé : $(Split-Path $p -Leaf)" 'OK' }
                catch { Write-Log "Relance impossible : $p" 'WARN' }
            }
        }
    }
    Remove-Item -Path $StatePath -Force -ErrorAction SilentlyContinue
    Write-Log 'PC revenu à son état normal.' 'OK'
}

function Invoke-Profile($Prof, $Items) {
    $sel = @($Items | Where-Object { $_.on })
    Write-Log "===== $($Prof.name) =====" 'TITLE'

    $restore = $sel | Where-Object { $_.type -eq 'restore' } | Select-Object -First 1
    if ($restore) { Restore-All -Relaunch:([bool]$restore.relaunch) }

    $state = Get-State
    if (-not $state.exists) {
        $state.powerPlan = Get-ActivePlanGuid
        $state.toast     = Get-Toast
    }

    foreach ($it in $sel) {
        switch ($it.type) {
            'power'    { Set-PowerPlan $it.name }
            'gamemode' { Set-GameMode $it.value }
            'toast'    { Set-Toast $it.value }
        }
    }
    foreach ($it in ($sel | Where-Object { $_.type -eq 'process' })) { Stop-AppProcess $it.name $state }
    foreach ($it in ($sel | Where-Object { $_.type -eq 'service' })) { Stop-Svc $it.name $state }

    $launch = @($sel | Where-Object { $_.type -eq 'launch' })
    foreach ($it in $launch) { Start-App $it.app }

    $prio = @($sel | Where-Object { $_.type -eq 'priority' })
    if ($prio.Count -gt 0) {
        if ($launch.Count -gt 0) { Start-Sleep -Seconds 3 }
        foreach ($it in $prio) { Set-Prio $it.name $it.value }
    }

    if (-not $restore) {
        $state.profile = $Prof.name
        $state.since   = (Get-Date).ToString('HH:mm')
        Save-State $state
    }
    Write-Log "Profil « $($Prof.name) » appliqué." 'OK'
}

# ---------------------------------------------------------------- Mode sans interface
if ($Headless) {
    if ($Restaurer) { Restore-All -Relaunch }
    else {
        $p = $script:Config.profiles | Where-Object { $_.name -eq $Profil } | Select-Object -First 1
        if ($p) { Invoke-Profile $p (Get-Items $p) } else { Write-Log "Profil introuvable : $Profil" 'ERR' }
    }
    exit
}

# ================================================================ Interface
[System.Windows.Forms.Application]::EnableVisualStyles()

$C = @{
    Bg     = [Drawing.Color]::FromArgb(18, 18, 22)
    Panel  = [Drawing.Color]::FromArgb(28, 28, 34)
    Panel2 = [Drawing.Color]::FromArgb(40, 40, 48)
    Text   = [Drawing.Color]::FromArgb(232, 232, 238)
    Dim    = [Drawing.Color]::FromArgb(140, 140, 155)
    Accent = [Drawing.Color]::FromArgb(124, 92, 255)
    Danger = [Drawing.Color]::FromArgb(110, 40, 48)
    Good   = [Drawing.Color]::FromArgb(90, 200, 120)
    Mid    = [Drawing.Color]::FromArgb(240, 180, 70)
    Bad    = [Drawing.Color]::FromArgb(240, 90, 90)
}
$FontUI    = New-Object Drawing.Font('Segoe UI', 9.5)
$FontBig   = New-Object Drawing.Font('Segoe UI Semibold', 18)
$FontTitle = New-Object Drawing.Font('Segoe UI Semibold', 13)
$FontSmall = New-Object Drawing.Font('Segoe UI', 8.5)
$FontMono  = New-Object Drawing.Font('Consolas', 9)

function New-Label($Text, $X, $Y, $W, $H, $Font, $Color) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $Text
    $l.Location = New-Object Drawing.Point($X, $Y)
    $l.Size = New-Object Drawing.Size($W, $H)
    if ($Font)  { $l.Font = $Font }
    if ($Color) { $l.ForeColor = $Color }
    $l.BackColor = [Drawing.Color]::Transparent
    return $l
}
function New-Button($Text, $X, $Y, $W, $H, $Back) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $Text
    $b.Location = New-Object Drawing.Point($X, $Y)
    $b.Size = New-Object Drawing.Size($W, $H)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.BackColor = $Back
    $b.ForeColor = $C.Text
    $b.Cursor = [Windows.Forms.Cursors]::Hand
    return $b
}

$form = New-Object Windows.Forms.Form
$form.Text = 'PerfManager'
$form.ClientSize = New-Object Drawing.Size(980, 690)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.BackColor = $C.Bg
$form.ForeColor = $C.Text
$form.Font = $FontUI
$icoPath = Join-Path $Root 'perfmanager.ico'
if (Test-Path -LiteralPath $icoPath) { try { $form.Icon = New-Object Drawing.Icon($icoPath) } catch {} }

# --- En-tête
$hw = ''
try {
    $cpuName = ((Get-CimInstance Win32_Processor | Select-Object -First 1).Name).Trim()
    $gpuName = (Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA|Radeon|Arc' } | Select-Object -First 1).Name
    $ramGo   = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    $hw = "$cpuName  ·  $gpuName  ·  $ramGo Go"
} catch {}
$form.Controls.Add((New-Label 'PerfManager' 18 10 300 38 $FontBig $C.Text))
$form.Controls.Add((New-Label $hw 21 48 600 18 $FontSmall $C.Dim))
$lblStatus = New-Label '' 560 20 400 22 $FontUI $C.Dim
$lblStatus.TextAlign = 'MiddleRight'
$form.Controls.Add($lblStatus)
$btnUpdate = New-Button '' 600 46 360 24 $C.Accent
$btnUpdate.Font = $FontSmall
$btnUpdate.Visible = $false
$form.Controls.Add($btnUpdate)

# --- Cartes de monitoring
function New-Card($X, $Title) {
    $p = New-Object Windows.Forms.Panel
    $p.Location = New-Object Drawing.Point($X, 78)
    $p.Size = New-Object Drawing.Size(226, 74)
    $p.BackColor = $C.Panel
    $t = New-Label $Title 12 8 200 18 $FontSmall $C.Dim
    $v = New-Label '—' 12 24 205 30 $FontTitle $C.Text
    $bg = New-Object Windows.Forms.Panel
    $bg.Location = New-Object Drawing.Point(12, 58)
    $bg.Size = New-Object Drawing.Size(202, 6)
    $bg.BackColor = $C.Panel2
    $bar = New-Object Windows.Forms.Panel
    $bar.Location = New-Object Drawing.Point(0, 0)
    $bar.Size = New-Object Drawing.Size(0, 6)
    $bar.BackColor = $C.Good
    $bg.Controls.Add($bar)
    $p.Controls.AddRange([Windows.Forms.Control[]]@($t, $v, $bg))
    $form.Controls.Add($p)
    return @{ value = $v; bar = $bar; width = 202 }
}
function Set-Card($Card, $Text, $Pct) {
    $Card.value.Text = $Text
    $Pct = [math]::Max(0, [math]::Min(100, [double]$Pct))
    $Card.bar.Width = [int]($Card.width * $Pct / 100)
    $Card.bar.BackColor = $(if ($Pct -ge 85) { $C.Bad } elseif ($Pct -ge 60) { $C.Mid } else { $C.Good })
}
$cardCpu  = New-Card 20  'PROCESSEUR'
$cardRam  = New-Card 258 'MÉMOIRE'
$cardGpu  = New-Card 496 'CARTE GRAPHIQUE'
$cardVram = New-Card 734 'MÉMOIRE VIDÉO'

# --- Colonne gauche : profils
$form.Controls.Add((New-Label 'PROFILS' 20 170 200 18 $FontSmall $C.Dim))
$flow = New-Object Windows.Forms.FlowLayoutPanel
$flow.Location = New-Object Drawing.Point(20, 192)
$flow.Size = New-Object Drawing.Size(212, 250)
$flow.FlowDirection = 'TopDown'
$flow.WrapContents = $false
$flow.AutoScroll = $true
$form.Controls.Add($flow)

$btnRestore = New-Button 'Tout restaurer' 20 448 210 40 $C.Danger
$btnEdit    = New-Button 'Modifier les profils' 20 494 128 32 $C.Panel2
$btnReload  = New-Button 'Recharger' 154 494 76 32 $C.Panel2
$btnEdit.Font = $FontSmall; $btnReload.Font = $FontSmall
$form.Controls.AddRange([Windows.Forms.Control[]]@($btnRestore, $btnEdit, $btnReload))

# --- Panneau central : détail du profil
$mid = New-Object Windows.Forms.Panel
$mid.Location = New-Object Drawing.Point(245, 170)
$mid.Size = New-Object Drawing.Size(470, 356)
$mid.BackColor = $C.Panel
$lblName = New-Label 'Choisis un profil à gauche' 16 12 440 28 $FontTitle $C.Text
$lblDesc = New-Label 'Coche ou décoche les actions, puis applique.' 16 42 440 40 $FontUI $C.Dim
$clb = New-Object Windows.Forms.CheckedListBox
$clb.Location = New-Object Drawing.Point(16, 88)
$clb.Size = New-Object Drawing.Size(438, 210)
$clb.BackColor = $C.Panel
$clb.ForeColor = $C.Text
$clb.BorderStyle = 'None'
$clb.CheckOnClick = $true
$clb.IntegralHeight = $false
$btnApply = New-Button 'Appliquer le profil' 16 302 438 42 $C.Accent
$btnApply.Font = New-Object Drawing.Font('Segoe UI Semibold', 11)
$mid.Controls.AddRange([Windows.Forms.Control[]]@($lblName, $lblDesc, $clb, $btnApply))
$form.Controls.Add($mid)

# --- Panneau droit : programmes gourmands
$right = New-Object Windows.Forms.Panel
$right.Location = New-Object Drawing.Point(728, 170)
$right.Size = New-Object Drawing.Size(232, 356)
$right.BackColor = $C.Panel
$right.Controls.Add((New-Label 'TOP MÉMOIRE (Mo)' 12 10 200 18 $FontSmall $C.Dim))
$lv = New-Object Windows.Forms.ListView
$lv.Location = New-Object Drawing.Point(12, 32)
$lv.Size = New-Object Drawing.Size(208, 312)
$lv.View = 'Details'
$lv.HeaderStyle = 'None'
$lv.FullRowSelect = $true
$lv.BorderStyle = 'None'
$lv.BackColor = $C.Panel
$lv.ForeColor = $C.Text
[void]$lv.Columns.Add('Programme', 140)
[void]$lv.Columns.Add('Mo', 60, [Windows.Forms.HorizontalAlignment]::Right)
$right.Controls.Add($lv)
$form.Controls.Add($right)

# --- Journal
$form.Controls.Add((New-Label 'JOURNAL' 20 538 200 18 $FontSmall $C.Dim))
$logBox = New-Object Windows.Forms.RichTextBox
$logBox.Location = New-Object Drawing.Point(20, 558)
$logBox.Size = New-Object Drawing.Size(940, 116)
$logBox.BackColor = $C.Panel
$logBox.ForeColor = $C.Dim
$logBox.BorderStyle = 'None'
$logBox.ReadOnly = $true
$logBox.Font = $FontMono
$form.Controls.Add($logBox)
$script:LogBox = $logBox

# --- Logique de l'interface
$script:CurrentProfile = $null
$script:CurrentItems = $null

function Update-Status {
    $s = Get-State
    if ($s.exists) { $lblStatus.Text = "●  Profil actif : $($s.profile)  (depuis $($s.since))"; $lblStatus.ForeColor = $C.Good }
    else { $lblStatus.Text = "○  État normal, aucun profil actif"; $lblStatus.ForeColor = $C.Dim }
}

function Set-Busy([bool]$Busy) {
    $form.UseWaitCursor = $Busy
    $btnApply.Enabled = -not $Busy
    $btnRestore.Enabled = -not $Busy
    $flow.Enabled = -not $Busy
    [Windows.Forms.Application]::DoEvents()
}

function Select-Profile($Prof) {
    $script:CurrentProfile = $Prof
    $script:CurrentItems = Get-Items $Prof
    $lblName.Text = $Prof.name
    $lblDesc.Text = [string]$Prof.description
    $clb.Items.Clear()
    foreach ($it in $script:CurrentItems) { [void]$clb.Items.Add($it.label, [bool]$it.on) }
    foreach ($b in $flow.Controls) {
        $b.BackColor = $(if ($b.Tag.name -eq $Prof.name) { $C.Accent } else { $C.Panel2 })
    }
}

function Build-ProfileButtons {
    $flow.Controls.Clear()
    foreach ($p in @($script:Config.profiles)) {
        if (-not $p) { continue }
        $b = New-Button $p.name 0 0 206 46 $C.Panel2
        $b.Margin = New-Object Windows.Forms.Padding(0, 0, 0, 6)
        $b.TextAlign = 'MiddleLeft'
        $b.Padding = New-Object Windows.Forms.Padding(10, 0, 0, 0)
        $b.Font = New-Object Drawing.Font('Segoe UI Semibold', 10)
        $b.Tag = $p
        $b.Add_Click({ Select-Profile $this.Tag })
        $flow.Controls.Add($b)
    }
}

$btnApply.Add_Click({
    if (-not $script:CurrentProfile) { return }
    for ($i = 0; $i -lt $clb.Items.Count; $i++) { $script:CurrentItems[$i].on = $clb.GetItemChecked($i) }
    Set-Busy $true
    try { Invoke-Profile $script:CurrentProfile $script:CurrentItems }
    catch { Write-Log "Erreur : $($_.Exception.Message)" 'ERR' }
    Set-Busy $false
    Update-Status
})

$btnRestore.Add_Click({
    Set-Busy $true
    try { Restore-All -Relaunch } catch { Write-Log "Erreur : $($_.Exception.Message)" 'ERR' }
    Set-Busy $false
    Update-Status
})

$btnEdit.Add_Click({ Start-Process -FilePath 'notepad.exe' -ArgumentList "`"$ConfigPath`"" })

$btnReload.Add_Click({
    try {
        $script:Config = Read-Config
        $script:Protected = @($script:Config.protectedProcesses | Where-Object { $_ })
        Build-ProfileButtons
        Write-Log 'Profils rechargés.' 'OK'
        if ($script:CurrentProfile) {
            $same = $script:Config.profiles | Where-Object { $_.name -eq $script:CurrentProfile.name } | Select-Object -First 1
            if ($same) { Select-Profile $same }
        }
    } catch { Write-Log "profiles.json invalide : $($_.Exception.Message)" 'ERR' }
})

# --- Monitoring
$script:NvSmi = $null
$nv = Get-Command 'nvidia-smi.exe' -ErrorAction SilentlyContinue
if ($nv) { $script:NvSmi = $nv.Source }
elseif (Test-Path 'C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe') { $script:NvSmi = 'C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe' }
if (-not $script:NvSmi) { $cardGpu.value.Text = 'nvidia-smi absent'; $cardVram.value.Text = '—' }

function Update-Monitor {
    try {
        $cpu = (Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction Stop).PercentProcessorTime
        Set-Card $cardCpu ("{0} %" -f $cpu) $cpu
    } catch {}
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $tot  = $os.TotalVisibleMemorySize / 1MB
        $used = $tot - ($os.FreePhysicalMemory / 1MB)
        Set-Card $cardRam ("{0:N1} / {1:N0} Go" -f $used, $tot) ($used / $tot * 100)
    } catch {}
    if ($script:NvSmi) {
        try {
            $line = & $script:NvSmi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total --format=csv,noheader,nounits | Select-Object -First 1
            $v = @($line -split ',' | ForEach-Object { [double]($_.Trim()) })
            Set-Card $cardGpu ("{0} %  ·  {1} °C" -f $v[0], $v[1]) $v[0]
            Set-Card $cardVram ("{0:N1} / {1:N0} Go" -f ($v[2] / 1024), ($v[3] / 1024)) ($v[2] / $v[3] * 100)
        } catch {}
    }
    try {
        $top = Get-Process | Group-Object ProcessName | ForEach-Object {
            [pscustomobject]@{ Name = $_.Name; MB = [math]::Round((($_.Group | Measure-Object WorkingSet64 -Sum).Sum) / 1MB) }
        } | Sort-Object MB -Descending | Select-Object -First 14
        $lv.BeginUpdate()
        $lv.Items.Clear()
        foreach ($t in $top) {
            $item = New-Object Windows.Forms.ListViewItem([string]$t.Name)
            [void]$item.SubItems.Add([string]$t.MB)
            [void]$lv.Items.Add($item)
        }
        $lv.EndUpdate()
    } catch {}
}

# --- Mise à jour : vérification GitHub en arrière-plan (l'interface ne se fige pas)
$script:UpdPs = $null; $script:UpdAr = $null; $script:UpdT = $null
function Start-UpdateCheck {
    if (-not $HasUpd -or -not (Get-UpdConfig)) { return }
    $ps = [powershell]::Create()
    [void]$ps.AddScript('param($p) . $p; Test-Update').AddArgument($UpdScript)
    $script:UpdPs = $ps
    $script:UpdAr = $ps.BeginInvoke()
}
function Receive-UpdateCheck {
    if (-not $script:UpdAr -or -not $script:UpdAr.IsCompleted) { return }
    $r = $null
    try { $r = @($script:UpdPs.EndInvoke($script:UpdAr)) | Select-Object -Last 1 } catch {}
    $script:UpdPs.Dispose(); $script:UpdAr = $null
    if ($r -and $r.ok -and $r.available) {
        $script:UpdT = $r
        $btnUpdate.Text = "Mise à jour disponible ($($r.short)) : installer"
        $btnUpdate.Visible = $true
        Write-Log "Mise à jour disponible : $($r.message)" 'TITLE'
    } elseif ($r -and -not $r.ok -and $r.configured) {
        Write-Log "Mise à jour : $($r.error)" 'WARN'
    }
}
$btnUpdate.Add_Click({
    if (-not $script:UpdT) { return }
    $msg = "Installer la version $($script:UpdT.short) ?`n`n$($script:UpdT.message)`n`nPerfManager va redémarrer. Tes profils sont conservés."
    if ([Windows.Forms.MessageBox]::Show($msg, 'Mise à jour', 'YesNo', 'Question') -ne 'Yes') { return }
    Set-Busy $true
    try {
        $n = Install-Update $script:UpdT.sha $script:UpdT.message
        Write-Log "Mise à jour installée ($n fichiers), redémarrage…" 'OK'
        Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Self`""
        $form.Close()
    } catch {
        Write-Log "Mise à jour impossible : $($_.Exception.Message)" 'ERR'
        Set-Busy $false
    }
})

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 2500
$timer.Add_Tick({ Update-Monitor; Update-Status; Receive-UpdateCheck })

$form.Add_Shown({
    Build-ProfileButtons
    Update-Status
    Update-Monitor
    $timer.Start()
    Start-UpdateCheck
    $s = Get-State
    if ($s.exists) { Write-Log "Un profil est déjà actif (« $($s.profile) »). « Tout restaurer » remet le PC à la normale." 'WARN' }
    else { Write-Log 'Prêt. Choisis un profil à gauche.' }
})
$form.Add_FormClosing({ $timer.Stop() })

[void]$form.ShowDialog()
