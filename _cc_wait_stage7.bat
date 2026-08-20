@echo off
rem Wait up to ~20 min for stage7 matlab to finish, then report status.
setlocal
set /a waited=0
:loop
tasklist /fi "imagename eq MATLAB.exe" | findstr /i "MATLAB.exe" >nul
if errorlevel 1 goto done
if %waited% geq 1200 goto timeout
timeout /t 30 /nobreak >nul
set /a waited+=30
goto loop
:done
echo STAGE7_DONE
goto end
:timeout
echo STAGE7_STILL_RUNNING
:end
endlocal
