# Paint-Lua — Projeto único (v0.39)

Editor experimental de pintura digital em Lua / LÖVE 11.5. A interface de Ibis-Lua e o núcleo de pintura v0.21 são **código-fonte do mesmo repositório**. Não há submódulos, download do Ibis-Lua na inicialização ou integração atual com DragonBones/Bono-Lua.

## Verificação automatizada no Windows

A CI da versão v0.39 agora executa **dois jobs**: o teste completo
de pixels e interface no LÖVE 11.5 no Linux e uma verificação adicional
em **`windows-latest`** do ZIP realmente disponibilizado ao usuário.
O job Windows extrai o pacote, baixa e valida por SHA-256 o runtime
portátil oficial do LÖVE 11.5, executa `testar.bat` com
`PAINT_LUA_VERIFY_ONLY=1` e comprova que o launcher recusa um arquivo
essencial ausente. Esse modo de verificação **não abre a interface**;
no uso normal, `testar.bat` continua a abrir o editor normalmente.

O job Windows também tenta rodar o **editor real com `lovec.exe`**,
capturar uma imagem PNG da interface e executar os testes de integração
NPNT, máscaras e GPU diretamente no Windows. Essa etapa é executada do
**ZIP extraído**, sem depender de arquivos do checkout do GitHub.
O runner Windows do GitHub ofereceu apenas **OpenGL 1.1 (GDI Generic)**,
abaixo do requisito do LÖVE 11.5 (**OpenGL 2.1 ou OpenGL ES 2**).
A CI emite um **aviso de teste gráfico não executado**, mantendo a
validação do pacote e do inicializador. Essa dispensa é permitida
**somente** quando o próprio LÖVE diagnostica esse driver incompatível;
erros de aplicação, falhas inesperadas e timeouts continuam reprovando.

Em um Windows com GPU compatível, o script
`scripts/windows-love-e2e.ps1` exige a inicialização, a captura PNG
e os testes de integração. Uma sessão manual ainda é necessária para
testar canetas, mesas digitalizadoras e desempenho em outras GPUs.

## Teste no Windows

1. Instale LÖVE 11.5: https://love2d.org/.
2. Baixe o ZIP completo do projeto e extraia-o.
3. Execute **testar.bat** na pasta raiz. Não precisa de Git, Python, PowerShell ou conexão à internet para iniciar.

Clone alternativo: git clone https://github.com/SrTristeSad/Paint-Lua.git (sem --recurse-submodules).

## Proteção das operações de seleção

Os comandos **Selecionar tudo**, **Inverter**, **Combinar** e
**Desmarcar** compartilham agora a mesma proteção contra mudanças
enquanto há uma pincelada, **preenchimento cooperativo**, arraste de
seleção, transformação ou prévia de PNG em andamento. Isso evita alterar a seleção e criar
histórico intermediário antes de concluir o gesto. As ferramentas
continuam funcionando normalmente quando a operação termina.

Detalhes e testes em
[docs/REVISAO_INTEGRACAO_v039.md](docs/REVISAO_INTEGRACAO_v039.md).

## Revisão de integração v0.35–v0.39

A revisão da linha de desenvolvimento identificou e corrigiu um caso
de segurança da seleção: **inverter uma área que cobre o documento todo
agora cria uma seleção vazia de verdade**. Anteriormente essa operação
removia a seleção (`nil`), liberando a pintura em toda a obra. Assim,
**Inverter** mantém o significado de complemento e **Desmarcar**
(Ctrl+D) continua sendo o comando explícito para pintura irrestrita.

A mesma revisão evita inicializar ou executar o shader das formigas
quando não há nenhum pixel selecionado. Foram incluídos testes de
inversão, combinação, pincel/balde, histórico, NPNT5 e renderização
em LÖVE real. A correção integra o **PR #6**, sem abrir outro PR ou
alterar a `main`.

Detalhes e ordem de integração: [docs/REVISAO_INTEGRACAO_v039.md](docs/REVISAO_INTEGRACAO_v039.md).

## Novidade v0.39 — pausar animação dos contornos

O editor oferece **Settings → Animar contorno da seleção** para
ligar ou desligar o movimento das faixas `marching ants`.

