@echo off
rem Lanza Win11-Privacidad.ps1 como administrador sin cambiar la politica de ejecucion del sistema.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0Win11-Privacidad.ps1\"'"
