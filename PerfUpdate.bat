@echo off
rem Double-clic : enregistre ta cle GitHub (une seule fois) et installe la derniere version.
rem Pour changer de cle : ouvrir une invite de commandes ici et taper  PerfUpdate.bat -Setup
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PerfUpdate.ps1" %*
