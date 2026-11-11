@echo off
setlocal EnableDelayedExpansion
title Windows Update ^& Auto-Reboot Control Tool

:: ============================================================================
:: Settings
:: ============================================================================
set "UX_KEY=HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
set "KEEPER_TASK=\WindowsUpdateControl\KeepActiveHours"
set "BACKUP_KEY=HKLM\SOFTWARE\WindowsUpdateControl"

:: Non-interactive verbs (no elevation prompt). The WUC_* overrides are for
:: tests\RebootBlock.test.ps1 and apply ONLY to these verbs, never to the
:: elevated menu that installs the SYSTEM task.
set "CLI_VERB="
if /i "%~1"=="/tick" set "CLI_VERB=TICK"
if /i "%~1"=="/status" set "CLI_VERB=STATUS_CLI"
if /i "%~1"=="/tickcmd" set "CLI_VERB=TICKCMD_CLI"
if defined CLI_VERB if defined WUC_UX_KEY set "UX_KEY=%WUC_UX_KEY%"
if defined CLI_VERB if defined WUC_TASK set "KEEPER_TASK=%WUC_TASK%"

:: Windows restarts for updates only outside "active hours" (max 18h window).
:: Rolling the window to [now, now+18h) every hour keeps "now" always inside it.
:: No quotes of any kind inside: schtasks rewrites ' as " when storing /tr, which
:: breaks the stored command. ($ErrorActionPreference=1 means Stop.)
set "PS_TICK=$ErrorActionPreference=1;$d=Get-Date;cd Registry::%UX_KEY%;sp . ActiveHoursStart $d.Hour;sp . ActiveHoursEnd $d.AddHours(18).Hour"

if defined CLI_VERB goto :%CLI_VERB%

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
echo      active hours cover now: !AH_COVER!  /  keeper task: !KEEPER_STATE!
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
set "REBOOT_STATUS=NOT BLOCKED"
set "AH_COVER=NO"
set "KEEPER_STATE=MISSING"
set "AH_S="
set "AH_E="
set "NOW_H="

:: Check Windows Update Status (wuauserv start type or AU policy)
for /f "tokens=3" %%a in ('sc.exe qc wuauserv 2^>nul ^| findstr /i "START_TYPE"') do (
    if "%%a"=="4" set "WU_STATUS=DISABLED"
)
for /f "tokens=3" %%a in ('reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "NoAutoUpdate" 2^>nul ^| findstr /i "NoAutoUpdate"') do (
    if "%%a"=="0x1" set "WU_STATUS=DISABLED"
)

:: Check Auto-Reboot Status: BLOCKED only if the current hour is inside the
:: active-hours window AND the hourly keeper task's last run succeeded.
:: (The NoAutoRebootWithLoggedOnUsers policy value alone proves nothing.)
for /f "tokens=3" %%a in ('reg query "%UX_KEY%" /v "ActiveHoursStart" 2^>nul ^| findstr /i "ActiveHoursStart"') do set /a AH_S=%%a
for /f "tokens=3" %%a in ('reg query "%UX_KEY%" /v "ActiveHoursEnd" 2^>nul ^| findstr /i "ActiveHoursEnd"') do set /a AH_E=%%a
for /f %%h in ('powershell -NoProfile -Command "(Get-Date).Hour"') do set /a NOW_H=%%h
if defined AH_S if defined AH_E if defined NOW_H (
    if !AH_S! lss !AH_E! if !NOW_H! geq !AH_S! if !NOW_H! lss !AH_E! set "AH_COVER=YES"
    if !AH_S! gtr !AH_E! if !NOW_H! geq !AH_S! set "AH_COVER=YES"
    if !AH_S! gtr !AH_E! if !NOW_H! lss !AH_E! set "AH_COVER=YES"
)
:: Column 7 of the verbose CSV is "Last Result" (position is locale-independent).
set "KEEPER_RESULT="
for /f "delims=" %%r in ('powershell -NoProfile -Command "$o=schtasks /query /tn '%KEEPER_TASK%' /v /fo csv 2>$null|ConvertFrom-Csv;if($o){@(@($o)[0].psobject.Properties)[6].Value}"') do set "KEEPER_RESULT=%%r"
if defined KEEPER_RESULT set "KEEPER_STATE=FAILING, last result !KEEPER_RESULT!"
if "!KEEPER_RESULT!"=="0" set "KEEPER_STATE=OK"
if "!AH_COVER!!KEEPER_STATE!"=="YESOK" set "REBOOT_STATUS=BLOCKED"
goto :eof

