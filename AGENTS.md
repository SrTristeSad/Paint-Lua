# Instruções para assistentes — Paint-Lua

- Leia PROMPT_DO_PROJETO.md, README.md e ORIGENS.md.
- A decisão atual é **projeto único** com interface e motor inteiramente neste repositório, sem submódulos.
- core/ é o motor; src/, assets/ e app/ibis_main.lua são a interface; app/paint_bridge.lua integra os dois.
- Preserve decisões, APIs, formato NPNT1–NPNT5, testes, código editável e atribuições.
- DragonBones/Bono-Lua não deve ser reinserido: não é dependência atual.
- Faça teste no LÖVE real quando possível; distinga do teste com mocks e não prometa FPS.
- Integre ferramentas gradualmente sem substituir o núcleo. A v0.22 usa Fill.newJob para balde, amostragem do compositor para conta-gotas e Alpha Lock em Lua. Confira compatibilidade em mudanças de pincel.

- A v0.23 adicionou `core/selection.lua` com retângulo, laço e varinha mágica, integrados ao `app/paint_bridge.lua` e painel superior de seleção. Preserve máscaras e roundtrip NPNT5.
- Rode `texlua tests/test_core.lua` (1.140 casos na v0.33) e os testes da UI; diferencie mocks de LÖVE real.

- v0.24: `core/transform.lua` realiza recortar/colar raster com preview antes do commit;
  `core/history.lua` suporta histórico combinado de pixels+seleção. Não quebrar undo único
  ou a compatibilidade NPNT1–NPNT5. Não oferecer transformação ilimitada sem avaliação
  de memória/CPU; limite atual de 1 milhão de pixels.

- v0.25: painel `layer_advanced` com 3 abas; `Bridge:layerMaskAction`, `Bridge:groupAction`, `Bridge:editMask` etc. reutilizam APIs existentes de `core.layers`, `core.groups` e `core.stroke`. O modo de máscara não deve modificar os pixels RGBA, e a UI deve manter coerência após undo/redo e load.
- Execute `texlua tests/test_core.lua` (969 verificações simuladas) e CI LÖVE 11.5. Nova camada no fim da pilha herda groupId quando aplicável. Veja `docs/GRUPOS_MASCARAS_v025.md`.

## Atualização v0.26
Miniaturas reais de camadas/máscaras com cache de revisões (`core/thumbnail.lua`), ordenação de camadas atômica (`core/layers.lua`) e movimentação de grupos inteiros entre irmãos (`core/groups.lua`). O painel Layer suporta scroll, ↑/↓ e arraste de linhas visíveis; o painel avançado tem ↑/↓ de grupos. Sem alterar NPNT5. Movimentos inválidos são bloqueados, histórico e IDs permanecem corretos. Próximos trabalhos: miniatura composta de grupos, scroll/drag refinados e desempenho no Windows.

- **v0.27:** a galeria persiste no save-directory do LÖVE; um NPNT por ID e dois índices alternados. Nunca gere nome de arquivo a partir do nome de uma obra. O backup `.bak` e a migração de `meu-desenho.npnt` não devem ser descartados.
- Rode `tests/test_gallery_storage.lua` e o teste E2E em duas execuções LÖVE ao modificar catalogação e salvamento.


### Atualização v0.28
A galeria agora usa miniaturas PNG derivadas dos arquivos `.npnt` e exporta composição PNG sem destruir as obras. `src/artwork_preview.lua` gera prévias por tiles sem alocar canvas inteiro; `src/png_export.lua` gera PNG até 4.194.304 pixels; `src/gallery_storage.lua` gerencia cache persistente por ID; `app/ibis_main.lua` oferece comandos de UI. Testes em `tests/test_gallery_preview_v028.lua`, `tests/test_core.lua`, e na CI de persistência da galeria. Não afirmar que suporta JPEG/PSD ou que o desempenho no Windows foi medido.