A animação continua **ligada por padrão**, como na v0.38. Quando a
opção é desligada, o programa desenha o **contorno estático vermelho**
da v0.37, **sem executar ou compilar o shader**. Se o shader já estiver
carregado, ele é liberado; ao reativar a animação, é criado novamente.
A geometria da seleção, inclusive inversões e contornos esparsos,
permanece intacta, assim como os pixels, NPNT5 e undo/redo.

A preferência é gravada automaticamente em `editor-preferences.txt`
e restaurada ao abrir o aplicativo. O formato de preferências continua
`version=1`: arquivos antigos, que não têm essa opção, usam o valor
padrão animado; campos inválidos e duplicados seguem rejeitados.
O teste de interface abre o editor em **duas execuções do LÖVE** para
verificar desligar, salvar, reabrir e reativar.

Veja [docs/PAUSA_CONTORNOS_v039.md](docs/PAUSA_CONTORNOS_v039.md).

## Novidade v0.38 — contornos animados (*marching ants*)

As áreas selecionadas agora são marcadas por faixas **claras e escuras
em movimento**. A animação é aplicada por shader sobre os **contornos
exatos** já disponíveis na v0.37 — retângulos, laços, varinha mágica,
uniões/subtrações e máscaras invertidas continuam usando a mesma
geometria de seleção.

O desenho utiliza coordenadas da tela para manter faixas de aproximadamente
**5 pixels**, mesmo durante zoom, rotação e deslocamento. A velocidade
é de **24 pixels por segundo** e o shader é reutilizado entre quadros,
sem recalcular pixels de máscara nem criar novos passos de histórico.
As seleções grandes continuam gerando as bordas progressivamente,
com os mesmos limites da v0.37.

Se shaders não estiverem disponíveis, o contorno permanece **estático**
em vez de impedir o uso do editor. A versão não altera RGBA, formatos
NPNT1–NPNT5, desfazer/refazer ou as decisões de UI anteriores.

Veja [docs/CONTORNOS_ANIMADOS_v038.md](docs/CONTORNOS_ANIMADOS_v038.md).

## Novidade v0.37 — contornos reais para seleções grandes

Seleções grandes, descontínuas ou invertidas agora exibem os **contornos
reais dos pixels** em vez de uma moldura retangular que poderia sugerir
uma área selecionada incorreta.

O editor calcula o contorno gradualmente, percorrendo apenas os tiles da
máscara que existem. As áreas invertidas mostram também o perímetro externo
do canvas **somente onde há pixels selecionados**, respeitando buracos
que encostam nas bordas. Durante o cálculo, as linhas já disponíveis são
exatas; novas bordas aparecem progressivamente nos quadros seguintes.

O trabalho por quadro tem limite de **8.192 pontos**; o cache é reutilizado
ao mover, girar ou ampliar a visualização. Seleções extremamente recortadas
têm limite de **8.192 segmentos** para preservar a responsividade;
nesse caso parte das linhas pode não ser exibida, mas nunca é substituída
por uma moldura falsa. Os pixels, o histórico e o formato NPNT5 não mudaram.

Veja [docs/CONTORNOS_SELECAO_v037.md](docs/CONTORNOS_SELECAO_v037.md).

## Novidade v0.36 — combinar seleções

A seção **Selection Area** agora permite escolher como o próximo retângulo,
laço ou clique da varinha interage com a seleção existente:

- **Nova**: substitui a área anterior (comportamento das versões anteriores).
- **Somar**: mantém a seleção anterior e acrescenta a nova região.
- **Subtrair**: remove da seleção os pixels da nova região.
- **Interseção**: mantém somente os pixels presentes nas duas regiões.

O modo escolhido permanece ativo para os gestos seguintes e funciona com
máscaras invertidas da v0.35. Cada operação aplicada é **um único passo
de desfazer/refazer**. Pintura e pixels antigos permanecem intactos até
o usuário pintar ou transformar a região. Arquivos NPNT5 preservam a
máscara resultante sem alterar o formato.

**Atenção:** uma combinação que resulta em zero pixels cria uma *seleção
vazia real*, e não `nil` (que no Paint-Lua significa editar sem restrições).
Se não havia seleção anterior, Somar inicia uma seleção nova; Subtrair e
Interseção não mudam o documento. Operações que exigiriam avaliar mais de
**2 milhões de pixels ou 256 tiles** são recusadas antes de modificar
a seleção ou o histórico. Veja
[docs/COMBINACAO_SELECOES_v036.md](docs/COMBINACAO_SELECOES_v036.md).

