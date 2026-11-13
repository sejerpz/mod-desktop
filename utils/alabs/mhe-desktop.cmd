@echo off
rem alabs-mod-desktop - MOD Desktop with an emulated controller, see mhe-desktop.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0mhe-desktop.ps1" %*
