# Importação com prévia — Paint-Lua v0.30

## Passos na interface

1. Abra uma obra no editor.
2. Arraste um arquivo `.png` do Explorador do Windows até o editor, ou abra **Back → Importar PNG** (`Ctrl+I`) e escolha um arquivo previamente colocado na pasta `imports` dos dados do LÖVE.
3. Uma prévia sem modificar o documento aparece sobre o canvas. Arraste para mover; use **- Zoom/+ Zoom** para escala, **-15°/+15°** para rotação. **Setas** movem um pixel; **Q/R** giram; **+/-** alteram a escala.
4. **Aplicar** ou **Enter**: rasteriza o PNG na posição prévia, cria uma camada, e registra uma única ação no histórico (`Ctrl+Z` remove, `Ctrl+Y` restaura).
5. **Cancelar** ou **Esc**: abandona a prévia, sem criar camada nem adicionar entrada de histórico.

## Engenharia

- `src/png_import.lua` mantém a API `insert` da v0.29 e ganha `preview/adjust/bounds/drawPreview/cancel`. Reusa as transformações geométricas (`Transform.set/bounds/inverse/drawPreview`) do motor v0.24.
- O raster é preparado em uma camada separada antes de `Layers.add`. A composição final usa amostragem nearest-neighbor e conserva RGBA; camadas preexistentes são preservadas.
- `app/paint_bridge.lua` guarda `pngPreview` e impede salvar/editar durante a prévia; `app/ibis_main.lua` mostra controles e intercepta arraste/teclado.
- Dados `.npnt` persistem apenas após aplicar e salvar. Nenhum formato novo foi introduzido.

## Segurança, limites e qualidade

O PNG é validado antes da decodificação (`IHDR` e tamanho), limitado a 16 MiB e 2.097.152 pixels, e a área de destino rasterizado também é limitada a 2.097.152 pixels. Prévia fora do canvas e imagem integralmente transparente não criam camadas. Uma falha de decodificação ou rasterização não modifica o documento. O tamanho da GPU para prévias depende do hardware; validação manual Windows/tablet continua pendente.
