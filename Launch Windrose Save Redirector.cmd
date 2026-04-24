@echo off
set SCRIPT=%~dp0WindroseSaveRedirector.ps1
net session >nul 2>&1
if %errorlevel% neq 0 (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File ""%SCRIPT%""' -Verb RunAs"
  if errorlevel 1 (
    echo.
    echo Could not request administrator rights.
    pause
  )
  exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
if errorlevel 1 (
  echo.
  echo Windrose Save Redirector stopped with an error.
  pause
)
