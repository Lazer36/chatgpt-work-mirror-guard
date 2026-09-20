@echo off
rem Registers the auto-start-with-ChatGPT WMI subscription (asks for admin once).
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','%~dp0scripts\install-wmi-subscription.ps1'"
