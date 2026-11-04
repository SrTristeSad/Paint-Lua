# Transformação raster suavizada — Paint-Lua v0.33

## Uso

Abra um desenho, selecione uma região com **retângulo**, **laço** ou **varinha**.
Escolha **Transformar**. Na barra de prévia, defina **Qualidade: Suave** (padrão
para a UI) ou **Pixelado**. Arraste a região para movê-la; use +15°/−15° ou
os controles de zoom. Clique **Aplicar** (Enter) para gravar uma única ação de
histórico; clique **Cancelar** (Esc) para descartar a sessão sem alterar a obra.

## Implementação

- `core/transform.lua`: `Transform.begin(doc,layer,selection,opts)` aceita
  `opts.interpolation='smooth'|'pixelated'`; `Transform.setInterpolation` alterna
  o modo em sessão aberta.
- **Pixelado** reproduz a transformação de seleção v0.24.
- **Suave** realiza amostragem bilinear com cores pré-multiplicadas por alfa.
  Nas bordas transformadas e nos limites de laços/varinhas, mede cobertura em
  4×4 subamostras antes de definir o alfa final. Áreas interiores usam uma
  amostra bilinear por pixel. Deslocamentos exatos de pixels não borram a fonte.
- Na confirmação, uma máscara temporária representa a nova seleção, enquanto
  os tiles são alterados sob transação do histórico com rollback.
  Pixels fora da seleção original continuam intocados na origem.
- `app/paint_bridge.lua` habilita o modo Suave para a interface; o núcleo mantém
  o default Pixelado para chamadas legadas. `app/ibis_main.lua` oferece os botões.

## Verificação e limites

A bateria simulada chega a **1.140 testes sem falhas**, incluindo os novos
`tests/test_transform_smooth_v033.lua`. Os testes LÖVE reais estão em
`tests/test_bridge_love.lua` e no controle E2E
`PAINT_LUA_TRANSFORM_FILTER_E2E=1 love .`, executados pelo GitHub Actions.

Não existe transformação em objeto inteligente ou vetor após aplicar: é um commit
raster. Os limites de área permanecem em 1 milhão de pixels de origem e de
destino. A suavização aumenta o tempo de CPU, especialmente em silhuetas
complexas e grandes. Não declarar validação no Windows ou FPS sem medição real.
