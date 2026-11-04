# Mapeamento visual — Windows (02/11/2026)

## Regra de evidência

Versão-alvo: **Windows 14.1.4**, anunciada oficialmente em 28/10/2026.
Capturas externas abaixo são da edição Windows, mas **não têm metadados suficientes para provar que representam a versão 14.1.4**. Não afirmar pixel-perfect até obter referência dessa compilação na mesma resolução e escala.

## W1 — My Gallery / New Canvas (Windows, terceiros)

URL: https://ibis-paint.uptodown.com/windows
Imagem: https://img.utdstc.com/screen/a65/274/a65274b8eed31f3f889105ad4259cd2290958b5cb1ff1e9b74ffed7e65b1ae2a%3A600

Observado: barra superior escura My Gallery, botões à direita (incluindo +, Select, Edit); fundo de galeria off-white; New Canvas **painel ancorado à direita** sob barra superior, título escuro, Import Picture, W/H com controles, Speed ↔ Quality, lista longa de modelos e botão OK no rodapé.

Modelos visíveis: SD (Speed), 1:1 (SD), 3:4 (SD), 9:16 (SD), Twitter Header, Chat Stamp, Vertical, Manga Manuscript, Postcard (JP), A4, A5, B4, B5.

Implementação: gallery_header, gallery_screen, draw_new_canvas.
Ainda não verificado: tamanhos exatos, fontes, ícones, posição das opções e alterações introduzidas em versões posteriores.

## W2 — Editor e pincéis (Windows, Microsoft Store)

URL: https://apps.microsoft.com/detail/9pfdf2zd4z4n
Imagem: https://store-images.s-microsoft.com/image/apps.62782.14202576542330599.5d8d33ef-6e70-4d7f-953d-99930bb9592a.91fbe5d5-ba54-4efc-92b2-f5f6b5059862

Observado: **barra vertical de ferramentas à esquerda**, ícones pequenos e seleção colorida; janela Brush flutuante sobre o canvas, com lista de brushes, propriedades e sliders; controles na parte inferior.

Implementação: editor_screen, draw_editor_panel(brush), draw_size_controls.
Limites: UI do pincel ainda parcial, ícones vetoriais próprios sem equivalência aprovada.

## W3 — Editor / janela Layer (Windows, terceiros)

URL: https://ibis-paint.en.uptodown.com/windows
Imagem: https://img.utdstc.com/screen/344/970/344970ad640d31c7b97ff56c968af1ca47289acda116499bf94c128b7d6e0d85%3A600

Observado: janela de camadas flutuante no lado inferior direito, cabeçalho, miniaturas, visibilidade, adição de camada e menus pequenos; barra de controle inferior permanece.

Implementação: draw_editor_panel(layer). Conteúdo simulado, sem renderização de obra.

## W4 — Referência oficial dos controles

URL: https://ibispaint.com/lecture/index.jsp?no=4

Documenta 15 ferramentas, a ordem dos 9 controles do rodapé e 6 botões na parte superior direita. Fonte funcional oficial, porém material multiplataforma; as dimensões e o desenho específico no Windows 14.1.4 precisam verificação.

## W5 — Tela inicial histórica

URL: https://prtimes.jp/main/html/rd/p/000000010.000015594.html

Screenshot original Windows **9.4.2** comprova paleta azul, logo, navegação circular e Daily Ranking, mas também mostra o antigo botão Collection. Este botão foi removido posteriormente e não foi desenhado na reconstrução. Nenhum pixel dessa tela pode ser declarado referência 14.1.4.

## W6 — Mudanças 14.1.4

URL: https://ibispaint.com/information.jsp?newsID=313331619

Inclui mudanças em Settings/login, checkmark de alguns diálogos e status de nuvem na galeria após sincronização. Essas interfaces não foram inventadas: os estados dependentes de nuvem/login precisam de referências e/ou conexão real, fora do escopo simulado.

## Resultados e problemas restantes

