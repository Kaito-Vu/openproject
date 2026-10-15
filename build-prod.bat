@echo off
rem Build production images and export them to dist\openproject-images-<sha>.tar
rem Usage: build-prod.bat [tag]   (default: TAG from .env.production, else 17)
setlocal EnableDelayedExpansion
cd /d "%~dp0"

if not exist .env.production (
  echo .env.production not found - copy .env.production.example first.
  exit /b 1
)
if not "%~1"=="" set TAG=%~1
for /f %%i in ('git rev-parse --short HEAD 2^>nul') do set GIT_SHA=%%i

where docker >nul 2>&1 && (set CE=docker) || (set CE=podman)
if defined CONTAINER_ENGINE set CE=%CONTAINER_ENGINE%
set DC=%CE% compose --env-file .env.production -f docker-compose.production.yml

echo === Building images ===
%DC% build web hocuspocus || exit /b 1

rem Images built from this repo; web/worker/cron/seeder share one image.
set IMAGES=
for /f %%i in ('%DC% config --images') do (
  echo %%i | findstr /b "openproject/openproject: openproject/hocuspocus:" >nul && (
    echo !IMAGES! | findstr /c:"%%i" >nul || set IMAGES=!IMAGES! %%i
  )
)

if not exist dist mkdir dist
set OUT=dist\openproject-images-%GIT_SHA%.tar
echo === Exporting%IMAGES% to %OUT% ===
%CE% save -o "%OUT%" %IMAGES% || exit /b 1

echo.
echo Done: %OUT%
echo On the server: docker load -i openproject-images-%GIT_SHA%.tar
echo Then:          docker compose --env-file .env.production -f docker-compose.production.yml up -d
