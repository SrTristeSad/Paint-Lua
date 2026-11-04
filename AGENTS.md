# Instruções para assistentes — Paint-Lua

- Leia PROMPT_DO_PROJETO.md, README.md e ORIGENS.md.
- A decisão atual é **projeto único** com interface e motor inteiramente neste repositório, sem submódulos.
- core/ é o motor; src/, assets/ e app/ibis_main.lua são a interface; app/paint_bridge.lua integra os dois.
- Preserve decisões, APIs, formato NPNT1–NPNT5, testes, código editável e atribuições.
- DragonBones/Bono-Lua não deve ser reinserido: não é dependência atual.
- Faça teste no LÖVE real quando possível; distinga do teste com mocks e não prometa FPS.
- Integre ferramentas gradualmente sem substituir o núcleo. A v0.22 usa Fill.newJob para balde, amostragem do compositor para conta-gotas e Alpha Lock em Lua. Confira compatibilidade em mudanças de pincel.

- A v0.23 adicionou `core/selection.lua` com retângulo, laço e varinha mágica, integrados ao `app/paint_bridge.lua` e painel superior de seleção. Preserve máscaras e roundtrip NPNT5.
- Rode `texlua tests/test_core.lua` (870 casos) e os testes da UI; diferencie mocks de LÖVE real.

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
