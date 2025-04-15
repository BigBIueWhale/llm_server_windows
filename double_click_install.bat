@echo off
:: Check if running with administrative privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting administrative privileges...
    :: Relaunch this script with admin rights
    powershell -Command "Start-Process '%~f0' -Verb runAs"
    exit /b
)

:: Change directory to the location of this batch file (in case it was double-clicked)
cd /d "%~dp0"

:: Run the PowerShell script with bypass of the execution policy
powershell -ExecutionPolicy Bypass -File "install.ps1"