## Novidade v0.35 — inverter seleção

No painel **Selection Area → Inverter seleção** (atalho **Ctrl+Shift+I**),
a área selecionada passa a ficar excluída e o restante do canvas passa a
ser selecionado. Funciona com retângulos, laços e varinha; **Ctrl+I**
continua reservado à importação PNG.

O comando não altera pixels, cria uma operação de histórico e é salvo em
**NPNT5**. A inversão usa uma máscara esparsa, sem rasterizar todo o canvas.
Inverter sem seleção seleciona tudo; inverter uma seleção retangular total
agora produz uma **seleção vazia**. Use Desmarcar para liberar a pintura. Por segurança, regiões iniciais retangulares ou laços com mais
de **2 milhões de pixels** não podem ser invertidos de uma vez.

Consulte [docs/INVERSAO_SELECAO_v035.md](docs/INVERSAO_SELECAO_v035.md).
Transformar mantém os limites e filtros Suave/Pixelado existentes.

## Novidade v0.34 — alças de transformação

A ferramenta **Transformar** agora oferece controles no próprio canvas:
**cantos** para redimensionar com o canto oposto fixo, **círculo acima da
seleção** para girar com o mouse e **arraste dentro da moldura girada** para
mover. As alças acompanham zoom/rotação/pan da visualização e mantêm tamanho
constante em tela. Para seleções muito pequenas, as alças ficam ocultas para
permitir arrastar um pixel; use os botões de zoom para fazê-las reaparecer.

Os modos **Suave/Pixelado**, botões de ±15°, zoom, aplicar/cancelar, histórico
e NPNT5 permanecem compatíveis. Consulte
[docs/ALCAS_TRANSFORMACAO_v034.md](docs/ALCAS_TRANSFORMACAO_v034.md).

## Novidade v0.33 — transformação Suave/Pixelado de áreas selecionadas

A ferramenta **Transformar** (selecione retângulo, laço ou varinha e escolha
**Transformar**) agora tem **Qualidade → Suave / Pixelado** acima dos botões de
ângulo, escala, Cancelar e Aplicar. A interface começa em **Suave**.

- **Suave:** interpolação bilinear com RGBA pré-multiplicado e cobertura subpixel
  nas bordas de seleções deslocadas, redimensionadas e rotacionadas; evita halos
  de pixels transparentes e reduz serrilhado dos contornos oblíquos.
- **Pixelado:** conserva o algoritmo nearest-neighbor da v0.24, adequado para
  pixel art ou para obter resultados compatíveis com a versão anterior.
- **Aplicar/Enter:** move os pixels e a seleção em **uma única ação de histórico**.
  **Cancelar/Esc:** não modifica a obra. O filtro é somente desta sessão, não
  do pincel ou da importação PNG.

A API `Transform.begin` **permanece Pixelado por padrão** para não mudar scripts
existentes; a ponte da interface habilita Suave explicitamente. O formato
continua **NPNT5**, sem alteração de compatibilidade.

**Limites:** não há escolha de interpolação persistida como propriedade de camada,
nem transformação vetorial; a ação final ainda é raster. Áreas de origem e
destino seguem limitadas a **1 milhão de pixels** e suavização exige mais CPU.
Windows, tablet e desempenho em documentos grandes ainda precisam de verificação
manual. [Guia técnico v0.33](docs/TRANSFORMACAO_SUAVE_v033.md).

## Novidade v0.32 — antialias de rotação e giro fino

Ao rotacionar um PNG no modo **Suave**, as bordas inclinadas agora usam cobertura subpixel (2×2 nas áreas internas, 4×4 junto às bordas), com RGB pré-multiplicado por alfa. Isso reduz serrilhados e evita franjas de cores invisíveis. O modo **Pixelado** preserva os pixels duros. Importações sem giro continuam com a amostragem v0.31, evitando alterações inesperadas nos resultados anteriores.

Na prévia PNG, use **−1° / +1° / Giro 0°** para ajustes finos, além dos botões de 15°, zoom, **Aplicar** e **Cancelar**. A interface mostra o ângulo e a escala atuais. A nova suavização pode consumir mais CPU em importações grandes. A aplicação mantém uma única operação de histórico e salva em NPNT5, sem modificar o PNG original. [Guia e limitações v0.32](docs/ROTACAO_PNG_v032.md).

