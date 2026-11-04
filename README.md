# Paint-Lua — Projeto único

Editor experimental de pintura digital em Lua / LÖVE 11.5. A interface de Ibis-Lua e o núcleo de pintura v0.21 são **código-fonte do mesmo repositório**. Não há submódulos, download do Ibis-Lua na inicialização ou integração atual com DragonBones/Bono-Lua.

## Teste no Windows

1. Instale LÖVE 11.5: https://love2d.org/.
2. Baixe o ZIP completo do projeto e extraia-o.
3. Execute **testar.bat** na pasta raiz. Não precisa de Git, Python, PowerShell ou conexão à internet para iniciar.

Clone alternativo: git clone https://github.com/SrTristeSad/Paint-Lua.git (sem --recurse-submodules).

## Organização

- **core/**: os 21 módulos Lua editáveis do núcleo (base v0.21 + seleção v0.23), com pincéis, tiles, histórico, máscaras, grupos e leitura NPNT1–NPNT5.
- **src/**: estados da interface Ibis-Lua, galeria, pincéis, cores, layout e preferências.
- **assets/icons/png/** e **assets/icons/svg/**: ícones Lucide, PNGs para LÖVE e fontes SVG editáveis. Licença em assets/icons/LICENSE-LUCIDE.txt.
- **app/ibis_main.lua**: interface Ibis-Lua adaptada para renderizar os pixels reais.
- **app/paint_bridge.lua**: conexão de ferramentas, documentos, camadas, pincel, histórico e salvamento ao núcleo.
- **main.lua**, **conf.lua**, **testar.bat**: inicialização.
- **tests/**, **tools/**, **docs/**: testes e documentação da interface e do núcleo.

## Situação funcional

A UI disponibiliza tela inicial, galeria, New Canvas, ferramentas, janelas de pincel, cores e camadas. O motor é responsável por pixels reais: **pintura, borracha, balde cooperativo, conta-gotas, Alpha Lock durante a sessão, camadas, recorte, desfazer/refazer e salvar/reabrir .npnt**. Zoom, rotação e pan usam a UI. Vários controles de filtros, transformações, máscaras, grupos e galeria **ainda são demonstrativos ou parcialmente integrados**. Não se deve assumir que um botão que existe na interface altera pixels.

A bateria do núcleo foi incorporada ao repositório na v0.23: **870 testes aprovados em texlua com mocks**, incluindo seleção, laço e NPNT5. A integração do editor também é verificada em LÖVE 11.5 real em Linux com display virtual. A integração básica passou em **LÖVE 11.5 real em Linux sob display virtual**, incluindo pincel, undo/redo e NPNT. Ainda são necessários testes manuais no Windows, desempenho e uso de caneta/tablet.

## Seleção na v0.23

No painel superior **Selection Area** há seleção por **retângulo**, **laço** e **varinha mágica**, além de Selecionar tudo e Desmarcar. O laço e a varinha também aparecem na barra de ferramentas. O desenho e o balde respeitam a área selecionada; desfazer/refazer restaura seleções anteriores. **Ctrl+A** seleciona tudo, **Ctrl+D** desmarca, **Esc** cancela a seleção em andamento ou a remove.

O **NPNT5** preserva o laço e a máscara da varinha ao salvar e abrir; projetos antigos (NPNT1–NPNT4) continuam legíveis. A varinha opera por cor RGBA da **camada ativa** com um limite de segurança de 2 milhões de pixels, em execução cooperativa. A seleção não possui feather nem antialiasing ainda. [Comportamento detalhado e limites](docs/SELECAO_v023.md).

## Novidades da integração v0.22

- **Balde:** usa o preenchimento scanline cooperativo do núcleo, distribuído em fatias por quadro; **Esc** cancela a operação, com rollback.
- **Conta-gotas:** amostra a cor composta dos pixels do desenho e atualiza o seletor de cores da interface.
- **Alpha Lock:** o pincel muda somente a cor dos pixels já opacos, sem criar novos pixels transparentes. A borracha não altera o alfa quando a trava está ativa.
- **Camadas:** visibilidade, clipping e blending alteram a composição real e entram no histórico; o slider de opacidade não cria centenas de entradas de undo. Desfazer/refazer atualiza também o estado do painel.
- **Limites conhecidos:** Alpha Lock e a flag de camada bloqueada ainda são estados da interface, **não persistem em .npnt**; o balde é bloqueado quando Alpha Lock está ligado. Os thumbnails das camadas e as amostras de pincéis continuam ilustrativos. Não há testes de FPS/tablet/Windows nem paridade de Alpha Lock no caminho FFI; nesse modo o pincel usa o caminho Lua.

## Créditos e continuidade

Os fontes da interface foram incorporados de https://github.com/SrTristeSad/Ibis-Lua (revisão fixada e atribuída em ORIGENS.md). Não é o aplicativo oficial ibisPaint. PhotoCraft é referência técnica; ibisPaint é referência funcional. Consulte LICENSE-PHOTOCRAFT-MIT.txt, ORIGENS.md e a licença dos ícones Lucide.

Para continuar em outro chat: PROMPT_DO_PROJETO.md e AGENTS.md.
