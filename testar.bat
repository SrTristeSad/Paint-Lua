@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title Paint-Lua Unificado - Ibis-Lua e motor v0.28
set "LOVE_EXE="
if defined LOVE11_EXE if exist "%LOVE11_EXE%" set "LOVE_EXE=%LOVE11_EXE%"
if not defined LOVE_EXE if exist "%~dp0love.exe" set "LOVE_EXE=%~dp0love.exe"
if not defined LOVE_EXE if exist "%ProgramFiles%\LOVE\love.exe" set "LOVE_EXE=%ProgramFiles%\LOVE\love.exe"
if not defined LOVE_EXE if defined ProgramFiles(x86) if exist "%ProgramFiles(x86)%\LOVE\love.exe" set "LOVE_EXE=%ProgramFiles(x86)%\LOVE\love.exe"
if not defined LOVE_EXE if exist "%LOCALAPPDATA%\Programs\LOVE\love.exe" set "LOVE_EXE=%LOCALAPPDATA%\Programs\LOVE\love.exe"
if not defined LOVE_EXE for /f "delims=" %%P in ('where love.exe 2^>nul') do if not defined LOVE_EXE set "LOVE_EXE=%%P"
if not defined LOVE_EXE (
  echo [ERRO] Instale LOVE 11.5: https://love2d.org/
  pause
  exit /b 1
)
if not exist "core\doc.lua" (
  echo [ERRO] core\doc.lua nao encontrado: extraia o ZIP completo.
  pause
  exit /b 2
)
if not exist "src\model.lua" (
  echo [ERRO] src\model.lua nao encontrado: extraia o ZIP completo.
  pause
  exit /b 3
)
"%LOVE_EXE%" "%CD%"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" echo [ERRO] LOVE encerrou com codigo %RC%.
pause
exit /b %RC%
