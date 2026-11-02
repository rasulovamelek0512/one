# IP Widget (Windows, PowerShell + WinForms). Python не нужен.
#
# Приватность:
#   * По умолчанию никаких сетевых запросов, телеметрии, логов и файлов.
#   * Сеть используется ТОЛЬКО для определения локации (запрос к ipwho.is,
#     сервис видит твой публичный IP). Это происходит:
#       - по нажатию кнопки "Локация (онлайн)";
#       - автоматически, если ты сам включил галочку "Автообновлять локацию"
#         (при смене локального адреса и раз в 10 минут). По умолчанию она выключена.
#   * Ничего не кэшируется и не сохраняется на диск.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function C($r, $g, $b) { [System.Drawing.Color]::FromArgb($r, $g, $b) }
$bg    = C 30 31 38
$fg    = C 232 233 238
$muted = C 139 143 163
$accent= C 91 140 255
$ok    = C 74 222 128
$warn  = C 251 191 36
$bad   = C 248 113 113

# --- Локальные адреса: читаются из ОС, трафик не генерируется ---
function Get-Info {
    $v4 = $null; $v6 = $null; $others = @()
    foreach ($nic in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        if ($nic.OperationalStatus -ne 'Up') { continue }
        if ($nic.NetworkInterfaceType -eq 'Loopback') { continue }
        $props = $nic.GetIPProperties()
        $gw = @($props.GatewayAddresses | Where-Object { $_.Address.ToString() -notin @('0.0.0.0', '::') })
        $hasGw = $gw.Count -gt 0
        foreach ($ua in $props.UnicastAddresses) {
            $a = $ua.Address
            if ($a.AddressFamily -eq 'InterNetwork') {
                $s = $a.ToString()
                if ($s.StartsWith('169.254')) { continue }
                if ($hasGw -and -not $v4) { $v4 = $s } else { $others += $s }
            }
            elseif ($a.AddressFamily -eq 'InterNetworkV6') {
                if ($a.IsIPv6LinkLocal -or $a.IsIPv6Teredo) { continue }
                if ($hasGw -and -not $v6) { $v6 = $a.ToString().Split('%')[0] }
            }
        }
    }
    $tz = [System.TimeZoneInfo]::Local
    $off = (Get-Date).ToString('zzz')
    [pscustomobject]@{
        V4 = $v4; V6 = $v6; Others = $others
        Host = $env:COMPUTERNAME
        Tz = "$($tz.Id) (UTC$off)"
    }
}

# --- Окно ---
$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = 'None'
$form.BackColor = $bg
$form.TopMost = $true
$form.ShowInTaskbar = $false
$form.StartPosition = 'Manual'
$form.Location = New-Object System.Drawing.Point(60, 60)
$form.Size = New-Object System.Drawing.Size(290, 264)

function New-Label($text, $x, $y, $w, $h, $font, $color) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.Size = New-Object System.Drawing.Size($w, $h)
    $l.Font = $font
    $l.ForeColor = $color
    $l.BackColor = $bg
    $l.AutoEllipsis = $true
    $form.Controls.Add($l)
    return $l
}

$fSmallB = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
$fBig    = New-Object System.Drawing.Font('Consolas', 18, [System.Drawing.FontStyle]::Bold)
$fMono   = New-Object System.Drawing.Font('Consolas', 9)
$fUi     = New-Object System.Drawing.Font('Segoe UI', 9)

$null      = New-Label 'ЛОКАЛЬНЫЙ IP' 14 10 200 16 $fSmallB $muted
$lblClose  = New-Label '✕' 262 8 20 18 $fUi $muted
$lblIp     = New-Label '…' 14 28 262 34 $fBig $fg
$lblV6     = New-Label '' 14 64 262 16 $fMono $muted
$lblHost   = New-Label '' 14 82 262 16 $fUi $muted
$lblOthers = New-Label '' 14 100 262 16 $fMono $muted
$lblTz     = New-Label '' 14 118 262 16 $fUi $muted
$lblLoc    = New-Label '' 14 138 262 34 $fMono $fg
$lblStatus = New-Label '● без сети наружу' 14 238 262 16 $fUi $ok