## Novidade v0.31 — qualidade da importação PNG (Suave / Pixelado)

A prévia de importação ganhou **dois modos de qualidade**, exibidos acima dos botões de
mover/rotacionar/aplicar:

- **Suave (padrão na interface):** interpolação bilinear CPU com cores pré-multiplicadas
  por alfa. Redimensiona e gira fotografias com transições mais suaves; pixels totalmente
  transparentes não contaminam a cor das bordas (evita halos). A prévia usa filtro
  linear na GPU, e o **resultado final é rasterizado pelo núcleo**, não capturado da tela.
- **Pixelado:** usa a amostragem nearest-neighbor da v0.30; mantém as bordas duras
  de pixel art. Pode alternar os modos quantas vezes quiser antes de **Aplicar**.

A escolha é por **importação**, não altera o filtro do canvas nem a forma de pintar.
A chamada legada `PNGImport.insert(doc, image, nome)` continua usando nearest-neighbor
para não quebrar scripts antigos; a prévia aberta pela UI inicia em Suave.
Aplicar continua criando **uma camada e uma única entrada no histórico**; Cancelar não
altera a obra. Arquivos NPNT5 antigos continuam legíveis.

**Limites:** a interpolação é bilinear, não bicúbica; ainda há contorno raster em
silhuetas rotacionadas, e imagens grandes podem exigir processamento na CPU. Mantêm-se
os limites de 16 MiB/2.097.152 pixels e escala 0,125×–8×. Windows e mesa
digitalizadora ainda precisam de teste manual.
[Guia técnico v0.31](docs/INTERPOLACAO_PNG_v031.md).

## Novidade v0.30 — prévia ajustável da importação PNG

Ao arrastar um PNG sobre uma obra aberta, ou escolher uma imagem em **Back → Importar PNG** (também em `Ctrl+I`), o editor agora abre uma **prévia flutuante**. O arquivo não é inserido imediatamente: você pode **arrastar para posicionar, girar em passos de 15° e aumentar/reduzir em passos de 10%**. Só o botão **Aplicar** ou **Enter** insere uma nova camada. **Esc** ou **Cancelar** descarta a prévia sem modificar pixels, camadas, histórico nem NPNT. As setas movem um pixel por tecla; **Q/R** giram; **+/-** ajustam escala.

A v0.30 original rasterizava em *nearest-neighbor*; a **v0.31 acrescentou o modo Suave (bilinear) sem perder Pixelado**. A operação continua recortada no canvas e registrada como **uma única ação desfazer/refazer**. O PNG original não é alterado. A camada importada é salva no NPNT5. O fluxo antigo de importação por API (`PNGImport.insert`) permanece suportado para scripts.

**Limites:** até 2.097.152 pixels no PNG de origem e na área rasterizada visível, 16 MiB de arquivo, dimensões máximas de 8.192 por lado e escala de 0,125× a 8×. A interpolação bilinear foi acrescentada na v0.31, mas ainda não há alças de arraste para rotação/escala nem edição posterior como objeto inteligente. A prévia impede salvar ou editar outras camadas até aplicar/cancelar. Testar manualmente no Windows e em mesa digitalizadora continua necessário.

## Organização

