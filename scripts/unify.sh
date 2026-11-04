#!/usr/bin/env bash
set -euo pipefail

# One-time import of the pinned Ibis-Lua revision into Paint-Lua.
sh scripts/prepare-core.sh
test -f core/doc.lua
test -f .ibis-import/src/model.lua
test -f .ibis-import/assets/icons/png/paintbrush.png

git rm -f vendor/Ibis-Lua .gitmodules
rm -rf vendor
mkdir -p src assets docs tools tests
cp -a .ibis-import/src/. src/
cp -a .ibis-import/assets/. assets/
cp -a .ibis-import/docs/. docs/
cp -a .ibis-import/tools/. tools/
cp -a .ibis-import/tests/. tests/
cp .ibis-import/requirements-dev.txt requirements-dev.txt
cp .ibis-import/README.md docs/IBIS_LUA_ORIGINAL.md
sed -i 's|vendor/Ibis-Lua/assets/icons/png/|assets/icons/png/|g' src/icon_pack.lua

git rm -r -f archive/core-v0.21.parts scripts/prepare-core.sh scripts/prepare-core.ps1
rm -rf archive .ibis-import
sed -i 's|;vendor/Ibis-Lua/?.lua;vendor/Ibis-Lua/?/init.lua||g' main.lua
sed -i 's|;vendor/Ibis-Lua/?.lua;vendor/Ibis-Lua/?/init.lua||g' tests/test_bridge_smoke.lua

test "$(find core -maxdepth 1 -name '*.lua' | wc -l)" -eq 20
test "$(find assets/icons/png -maxdepth 1 -name '*.png' | wc -l)" -ge 35
if grep -R -l 'integrations.bono' --include='*.lua' app core src main.lua; then
  echo 'ERROR: unexpected Bono-Lua import' >&2
  exit 1
fi

cat > testar.bat <<'BATCH'
@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title Paint-Lua Unificado - Ibis-Lua e motor v0.21
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
BATCH
sed -i 's/$/\r/' testar.bat

cat > README.md <<'DOC'
# Paint-Lua — Projeto único

Editor experimental de pintura digital em Lua / LÖVE 11.5. A interface de Ibis-Lua e o núcleo de pintura v0.21 são **código-fonte do mesmo repositório**. Não há submódulos, download do Ibis-Lua na inicialização ou integração atual com DragonBones/Bono-Lua.

## Teste no Windows

1. Instale LÖVE 11.5: https://love2d.org/.
2. Baixe o ZIP completo do projeto e extraia-o.
3. Execute **testar.bat** na pasta raiz. Não precisa de Git, Python, PowerShell ou conexão à internet para iniciar.

Clone alternativo: git clone https://github.com/SrTristeSad/Paint-Lua.git (sem --recurse-submodules).

## Organização

