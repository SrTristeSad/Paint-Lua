# Instruções para assistentes — Paint-Lua

- Leia PROMPT_DO_PROJETO.md, README.md e ORIGENS.md.
- A decisão atual é **projeto único** com interface e motor inteiramente neste repositório, sem submódulos.
- core/ é o motor; src/, assets/ e app/ibis_main.lua são a interface; app/paint_bridge.lua integra os dois.
- Preserve decisões, APIs, formato NPNT1–NPNT4, testes, código editável e atribuições.
- DragonBones/Bono-Lua não deve ser reinserido: não é dependência atual.
- Faça teste no LÖVE real quando possível; distinga do teste com mocks e não prometa FPS.
- Integre ferramentas gradualmente sem substituir o núcleo.
