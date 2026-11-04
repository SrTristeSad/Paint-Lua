@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title Paint-Lua - Ibis-Lua + motor v0.21
if not exist "vendor\Ibis-Lua\src\model.lua" (
    where git.exe >nul 2>nul
    if errorlevel 1 (
        echo [ERRO] Falta Ibis-Lua. Instale Git e clone com --recurse-submodules.
        echo git clone --recurse-submodules https://github.com/SrTristeSad/Paint-Lua.git
        pause
        exit /b 1
    )
    git submodule update --init --recursive
    if errorlevel 1 (echo [ERRO] Falha ao obter Ibis-Lua.&pause&exit /b 1)
)
if not exist "core\doc.lua" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\prepare-core.ps1"
    if errorlevel 1 (echo [ERRO] Falha ao preparar o nucleo.&pause&exit /b 2)
)
set "LOVE_EXE="
if exist "%ProgramFiles%\LOVE\love.exe" set "LOVE_EXE=%ProgramFiles%\LOVE\love.exe"
if not defined LOVE_EXE if defined ProgramFiles(x86) if exist "%ProgramFiles(x86)%\LOVE\love.exe" set "LOVE_EXE=%ProgramFiles(x86)%\LOVE\love.exe"
if not defined LOVE_EXE if exist "%LOCALAPPDATA%\Programs\LOVE\love.exe" set "LOVE_EXE=%LOCALAPPDATA%\Programs\LOVE\love.exe"
if not defined LOVE_EXE for /f "delims=" %%P in ('where love.exe 2^>nul') do if not defined LOVE_EXE set "LOVE_EXE=%%P"
if not defined LOVE_EXE (
    echo [ERRO] Instale LÖVE 11.5 em https://love2d.org/
    pause
    exit /b 3
)
"%LOVE_EXE%" "%CD%"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (echo [ERRO] LÖVE retornou codigo %RC%.&pause)
exit /b %RC%