- **core/**: os 22 módulos Lua editáveis do núcleo (base v0.21 + seleção v0.23 + transformações v0.24), com pincéis, tiles, histórico, máscaras, grupos e leitura NPNT1–NPNT5.
- **src/**: estados da interface Ibis-Lua, galeria, pincéis, cores, layout e preferências.
- **assets/icons/png/** e **assets/icons/svg/**: ícones Lucide, PNGs para LÖVE e fontes SVG editáveis. Licença em assets/icons/LICENSE-LUCIDE.txt.
- **app/ibis_main.lua**: interface Ibis-Lua adaptada para renderizar os pixels reais.
- **app/paint_bridge.lua**: conexão de ferramentas, documentos, camadas, pincel, histórico e salvamento ao núcleo.
- **main.lua**, **conf.lua**, **testar.bat**: inicialização.
- **tests/**, **tools/**, **docs/**: testes e documentação da interface e do núcleo.

## Novidade v0.27 — galeria de múltiplas obras

A **My Gallery** agora persiste obras diferentes em arquivos NPNT separados, com pastas, títulos e movimentação de itens preservados após reiniciar o programa. O editor **salva automaticamente ao voltar à galeria e ao encerrar normalmente**, além de permitir `Ctrl+S`. Ele mostra erro e mantém a edição aberta quando o salvamento falha. Um arquivo ausente/corrompido não é substituído por um canvas em branco.

O catálogo alterna entre dois índices validados, e cada obra mantém uma cópia de segurança anterior ao sobrescrever; o formato de projeto continua **NPNT1–NPNT5**. Ao iniciar sem catálogo, tenta importar o antigo `meu-desenho.npnt` sem apagá-lo. O repositório e o ZIP continuam completamente independentes do Ibis-Lua.

Consulte [docs/GALERIA_PERSISTENTE_v027.md](docs/GALERIA_PERSISTENTE_v027.md) para limites e recuperação. **Ainda não existe galeria na nuvem nem exclusão definitiva.** As miniaturas reais de obras foram adicionadas na v0.28, além das miniaturas de camadas. Dados ficam no diretório de salvamento do LÖVE, não junto ao executável.

## Novidade v0.29 — importar PNG como camada

No editor, **arraste um arquivo `.png` do Explorador de Arquivos para a janela do Paint-Lua**. Na v0.29 a importação criava imediatamente uma camada; **desde a v0.30 ela abre primeiro a prévia ajustável** descrita acima. A nova camada conserva RGBA e transparência e não apaga o desenho anterior. **Ctrl+Z desfaz** a importação aplicada e **Ctrl+Y refaz**.

Também é possível usar **Back → Importar PNG** ou **Ctrl+I** para escolher arquivos colocados em `imports/` no diretório de dados do LÖVE (normalmente `%APPDATA%\LOVE\paint-lua\imports` no Windows). A lista pode ser atualizada no painel. **Não há diálogo nativo de arquivos**; arrastar do Explorador é o caminho mais direto.

Para proteger memória, só são aceitos PNGs com até **16 MiB de arquivo**, **2.097.152 pixels** e **8.192 por lado**. Imagens maiores são recusadas sem alterar a obra. Na v0.29 o PNG não era escalado; a v0.30 permite escala e rotação na prévia, com recorte nas bordas do canvas. O original não é movido nem apagado, e a camada importada passa a integrar o `.npnt` ao salvar. Ainda não há importação de JPEG, PSD ou SVG. Veja [guia de importação](docs/IMPORTACAO_PNG_v029.md).

## Novidade v0.28 — miniaturas reais e exportação PNG

- A galeria exibe **prévias reais da composição** em arquivos PNG de 160×160, incluindo efeitos de máscaras e grupos. Elas são derivadas do NPNT: miniatura ausente ou inválida pode ser reconstruída sem substituir o arquivo da obra.
- O carregamento das prévias é **parcelado (até uma por quadro)** e usa cache de imagens limitado, para reduzir travamentos ao navegar por muitas obras.
- **Exportar PNG no editor:** abra **Back → Exportar PNG**. **Exportar pela galeria:** selecione uma única obra e use o ícone de download da barra superior. A galeria mostra o caminho completo do PNG gerado.
- O PNG final preserva transparência RGBA, mas o limite inicial é de **4.194.304 pixels, até 8.192 por lado**. Exportações recebem novos nomes (`obra-2.png`, `obra-2-2.png` etc.) e **não sobrescrevem** anteriores.
- Os PNGs são criados no diretório de dados do LÖVE, dentro da pasta `exports/`, **não ao lado do .bat**. No Windows, normalmente fica em `%APPDATA%\LOVE\paint-lua\exports`. O caminho exato é mostrado pelo aplicativo.
- **Na v0.28 não havia importação PNG; ela foi acrescentada na v0.29 e ganhou prévia na v0.30. Ainda não há exportação JPEG ou PSD.** Os arquivos originais continuam em `.npnt`.

## Situação funcional

A UI disponibiliza tela inicial, galeria, New Canvas, ferramentas, janelas de pincel, cores e camadas. O motor é responsável por pixels reais: **pintura, borracha, balde cooperativo, conta-gotas, Alpha Lock durante a sessão, camadas, recorte, desfazer/refazer e salvar/reabrir .npnt**. Zoom, rotação e pan usam a UI. Vários controles de filtros e galeria **ainda são demonstrativos ou parcialmente integrados**. A v0.25 conecta máscaras de camada e grupo, além de criar/desagrupar grupos, ao núcleo real. Não se deve assumir que um botão que existe na interface altera pixels.

A bateria do núcleo foi incorporada ao repositório na v0.23: **1.008 testes aprovados em texlua com mocks na v0.26**, incluindo seleção, laço e NPNT5. A integração do editor também é verificada em LÖVE 11.5 real em Linux com display virtual. A integração básica passou em **LÖVE 11.5 real em Linux sob display virtual**, incluindo pincel, undo/redo e NPNT. Ainda são necessários testes manuais no Windows, desempenho e uso de caneta/tablet.

## Miniaturas e ordenação v0.26

O painel **Layer** agora apresenta **miniaturas reais** (40×40) amostradas dos pixels de cada camada, e uma miniatura de máscara (19×19) quando ela existe. As imagens mantêm a proporção do documento e são armazenadas em cache; são reconstruídas quando mudam tiles, máscaras ou após desfazer/refazer. A aba avançada exibe uma prévia da camada ou da máscara selecionada.

**Reordenar camadas:** selecione uma camada e use os botões **↑ / ↓** no topo da lista, ou arraste sua linha até outra linha visível. A lista aceita rolagem do mouse para visualizar camadas adicionais. Cada movimento é uma única operação de desfazer/refazer. A operação é recusada se dividir grupos, cruzar limites de grupo ou alterar a base de um clipping.

**Reordenar grupos:** no painel **Grupos / Máscaras → Grupos**, use **Subir grupo / Descer grupo**. Todo o grupo e os descendentes são deslocados como um bloco entre irmãos compatíveis, preservando os tiles, máscaras e a hierarquia. Movimentos inválidos são recusados sem alterar o histórico. A ordem é salva no arquivo NPNT5.

**Limites:** as miniaturas usam amostragem nearest-neighbor (traços de menos de um pixel na prévia podem não aparecer). Não há ainda miniaturas compósitas dos grupos, arraste livre entre grupos, nem rearranjo do clipping como um bloco. O LÖVE no Windows ainda precisa ser validado manualmente. [Detalhes e testes da v0.26](docs/MINIATURAS_CAMADAS_v026.md).

## Grupos e máscaras v0.25

O painel **Layer → Grupos / Máscaras >** agora oferece três abas adaptáveis a janelas menores: **Grupos**, **Máscara camada** e **Máscara grupo**. É possível criar grupos de uma camada ou de duas camadas adjacentes, desfazer o grupo, alternar visibilidade e controlar opacidade em passos de 10%. Ao adicionar nova camada no fim da pilha, ela herda o grupo da anterior.

As máscaras são **não destrutivas**: adicionar, remover, ativar/desativar, inverter e pintar com pincel/borracha usam as APIs reais do núcleo, com histórico e salvamento `.npnt` (NPNT5). No modo de edição, pincel revela e borracha esconde; **Pintar pixels** volta à imagem original. Os marcadores de grupos aparecem junto às camadas; a v0.26 acrescenta miniaturas reais das camadas e máscaras. [Instruções, limites e testes](docs/GRUPOS_MASCARAS_v025.md).

**Limitações:** não há ainda controle de grupos por arraste livre, thumbnails reais de máscaras, feather ou operação em lote de várias camadas. A interface não é uma cópia do ibisPaint oficial e funcionalidades não conectadas continuam demonstrativas.

## Transformação v0.24 — prévia não destrutiva

O **Transformar** do Ibis-Lua agora trabalha nos pixels reais da camada ativa, desde que exista uma seleção.
Selecione um retângulo, laço ou região com a varinha; escolha **Transformar** na barra lateral ou
em Tool Select. O conteúdo selecionado é mostrado numa **prévia translúcida**, sem alterar
os tiles originais até escolher **Aplicar**.

- **Arrastar**: move a prévia dentro do canvas.
- **-15° / +15°**: gira em passos de 15 graus; **- Zoom / + Zoom**: redimensiona em 10%.
- **Aplicar** (ou **Enter**): recorta os pixels de origem, compõe no destino e move a seleção como
  máscara raster; tudo em **uma ação** de desfazer/refazer.
- **Cancelar** (ou **Esc**): encerra a prévia mantendo os pixels intactos.
- **Setas**: deslocam 1 pixel; **Q/R**: giram 15°; **+/−**: alteram a escala.

**Limitações:** a v0.24 usava somente *nearest-neighbor*; a v0.33
acrescentou Suave/Pixelado e manteve o padrão antigo para a API. A ferramenta
movimenta apenas a camada ativa e não preserva uma entidade vetorial/flutuante entre sessões.
O commit fica limitado a **1 milhão de pixels de origem e destino** para proteger memória e CPU.
Nenhum formato novo é necessário: o resultado raster e a máscara da seleção usam NPNT5.
O teste de LÖVE 11.5 com a transformação foi incluído no CI; o uso manual em Windows,
caneta e tablet continua pendente.

## Seleção na v0.23

No painel superior **Selection Area** há seleção por **retângulo**, **laço** e **varinha mágica**, além de Selecionar tudo e Desmarcar. O laço e a varinha também aparecem na barra de ferramentas. O desenho e o balde respeitam a área selecionada; desfazer/refazer restaura seleções anteriores. **Ctrl+A** seleciona tudo, **Ctrl+D** desmarca, **Esc** cancela a seleção em andamento ou a remove.

O **NPNT5** preserva o laço e a máscara da varinha ao salvar e abrir; projetos antigos (NPNT1–NPNT4) continuam legíveis. A varinha opera por cor RGBA da **camada ativa** com um limite de segurança de 2 milhões de pixels, em execução cooperativa. A seleção não possui feather nem antialiasing ainda. [Comportamento detalhado e limites](docs/SELECAO_v023.md).

## Novidades da integração v0.22

- **Balde:** usa o preenchimento scanline cooperativo do núcleo, distribuído em fatias por quadro; **Esc** cancela a operação, com rollback.
- **Conta-gotas:** amostra a cor composta dos pixels do desenho e atualiza o seletor de cores da interface.
- **Alpha Lock:** o pincel muda somente a cor dos pixels já opacos, sem criar novos pixels transparentes. A borracha não altera o alfa quando a trava está ativa.
- **Camadas:** visibilidade, clipping e blending alteram a composição real e entram no histórico; o slider de opacidade não cria centenas de entradas de undo. Desfazer/refazer atualiza também o estado do painel.
- **Limites conhecidos:** Alpha Lock e a flag de camada bloqueada ainda são estados da interface, **não persistem em .npnt**; o balde é bloqueado quando Alpha Lock está ligado. As amostras de pincéis continuam ilustrativas; as miniaturas de camadas são reais desde a v0.26. Não há testes de FPS/tablet/Windows nem paridade de Alpha Lock no caminho FFI; nesse modo o pincel usa o caminho Lua.

## Créditos e continuidade

Os fontes da interface foram incorporados de https://github.com/SrTristeSad/Ibis-Lua (revisão fixada e atribuída em ORIGENS.md). Não é o aplicativo oficial ibisPaint. PhotoCraft é referência técnica; ibisPaint é referência funcional. Consulte LICENSE-PHOTOCRAFT-MIT.txt, ORIGENS.md e a licença dos ícones Lucide.

Para continuar em outro chat: PROMPT_DO_PROJETO.md e AGENTS.md.


## Novidades v0.28 — prévias reais da galeria e PNG

- **Miniaturas reais:** a galeria desenha o resultado composto das camadas, incluindo opacidade, visibilidade, grupos, clipping e máscaras. Cada obra tem um arquivo derivado `gallery/thumbs/<id>.png` de 160 × 160 px. A versão original da obra continua em `gallery/works/<id>.npnt`.
- **Regeneração:** novas prévias são criadas depois de salvar a obra. A galeria pode reconstruir as de obras antigas a partir do `.npnt`; processa somente uma por quadro e mantém até 40 imagens carregadas.
- **Exportar PNG:** no editor, use **Back → Exportar PNG**. Na galeria, selecione **uma obra** pelo modo Selecionar e pressione o ícone de download na barra superior. A imagem resultante preserva a transparência e a composição do documento, sem alterar o `.npnt`.
- **Onde encontrar:** os PNGs aparecem na pasta de dados do LÖVE: `exports/obra-<id>.png` (Windows, geralmente `%APPDATA%\LOVE\paint-lua\exports`). Exportações posteriores recebem sufixos `-2`, `-3` etc.; nenhuma substitui uma exportação anterior.
- **Segurança e limites:** PNG de resolução total limitado a **4.194.304 pixels** e lado máximo de 8.192 px, evitando alocação excessiva. Arquivos `.npnt` maiores podem continuar sendo abertos e editados; somente a exportação integral é recusada. A prévia mantém o tamanho máximo de 160 × 160 px. Não há sincronização em nuvem nem exportação JPEG/PSD nesta versão.
- **Qualidade:** os testes puros do núcleo somam 1.029 verificações aprovadas. Teste de inicialização, persistência de miniaturas e exportação no LÖVE real acontece pela CI; teste manual no Windows ainda é necessário.

**Correção adicional v0.33:** os botões de giro fino de PNG (−1°, +1°, Giro 0°)
agora são aceitos mesmo enquanto a importação está em prévia; a proteção
contra outras operações continua ativa.

### Atalhos durante uma seleção

Enquanto um retângulo ou laço está sendo arrastado, **Ctrl+Z / Ctrl+Y**
não desfazem ações anteriores nem cancelam o gesto em silêncio.
Confirme ou cancele a seleção primeiro. Um preenchimento cooperativo
ainda em andamento também impede novos gestos de seleção e o uso da
varinha, para evitar leitura de pixels provisórios.

Os testes de ciclo de vida ficam em
`tests/test_selection_lifecycle_v039.lua`.

### Trocar de obra sem reter o documento anterior

Ao abrir uma pintura existente ou criar outra tela, o editor descarta
as referências de camadas, o contorno incremental e os caches da obra
anterior. A primeira seleção de uma obra aberta pela galeria começa
em **Substituir**, sem herdar acidentalmente o modo Subtrair/Interseção
da pintura anterior. Um preenchimento ainda ativo é cancelado com
rollback antes da troca. Regressões em
`tests/test_document_switch_v039.lua`.

### Propriedades de camadas durante uma operação

Enquanto o balde cooperativo ou a varinha mágica estão calculando uma
região, o editor **adia alterações de opacidade e troca da camada
ativa** até concluir ou cancelar a operação. Isso evita modificar
a camada usada por um trabalho ainda em andamento. O controle de
opacidade mantém seu comportamento anterior, sem criar uma ação de
desfazer para cada atualização; a regressão está em
`tests/test_layer_sync_during_jobs_v039.lua`.

### Exportar PNG somente depois de concluir a operação

A exportação PNG aguarda a conclusão ou o cancelamento do balde
cooperativo e de pinceladas ainda abertas, inclusive quando essas
operações são iniciadas diretamente pelo motor. O aplicativo nunca
grava uma imagem de pixels provisórios que poderiam desaparecer após
um cancelamento. Com o documento liberado, a exportação aplica as
propriedades pendentes das camadas e continua criando nomes
incrementais sem sobrescrever PNGs existentes. Testes:
`tests/test_png_export_operation_lock_v039.lua`.

### Mudanças de camada durante prévias

Uma transformação em andamento, a prévia de importação PNG e o
arraste de seleção mantêm a camada original até o gesto ser confirmado
ou cancelado. Alterações de nome, visibilidade, mesclagem, opacidade
e camada ativa feitas durante a prévia ficam pendentes até a próxima
sincronização permitida; o histórico da seleção e o histórico das
camadas permanecem independentes. Cobertura de regressão em
`tests/test_pending_preview_sync_v039.lua`.

### Desmarcar durante arraste de seleção

**Ctrl+D** ou o botão **Desmarcar** não cancelam um retângulo ou laço
enquanto ele está sendo desenhado. Conclua o gesto com o mouse ou
cancele explicitamente com **Esc** antes de desmarcar. Isso protege a
seleção anterior e evita gerar uma ação de desfazer indesejada.
A inversão e a combinação de seleções também evitam cálculos
desnecessários enquanto um balde cooperativo estiver ativo.
Regressões: `tests/test_selection_clear_during_drag_v039.lua`.
