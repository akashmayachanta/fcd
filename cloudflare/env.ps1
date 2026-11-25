# Shared helpers for the Cloudflare setup scripts. Dot-source it: . "$PSScriptRoot\env.ps1"
# Reads ..\.env, exports CLOUDFLARE_ACCOUNT_ID for wrangler, and wraps `npx wrangler`.

$Root    = Split-Path -Parent $PSScriptRoot
$EnvFile = Join-Path $Root '.env'
if (-not (Test-Path $EnvFile)) { throw ".env not found in $Root. Copy .env.example to .env first." }

function Read-DotEnv {
    $cfg = @{}
    foreach ($line in Get-Content $EnvFile) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') { $cfg[$matches[1]] = $matches[2].Trim('"') }
    }
    return $cfg
}

# Sets KEY=value in .env, keeping every other line (and its comments) as it is.
function Set-DotEnvValue([string]$key, [string]$value) {
    $lines = @(Get-Content $EnvFile)
    $found = $false
    $lines = $lines | ForEach-Object {
        if ($_ -match "^\s*$key\s*=") { $found = $true; "$key=$value" } else { $_ }
    }
    if (-not $found) { $lines += "$key=$value" }
    Set-Content $EnvFile $lines
    Write-Host "  .env: $key=$value"
}

# Runs wrangler (pinned to major version 4) and returns its output as text; throws on failure.
function Invoke-Wrangler {
    # npx.cmd, not npx.ps1, with $args copied first: splatting @args into npx.ps1 drops every argument.
    $wranglerArgs = $args
    $out = & npx.cmd --yes wrangler@4 @wranglerArgs 2>&1 | Out-String
    if ($LASTEXITCODE) { Write-Host $out; throw "wrangler $($args -join ' ') failed ($LASTEXITCODE)" }
    return $out
}

function Get-Uuids([string]$text) {
    return [regex]::Matches($text, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}') | ForEach-Object Value
}

$Cfg = Read-DotEnv
if ($Cfg['CLOUDFLARE_ACCOUNT_ID']) { $env:CLOUDFLARE_ACCOUNT_ID = $Cfg['CLOUDFLARE_ACCOUNT_ID'] }
