# uninstall-wmi-subscription.ps1  (run as ADMIN)
# Removes the auto-start-on-ChatGPT WMI subscription created by
# install-wmi-subscription.ps1. A guard that is currently running will
# exit by itself ~45s after ChatGPT closes, or stop it manually.

$ErrorActionPreference = "Stop"
$ns = "root\subscription"
Get-WmiObject -Namespace $ns -Class __EventFilter             -Filter "Name='ChatGPTMirrorGuardFilter'"   -ErrorAction SilentlyContinue | Remove-WmiObject
Get-WmiObject -Namespace $ns -Class CommandLineEventConsumer  -Filter "Name='ChatGPTMirrorGuardConsumer'" -ErrorAction SilentlyContinue | Remove-WmiObject
Get-WmiObject -Namespace $ns -Class __FilterToConsumerBinding -Filter "Name='ChatGPTMirrorGuardBinding'"  -ErrorAction SilentlyContinue | Remove-WmiObject
Write-Host "OK: auto-start subscription removed." -ForegroundColor Green
if (-not $NoPause) { Read-Host "Press Enter to close" | Out-Null }
