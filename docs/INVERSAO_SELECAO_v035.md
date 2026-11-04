# Paint-Lua v0.35 — inversão da seleção

Em **Selection Area**, use **Inverter seleção** ou **Ctrl+Shift+I**.
Retângulos, laços e varinhas passam a selecionar a área complementar.
**Ctrl+I** mantém a função de importar PNG.

A seleção inversa não altera os pixels de nenhuma camada. O comando
é uma ação única de histórico, desfeita/refeita normalmente. O resultado
é salvo e reaberto em **NPNT5**, sem mudança do formato.

Com nenhuma seleção ativa, o comando seleciona tudo; ao inverter uma
seleção retangular que cobre o documento inteiro, desmarca. Nesse
último caso, a pintura volta a ficar irrestrita, como sempre ocorreu
quando não há seleção no Paint-Lua.

## Geometria e limites

Máscaras invertidas usam o bit `mask.inverted` presente no NPNT5 e
são esparsas. A função `Selection.contains` utiliza `Mask.value`,
de modo que as operações de pintura seguem o recorte exato.
Inverter uma seleção pequena em um canvas enorme não materializa
pixels para toda a tela.

Ao converter retângulo ou laço em máscara, só os pixels dentro da
área delimitadora original são avaliados, no máximo **2 milhões**.
A inversão de uma máscara já existente não clona imagens. Reverter
uma máscara invertida determina o bounding box positivo lendo até
**256 tiles**, recusando uma operação excessiva sem tocar o documento.

Em seleções invertidas muito grandes, o contorno pode mostrar apenas
a moldura geral, embora a área efetiva de pintura seja correta.
Transformar mantém seu próprio limite de 1 milhão de pixels, e a
varinha mantém seu limite de 2 milhões. Não há feather ou combinação
de seleções nesta atualização.

## Testes

`tests/test_selection_invert_v035.lua` cobre retângulos, laços,
varinha, inversão dupla, roundtrip NPNT5, documentos grandes e
histórico. `tests/test_bridge_love.lua` executa pixel real,
undo/redo e persistência com LÖVE 11.5. O teste automático em
Linux não substitui teste manual no Windows/mesa digitalizadora.
