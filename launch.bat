@echo off
title OpenRelax PC Care
cd /d "%~dp0"
start /b powershell -WindowStyle Hidden -STA -NoProfile -ExecutionPolicy Bypass -File "%~dp0openrelax.ps1"
exit
