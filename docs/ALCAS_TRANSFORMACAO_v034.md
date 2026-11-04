# Paint-Lua v0.34 — alças interativas da ferramenta Transformar

A seleção permanece **não destrutiva até Aplicar**. As alças são calculadas
no mesmo sistema de coordenadas da composição e do hit-test do mouse.

## Uso

1. Selecione uma região no editor (retângulo, laço ou varinha mágica).
2. Abra **Transformar**.
3. Arraste **dentro da seleção** para mover a prévia.
4. Arraste um **canto** para redimensionar uniformemente, sem inverter a
   imagem. O canto oposto fica fixo, inclusive se a seleção já foi girada.
5. Arraste o **círculo acima da aresta superior** para girar livremente.
6. Use **Aplicar / Enter** para confirmar ou **Cancelar / Esc** para abandonar.

Os botões antigos de rotação (±15°) e zoom continuam disponíveis, assim como
os modos **Suave** e **Pixelado**. O mouse funciona com o canvas ampliado,
girado e deslocado. Alças mantêm raio constante em pixels da interface.

Em seleções com menos de **28 px de tela** na dimensão menor, as alças de giro
e redimensionamento são temporariamente ocultadas para que um pixel ou pequena
região ainda possa ser movida; aumente pelo botão de zoom para ativá-las.

## Restrições e continuidade

- O redimensionamento por canto mantém a proporção; suporta escalas de 0,125×
  a 8× (sem espelhamento por arraste).
- A ferramenta continua raster; não há objeto vetorial permanente.
- O limite de origem/destino na confirmação permanece 1 milhão de pixels.
- Cancelar não modifica os pixels; aplicar produz uma operação de histórico.
- NPNT5 preserva o resultado aplicado; não salva uma prévia ainda aberta.
- A execução automática do LÖVE ocorre no Linux em display virtual. Windows,
  mesa digitalizadora e comportamento manual ainda precisam ser verificados.

## Testes

`tests/test_transform_handles_v034.lua` cobre geometria e hit-test, zoom e
rotação do canvas, âncora oposta, limites, movimentos, cancelamento e histórico.
`tests/test_bridge_love.lua` usa ImageData e renderização GPU do LÖVE real.