function New-Button($text, $x, $y, $w, $color) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.Size = New-Object System.Drawing.Size($w, 26)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.BackColor = $color
    $b.ForeColor = [System.Drawing.Color]::White
    $b.Font = $fUi
    $b.Cursor = 'Hand'
    $form.Controls.Add($b)
    return $b
}
$btnCopy = New-Button 'Копировать' 14 180 100 $accent
$btnLoc  = New-Button 'Локация (онлайн)' 122 180 154 (C 44 46 58)

# Галочка автообновления локации. По умолчанию ВЫКЛЮЧЕНА.
$chkAuto = New-Object System.Windows.Forms.CheckBox
$chkAuto.Text = 'Автообновлять локацию (онлайн)'
$chkAuto.Location = New-Object System.Drawing.Point(14, 210)
$chkAuto.Size = New-Object System.Drawing.Size(262, 22)
$chkAuto.Font = $fUi
$chkAuto.ForeColor = $fg
$chkAuto.BackColor = $bg
$chkAuto.Checked = $false
$chkAuto.Cursor = 'Hand'
$form.Controls.Add($chkAuto)

# Крестик скрывает окно в трей, полный выход: правый клик по иконке -> Выход
$lblClose.Cursor = 'Hand'
$lblClose.Add_Click({ $form.Hide() })

# --- Перетаскивание мышью ---
$script:startCur = $null
$script:startLoc = $null
$dragDown = {
    $script:startCur = [System.Windows.Forms.Cursor]::Position
    $script:startLoc = $form.Location
}
$dragMove = {
    param($s, $e)
    if ($e.Button -eq 'Left' -and $script:startCur) {
        $p = [System.Windows.Forms.Cursor]::Position
        $form.Location = New-Object System.Drawing.Point(
            ($script:startLoc.X + $p.X - $script:startCur.X),
            ($script:startLoc.Y + $p.Y - $script:startCur.Y))
    }
}
foreach ($c in @($form, $lblIp, $lblV6, $lblHost, $lblTz)) {
    $c.Add_MouseDown($dragDown)
    $c.Add_MouseMove($dragMove)
}

# --- Иконка в трее (рядом с часами) ---
function New-TrayIcon {
    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $brush = New-Object System.Drawing.SolidBrush $accent
    $g.FillEllipse($brush, 1, 1, 30, 30)
    $font = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = 'Center'
    $sf.LineAlignment = 'Center'
    $rect = New-Object System.Drawing.RectangleF(0, 1, 32, 32)
    $g.DrawString('IP', $font, [System.Drawing.Brushes]::White, $rect, $sf)
    $g.Dispose()
    return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}

$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon = New-TrayIcon
$tray.Text = 'IP виджет'
$tray.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miShow = $menu.Items.Add('Показать / скрыть')
$miCopy = $menu.Items.Add('Копировать IP')
$miExit = $menu.Items.Add('Выход')
$tray.ContextMenuStrip = $menu

function Switch-Form {
    if ($form.Visible) { $form.Hide() }
    else { $form.Show(); $form.Activate() }
}
$tray.Add_MouseClick({
    param($s, $e)
    if ($e.Button -eq 'Left') { Switch-Form }
})
$miShow.Add_Click({ Switch-Form })
$miCopy.Add_Click({
    if ($lblIp.Text -match '^\d') { [System.Windows.Forms.Clipboard]::SetText($lblIp.Text) }
})
$miExit.Add_Click({ $form.Close() })

# --- Локация (ОНЛАЙН). Запрос идёт в фоне, окно не зависает ---
$script:job = $null
$script:lastLookup = [datetime]::MinValue

