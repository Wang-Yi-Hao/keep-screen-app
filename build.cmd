@echo off
chcp 65001
rem 默认执行真机/发布版构建脚本
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0一键构建（真机）.ps1"
pause
