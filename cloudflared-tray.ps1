# Tray app: runs cloudflared hidden and shows the tunnel's status as a tray icon.
# Settings come from .env next to this script (see .env.example). Start it by running cloudflared-tray.exe
# (built by build-tray.ps1): it runs this script with no console window.
# The tray menu's "Start at login" writes the exe's path to HKCU\...\Run\CloudflareTunnel (no admin needed).

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe = Join-Path $dir 'cloudflared.exe'
$log = Join-Path $dir 'cloudflared.log'

function Fail($msg) {
    [System.Windows.Forms.MessageBox]::Show($msg, 'Cloudflare tunnel', 'OK', 'Warning') | Out-Null
    exit 1
}

# .env: KEY=VALUE lines; blank lines and # comments ignored.
$envFile = Join-Path $dir '.env'
if (-not (Test-Path $envFile)) { Fail ".env not found in $dir. Copy .env.example to .env and fill it in." }
$cfg = @{}
foreach ($line in Get-Content $envFile) {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') { $cfg[$matches[1]] = $matches[2].Trim('"') }
}
$token    = $cfg['TUNNEL_TOKEN']
$appName  = $(if ($cfg['APP_NAME']) { $cfg['APP_NAME'] } else { 'Cloudflare tunnel' })
$protocol = $(if ($cfg['TUNNEL_PROTOCOL']) { $cfg['TUNNEL_PROTOCOL'] } else { 'http2' })
$port     = $(if ($cfg['METRICS_PORT']) { [int]$cfg['METRICS_PORT'] } else { 20251 })   # cloudflared's local status port

# One copy only.
$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\TasksTunnelTray', [ref]$created)
if (-not $created) { exit }

if (-not (Test-Path $exe)) { Fail "cloudflared.exe not found in $dir" }
if (-not $token) { Fail "TUNNEL_TOKEN is empty in $envFile" }

# Keep the log small: past 5 MB, move it to cloudflared.log.old (replacing the previous one).
if ((Test-Path $log) -and (Get-Item $log).Length -gt 5MB) { Move-Item $log "$log.old" -Force }

# Stop copies of this cloudflared started some other way (e.g. by hand).
Get-Process cloudflared -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe } | Stop-Process -Force

$script:proc = $null
$script:wanted = $true          # false after "Stop tunnel": don't restart it
$script:state = ''
$script:lastStart = [datetime]::MinValue

