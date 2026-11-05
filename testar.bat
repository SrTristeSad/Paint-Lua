@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title Paint-Lua Unificado - v0.39
set "LOVE_EXE="
if defined LOVE11_EXE if exist "%LOVE11_EXE%" set "LOVE_EXE=%LOVE11_EXE%"
if not defined LOVE_EXE if exist "%~dp0love.exe" set "LOVE_EXE=%~dp0love.exe"
if not defined LOVE_EXE if exist "%ProgramFiles%\LOVE\love.exe" set "LOVE_EXE=%ProgramFiles%\LOVE\love.exe"
if not defined LOVE_EXE if defined ProgramFiles(x86) if exist "%ProgramFiles(x86)%\LOVE\love.exe" set "LOVE_EXE=%ProgramFiles(x86)%\LOVE\love.exe"
if not defined LOVE_EXE if exist "%LOCALAPPDATA%\Programs\LOVE\love.exe" set "LOVE_EXE=%LOCALAPPDATA%\Programs\LOVE\love.exe"
if not defined LOVE_EXE for /f "delims=" %%P in ('where love.exe 2^>nul') do if not defined LOVE_EXE set "LOVE_EXE=%%P"
if not defined LOVE_EXE (
  echo [ERRO] Instale LOVE 11.5: https://love2d.org/
  if not defined PAINT_LUA_NO_PAUSE pause
  exit /b 1
)
if not exist "core\doc.lua" (
  echo [ERRO] core\doc.lua nao encontrado: extraia o ZIP completo.
  if not defined PAINT_LUA_NO_PAUSE pause
  exit /b 2
)
if not exist "src\model.lua" (
  echo [ERRO] src\model.lua nao encontrado: extraia o ZIP completo.
  if not defined PAINT_LUA_NO_PAUSE pause
  exit /b 3
)
if not exist "app\ibis_main.lua" (
  echo [ERRO] app\ibis_main.lua nao encontrado: extraia o ZIP completo.
  if not defined PAINT_LUA_NO_PAUSE pause
  exit /b 4
)
if not exist "app\selection_ants.lua" (
  echo [ERRO] app\selection_ants.lua nao encontrado: extraia o ZIP completo.
  if not defined PAINT_LUA_NO_PAUSE pause
  exit /b 5
)
if not exist "core\selection.lua" (
  echo [ERRO] core\selection.lua nao encontrado: extraia o ZIP completo.
  if not defined PAINT_LUA_NO_PAUSE pause
  exit /b 6
)
if not exist "src\editor_preferences.lua" (
  echo [ERRO] src\editor_preferences.lua nao encontrado: extraia o ZIP completo.
  if not defined PAINT_LUA_NO_PAUSE pause
  exit /b 7
)
if not exist "assets\icons\png\paintbrush.png" (
  echo [ERRO] asset de interface ausente: extraia o ZIP completo.
  if not defined PAINT_LUA_NO_PAUSE pause
  exit /b 8
)
if defined PAINT_LUA_VERIFY_ONLY (
  echo [TESTE] Verificando arquivos e caminho do executavel LOVE...
  echo [OK] Inicializador e executavel LOVE encontrados.
  exit /b 0
)
"%LOVE_EXE%" "%CD%"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" echo [ERRO] LOVE encerrou com codigo %RC%.
if not defined PAINT_LUA_NO_PAUSE pause
exit /b %RC%
