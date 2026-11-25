# Creates the Cloudflare side with wrangler: the tunnel, then the Workers VPC service that routes
# through it. Safe to re-run: anything whose ID is already in .env is skipped.
# Needs Node.js (for npx) and a wrangler login: run `npx wrangler login` once.
#
#   .\cloudflare\setup.ps1
. "$PSScriptRoot\env.ps1"

Write-Host 'Checking wrangler login...'
$who = Invoke-Wrangler whoami
if ($who -match 'not (logged|authenticated)') { throw 'Not logged in. Run: npx wrangler login' }
if (-not $Cfg['CLOUDFLARE_ACCOUNT_ID']) {
    $acct = [regex]::Match($who, '[0-9a-f]{32}').Value
    if ($acct) { Set-DotEnvValue CLOUDFLARE_ACCOUNT_ID $acct; $env:CLOUDFLARE_ACCOUNT_ID = $acct }
}

# 1. Tunnel
$tunnelName = $Cfg['TUNNEL_NAME']
if (-not $tunnelName) { throw 'TUNNEL_NAME is empty in .env' }
$tunnelId = $Cfg['TUNNEL_ID']
if ($tunnelId) {
    Write-Host "Tunnel: using $tunnelName ($tunnelId) from .env"
} else {
    $existing = Invoke-Wrangler tunnel list
    if ($existing -match "\b$([regex]::Escape($tunnelName))\b") {
        Write-Host "Tunnel: $tunnelName already exists, reading its ID"
        $out = Invoke-Wrangler tunnel info $tunnelName
    } else {
        Write-Host "Tunnel: creating $tunnelName"
        $out = Invoke-Wrangler tunnel create $tunnelName
    }
    Write-Host $out
    $tunnelId = @(Get-Uuids $out)[0]
    if (-not $tunnelId) { throw 'Could not find the tunnel ID in the output above; put it in .env as TUNNEL_ID.' }
    Set-DotEnvValue TUNNEL_ID $tunnelId
}

# 2. Workers VPC service: lets a Worker call VPC_SERVICE_HOSTNAME:VPC_SERVICE_HTTP_PORT on this PC through the tunnel.
if ($Cfg['VPC_SERVICE_ID']) {
    Write-Host "VPC service: using $($Cfg['VPC_SERVICE_ID']) from .env"
} else {
    $name = $Cfg['VPC_SERVICE_NAME']; $hostName = $Cfg['VPC_SERVICE_HOSTNAME']; $port = $Cfg['VPC_SERVICE_HTTP_PORT']
    if (-not ($name -and $hostName -and $port)) { throw 'Set VPC_SERVICE_NAME, VPC_SERVICE_HOSTNAME and VPC_SERVICE_HTTP_PORT in .env' }
    Write-Host "VPC service: creating $name -> http://${hostName}:$port via tunnel $tunnelId"
    # An IP address (e.g. 127.0.0.1) goes in --ipv4/--ipv6; anything else is a DNS name for --hostname.
    $ip = $null
    $hostFlag = if (-not [System.Net.IPAddress]::TryParse($hostName, [ref]$ip)) { '--hostname' }
                elseif ($ip.AddressFamily -eq 'InterNetworkV6') { '--ipv6' } else { '--ipv4' }
    $out = Invoke-Wrangler vpc service create $name --type http --tunnel-id $tunnelId $hostFlag $hostName --http-port $port
    Write-Host $out
    $serviceId = @(Get-Uuids $out | Where-Object { $_ -ne $tunnelId })[0]
    if (-not $serviceId) { throw 'Could not find the service ID in the output above; put it in .env as VPC_SERVICE_ID.' }
    Set-DotEnvValue VPC_SERVICE_ID $serviceId
}

$Cfg = Read-DotEnv
Write-Host ''
Write-Host 'Done. Next:'
if (-not $Cfg['TUNNEL_TOKEN']) {
    Write-Host '  - Put the tunnel token in .env as TUNNEL_TOKEN (dashboard: Zero Trust > Networks > Tunnels >'
    Write-Host "    $tunnelName > Configure; the string after --token)."
}
Write-Host '  - In the Worker''s wrangler config, bind the VPC service:'
Write-Host "      `"vpc_services`": [{ `"binding`": `"TASKS`", `"service_id`": `"$($Cfg['VPC_SERVICE_ID'])`" }]"
Write-Host '  - Start cloudflared-tray.exe.'