- **Corrigido no código**: barras pretas de letterbox derivadas de largura virtual fixa; desenho agora utiliza toda a janela e âncoras relativas.
- **Corrigido no código**: New Canvas deixou de ser modal central genérico; agora é lateral como no Windows.
- **Corrigido no código**: toolbar de texto no rodapé foi trocada por barra vertical com ferramentas e footer iconográfico.
- **Testado**: screenshots de título, gallery, new canvas, editor e layer gerados por LÖVE Linux/Xvfb. Não são comparações com o ibisPaint original.
- **Não concluídos**: equivalência visual de ícones, todas as configurações, menus, ferramentas, fontes, estados hover, conteúdo de My Gallery e detalhes de New Canvas.
- **Sem percentual de fidelidade**: falta referência original Windows **14.1.4** com DPI, resolução, idioma e estado registrados.

A ferramenta de diff de screenshots permanece em tools/compare_screenshots.py; gerar métricas só quando existirem imagens realmente comparáveis.

## W7 — Seletor de cor (captura publicada por usuário Windows)

Página: https://note.com/nitijo_tubuyaki/n/nddff01f99a4f

Referência visual pública: screenshot da janela Color com grade de amostras à esquerda, círculo de matiz à direita e losango interno de saturação e luminosidade, além de controles RGB/alpha.

Implementação: draw_hue_wheel e draw_editor_panel(color): círculo HSV e losango reconstruídos geometricamente, interação de matiz/saturação/luminosidade, paleta demonstrativa, prévia hexadecimal e canais RGB.

**Limites:** captura sem comprovação de ser Windows 14.1.4; não afirmar equivalência da paleta de amostras, da disposição dos canais ou das medidas. O alfa permanece simulado por opacidade do rodapé.

## Incremento de navegação e camadas — 02/11/2026

- **Viewport visual, sem edição de imagens**: módulo puro src/viewport.lua. Mouse wheel aproxima/afasta o canvas com ancoragem no cursor; Shift+mouse wheel rotaciona; Espaço+arrastar move; limites de zoom testados.
- **Modo Solo de camadas**: módulo src/model.lua preserva a visibilidade anterior, permite trocar a camada isolada, restaura o estado ao desativar e encerra o Solo quando uma operação incompatível é solicitada.
- **Bug de cliques atravessando janelas**: painéis e New Canvas interceptam cliques em suas superfícies, em vez de acionar controles posicionados atrás.
- **Campos numéricos New Canvas**: o primeiro dígito digitado substitui o conteúdo selecionado; Tab alterna os campos e Backspace edita valores.
- **Ressalva**: gestos e modo Solo foram implementados a partir de tutoriais/documentação oficial de Windows/14.1.0, mas os elementos visuais da versão-alvo 14.1.4 continuam aguardando confrontação.

Fontes: https://ibispaint.com/lecture/index.jsp?no=167 e https://ibispaint.com/newFeature.jsp

## W8 — Refinamento de New Canvas e testes de interação

- A proporção horizontal da janela lateral foi ajustada para ~69% da área lógica em janelas grandes, de acordo com a referência visual Windows apresentada em W1; **nenhuma medição 14.1.4 foi feita**.
- Os controles W/H `-`, slider arrastável e `+` agora alteram numericamente as dimensões. A faixa atual do slider (1–8192) é apenas uma escolha implementativa provisória; não é parâmetro oficial verificado. Entrada manual continua permitindo valores até 16384.
- O valor inicial **1000 x 1000** não seleciona falsamente o preset SD (Speed), porque ele tem valores diferentes.
- O pipeline executa interação end-to-end com mouse: título → galeria → novo canvas → editor → layer → zoom. Também captura nove estados em screenshots para inspeção posterior.
- Evidência original: https://ibis-paint.uptodown.com/windows (imagem Windows de versão não identificada). Falta confronto com captura real Windows 14.1.4.

## W9 — View Menu, Grid Settings e janela de referência (documentação oficial)

Referências oficiais de nomenclatura e funcionamento:

