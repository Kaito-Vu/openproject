# Usage: .\local.ps1 [build|up|run|down|restart|logs|ps]   (default: run = build + up)
param([ValidateSet('build','up','run','down','restart','logs','ps')][string]$Action = 'run')
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

if (-not (Test-Path .env.local)) {
    Copy-Item .env.local.example .env.local
    Write-Host 'Created .env.local from .env.local.example - edit it if needed.'
}
$env:GIT_SHA = (git rev-parse --short HEAD 2>$null)
# docker, or podman when docker is not installed (override: $env:CONTAINER_ENGINE)
$ce = if ($env:CONTAINER_ENGINE) { $env:CONTAINER_ENGINE } elseif (Get-Command docker -ErrorAction SilentlyContinue) { 'docker' } else { 'podman' }
$dc = @('compose', '--env-file', '.env.local', '-f', 'docker-compose.local.yml')

switch ($Action) {
    'build'   { & $ce @dc build }
    'up'      { & $ce @dc up -d }
    'run'     { & $ce @dc up -d --build }
    'down'    { & $ce @dc down }
    'restart' { & $ce @dc restart web worker }
    'logs'    { & $ce @dc logs -f web worker }
    'ps'      { & $ce @dc ps }
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if ($Action -in 'run','up') { Write-Host 'OpenProject: http://localhost:8080 (HTTP_PORT in .env.local)' }
