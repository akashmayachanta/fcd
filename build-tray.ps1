# Builds cloudflared-tray.exe (uses the .NET Framework compiler built into Windows).
# The exe is a tiny host for cloudflared-tray.ps1: its C# source is below, written to a temp file only while compiling.
# The exe's publisher comes from APP_PUBLISHER in .env (default "Cloudflared Tray"); rebuild after changing it.
# If this folder's tray app is running, it is stopped for the build and started again afterwards.
# The app icon is cloudflared-tray.ico (the one source of the artwork; the tray script uses it too).
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ico = Join-Path $dir 'cloudflared-tray.ico'
$cs  = Join-Path $env:TEMP 'cloudflared-tray.cs'    # build-time only, then deleted

# Publisher shown in Task Manager, file properties and error boxes: APP_PUBLISHER in .env, if set.
$publisher = 'Cloudflared Tray'
$envFile = Join-Path $dir '.env'
if (Test-Path $envFile) {
    foreach ($line in Get-Content $envFile) {
        if ($line -match '^\s*APP_PUBLISHER\s*=\s*(.*?)\s*$' -and $matches[1].Trim('"')) { $publisher = $matches[1].Trim('"') }
    }
}
$publisherCs = $publisher.Replace('\', '\\').Replace('"', '\"')    # escaped for a C# string literal

# Host program: runs cloudflared-tray.ps1 in-process (STA, execution policy Bypass, no console window),
# so Task Manager shows this exe's name and publisher instead of "Console Window Host" / "Windows PowerShell".
Set-Content $cs -Encoding UTF8 -Value (@'
using System;
using System.IO;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;
using System.Management.Automation;
using System.Management.Automation.Runspaces;

[assembly: AssemblyTitle("__PUBLISHER__")]
[assembly: AssemblyProduct("__PUBLISHER__")]
[assembly: AssemblyCompany("__PUBLISHER__")]
[assembly: AssemblyCopyright("__PUBLISHER__")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

static class Program
{
    [STAThread]
    static int Main()
    {
        string dir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
        string script = Path.Combine(dir, "cloudflared-tray.ps1");
        if (!File.Exists(script))
        {
            MessageBox.Show("cloudflared-tray.ps1 not found in " + dir, "__PUBLISHER__");
            return 1;
        }

        var iss = InitialSessionState.CreateDefault();
        iss.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
        using (var rs = RunspaceFactory.CreateRunspace(iss))
        {
            rs.ApartmentState = ApartmentState.STA;
            rs.ThreadOptions = PSThreadOptions.UseCurrentThread;
            rs.Open();
            using (var ps = PowerShell.Create())
            {
                ps.Runspace = rs;
                ps.AddCommand(script);
                try { ps.Invoke(); }
                catch (Exception e) { MessageBox.Show(e.Message, "__PUBLISHER__"); return 1; }
            }
        }
        return 0;
    }
}
'@).Replace('__PUBLISHER__', $publisherCs)

$out = Join-Path $dir 'cloudflared-tray.exe'

# A running tray app locks the exe: stop this folder's copy (and its cloudflared) now, start it again after the build.
$running = @(Get-Process cloudflared-tray -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $out })
if ($running) {
    Write-Host 'Stopping the running tray app...'
    $running | Stop-Process -Force
    $running | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue
    Get-Process cloudflared -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -eq (Join-Path $dir 'cloudflared.exe') } | Stop-Process -Force
}

$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$sma = (Get-ChildItem "$env:WINDIR\Microsoft.NET\assembly\GAC_MSIL\System.Management.Automation" -Recurse -Filter System.Management.Automation.dll | Select-Object -First 1).FullName
& $csc /nologo /target:winexe /optimize+ "/out:$out" "/win32icon:$ico" `
    "/reference:$sma" /reference:System.Windows.Forms.dll $cs
$code = $LASTEXITCODE
Remove-Item $cs -ErrorAction SilentlyContinue

# Restart the tray app if it was running, even if the build failed (the old exe is still there then).
if ($running -and (Test-Path $out)) { Write-Host 'Starting the tray app again.'; Start-Process $out -WorkingDirectory $dir }
if ($code) { throw "csc failed ($code)" }
Write-Host "Built $out (publisher: $publisher)"
