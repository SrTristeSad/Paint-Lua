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

A UI disponibiliza tela inicial, galeria, New Canvas, ferramentas, janelas de pincel, cores e camadas. O motor é responsável por pixels reais: **pintura, borracha, balde cooperativo, conta-gotas, Alpha Lock durante a sessão, camadas, recorte, desfazer/refazer e salvar/reabrir .npnt**. Zoom, rotação e pan usam a UI. Vários controles de filtros, transformações, máscaras, grupos e galeria **ainda são demonstrativos ou parcialmente integrados**. Não se deve assumir que um botão que existe na interface altera pixels.

A base v0.21 registrou 777 testes históricos com mocks. A integração v0.22 incorporou testes novos de Alpha Lock e sincronização de camadas; o pacote de desenvolvimento local passou em **806 verificações simuladas** (a bateria completa antiga ainda não está versionada neste repositório). A integração básica passou em **LÖVE 11.5 real em Linux sob display virtual**, incluindo pincel, undo/redo e NPNT. Ainda são necessários testes manuais no Windows, desempenho e uso de caneta/tablet.

## Novidades da integração v0.22

- **Balde:** usa o preenchimento scanline cooperativo do núcleo, distribuído em fatias por quadro; **Esc** cancela a operação, com rollback.
- **Conta-gotas:** amostra a cor composta dos pixels do desenho e atualiza o seletor de cores da interface.
- **Alpha Lock:** o pincel muda somente a cor dos pixels já opacos, sem criar novos pixels transparentes. A borracha não altera o alfa quando a trava está ativa.
- **Camadas:** visibilidade, clipping e blending alteram a composição real e entram no histórico; o slider de opacidade não cria centenas de entradas de undo. Desfazer/refazer atualiza também o estado do painel.
- **Limites conhecidos:** Alpha Lock e a flag de camada bloqueada ainda são estados da interface, **não persistem em .npnt**; o balde é bloqueado quando Alpha Lock está ligado. Os thumbnails das camadas e as amostras de pincéis continuam ilustrativos. Não há testes de FPS/tablet/Windows nem paridade de Alpha Lock no caminho FFI; nesse modo o pincel usa o caminho Lua.

## Créditos e continuidade

Os fontes da interface foram incorporados de https://github.com/SrTristeSad/Ibis-Lua (revisão fixada e atribuída em ORIGENS.md). Não é o aplicativo oficial ibisPaint. PhotoCraft é referência técnica; ibisPaint é referência funcional. Consulte LICENSE-PHOTOCRAFT-MIT.txt, ORIGENS.md e a licença dos ícones Lucide.

Para continuar em outro chat: PROMPT_DO_PROJETO.md e AGENTS.md.
