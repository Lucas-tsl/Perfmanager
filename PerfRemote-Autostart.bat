@echo off
rem Double-clic : PerfDeck Remote demarre tout seul a chaque ouverture de session Windows.
rem Pour l'enlever : ouvrir une invite de commandes ici et taper  PerfRemote-Autostart.bat retirer
if /i "%~1"=="retirer" (
  start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PerfRemote.ps1" -RemoveAutostart
) else (
  start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PerfRemote.ps1" -InstallAutostart
)
