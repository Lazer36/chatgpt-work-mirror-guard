# uninstall-wmi-subscription.ps1  (run as ADMIN)
# Removes the auto-start-on-ChatGPT WMI subscription created by
# install-wmi-subscription.ps1. A guard that is currently running will
# exit by itself ~45s after ChatGPT closes, or stop it manually.
# Note: __FilterToConsumerBinding has no Name property on current builds;
# match the binding by its Filter reference instead.

$ErrorActionPreference = "Continue"
$ns = "root\subscription"

Get-WmiObject -Namespace $ns -Class __FilterToConsumerBinding -ErrorAction SilentlyContinue |
    Where-Object { $_.Filter -like '*ChatGPTMirrorGuard*' } |
    Remove-WmiObject
Get-WmiObject -Namespace $ns -Class CommandLineEventConsumer -Filter "Name='ChatGPTMirrorGuardConsumer'" -ErrorAction SilentlyContinue |
    Remove-WmiObject
Get-WmiObject -Namespace $ns -Class __EventFilter -Filter "Name='ChatGPTMirrorGuardFilter'" -ErrorAction SilentlyContinue |
    Remove-WmiObject

$b = Get-WmiObject -Namespace $ns -Class __FilterToConsumerBinding -ErrorAction SilentlyContinue |
     Where-Object { $_.Filter -like '*ChatGPTMirrorGuard*' }
if ($b) { Write-Host "WARNING: binding still present." -ForegroundColor Red }
else    { Write-Host "OK: auto-start subscription removed." -ForegroundColor Green }
if (-not $NoPause) { Read-Host "Press Enter to close" | Out-Null }