- **core/**: os 20 módulos Lua editáveis do núcleo v0.21, com pincéis, tiles, composição, histórico, máscaras, grupos e NPNT1–NPNT4.
- **src/**: estados da interface Ibis-Lua, galeria, pincéis, cores, layout e preferências.
- **assets/icons/png/** e **assets/icons/svg/**: ícones Lucide, PNGs para LÖVE e fontes SVG editáveis. Licença em assets/icons/LICENSE-LUCIDE.txt.
- **app/ibis_main.lua**: interface Ibis-Lua adaptada para renderizar os pixels reais.
- **app/paint_bridge.lua**: conexão de ferramentas, documentos, camadas, pincel, histórico e salvamento ao núcleo.
- **main.lua**, **conf.lua**, **testar.bat**: inicialização.
- **tests/**, **tools/**, **docs/**: testes e documentação da interface e do núcleo.

## Situação funcional

A UI disponibiliza tela inicial, galeria, New Canvas, ferramentas, janelas de pincel, cores e camadas. O motor é responsável por pixels reais: **pintura básica, borracha, camadas simples, desfazer/refazer e salvar/reabrir .npnt**. Zoom, rotação e pan usam a UI. Vários controles de filtros, transformações, máscaras, grupos e galeria **ainda são demonstrativos ou parcialmente integrados**. Não se deve assumir que um botão que existe na interface altera pixels.

O núcleo v0.21 registrou 777 testes históricos com mocks. A integração básica passou em **LÖVE 11.5 real em Linux sob display virtual**, incluindo pincel, undo/redo e NPNT. Ainda são necessários testes manuais no Windows, desempenho e uso de caneta/tablet.

## Créditos e continuidade

Os fontes da interface foram incorporados de https://github.com/SrTristeSad/Ibis-Lua (revisão fixada e atribuída em ORIGENS.md). Não é o aplicativo oficial ibisPaint. PhotoCraft é referência técnica; ibisPaint é referência funcional. Consulte LICENSE-PHOTOCRAFT-MIT.txt, ORIGENS.md e a licença dos ícones Lucide.

Para continuar em outro chat: PROMPT_DO_PROJETO.md e AGENTS.md.
DOC

cat > PROMPT_DO_PROJETO.md <<'DOC'
# Continuidade — Paint-Lua unificado

**Decisão do criador:** este é **um projeto único** que incorpora diretamente a interface do Ibis-Lua e o motor do Paint-Lua. Não utilizar submódulos ou baixadores do outro repositório. Bono-Lua/DragonBones é uma possível ideia futura, NÃO é usado agora.

## Prompt para o próximo chat

Continue o desenvolvimento do repositório https://github.com/SrTristeSad/Paint-Lua. Leia este documento, README.md, AGENTS.md e ORIGENS.md, examine o código atual e os testes antes de modificar. Sou o criador e tomo as decisões finais. Colabore criticamente, preserve decisões e não reescreva funcionalidades existentes desnecessariamente.

Motor próprio v0.21: 20 módulos em core/, com pincéis, pressão, estabilização, texturas, composição por tiles, cache, histórico, preenchimento, camadas, máscaras, clipping, grupos e persistência NPNT1–NPNT4. Interface Ibis-Lua incorporada em src/, assets/ e app/ibis_main.lua. Ponte em app/paint_bridge.lua. **Nem toda opção da interface tem lógica de pintura conectada.** Manter a divisão entre motor e UI.

Objetivo: editor de pintura em Lua para LÖVE 11.5, com PhotoCraft como referência técnica e ibisPaint como referência funcional, sem código nem arquivos proprietários. A interface original Ibis-Lua é do mesmo criador, mas sua cópia neste projeto é independente e editável.

Verificação: 777 testes históricos no motor com simulações; CI de LÖVE 11.5 no Linux com display virtual testou pincel, undo, redo, salvar/abrir NPNT. Faltam teste no Windows, tablet e medidas de desempenho. Priorizar a integração correta de propriedades das camadas, ferramentas, máscaras e grupos; corrigir erros reais, testar antes de publicar, e nunca inventar validação.

O backup da arquitetura antiga está na branch backup/pre-ibis-rebuild-2026-11-03, e a fase com submódulo permanece no histórico Git. Não restaurar essas arquiteturas sem autorização do criador.
DOC

cat > AGENTS.md <<'DOC'
# Instruções para assistentes — Paint-Lua

- Leia PROMPT_DO_PROJETO.md, README.md e ORIGENS.md.
- A decisão atual é **projeto único** com interface e motor inteiramente neste repositório, sem submódulos.
- core/ é o motor; src/, assets/ e app/ibis_main.lua são a interface; app/paint_bridge.lua integra os dois.
- Preserve decisões, APIs, formato NPNT1–NPNT4, testes, código editável e atribuições.
- DragonBones/Bono-Lua não deve ser reinserido: não é dependência atual.
- Faça teste no LÖVE real quando possível; distinga do teste com mocks e não prometa FPS.
- Integre ferramentas gradualmente sem substituir o núcleo.
DOC

cat > ORIGENS.md <<'DOC'
# Proveniência e licenças — Paint-Lua unificado

**Interface:** código do projeto do mesmo criador https://github.com/SrTristeSad/Ibis-Lua, incorporado da revisão c6570a8ec802d2f47de23a87903b43b9c84c3022 em src/, assets/, docs/, tests/ e app/ibis_main.lua. O original é um protótipo de interface, não o aplicativo oficial ibisPaint. Os ícones Lucide têm avisos de licença em assets/icons/LICENSE-LUCIDE.txt.

**Motor:** núcleo de pintura v0.21 Lua próprio, com conceitos técnicos de https://github.com/storytold/photocraft, licenciado e atribuído conforme LICENSE-PHOTOCRAFT-MIT.txt. ibisPaint é referência funcional, não fonte de código ou de arquivos proprietários.

**Integração:** app/paint_bridge.lua permite pintura real com recursos básicos. Vários painéis permanecem demonstrativos. Não afirmar fidelidade 1:1 ou compatibilidade com arquivos proprietários.

**Bono-Lua/DragonBones:** não participa deste projeto na versão atual; possibilidade futura.
DOC

cat > .gitignore <<'DOC'
.DS_Store
.vscode/
*.love
*.zip
*.log
*.npnt
__pycache__/
.pytest_cache/
screenshots/
ci-smoke.png
DOC

git rm -f .github/workflows/unify.yml scripts/unify.sh
git add -A
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
echo 'UNIFIED_SOURCE_READY'