- Tutorial View Menu: https://ibispaint.com/lecture/index.jsp?no=168
- Imagem de opções: https://ibispaint.com/img/lecture/en/chapter_168_01.png
- Imagem de Grid Settings: https://ibispaint.com/img/lecture/en/chapter_168_02.png
- Referência da janela de Settings: https://ibispaint.com/lecture/index.jsp?no=81

**Verificado funcionalmente**: toggles Reference Window, Grid e Manga Manuscript; configurações de Grid 1/2 Interval, Grid 1/2 Color e Position X/Y; Reset; opções Smooth/Pixelated para exibição ampliada. O tutorial oficial apresenta controles dessas funções, porém não atesta a geometria específica **Windows 14.1.4**.

**Implementado agora**: ViewState independente de motor de pintura, opções com controles de estado, guias renderizadas sobre o canvas respeitando zoom/rotação, janela de referência demonstrativa em modo Canvas, seleção Smooth/Pixelated, botões para intervalos, origem e cores de exemplo. Novos testes de modelo e cliques reais de integração (incluindo View Menu e Grid Settings); quatro capturas adicionais incorporadas ao CI.

**Pendências**: seletor real de cores de guia, edição fina/drag dos parâmetros da grade, proporções exatas, toda a janela real de referência e referência Windows 14.1.4 em resolução, DPI e idioma medidos. Os controles de interpolação mudam apenas o estado porque não existe motor de imagens.

## W10 — Layer Window Details: estrutura e interação

**Fonte principal oficial:** https://ibispaint.com/lecture/index.jsp?no=156

**Referência Windows com versão não comprovada:** https://ibis-paint.en.uptodown.com/windows, captura do painel Layer.

**Componentes fundamentados:** Selection Layer, itens de camada com miniatura, controle de visibilidade, Add Layer, Clipping, Alpha Lock, Opacity, Blending Mode e janela Layer flutuante móvel em PC. O manual oficial descreve também ferramentas com impacto em pixels, mas elas **não** foram implementadas.

**Implementação:** novos estados de camada em `src/model.lua` com opacidade 0–100, blending simulado, clipping, alpha lock, lock, rename, modos de fundo branco/transparente claro/transparente escuro. Em `main.lua`: painel flutuante arrastável, lista de camadas demonstrativas, popup de blending, sliders de opacidade, opções de fundo e padrão de xadrez apenas visual.

**Teste:** `tests/test_layer_properties.lua` para propriedades e limites; E2E LÖVE para adicionar camada, alternar clipping/Alpha Lock, ajustar opacidade, escolher Multiply e fundo transparente escuro.

**Incertezas:** screenshots públicos da edição Windows não certificam a compilação **14.1.4**, nem medidas exatas de janela, tipografia ou ícones. Miniaturas não contêm obras, e blending não é aplicado aos pixels. O desenho e a geometria permanecem classificados como **provisórios**, não como reprodução fiel.

## W11 — Janela flutuante redimensionável (desktop)