function Start-Tunnel {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = "tunnel --protocol $protocol --metrics 127.0.0.1:$port --logfile `"$log`" run"
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables['TUNNEL_TOKEN'] = $token
    $script:lastStart = Get-Date
    $script:wanted = $true
    try { $script:proc = [System.Diagnostics.Process]::Start($psi) } catch { $script:proc = $null }
}

function Stop-Tunnel {
    $script:wanted = $false
    if ($script:proc -and -not $script:proc.HasExited) {
        $script:proc.Kill()
        $script:proc.WaitForExit(3000) | Out-Null
    }
}

function Test-Connected {
    try {
        $req = [System.Net.WebRequest]::Create("http://127.0.0.1:$port/ready")
        $req.Proxy = $null
        $req.Timeout = 1000
        $res = $req.GetResponse()
        $ok = ([int]$res.StatusCode -eq 200)
        $res.Close()
        return $ok
    } catch { return $false }
}

# Tray icons: cloudflared-tray.ico (the app's artwork, also embedded in the exe) scaled to the tray's
# own icon size (so Windows doesn't shrink it again). Connected shows the artwork as-is; connecting and
# stopped show it faded to gray, so the white cloud reads as gray on a dark taskbar.
$appIco = Join-Path $dir 'cloudflared-tray.ico'
if (-not (Test-Path $appIco)) { Fail "cloudflared-tray.ico not found in $dir" }
$traySize = [System.Windows.Forms.SystemInformation]::SmallIconSize.Width

# The largest image in the .ico. Read by hand: the .NET Framework Icon class (Windows PowerShell 5.1,
# which the exe hosts) can't decode PNG-compressed frames, and 256 px frames are usually PNG.
function Get-IcoArt {
    $bytes = [System.IO.File]::ReadAllBytes($appIco)
    $best = -1; $bestW = 0
    for ($i = 0; $i -lt [BitConverter]::ToUInt16($bytes, 4); $i++) {
        $w = $bytes[6 + 16 * $i]; if ($w -eq 0) { $w = 256 }
        if ($w -gt $bestW) { $bestW = $w; $best = $i }
    }
    $e = 6 + 16 * $best
    $size = [BitConverter]::ToInt32($bytes, $e + 8); $off = [BitConverter]::ToInt32($bytes, $e + 12)
    if ($bytes[$off] -eq 0x89 -and $bytes[$off + 1] -eq 0x50) {   # PNG signature
        $ms = New-Object System.IO.MemoryStream (, $bytes[$off..($off + $size - 1)])
        return New-Object System.Drawing.Bitmap $ms
    }
    return (New-Object System.Drawing.Icon $appIco, $bestW, $bestW).ToBitmap()
}

function New-TunnelIcon([double]$opacity) {
    $art = Get-IcoArt
    $bmp = New-Object System.Drawing.Bitmap $traySize, $traySize
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.PixelOffsetMode = 'HighQuality'
    # Grayscale + opacity. The artwork is black/white already; this keeps it gray if the .ico gains color.
    $m = New-Object System.Drawing.Imaging.ColorMatrix
    if ($opacity -lt 1) {
        foreach ($row in 0..2) { $m[$row, 0] = @(0.299, 0.587, 0.114)[$row]; $m[$row, 1] = $m[$row, 0]; $m[$row, 2] = $m[$row, 0] }
    }
    $m.Matrix33 = $opacity
    $attr = New-Object System.Drawing.Imaging.ImageAttributes
    $attr.SetColorMatrix($m)
    $rect = New-Object System.Drawing.Rectangle 0, 0, $traySize, $traySize
    $g.DrawImage($art, $rect, 0, 0, $art.Width, $art.Height, 'Pixel', $attr)
    $g.Dispose(); $attr.Dispose(); $art.Dispose()
    return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}

$iconOk   = New-TunnelIcon 1.0    # connected: full artwork
$iconWait = New-TunnelIcon 0.6    # connecting: half-faded gray
$iconOff  = New-TunnelIcon 0.35   # stopped: faded gray

# Tray icon and menu
$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon = $iconWait
$tray.Text = "${appName}: starting"
$tray.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$status = $menu.Items.Add('Tunnel: starting')
$status.Enabled = $false
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$toggle = $menu.Items.Add('Stop tunnel')
$restart = $menu.Items.Add('Restart tunnel')
$openLog = $menu.Items.Add('Open log')
$openDash = $menu.Items.Add('Open Cloudflare dashboard')
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$autoItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Start at login'
$menu.Items.Add($autoItem) | Out-Null
$exitItem = $menu.Items.Add('Exit')
$tray.ContextMenuStrip = $menu

function Update-Status {
    $running = ($script:proc -ne $null) -and (-not $script:proc.HasExited)
    if ($running -and (Test-Connected)) { $state = 'Connected' }
    elseif ($running)                   { $state = 'Connecting...' }
    elseif ($script:wanted)             { $state = 'Stopped, restarting...' }
    else                                { $state = 'Stopped' }

    $status.Text = "Tunnel: $state"
    $tray.Text = "${appName}: $state"
    $toggle.Text = $(if ($script:wanted) { 'Stop tunnel' } else { 'Start tunnel' })
    $tray.Icon = switch ($state) { 'Connected' { $iconOk } 'Connecting...' { $iconWait } default { $iconOff } }

    # Tell once when it drops, unless you stopped it.
    if ($script:state -eq 'Connected' -and $state -ne 'Connected' -and $script:wanted) {
        $tray.ShowBalloonTip(5000, $appName, "Tunnel: $state", 'Warning')
    }
    $script:state = $state
}

# "Start at login": a value under HKCU Run. Task Manager's Startup tab can disable it
# (StartupApproved\Run, odd first byte = disabled); that counts as off here too.
$runKey      = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$approvedKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
$runName     = 'CloudflareTunnel'
$runCmd      = "`"$(Join-Path $dir 'cloudflared-tray.exe')`""

function Test-AutoStart {
    $v = (Get-ItemProperty $runKey -Name $runName -ErrorAction SilentlyContinue).$runName
    if (-not $v) { return $false }
    $a = (Get-ItemProperty $approvedKey -Name $runName -ErrorAction SilentlyContinue).$runName
    return -not ($a -and ($a[0] % 2 -eq 1))
}

function Set-AutoStart([bool]$on) {
    Remove-ItemProperty $approvedKey -Name $runName -ErrorAction SilentlyContinue   # clear any Task Manager "disabled"
    if ($on) { New-ItemProperty $runKey -Name $runName -Value $runCmd -PropertyType String -Force | Out-Null }
    else     { Remove-ItemProperty $runKey -Name $runName -ErrorAction SilentlyContinue }
}

$autoItem.Add_Click({ Set-AutoStart (-not (Test-AutoStart)); $autoItem.Checked = Test-AutoStart })
$menu.Add_Opening({ $autoItem.Checked = Test-AutoStart })

$toggle.Add_Click({ if ($script:wanted) { Stop-Tunnel } else { Start-Tunnel }; Update-Status })
$restart.Add_Click({ Stop-Tunnel; Start-Tunnel; Update-Status })
$openLog.Add_Click({ if (Test-Path $log) { Start-Process notepad.exe "`"$log`"" } })
$openDash.Add_Click({ Start-Process 'https://dash.cloudflare.com' })
$tray.Add_DoubleClick({ $tray.ShowBalloonTip(3000, $appName, $status.Text, 'Info') })

# Every 5 s: refresh the status; restart cloudflared if it died (at most every 30 s).
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 5000
$timer.Add_Tick({
    $dead = ($script:proc -eq $null) -or $script:proc.HasExited
    if ($script:wanted -and $dead -and ((Get-Date) - $script:lastStart).TotalSeconds -ge 30) { Start-Tunnel }
    Update-Status
})

$exitItem.Add_Click({
    $timer.Stop()
    Stop-Tunnel
    $tray.Visible = $false
    $tray.Dispose()
    [System.Windows.Forms.Application]::Exit()
})

Start-Tunnel
Update-Status
$timer.Start()
[System.Windows.Forms.Application]::Run((New-Object System.Windows.Forms.ApplicationContext))
$mutex.ReleaseMutex()
