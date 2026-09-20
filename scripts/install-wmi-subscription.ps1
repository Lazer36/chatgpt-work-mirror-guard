# install-wmi-subscription.ps1  (run as ADMIN, once)
#
# Registers a WMI permanent subscription in root\subscription:
#   when the ChatGPT desktop app starts (a "codex.exe" process appears),
#   Windows automatically launches the mirror guard (watch-codex-mirror.ps1,
#   hidden). The guard self-exits ~45s after ChatGPT closes, so nothing
#   lingers while you are not using ChatGPT.
#
# To undo: run uninstall-wmi-subscription.ps1 (also as ADMIN).

$ErrorActionPreference = "Stop"

$here       = Split-Path -Parent $MyInvocation.MyCommand.Path
$guardPath  = Join-Path $here "watch-codex-mirror.ps1"
if (-not (Test-Path $guardPath)) { throw "watch-codex-mirror.ps1 not found next to this script." }

# The WMI consumer runs as SYSTEM, where %USERPROFILE% differs from yours,
# so bake the installing (admin) user's real profile into the arguments.
$userProfile = [Environment]::GetFolderPath("UserProfile")
$argsLine = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$guardPath`" -NoPause " +
            "-MirrorRoot `"$userProfile\.codex\.chatgpt-projects`" " +
            "-LogPath `"$userProfile\Documents\chatgpt-work-mirror-guard\guard.log`""

$ns = "root\subscription"
Get-WmiObject -Namespace $ns -Class __EventFilter             -Filter "Name='ChatGPTMirrorGuardFilter'"   | Remove-WmiObject
Get-WmiObject -Namespace $ns -Class CommandLineEventConsumer  -Filter "Name='ChatGPTMirrorGuardConsumer'" | Remove-WmiObject
Get-WmiObject -Namespace $ns -Class __FilterToConsumerBinding -Filter "Name='ChatGPTMirrorGuardBinding'"  | Remove-WmiObject

$flt = Set-WmiInstance -Namespace $ns -Class __EventFilter -Arguments @{
    Name           = "ChatGPTMirrorGuardFilter"
    EventNamespace = "root\cimv2"
    QueryLanguage  = "WQL"
    Query          = "SELECT * FROM __InstanceCreationEvent WITHIN 5 WHERE TargetInstance ISA 'Win32_Process' AND TargetInstance.Name = 'codex.exe'"
}

$cns = Set-WmiInstance -Namespace $ns -Class CommandLineEventConsumer -Arguments @{
    Name                = "ChatGPTMirrorGuardConsumer"
    CommandLineTemplate = "powershell.exe $argsLine"
}

$bin = Set-WmiInstance -Namespace $ns -Class __FilterToConsumerBinding -Arguments @{
    Name     = "ChatGPTMirrorGuardBinding"
    Filter   = $flt
    Consumer = $cns
}

Write-Host ""
Write-Host "OK: the mirror guard will auto-start (hidden) whenever ChatGPT starts," -ForegroundColor Green
Write-Host "and will exit by itself about 45 seconds after ChatGPT closes."
Write-Host "Uninstall with: uninstall-wmi-subscription.ps1"
if (-not $NoPause) { Read-Host "Press Enter to close" | Out-Null }
