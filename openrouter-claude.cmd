@echo off
rem openrouter-claude.cmd — cmd.exe shim that delegates to the PowerShell script.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0openrouter-claude.ps1" %*
