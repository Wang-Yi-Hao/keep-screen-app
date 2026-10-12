@echo off
rem ============================================================
rem  Double-click this file to build the app (no PowerShell typing needed).
rem  It finds the .ps1 next to it and runs it with execution policy bypassed.
rem ============================================================
for %%f in ("%~dp0*.ps1") do powershell -NoProfile -ExecutionPolicy Bypass -File "%%~ff"
pause
