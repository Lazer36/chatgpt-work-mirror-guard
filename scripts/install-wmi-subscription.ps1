# install-wmi-subscription.ps1  (run as ADMIN, once)
#
# Registers a WMI permanent subscription in root\subscription:
#   when the ChatGPT desktop app starts (a "codex.exe" process appears),
#   Windows automatically launches the mirror guard (watch-codex-mirror.ps1,
#   hidden). The guard self-exits ~45s after ChatGPT closes, so nothing
#   lingers while you are not using ChatGPT.
#
# Implementation note: the binding is registered via mofcomp, NOT via
# Set-WmiInstance -Class __FilterToConsumerBinding. On recent Windows 11
# builds Set-WmiInstance silently returns nothing for that association
# class (and the class has no Name property, so query-by-Name fails too).
# mofcomp is the reliable path.
#
# To undo: run uninstall-wmi-subscription.ps1 (also as ADMIN).

$ErrorActionPreference = "Stop"

$here      = Split-Path -Parent $MyInvocation.MyCommand.Path
$guardPath = Join-Path $here "watch-codex-mirror.ps1"
if (-not (Test-Path $guardPath)) { throw "watch-codex-mirror.ps1 not found next to this script." }

# The WMI consumer runs as SYSTEM, where %USERPROFILE% differs from yours,
# so bake the installing (admin) user's real profile into the arguments.
$userProfile = [Environment]::GetFolderPath("UserProfile")
$mirrorRoot  = Join-Path $userProfile ".codex\.chatgpt-projects"
$logPath     = Join-Path $userProfile "Documents\chatgpt-work-mirror-guard\guard.log"
New-Item -ItemType Directory -Path (Split-Path -Parent $logPath) -Force | Out-Null

$cmd = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -NoPause -MirrorRoot "{1}" -LogPath "{2}"' -f $guardPath, $mirrorRoot, $logPath
$esc = { param($s) $s.Replace('\', '\\').Replace('"', '\"') }

# Build the MOF (escape \ and " for MOF string literals; keep `$F refs literal)
$mof = @"
#PRAGMA AUTORECOVER
#pragma namespace("\\\\.\\root\\subscription")

instance of __EventFilter as `$F
{
    Name = "ChatGPTMirrorGuardFilter";
    EventNamespace = "root\\cimv2";
    QueryLanguage = "WQL";
    Query = "SELECT * FROM __InstanceCreationEvent WITHIN 5 WHERE TargetInstance ISA 'Win32_Process' AND TargetInstance.Name = 'codex.exe'";
};

instance of CommandLineEventConsumer as `$C
{
    Name = "ChatGPTMirrorGuardConsumer";
    CommandLineTemplate = "$( & $esc $cmd )";
};

instance of __FilterToConsumerBinding
{
    Filter = `$F;
    Consumer = `$C;
};
"@
$mofPath = Join-Path $env:TEMP "ChatGPTMirrorGuard.mof"
$mof | Out-File -FilePath $mofPath -Encoding ascii

$mofcomp = Join-Path $env:SystemRoot "System32\wbem\mofcomp.exe"
$out = & $mofcomp -N:root\subscription $mofPath 2>&1
Write-Host (($out | Out-String).Trim())

Start-Sleep -Seconds 2
$f = Get-WmiObject -Namespace root\subscription -Class __EventFilter             -Filter "Name='ChatGPTMirrorGuardFilter'"   -ErrorAction SilentlyContinue
$c = Get-WmiObject -Namespace root\subscription -Class CommandLineEventConsumer  -Filter "Name='ChatGPTMirrorGuardConsumer'" -ErrorAction SilentlyContinue
$b = Get-WmiObject -Namespace root\subscription -Class __FilterToConsumerBinding -ErrorAction SilentlyContinue |
     Where-Object { $_.Filter -like '*ChatGPTMirrorGuard*' }

if ($f -and $c -and $b) {
    Write-Host ""
    Write-Host "OK: the mirror guard will auto-start (hidden) whenever ChatGPT starts," -ForegroundColor Green
    Write-Host "and will exit by itself about 45 seconds after ChatGPT closes."
    Write-Host "Uninstall with: uninstall-wmi-subscription.ps1"
} else {
    throw "Registration incomplete (filter=$([bool]$f) consumer=$([bool]$c) binding=$([bool]$b)). See mofcomp output above."
}
if (-not $NoPause) { Read-Host "Press Enter to close" | Out-Null }