function Start-Lookup {
    if ($script:job) { return }
    $script:lastLookup = Get-Date
    $lblLoc.ForeColor = $muted
    $lblLoc.Text = 'Запрос к ipwho.is…'
    $lblStatus.Text = '● идёт запрос в сеть'
    $lblStatus.ForeColor = $warn
    $script:job = Start-Job -ScriptBlock {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-RestMethod -Uri 'https://ipwho.is/' -TimeoutSec 6 -ErrorAction Stop
    }
}

function Complete-Lookup {
    if (-not $script:job) { return }
    if ($script:job.State -eq 'Running' -or $script:job.State -eq 'NotStarted') { return }
    $j = $script:job
    $script:job = $null
    try {
        $d = Receive-Job $j -ErrorAction Stop
        if (-not $d.success) { throw 'fail' }
        $place = (@($d.city, $d.country) | Where-Object { $_ }) -join ', '
        $lblLoc.Text = "Публичный IP: $($d.ip)`n$place"
    }
    catch {
        $lblLoc.Text = 'Не удалось определить'
    }
    Remove-Job $j -Force -ErrorAction SilentlyContinue
    $lblLoc.ForeColor = $fg
    $lblStatus.Text = '● запрос отправлен в ' + (Get-Date).ToString('HH:mm')
    $lblStatus.ForeColor = $warn
}

$btnLoc.Add_Click({ Start-Lookup })

$chkAuto.Add_CheckedChanged({
    if ($chkAuto.Checked) { Start-Lookup }
    elseif ($script:lastLookup -eq [datetime]::MinValue) {
        $lblStatus.Text = '● без сети наружу'
        $lblStatus.ForeColor = $ok
    }
})

# --- Обновление локальных данных (офлайн) ---
$script:last = $null
function Update-Info {
    $i = Get-Info
    if ($i.V4) { $lblIp.Text = $i.V4; $lblIp.ForeColor = $fg }
    else       { $lblIp.Text = 'Нет сети'; $lblIp.ForeColor = $bad }
    $lblV6.Text   = if ($i.V6) { "IPv6: $($i.V6)" } else { 'IPv6: —' }
    $lblHost.Text = "Хост: $($i.Host)"
    $lblTz.Text   = "Пояс: $($i.Tz)"
    $rest = @($i.Others | Where-Object { $_ -ne $i.V4 })
    $lblOthers.Text = if ($rest.Count) { 'Ещё: ' + ($rest -join ', ') } else { '' }
    $tray.Text = if ($i.V4) { "IP: $($i.V4)" } else { 'Нет сети' }

    $changed = ($script:last -and $script:last -ne $lblIp.Text)
    if ($changed) {
        $lblStatus.Text = '● адрес изменился'
        $lblStatus.ForeColor = $warn
    }
    $script:last = $lblIp.Text

    if ($chkAuto.Checked) {
        $old = ((Get-Date) - $script:lastLookup).TotalMinutes -ge 10
        if (($changed -and $lblIp.Text -match '^\d') -or $old) { Start-Lookup }
    }
}

$btnCopy.Add_Click({
    if ($lblIp.Text -match '^\d') {
        [System.Windows.Forms.Clipboard]::SetText($lblIp.Text)
        $btnCopy.Text = 'Скопировано ✓'
        $t = New-Object System.Windows.Forms.Timer
        $t.Interval = 1200
        $t.Add_Tick({ $btnCopy.Text = 'Копировать'; $t.Stop(); $t.Dispose() })
        $t.Start()
    }
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 5000
$timer.Add_Tick({ Update-Info })

$poll = New-Object System.Windows.Forms.Timer
$poll.Interval = 300
$poll.Add_Tick({ Complete-Lookup })

$form.Add_FormClosed({
    $tray.Visible = $false
    $tray.Dispose()
    Get-Job | Remove-Job -Force -ErrorAction SilentlyContinue
})

Update-Info
$timer.Start()
$poll.Start()
[System.Windows.Forms.Application]::Run($form)
