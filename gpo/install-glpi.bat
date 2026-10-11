@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "\\empresa.local\netlogon\scripts\GLPI\Install-GLPIAgent.ps1"
exit /b 0