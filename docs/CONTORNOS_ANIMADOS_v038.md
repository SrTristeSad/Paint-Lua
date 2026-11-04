# Paint-Lua v0.38 — contornos animados (*marching ants*)

## Comportamento

Ao criar um retângulo de seleção, laço, varinha, união/interseção ou
seleção invertida, o contorno alterna **claro e escuro em movimento**.
A animação aplica cores exclusivamente às arestas que já eram
desenhadas pelo núcleo na v0.37. Não modifica a máscara, não pinta a
camada, não insere históricos e não altera o formato NPNT5.

O shader em `app/selection_ants.lua` consulta coordenadas de pixel
**da tela** para garantir que as faixas não cresçam nem encolham ao
alterar o zoom. Cada faixa tem aproximadamente **5 pixels** e o
padrão avança a **24 pixels/segundo**. A direção é a de uma projeção
diagonal sobre a tela, não uma parametrização do comprimento ao longo
de cada laço. A animação tem taxa de atualização dos quadros do LÖVE.

## Integração e limites

`Bridge:drawSelection(x,y,canvasScale,seconds)` aceita um instante
opcional apenas para verificação determinística. A interface normal
obtém o tempo com `love.timer.getTime()`. O método preserva a seleção
e sua geometria do modo v0.37:

- Retângulos e polígonos seguem seus contornos originais.
- Máscaras raster grandes, esparsas e invertidas reutilizam o cache
  incremental, inclusive furos e ilhas distantes.
- Seleções vazias continuam invisíveis; arraste temporário permanece
  azul e não herda o shader; transformação mantém a prévia existente.
- O código compila o shader **uma única vez por contexto Bridge** e
  restaura o shader gráfico anterior em cada desenho.
- Se a GPU não puder compilar/aplicar o shader, o contorno é desenhado
  sem animação. Uma falha não dispara recompilação a cada quadro.
- `Bridge:dropImages()` libera o shader e permite recompilar em novo
  documento. Os limites de **8.192 pontos/quadro** e até **8.192
  segmentos** da versão anterior continuam valendo.

## Testes

`tests/test_selection_ants_v038.lua` valida progressão do uniform,
reutilização e descarte da GPU, fallback estático, restauração do
shader anterior, erro propagado, geometria e drag sem contaminação.

`tests/test_bridge_love.lua` renderiza o mesmo retângulo em dois
instantes numa `Canvas` real do LÖVE, compara pixels alterados no
contorno e garante que o interior e as camadas permanecem intactos.

O E2E `PAINT_LUA_SELECTION_OUTLINE_E2E=1 love .` também confirma a
criação do shader durante renderização real com zoom, pan e rotação.
A CI Linux não substitui teste de FPS ou mesa digitalizadora no Windows.
