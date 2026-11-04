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
