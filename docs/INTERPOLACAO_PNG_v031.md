# Paint-Lua v0.31 — Interpolação de PNG

## Usar na interface

Abra uma obra e arraste um PNG para a janela do editor ou selecione-o pelo painel
**Back → Importar PNG**. Antes de aplicar, use os botões **Suave** e **Pixelado**
acima dos controles de rotação e zoom. O modo **Suave é o padrão da interface**.

- **Suave:** bilinear para imagens fotográficas e ilustrações com transições contínuas.
- **Pixelado:** nearest-neighbor para pixel art e desenhos que precisam manter
  contornos de pixels nítidos.
- **Aplicar / Enter:** cria uma camada na posição e escala definidas, com um undo.
- **Cancelar / Esc:** descarta a sessão sem modificar camadas ou pixels.

## Implementação

`src/png_import.lua` valida o PNG e rasteriza na camada temporária. As coordenadas
inversas usam `core/transform.lua`; bilinear amostra quatro vizinhos e mistura
**RGB pré-multiplicado por alfa**, normalizando RGB apenas depois. A amostragem
nas bordas faz *clamp* para os pixels mais próximos, como o filtro da textura
na GPU do LÖVE. Isso reduz halos de imagens com pixels transparentes coloridos.

`core/transform.lua` conserva o filtro nearest para transformações de seleção.
Apenas sessões de importação possuem `interpolation='smooth'|'pixelated'`. Ao
alternar, a **prévia na GPU** muda de filtro sem reconstruir a textura; a
**rasterização final na CPU** consulta a mesma opção. O código não modifica
`src/view_state.lua` nem a qualidade global da visualização.

`PNGImport.insert(doc,pixels,filename)` (sem sessão) segue pixelated por
compatibilidade; a ponte `Bridge:importPNGBytes` configura smooth por padrão.
`Bridge:setPNGInterpolation` valida a opção. Valores inválidos são rejeitados,
sem alterar as camadas.

## Integridade e testes

A criação de tiles acontece antes de anexar a camada nova ao documento; erro de
leitura, rasterização ou limite de tamanho deixa o documento intacto. Testes
cobrem mistura de duas cores, alfa parcial sem halos, identidade na escala 1:1,
modo pixelado, troca de filtro GPU, cancelamento, histórico e NPNT5.

`tests/test_png_interpolation_v031.lua` roda com mocks, enquanto
`tests/test_bridge_love.lua` e a UI automatizada confirmam o mesmo comportamento
com LÖVE 11.5 e decodificação PNG verdadeira no GitHub Actions.

Limites existentes: PNG de até 16 MiB, 2.097.152 pixels e 8.192 por lado;
área de destino até 2.097.152 pixels e escala 0,125×–8×. O processo de
rasterização ainda é síncrono; não há interpolação bicúbica, antialias completo
de contornos rotacionados ou reedição do PNG como objeto inteligente.
