# Paint-Lua v0.37 — contornos reais de seleções extensas

## O problema resolvido

Quando uma seleção de varinha, máscara combinada ou complemento
invertido tinha uma área delimitadora grande, a interface v0.36
exibia apenas a *bounding box* — que não necessariamente correspondia
à área selecionada. Uma ilha distante ou um grande buraco podia
parecer uma seleção retangular sólida.

## Comportamento atual

O contorno de máscaras raster `kind='wand'` é calculado por arestas
entre pixels selecionados e não selecionados. Para máscaras esparsas,
o programa percorre apenas os tiles materializados, **não a área
retangular inteira entre ilhas**.

Máscaras invertidas exibem os contornos dos buracos armazenados e
o perímetro externo do canvas, mas somente nos trechos em que o
pixel da borda realmente está selecionado. Isso evita desenhar
uma linha sobre um buraco que alcança a extremidade da imagem.

- As linhas são coordenadas do documento: zoom, rotação e deslocamento
  do canvas utilizam o mesmo cache.
- Regiões pequenas continuam usando o contorno síncrono existente;
  regiões maiores são calculadas de modo incremental.
- Cada quadro examina no máximo **8.192 pontos**. Enquanto o
  processamento continua, linhas já computadas podem aparecer antes
  das demais; não existe fallback retangular enganoso.
- O máximo de **8.192 segmentos** limita memória e operações de
  desenho. Em seleções extremamente complexas o contorno visual
  pode ficar incompleto; a máscara exata de pintura não é alterada.
- Uma seleção vazia tem zero segmentos, não uma moldura falsa.

## Compatibilidade e segurança

`Selection.outline` foi preservada como API síncrona.
As novas APIs são `Selection.startOutline` e
`Selection.stepOutline`. O cache da UI é invalidado ao trocar a
identidade da seleção. A operação não mexe em pixels, seleção,
undo/redo, persistência nem NPNT5.

A melhoria não implementa animação *marching ants*, feather,
antialias de seleção ou seleção vetorial. Testes de desempenho
no Windows e em tablet permanecem pendentes.

## Testes

`tests/test_selection_outline_v037.lua` valida perímetro e buracos
exatos, ilhas distantes, limites de trabalho, truncamento seguro,
máscaras vazias, cache no zoom e desenho sem bbox falsa.
`tests/test_bridge_love.lua` valida a GPU com LÖVE 11.5 real.
`PAINT_LUA_SELECTION_OUTLINE_E2E=1 love .` valida a interface
com rotação, pan e zoom no Linux com display virtual.