:: ============================================================================
:: Non-interactive verbs
:: ============================================================================
:TICK
powershell -NoProfile -Command "%PS_TICK%"
exit /b %errorlevel%

:STATUS_CLI
call :CHECK_STATUS
echo ACTIVE_HOURS_COVER_NOW=!AH_COVER!
echo KEEPER_TASK=!KEEPER_STATE!
echo REBOOT_BLOCK=!REBOOT_STATUS!
exit /b 0

:: Prints the exact command line the keeper task runs (schtasks /tr limit: 261 chars)
:TICKCMD_CLI
echo powershell -NoProfile -Command "%PS_TICK%"
exit /b 0

:: ============================================================================
:: Shared: Block Auto-Reboot (used by Mode 1 and Mode 2)
:: ============================================================================
:BLOCK_REBOOT
echo [*] Configuring Registry to Block Auto-Reboot...
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "NoAutoRebootWithLoggedOnUsers" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "AUPowerManagement" /t REG_DWORD /d 0 /f >nul
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v "AlwaysAutoRebootAtScheduledTime" /t REG_DWORD /d 0 /f >nul

echo [*] Disabling Scheduled Reboot Tasks (absent on newer builds)...
schtasks /change /tn "\Microsoft\Windows\UpdateOrchestrator\Reboot" /disable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\UpdateOrchestrator\Reboot_AC" /disable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\UpdateOrchestrator\Reboot_Battery" /disable >nul 2>&1

echo [*] Installing hourly Active Hours keeper task...
:: Back up the user's own active hours once, so Mode 3 can restore them.
:: BackupTaken marks "backup done" even when the user had no values to copy.
reg query "%BACKUP_KEY%" /v "BackupTaken" >nul 2>&1 || (
    call :COPY_ACTIVE_HOURS "%UX_KEY%" "%BACKUP_KEY%"
    reg add "%BACKUP_KEY%" /v "BackupTaken" /t REG_DWORD /d 1 /f >nul
)
schtasks /create /tn "%KEEPER_TASK%" /tr "powershell -NoProfile -Command \"%PS_TICK%\"" /sc hourly /ru SYSTEM /rl highest /f >nul
:: schtasks defaults to "AC power only"; a laptop on battery would stop refreshing.
:: StartWhenAvailable catches up a run missed while the PC was off or asleep.
powershell -NoProfile -Command "Set-ScheduledTask -TaskPath '\WindowsUpdateControl\' -TaskName 'KeepActiveHours' -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable) | Out-Null" || echo  [X] Could not set battery/catch-up options on the keeper task.

:: Run the task itself (not a direct write) so that success proves the SYSTEM task works.
schtasks /run /tn "%KEEPER_TASK%" >nul
set "WAIT_LEFT=10"
:WAIT_KEEPER
timeout /t 1 /nobreak >nul
call :CHECK_STATUS
set /a WAIT_LEFT-=1
if not "!KEEPER_STATE!"=="OK" if !WAIT_LEFT! gtr 0 goto :WAIT_KEEPER

if "!REBOOT_STATUS!"=="BLOCKED" (
    echo  [+] Auto-reboot block verified: keeper task ran OK and active hours cover now.
) else (
    echo  [X] Auto-reboot is NOT blocked. active hours cover now: !AH_COVER! / keeper task: !KEEPER_STATE!
    echo      See the error output above.
)
goto :eof

:: %1 = source key, %2 = destination key
:COPY_ACTIVE_HOURS
for %%v in (ActiveHoursStart ActiveHoursEnd) do (
    for /f "tokens=3" %%a in ('reg query "%~1" /v "%%v" 2^>nul ^| findstr /i "%%v"') do reg add "%~2" /v "%%v" /t REG_DWORD /d %%a /f >nul
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

call :BLOCK_REBOOT

echo.
echo  Mode 1 finished. Check the verification line above.
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

call :BLOCK_REBOOT

echo.
echo  Mode 2 finished. Check the verification line above.
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

echo [*] Removing Active Hours keeper task and restoring original active hours...
schtasks /delete /tn "%KEEPER_TASK%" /f >nul 2>&1
:: Only if this tool took a backup: drop the rolled window, then put back what the user had (if anything).
reg query "%BACKUP_KEY%" /v "BackupTaken" >nul 2>&1 && (
    reg delete "%UX_KEY%" /v "ActiveHoursStart" /f >nul 2>&1
    reg delete "%UX_KEY%" /v "ActiveHoursEnd" /f >nul 2>&1
    call :COPY_ACTIVE_HOURS "%BACKUP_KEY%" "%UX_KEY%"
    reg delete "%BACKUP_KEY%" /f >nul 2>&1
)

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
