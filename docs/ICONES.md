# Ícones Lucide do Paint Lua

Ícones: [Lucide](https://github.com/lucide-icons/lucide), licença ISC/MIT.
`assets/icons/svg`: fontes vetoriais editáveis; `assets/icons/png`:
PNG de 96 × 96 para execução offline no LÖVE 11.5.

O arquivo `src/icon_pack.lua` preserva os identificadores de controles.
O script `tools/rebuild_icons.py` recria os PNGs; para executá-lo:
`python -m pip install cairosvg && python tools/rebuild_icons.py`.
Os SVGs são incluídos como arquivos de texto para manutenção.
O CI da pasta `.github/workflows/generate-icons.yml` os rasteriza
e publica os PNGs no próprio repositório.
Não são ícones oficiais proprietários do ibisPaint.
