@echo off
rem Usage: local.bat [build|up|run|down|restart|logs|ps]   (default: run)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0local.ps1" %*
exit /b %ERRORLEVEL%
