@echo off
setlocal EnableDelayedExpansion
title Windows Update ^& Auto-Reboot Control Tool

:: ============================================================================
:: 0. Administrator Privileges Check and Self-Elevation
:: ============================================================================
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ======================================================================
    echo  Requesting Administrator Privileges...
    echo ======================================================================
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"

:: ============================================================================
:: Main Interactive Menu Loop
:: ============================================================================
:MENU_LOOP
cls
call :CHECK_STATUS

echo ======================================================================
echo           Windows Update ^& Auto-Reboot Control Tool
echo ======================================================================
echo  Supported OS: Windows 10 / 11 (Home, Pro, Enterprise, Education)
echo.
echo  [CURRENT SYSTEM STATUS]
echo  - Windows Update : [!WU_STATUS!]
echo  - Auto-Reboot    : [!REBOOT_STATUS!]
echo ======================================================================
echo.
echo   [1] Disable Windows Update ^& Block Auto-Reboot
echo   [2] Allow Windows Update ^& Block Auto-Reboot
echo   [3] Restore Defaults (Allow Update ^& Allow Auto-Reboot)
echo.
echo   [0] Exit
echo.
echo ======================================================================
set "CHOICE="
set /p CHOICE=" Enter choice [0-3]: "

if "%CHOICE%"=="1" goto :MODE_1
if "%CHOICE%"=="2" goto :MODE_2
if "%CHOICE%"=="3" goto :MODE_3
if "%CHOICE%"=="0" goto :EXIT_SCRIPT

echo.
echo  [!] Invalid choice. Please enter a valid number (0, 1, 2, or 3).
timeout /t 2 >nul
goto :MENU_LOOP

:: ============================================================================
:: Status Check Routine
:: ============================================================================
:CHECK_STATUS
set "WU_STATUS=ENABLED"
set "REBOOT_STATUS=ALLOWED"

:: Check Windows Update Status (wuauserv start type or AU policy)
for /f "tokens=3" %%a in ('sc.exe qc wuauserv 2^>nul ^| findstr /i "START_TYPE"') do (
    if "%%a"=="4" set "WU_STATUS=DISABLED"
)
for /f "tokens=3" %%a in ('reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "NoAutoUpdate" 2^>nul ^| findstr /i "NoAutoUpdate"') do (
    if "%%a"=="0x1" set "WU_STATUS=DISABLED"
)

:: Check Auto-Reboot Status
for /f "tokens=3" %%a in ('reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "NoAutoRebootWithLoggedOnUsers" 2^>nul ^| findstr /i "NoAutoRebootWithLoggedOnUsers"') do (
    if "%%a"=="0x1" set "REBOOT_STATUS=BLOCKED"
)
goto :eof

:: ============================================================================
:: Mode 1: Disable Windows Update & Block Auto-Reboot
:: ============================================================================
:MODE_1
cls
echo ======================================================================
echo  Applying: Mode 1 - Disable Windows Update ^& Block Auto-Reboot
echo ======================================================================
echo.

echo [*] Configuring Policy Registries for Windows Update...
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "NoAutoUpdate" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "AUOptions" /t REG_DWORD /d 1 /f >nul

echo [*] Stopping and Disabling Windows Update Services...
net stop wuauserv /y >nul 2>&1
sc.exe config wuauserv start=disabled >nul 2>&1
net stop UsoSvc /y >nul 2>&1
sc.exe config UsoSvc start=disabled >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" /v "Start" /t REG_DWORD /d 4 /f >nul 2>&1
net stop WaaSMedicSvc /y >nul 2>&1

echo [*] Configuring Registry to Block Auto-Reboot...
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "NoAutoRebootWithLoggedOnUsers" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "AUPowerManagement" /t REG_DWORD /d 0 /f >nul
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v "AlwaysAutoRebootAtScheduledTime" /t REG_DWORD /d 0 /f >nul

echo [*] Disabling Scheduled Reboot Tasks...
schtasks /change /tn "\Microsoft\Windows\UpdateOrchestrator\Reboot" /disable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\UpdateOrchestrator\Reboot_AC" /disable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\UpdateOrchestrator\Reboot_Battery" /disable >nul 2>&1

echo.
echo  [+] Mode 1 applied successfully!
echo.
pause
goto :MENU_LOOP

:: ============================================================================
:: Mode 2: Allow Windows Update & Block Auto-Reboot
:: ============================================================================
:MODE_2
cls
echo ======================================================================
echo  Applying: Mode 2 - Allow Windows Update ^& Block Auto-Reboot
echo ======================================================================
echo.

echo [*] Configuring Policy Registries for Windows Update...
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "NoAutoUpdate" /t REG_DWORD /d 0 /f >nul
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "AUOptions" /t REG_DWORD /d 2 /f >nul

echo [*] Restoring Windows Update Services to Active state...
sc.exe config wuauserv start=demand >nul 2>&1
net start wuauserv >nul 2>&1
sc.exe config UsoSvc start=delayed-auto >nul 2>&1 || sc.exe config UsoSvc start=auto >nul 2>&1
net start UsoSvc >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" /v "Start" /t REG_DWORD /d 3 /f >nul 2>&1

echo [*] Configuring Registry to Block Auto-Reboot...
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "NoAutoRebootWithLoggedOnUsers" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "AUPowerManagement" /t REG_DWORD /d 0 /f >nul
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v "AlwaysAutoRebootAtScheduledTime" /t REG_DWORD /d 0 /f >nul

echo [*] Disabling Scheduled Reboot Tasks...
schtasks /change /tn "\Microsoft\Windows\UpdateOrchestrator\Reboot" /disable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\UpdateOrchestrator\Reboot_AC" /disable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\UpdateOrchestrator\Reboot_Battery" /disable >nul 2>&1

echo.
echo  [+] Mode 2 applied successfully!
echo.
pause
goto :MENU_LOOP

:: ============================================================================
:: Mode 3: Restore Defaults (Allow Update & Allow Auto-Reboot)
:: ============================================================================
:MODE_3
cls
echo ======================================================================
echo  Applying: Mode 3 - Restore Defaults (Allow Update ^& Allow Auto-Reboot)
echo ======================================================================
echo.

echo [*] Removing Custom Update Policies...
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "NoAutoUpdate" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "AUOptions" /f >nul 2>&1

echo [*] Restoring Default Service Configurations...
sc.exe config wuauserv start=demand >nul 2>&1
net start wuauserv >nul 2>&1
sc.exe config UsoSvc start=delayed-auto >nul 2>&1 || sc.exe config UsoSvc start=auto >nul 2>&1
net start UsoSvc >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" /v "Start" /t REG_DWORD /d 3 /f >nul 2>&1

echo [*] Removing Reboot Block Policies...
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "NoAutoRebootWithLoggedOnUsers" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "AUPowerManagement" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v "AlwaysAutoRebootAtScheduledTime" /f >nul 2>&1

echo [*] Re-enabling Scheduled Reboot Tasks...
schtasks /change /tn "\Microsoft\Windows\UpdateOrchestrator\Reboot" /enable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\UpdateOrchestrator\Reboot_AC" /enable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\UpdateOrchestrator\Reboot_Battery" /enable >nul 2>&1

echo.
echo  [+] Default settings restored successfully!
echo.
pause
goto :MENU_LOOP

:: ============================================================================
:: Exit Script
:: ============================================================================
:EXIT_SCRIPT
cls
echo Exiting Windows Update ^& Auto-Reboot Control Tool. Goodbye!
exit /b 0