A documentação oficial **Layer Window Details** (https://ibispaint.com/lecture/index.jsp?no=156) especifica que a janela Layer flutuante existe em tablets e PCs, pode ser movida pela barra superior e redimensionada pelo canto inferior direito ou pelas bordas. Esta etapa implementa o **arraste pelo cabeçalho e pelo canto inferior direito**, com limites de dimensão e posição. O gesto é exercitado no teste end-to-end do LÖVE.

A geometria de janela (largura/altura inicial, margens e hit area) continua provisória até uma comparação com capturas do ibisPaint **Windows 14.1.4** na mesma escala.

## W12 — Medidas observáveis do New Canvas Windows e revisão de DPI

- Captura publicada: https://img.utdstc.com/screen/a65/274/a65274b8eed31f3f889105ad4259cd2290958b5cb1ff1e9b74ffed7e65b1ae2a%3A600
- Página: https://ibis-paint.uptodown.com/windows (exibe o pacote 14.0.10.0 em 02/11/2026, mas **não afirma versão da captura**).
- Estrutura observável: lista em faixas horizontais separadas por linhas finas; miniaturas da razão de aspecto à esquerda; rótulo de cada modelo ao centro; dimensões à direita; nos formatos de papel/cartão-postal há indicação de DPI.
- Presets de referência transcritos para `src/canvas_presets.lua`; registro de DPI inicial: cartão-postal 300; A4/A5/B4/B5 150. O DPI pode ser alterado no protótipo para conferir atualização dos campos W/H.
- **Inconsistência da fonte:** a linha de rótulo `9 : 16 (SD)` acompanha `1280 x 720` na captura pequena. Não foi corrigida por suposição, e precisa ser confrontada com a interface oficial 14.1.4.
- Melhorias atuais: escala vertical das linhas ao espaço disponível, controles de DPI, miniaturas vetoriais com aspecto de cada modelo, leitura de dimensões na faixa inferior e limites de rolagem definidos pela altura do conteúdo.
- **Nenhuma comparação geométrica foi aprovada**: sem screenshot 14.1.4 capturado no mesmo DPI e resolução, fontes/ícones/tamanhos de linhas ainda são aproximações.

## W13 — Artworks Folder Feature, origem e fidelidade Windows

Fontes oficiais:
- https://ibispaint.com/lecture/index.jsp?no=193 (pasta criada a partir do botão `+` e de uma opção `Folder` em uma janela `New`; navegação, pastas aninhadas, renomeação, seleção e movimentação de obras).
- https://ibispaint.com/lecture/index.jsp?no=183 (o recurso Artworks Folder é uma funcionalidade Pro/Premium no Windows/Mac).
- https://ibispaint.com/newFeature.jsp (introdução das pastas no ibisPaint 12.2.0 e remoção de Collection).
- https://ibispaint.com/information.jsp?newsID=313331619 (mudanças na My Gallery da versão 14.1.4, incluindo o número de obras sincronizadas quando a sincronização é concluída; isso **não** foi simulado como se estivesse conectado a uma conta).

**Implementado funcionalmente:** menu New (Canvas e Folder), diretórios em árvore, obras sem pixels, mover seleção, renomear, reabrir tela simulada, retornar ao diretório anterior, grade adaptada à largura e rolagem com recorte vertical. Fonte visual Windows histórica da galeria: W1.

**Correção encontrada por inspeção de screenshot gerado:** as áreas de clique dos cinco ícones à direita da My Gallery entravam nas áreas de Select e Edit. Os botões foram redistribuídos, e um teste E2E verifica ausência dessa sobreposição.

**Restrições:** não existe armazenamento, transferência real, login ou nuvem. A função de pastas é apresentada como demonstração e não prova um direito de uso adquirido pelo usuário. O visual de pastas e ícones não é validado para Windows 14.1.4. Nenhuma porcentagem de fidelidade pode ser inferida das capturas de smoke.

## W14 — Brush Window da edição Windows (captura Microsoft Store)

- Página: https://apps.microsoft.com/detail/9pfdf2zd4z4n
- Imagem Windows da biblioteca de pincéis: https://store-images.s-microsoft.com/image/apps.32378.14202576542330599.5d8d33ef-6e70-4d7f-953d-99930bb9592a.1715e9a7-d182-4d1e-a9b7-883949af7782

**Observações visualmente sustentadas:** janela Brush em primeiro plano, biblioteca predominantemente **branca/cinza-clara no lado esquerdo**, abas Basic/Custom/Online e pesquisa, vários itens com amostras de traços e números de tamanho. À direita há área escura com prévia do traço e ajustes, com sliders e outros parâmetros.

**Implementado:** nova composição de painel em `main.lua`; 12 exemplos locais em `src/brush_catalog.lua`, desenho vetorial de traços sem tocar em pixels de obras, busca filtrável e sliders de espessura/opacidade. Novo smoke `brush_search` e teste de cliques sequenciais.

**O que NÃO está comprovado:** números/tipos exatos de pincéis da versão 14.1.4; tipografia, dimensões e alinhamento milimétricos; ícones oficiais; equivalência dos parâmetros avançados. Os valores de espessura e o desenho das miniaturas são demonstrativos. As abas Custom/Online são apenas superfícies indicativas sem acesso ao catálogo oficial.

A documentação oficial dos parâmetros de pincel está em https://ibispaint.com/lecture/index.jsp?no=118. Ela corrobora os conceitos de Thickness, Opacity, Reset, Fade e Shape, mas não mede a posição exata dos controles na versão Windows-alvo.

## W15 — Tool Select Position e Settings (fonte oficial)

Fonte principal, com variações de colunas e instrução Back → Settings:
https://ibispaint.com/lecture/index.jsp?no=4

Documentação oficial detalhada de Settings, incluindo Invert Direction of Mouse Wheel disponível em Windows/Mac:
https://ibispaint.com/lecture/index.jsp?no=81

Imagem oficial do menu de Settings (não certificada como captura Windows 14.1.4):
https://ibispaint.com/img/lecture/common/chapter_04_05.png

**Conceitos comprovados:** Tool Select Position pode ser Left, Right ou Popup. No modo Popup, o número de colunas pode ser 1, 2 ou 3. Show Label in Tool Select alterna legendas, e Invert Direction of Mouse Wheel altera o sentido da navegação no Windows/Mac. São recursos de configuração da interface, não funcionalidades de pintura.

**Implementação local:** `src/editor_preferences.lua` guarda preferências e valida o domínio de cada opção. `main.lua` posiciona a faixa de 15 ferramentas à esquerda/direita ou mostra seleção Popup; reorganiza a área do canvas e os seis botões superiores quando a barra está à direita; oferece Settings pelo menu Back; permite alternar rótulos, mensagens e sentido da roda do mouse.

**Validação executável:** teste Lua do modelo, integração LÖVE em 1024×768/1600×900, seis screenshots novos (30 no total) e verificador de presença/ausência e lateralidade da faixa de ferramentas. Isso não valida espaçamento, iconografia ou equivalência pixel-perfect com Windows 14.1.4.

**Incertezas preservadas:** ordem exata dos itens dentro da janela Settings na build-alvo, fontes, cores e dimensões dos menus Popup. Os elementos são protótipos vetoriais, sem assets do software proprietário.

## W16 — Persistência das opções de interface (implementação interna)

As configurações de posição da Tool Select e outras preferências passaram a ser serializadas como texto simples no diretório de dados do LÖVE. Isto é uma **decisão de engenharia própria do Ibis-Lua**, não uma afirmação sobre o formato proprietário usado pelo ibisPaint Windows 14.1.4.

Fontes funcionais dos campos: https://ibispaint.com/lecture/index.jsp?no=81. O comportamento de restauração é simulado e seguro contra conteúdo malformado. Testes automatizados verificam round-trip e rejeição de entradas inválidas.

## W17 — Color Window v14: seleção, paletas e janela flutuante

**Fontes oficiais:**
- https://ibispaint.com/lecture/index.jsp?no=11 — Color Circle / HSB box, Current/Previous Color, HEX, sliders HSB/RGB e opacidade, HSB/Palette e histórico.
- https://ibispaint.com/newFeature.jsp — versão 14.0.0: múltiplas paletas, renomeação, reorganização das cores e Floating Color Window em desktops/tablets.

**Implementado:** novo módulo `src/color_state.lua`, com conversões RGB/HSB/HEX, controle de opacidade, paletas individuais, seleção de cores, rearranjo arrastável, histórico limitado a 100 cores selecionadas e cópias defensivas. O código `main.lua` exibe a janela com os controles, modal de HEX, listas de paletas com paginação, botão de modo flutuante e alça de redimensionamento. O círculo/diamante é renderizado com polígonos LÖVE próprios; não há assets extraídos do programa original.

**Capturas geradas:** `color`, `color_rgb`, `color_palette`, `color_hex`, `color_floating`. Um defeito de sobreposição de texto e uma tonalidade inconsistente nas capturas de smoke foram identificados na inspeção visual e corrigidos.

**Pendências:** disposição geométrica oficial de Windows 14.1.4, cores e fontes exatas, seletor de paletas original, gerenciamento de QR Codes, importação/exportação, persistência de paletas e histórico de pintura real. A opção de opacidade modifica somente o modelo da janela.