### v0.29 — Importação PNG
`src/png_import.lua` converte PNG para camada raster em memória antes de alterar o documento, cria uma ação de histórico e preserva a origem. `Bridge:importPNGBytes`/`importPNGFromFolder` integram; a UI oferece arrastar arquivo e Back > Importar PNG / Ctrl+I. Preserve validação de tamanho/assinatura, proteção de caminho, alpha, undo/redo e compatibilidade NPNT5. Rode `texlua tests/test_core.lua` e CI com `love .` (LÖVE 11.5). A integração não significa suporte a JPEG/PSD ou validação no Windows.

- v0.30: importação PNG é prévia ajustável; não adicione tiles antes de aplicar. `src/png_import.lua` reutiliza `core.transform` para geometria. Preserve API antiga `Import.insert` e testes de não alteração/cancelamento/limites.

- v0.31: não confundir o filtro de visualização de canvas com a interpolação
  da **importação PNG**. Suave usa bilinear com alfa pré-multiplicado; Pixelado
  usa nearest; chamadas legadas `PNGImport.insert` continuam nearest.

## Atualização v0.32 — importação PNG

A rasterização suave de PNGs com rotação oblíqua aplica antialias por subamostragem com acumulação de RGB premultiplicada por alfa (`src/png_import.lua`). A importação pixelada e a transformação de seleções permanecem inalteradas. A UI expõe −1°, +1° e reset de giro; validar via `tests/test_png_rotation_aa_v032.lua`, E2E no LÖVE e documentação `docs/ROTACAO_PNG_v032.md`.

## Atualização v0.33 — suavização de transformações de seleção

`core/transform.lua` implementa `Transform.setInterpolation(s, 'smooth'|'pixelated')` e
`Transform.begin(...,{interpolation='smooth'})`. A API antiga continua pixelada;
`Bridge:startTransform` inicia Suave e a UI permite mudar para Pixelado. O
resultado raster e a máscara da seleção são aplicados como uma só ação do
histórico, incluindo undo/redo. O algoritmo bilinear usa RGB premultiplicado
por alfa e cobertura 4x4 nos contornos; manter a proteção de 1 milhão de pixels.
Testes em `tests/test_transform_smooth_v033.lua` e E2E com
`PAINT_LUA_TRANSFORM_FILTER_E2E=1 love .`. Não confundir com filtros PNG.

### Integração v0.34

As alças de Transformar são calculadas em `core/transform.lua` e usadas em `app/paint_bridge.lua`; manter hit-test e desenho sincronizados. Arrastar cantos preserva a proporção e o canto oposto. Alças ficam ocultas se a seleção ocupar menos de 28 px em tela. Veja `docs/ALCAS_TRANSFORMACAO_v034.md` e a suíte de testes.

### Atualização v0.35

`core.selection.invert` oferece complemento esparso de retângulos, laços
e varinha usando `mask.inverted=true`. `Selection.contains` agora consulta
`Mask.value`, sem mudança de formato NPNT5. A inversão não altera pixels,
entra como um só undo e é acessada por `Bridge:invertSelection`, pelo painel
Selection Area e por Ctrl+Shift+I (Ctrl+I ainda importa PNG).
A rasterização inicial de retângulos/laços é limitada a 2 milhões de pixels;
a reversão de máscaras invertidas lê no máximo 256 tiles para a bounding box.
Consulte `docs/INVERSAO_SELECAO_v035.md` e a suíte de testes.

### Atualização v0.36 — combinações booleanas

`Selection.combine(doc,old,new,'replace'|'add'|'subtract'|'intersect')`
produz máscaras esparsas NPNT5 com suporte a inversões anteriores,
sem alterar as entradas de histórico. `nil` significa pintura irrestrita,
portanto combinações vazias geram máscara explícita de zero pixels,
jamais `nil`. A ponte expõe `Bridge:setSelectionMode` e
`Bridge:combineSelection`; os três gestos (retângulo, laço e varinha)
aplicam o modo capturado quando começaram. Selecionar tudo, Desmarcar e
Inverter continuam comandos independentes. Limite: 2 milhões de pixels
e 256 tiles candidatos por combinação. Ver
`docs/COMBINACAO_SELECOES_v036.md`,
`tests/test_selection_combine_v036.lua` e
`PAINT_LUA_SELECTION_COMBINE_E2E=1 love .`.
