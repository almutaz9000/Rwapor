@echo off
REM Launch the Rwapor Control Room Streamlit dashboard.
REM Double-click this file to start the dashboard and open it in your browser.
REM Reads agent-workflow\agents-board.json live -- leave the window open.

setlocal
set "SCRIPT_DIR=%~dp0"
set "DASHBOARD_DIR=%SCRIPT_DIR%..\dashboard"
set "APP_PATH=%DASHBOARD_DIR%\app.py"
set "REQ_PATH=%DASHBOARD_DIR%\requirements.txt"
set "PORT=8511"

if not exist "%APP_PATH%" (
    echo [run_dashboard] BROKEN: app.py not found at "%APP_PATH%"
    pause
    exit /b 1
)

where python >nul 2>nul
if errorlevel 1 (
    echo [run_dashboard] No 'python' on PATH. Install Python 3.10+ and re-run.
    pause
    exit /b 1
)

echo [run_dashboard] Checking dashboard dependencies...
python -m pip install --quiet -r "%REQ_PATH%"

REM Find a free port starting at 8511, trying up to 10 ports upward if busy.
set "TRY_PORT=%PORT%"
set /a ATTEMPTS=0

:CHECK_PORT
netstat -ano | findstr /r /c:":%TRY_PORT% .*LISTENING" >nul 2>nul
if %errorlevel%==0 (
    set /a TRY_PORT=%TRY_PORT%+1
    set /a ATTEMPTS=%ATTEMPTS%+1
    if %ATTEMPTS% lss 10 goto CHECK_PORT
)

echo [run_dashboard] Starting Streamlit on port %TRY_PORT% ...
echo [run_dashboard] Dashboard will open at http://localhost:%TRY_PORT%
echo [run_dashboard] Close this window to stop the dashboard.

cd /d "%DASHBOARD_DIR%"
python -m streamlit run app.py --server.port %TRY_PORT%

pause
