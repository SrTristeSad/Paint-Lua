# Paint-Lua — Projeto único

Editor experimental de pintura digital em Lua / LÖVE 11.5. A interface de Ibis-Lua e o núcleo de pintura v0.21 são **código-fonte do mesmo repositório**. Não há submódulos, download do Ibis-Lua na inicialização ou integração atual com DragonBones/Bono-Lua.

## Teste no Windows

1. Instale LÖVE 11.5: https://love2d.org/.
2. Baixe o ZIP completo do projeto e extraia-o.
3. Execute **testar.bat** na pasta raiz. Não precisa de Git, Python, PowerShell ou conexão à internet para iniciar.

Clone alternativo: git clone https://github.com/SrTristeSad/Paint-Lua.git (sem --recurse-submodules).

## Organização

- **core/**: os 20 módulos Lua editáveis do núcleo v0.21, com pincéis, tiles, composição, histórico, máscaras, grupos e NPNT1–NPNT4.
- **src/**: estados da interface Ibis-Lua, galeria, pincéis, cores, layout e preferências.
- **assets/icons/png/** e **assets/icons/svg/**: ícones Lucide, PNGs para LÖVE e fontes SVG editáveis. Licença em assets/icons/LICENSE-LUCIDE.txt.
- **app/ibis_main.lua**: interface Ibis-Lua adaptada para renderizar os pixels reais.
- **app/paint_bridge.lua**: conexão de ferramentas, documentos, camadas, pincel, histórico e salvamento ao núcleo.
- **main.lua**, **conf.lua**, **testar.bat**: inicialização.
- **tests/**, **tools/**, **docs/**: testes e documentação da interface e do núcleo.

## Situação funcional

A UI disponibiliza tela inicial, galeria, New Canvas, ferramentas, janelas de pincel, cores e camadas. O motor é responsável por pixels reais: **pintura básica, borracha, camadas simples, desfazer/refazer e salvar/reabrir .npnt**. Zoom, rotação e pan usam a UI. Vários controles de filtros, transformações, máscaras, grupos e galeria **ainda são demonstrativos ou parcialmente integrados**. Não se deve assumir que um botão que existe na interface altera pixels.

O núcleo v0.21 registrou 777 testes históricos com mocks. A integração básica passou em **LÖVE 11.5 real em Linux sob display virtual**, incluindo pincel, undo/redo e NPNT. Ainda são necessários testes manuais no Windows, desempenho e uso de caneta/tablet.

## Créditos e continuidade

Os fontes da interface foram incorporados de https://github.com/SrTristeSad/Ibis-Lua (revisão fixada e atribuída em ORIGENS.md). Não é o aplicativo oficial ibisPaint. PhotoCraft é referência técnica; ibisPaint é referência funcional. Consulte LICENSE-PHOTOCRAFT-MIT.txt, ORIGENS.md e a licença dos ícones Lucide.

Para continuar em outro chat: PROMPT_DO_PROJETO.md e AGENTS.md.
