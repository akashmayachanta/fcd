# Shows the tunnel and the Workers VPC service as Cloudflare sees them.
#   .\cloudflare\status.ps1
. "$PSScriptRoot\env.ps1"

$tunnel = $(if ($Cfg['TUNNEL_ID']) { $Cfg['TUNNEL_ID'] } else { $Cfg['TUNNEL_NAME'] })
Write-Host "=== Tunnel $tunnel"
Write-Host (Invoke-Wrangler tunnel info $tunnel)

if ($Cfg['VPC_SERVICE_ID']) {
    Write-Host "=== VPC service $($Cfg['VPC_SERVICE_ID'])"
    Write-Host (Invoke-Wrangler vpc service get $Cfg['VPC_SERVICE_ID'])
} else {
    Write-Host '=== VPC services (VPC_SERVICE_ID not set in .env)'
    Write-Host (Invoke-Wrangler vpc service list)
}
