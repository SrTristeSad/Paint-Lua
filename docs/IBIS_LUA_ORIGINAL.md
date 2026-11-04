# Paint Lua — interface visual em Lua/LÖVE (repositório Ibis-Lua)

**Objetivo:** interface visual e navegável do ibisPaint Windows 14.1.4, sem motor de pintura, escrita em Lua/LuaJIT e LÖVE 11.5.

## Estado atual — 03/11/2026

Esta versão **já contém telas e controles clicáveis**. A reconstrução **não está concluída nem validada como cópia 1:1**. A maior parte das capturas Windows públicas consultadas não identifica a compilação 14.1.4.

- **Tela inicial Paint Lua**, com identidade azul-tinta e coral, cartões de acesso à galeria e aviso de protótipo. Não utiliza o logo oficial do ibisPaint.
- **My Gallery** com barra superior, menu New, pastas e miniaturas demonstrativas, seleção, movimentação de itens, renomeação de pastas, navegação aninhada e rolagem.
- **New Canvas lateral direito**, incluindo edição de dimensões, lista rolável de presets e criação de documento demonstrativo; substitui o diálogo central anterior.
- **Editor** com faixa vertical compacta de 15 ferramentas, ícones Lucide licenciados, controles inferiores, botões superiores, painéis de pincel, cor e camadas. Visualização do canvas com **zoom pelo scroll do mouse, rotação com Shift+scroll e pan com Espaço+arrastar**.
- **Comportamentos simulados**: seleção de ferramenta, brush/eraser, dimensões, espessura, opacidade, paleta e camadas. Inclui **modo Solo**: manter pressionado o ícone de visibilidade da camada e soltar; pressionar de novo restaura os estados anteriores.
- Recursos que precisariam de processamento de imagens não são fingidos: pintura, filtros reais, importação/exportação e renderização de camadas estão fora do escopo.

**Nenhuma tela é certificada como visualmente equivalente ao original.** O desenho de diversos ícones, cores e subpainéis ainda precisa de comparação com a aplicação real versão 14.1.4.

## Execução

Instale LÖVE 11.5 (https://love2d.org/) e execute testar.bat na pasta do projeto.

No programa: clique em My Gallery, +, escolha dimensões e clique OK. Os campos W/H aceitam seleção e substituição ao digitar (Backspace apaga, Tab troca o foco). No editor, scroll amplia/reduz o canvas, Shift+scroll o rotaciona e Espaço+arrastar move a visualização sem alterar os pixels. Mantenha pressionado o olho de uma camada para ativar/desativar o modo Solo; clique curto alterna visibilidade. B/E trocam pincel/borracha, L abre camadas, C abre cores, colchetes alteram a espessura, Escape volta e F12 captura.

## Testes

- Lua: luajit tests/test_model.lua, luajit tests/test_viewport.lua, luajit tests/test_layer_solo.lua e luajit tests/test_view_state.lua
- Dependências Python: pip install -r requirements-dev.txt
- Comparador: python -m unittest discover -s tests -p "test_compare.py"
- Diferença de imagens: python tools/compare_screenshots.py --reference original.png --actual copia.png --output-dir comparison_output

O GitHub Actions realiza verificação sintática, testes do modelo, testes do comparador, integração por cliques e **captura trinta e quatro estados no LÖVE** (título, galeria, menu New, galeria com pastas, galeria dentro de pasta, seleção da galeria, galeria com muitos itens, novo canvas, novo canvas com DPI, editor, camadas, janela flutuante, propriedades, blending, fundo transparente, pincéis, cor, zoom/rotação, Solo, View Menu, Grid Settings, grade e janela de referência). Capturas automatizadas não comprovam correspondência com o software original.

## Pesquisa e qualidade

- docs/REFERENCIAS_WINDOWS.md — fontes públicas e limitações.
- docs/MAPEAMENTO_VISUAL.md — observações da interface, origem por elemento e lacunas.
- docs/INVENTARIO_14_1_4.md — inventário.
- docs/VALIDACAO.md — procedimento de verificação e critérios de aceitação.

**Avisos:** não incorporar imagens ou arquivos proprietários do ibisPaint ao projeto; não afirmar porcentagens não verificadas; não usar telas Android para preencher lacunas Windows; manter os arquivos Lua editáveis. O projeto não é afiliado à ibis inc.

## Teste de navegação real e controles New Canvas

A variável `PAINT_LUA_E2E=1` executa uma sequência de cliques dentro do próprio LÖVE (sem substituir callbacks por chamadas diretas ao modelo): abre **My Gallery**, abre **New Canvas**, aumenta a largura com `+`, digita largura e altura, cria uma tela de demonstração, abre **Layer**, muda a visibilidade de uma camada, fecha a janela e amplia o canvas com a roda do mouse. O GitHub Actions executa o teste e falha se a navegação ou o estado não corresponderem às verificações.

No painel **New Canvas** os botões `-`/`+` e os sliders W/H funcionam; os controles respondem ao arrastar. Para o slider, a faixa demonstrativa é de **1 a 8192 pixels**, enquanto os campos manuais aceitam de 1 a 16384. **Essa faixa não foi confirmada na versão oficial 14.1.4** e não representa uma afirmação sobre o comportamento exato do aplicativo proprietário.

## View Menu e grade — etapa atual

- No editor, abra **View Menu** no primeiro ícone da região superior direita.
- **Grid** alterna as linhas de referência no canvas; **Grid Settings** permite mudar os intervalos, alternar as cores demonstrativas, deslocar a origem em passos de 8 pixels e restaurar os valores da simulação.
- **Reference Window** abre uma miniatura demonstrativa do canvas, sem importação de imagens; **Manga Manuscript** alterna guias ilustrativos, ainda não validados geometricamente.
- A escolha **Smooth / Pixelated** é mantida no estado da interface. **Não há rasterização nem imagem importada**, portanto não há efeito de interpolação aplicado a pixels reais.
- Valores atuais (64/256 px e posições 0/0) e cores ilustrativas **não são valores padrão comprovados do ibisPaint Windows 14.1.4**.
- As operações foram fundamentadas na documentação oficial de View Menu: https://ibispaint.com/lecture/index.jsp?no=168. As imagens desse tutorial são multiplataforma e **não devem ser apresentadas como capturas Windows 14.1.4**.

## Janela de camadas — atualização de 02/11/2026

O painel Layer foi reconstruído a partir da documentação de **Layer Window Details** e de capturas publicadas da edição Windows. Agora apresenta Selection Layer, miniaturas demonstrativas, seleção/visibilidade de camadas, botão para adicionar camadas, opacidade com slider, Clipping, Alpha Lock, seletor de Blending Mode e opções visuais de fundo White/Light/Dark. Arraste o cabeçalho da janela Layer para reposicioná-la; arraste seu canto inferior direito para redimensioná-la. O tamanho e a posição ficam no estado da interface, sem alterar os dados da obra.

**Importante:** nenhuma dessas opções processa uma imagem real. Modos Multiply/Screen/Overlay são apenas estados selecionáveis, e a transparência é apenas um padrão quadriculado na visualização do canvas. Renomear e bloquear camadas têm suporte no modelo de dados, mas **ainda não possuem interfaces próprias**.

A versão atual inclui `tests/test_layer_properties.lua`, executado no CI, além de verificações end-to-end pelos próprios botões. A interface de camadas da build Windows 14.1.4 **não foi medida pixel a pixel**.

Fontes: https://ibispaint.com/lecture/index.jsp?no=156 e https://ibis-paint.en.uptodown.com/windows.

## New Canvas — presets de tamanho e DPI

A lista agora é carregada de `src/canvas_presets.lua`, não de constantes escondidas no desenho. Cada modelo possui identificador, título e dimensões. Modelos de papel/postcard expõem DPI clicável (150, 300, 600) que recalcula as dimensões **somente no formulário**. O aspecto de cada miniatura acompanha a proporção do modelo. O espaçamento vertical se ajusta à altura da janela, e a rolagem respeita o conteúdo.

Esta é uma **transcrição de uma captura pública de Windows de versão indeterminada**, não a comprovação dos modelos atuais da versão 14.1.4. A página que hospeda a captura atualmente identifica o pacote Windows 14.0.10.0; isso não certifica a data nem a versão da própria imagem. A inconsistência visível entre o rótulo `9 : 16 (SD)` e as dimensões `1280 x 720` permanece registrada como **pendência de verificação**, não como uma regra de proporção garantida.

O CI executa `tests/test_canvas_presets.lua`, verifica seleção A4 e a mudança de DPI pelos callbacks reais, e testa a navegação em 1024×768 e 1600×900. A captura `new_canvas_dpi.png` fica disponível no artefato de screenshots do GitHub Actions.

## My Gallery — pastas e navegação (atualização)

A My Gallery foi atualizada para contemplar o recurso oficial **Artworks Folder** (adicionado ao ibisPaint 12.2.0). O botão `+` agora abre `New`, permitindo escolher `Canvas` ou `Folder (Pro)`. A versão Windows exige Pro Upgrade ou Premium Membership para habilitar Artworks Folder; neste protótipo a função é **uma simulação independente**, sem licenças, contas ou sincronização.

Nesta etapa foram adicionados `src/gallery.lua` e `tests/test_gallery.lua`. O módulo fornece pastas aninhadas, obras demonstrativas com dimensões, seleção, renomeação, movimentação com prevenção de ciclos, hierarquia de navegação e cópias de leitura. `main.lua` agora apresenta uma grade de miniaturas e pastas, seleção múltipla, menu de destino de movimentação, formulário de pasta, retorno ao editor e rolagem vertical com recorte.

**Persistência:** nenhum documento de obra, pasta ou miniatura é gravado em disco. Os itens da galeria existem **apenas durante a execução**. Reabrir uma obra inicia o estado demonstrativo do editor; não recupera pinturas, pois o projeto exclui motor de pintura.

**Fidelidade:** geometria e ícones da galeria são desenhos de trabalho, **não** reproduções validadas da edição Windows 14.1.4. A fonte funcional é o tutorial oficial https://ibispaint.com/lecture/index.jsp?no=193; a fonte específica do produto Windows para o requisito de Pro/Premium é https://ibispaint.com/lecture/index.jsp?no=183.

**Verificações adicionais:** `luajit tests/test_gallery.lua` e `PAINT_LUA_GALLERY_E2E=1 love .`, com o fluxo My Gallery → New → Folder → Canvas → Layer/Back → Select/Move → Rename → Scroll/Reopen. O teste de layout confirma que os sete controles do cabeçalho não possuem áreas clicáveis sobrepostas. O workflow produz **23 capturas** de estados diferentes.

## Painel Brush — reconstrução visual do Windows

A janela de pincéis foi refeita tomando como referência visual uma captura pública da **Microsoft Store, versão Windows**, disponível em https://apps.microsoft.com/detail/9pfdf2zd4z4n. Ela agora separa a **biblioteca clara à esquerda** da **área escura de parâmetros e pré-visualização à direita**, conforme observado nessa captura.

**Elementos implementados:** abas Basic/Custom/Online, campo de busca, lista rolável com nomes e tamanhos de exemplo, miniaturas de traço procedurais (desenhos vetoriais próprios), prévia ampliada do pincel selecionado, sliders interativos de espessura e opacidade e botão de restauração. A lista de 12 exemplos foi separada em `src/brush_catalog.lua`; `tests/test_brush_catalog.lua` verifica busca e integridade dos dados.

**Limites:** os traços são miniaturas sintéticas feitas por LÖVE, não são texturas extraídas nem um motor de pintura. O programa não oferece os milhares de pincéis oficiais, as abas Custom/Online não carregam coleções e as configurações avançadas do editor original não foram reproduzidas. **Não há comprovação de que a imagem da Microsoft Store corresponda especificamente à versão 14.1.4.**

O teste de integração passa pelos controles reais da janela (busca, seleção, espessura, opacidade e Reset), e o GitHub Actions produz uma captura adicional `brush_search.png`. A estrutura está organizada em Lua editável.

## Verificações estruturais das capturas LÖVE

Além dos testes Lua, o projeto inclui `tools/check_ui_screenshots.py`. Após gerar as capturas de smoke, execute:

```bash
python tools/check_ui_screenshots.py screenshots
```

O programa verifica a presença e a integridade das **34 imagens PNG** produzidas pelo LÖVE no CI (1024×768) e examina a estrutura principal do painel Brush: **biblioteca clara à esquerda e propriedades escuras à direita**. A validação também tem testes unitários em `tests/test_ui_screenshots.py`; o GitHub Actions executa as verificações automaticamente.

**Esse teste não mede a fidelidade 1:1 ao ibisPaint.** Para avaliar equivalência, ainda são necessárias capturas comparáveis do Windows 14.1.4 e uso do comparador `tools/compare_screenshots.py`. A arte final do painel Brush pode ser inspecionada nos artefatos da execução do CI.

## Editor: Tool Select e Settings (etapa de 03/11/2026)

A disposição da seleção de ferramentas pode ser ajustada em **Back → Settings**. As opções documentadas no ibisPaint são `Tool Select Position` (**Left**, **Right** e **Popup**) e, quando a posição é `Popup`, o `Number of Columns in Tool Select Popup` (**1**, **2**, **3**). O protótipo agora oferece essas variações de disposição e mantém os 15 instrumentos simulados acessíveis.

Também estão disponíveis `Show Label in Tool Select`, `Show Message on Undo` e `Invert Direction of Mouse Wheel` (específica de Windows/Mac). A última opção muda a direção do zoom demonstrativo; **não** modifica o sistema operacional nem o dispositivo do usuário.

- Estado editável e testável: `src/editor_preferences.lua`.
- Teste do módulo Lua: `tests/test_editor_preferences.lua`.
- Integração por cliques reais: `PAINT_LUA_SETTINGS_E2E=1 love .` (também testada em janela 1600×900).
- Capturas: `editor_settings`, `tool_popup_1`, `tool_popup_2`, `tool_popup_3`, `tool_right` e `tool_labels_off`.
- Inspeção estrutural: `tools/check_ui_screenshots.py` confirma que a barra fica à esquerda ou direita, ou desaparece quando `Popup` é escolhido.

**Fontes oficiais de funcionamento:** https://ibispaint.com/lecture/index.jsp?no=4 e https://ibispaint.com/lecture/index.jsp?no=81. Essas fontes documentam a presença e a finalidade das opções, mas não certificam a geometria **Windows 14.1.4**. Os controles são desenhados com vetores próprios. Não foi implementado um motor de pintura.

## Persistência das preferências de interface

As opções alteradas em **Back → Settings** são salvas automaticamente em `editor-preferences.txt`, no diretório de dados do LÖVE da aplicação `ibis-lua-fidelity` (identidade definida em `conf.lua`). Na próxima execução normal, são restauradas sem gravar ou modificar quaisquer obras da galeria.

O arquivo é texto simples, com campos `tool_position`, `popup_columns`, `show_tool_labels`, `invert_wheel` e `show_undo_message`. Seu conteúdo é validado como dados; o programa **não executa Lua lido do disco**. Um arquivo corrompido é ignorado e as preferências voltam aos valores padrão. Para voltar manualmente ao padrão, basta encerrar o programa e apagar apenas `editor-preferences.txt` do diretório de dados, sem mexer nas outras configurações.

Os testes de screenshot e de interação desativam intencionalmente a restauração/gravação das preferências, garantindo capturas determinísticas. O teste puro `tests/test_editor_preferences.lua` valida a serialização, leitura e rejeição de dados malformados.

## Color Window — atualização da versão 14

O painel **Color** foi reconstruído usando a documentação oficial de seleção de cores (https://ibispaint.com/lecture/index.jsp?no=11) e as mudanças introduzidas no ibisPaint 14.0.0 (https://ibispaint.com/newFeature.jsp). A interface inclui amostras **Current / Previous**, círculo de cor com controle HSB, escolha entre sliders HSB e RGB, campo hexadecimal editável, opacidade, seleção de paletas e histórico local de **cores selecionadas**.

Na aba **Palette**, é possível criar e renomear paletas, mudar entre várias paletas (até três nomes visíveis por página), adicionar a cor atual e reorganizar as amostras arrastando uma delas para outra posição. O estado editável fica em `src/color_state.lua` e é validado por `tests/test_color_state.lua`.

O botão **Floating Window** alterna a janela móvel, que pode ser arrastada pela barra superior e redimensionada pelo canto inferior direito. O botão de confirmação/fechamento do painel permanece disponível. Capturas de comparação interna: `color`, `color_rgb`, `color_palette`, `color_hex`, `color_floating`.

**Limitações importantes:** não há aplicação de tinta ao canvas, exportação/importação de paletas por QR Code, sincronização com o software original ou armazenamento permanente dessas paletas. As cores do histórico são cores **selecionadas no protótipo**, não cores empregadas em pinceladas reais. As geometrias, ícones e tamanhos ainda não foram validados pixel a pixel contra o Windows 14.1.4. O CI executa um E2E específico (`PAINT_LUA_COLOR_E2E=1 love .`) nas resoluções 1024×768 e 1600×900.

## Atualização do layout e dos ícones (03/11/2026)

Esta etapa integra ao **GitHub** as correções que foram experimentadas no pacote `Paint-Lua-layout-corrigido.zip`, com foco na captura Windows que mostrava rótulos de ferramentas sobrepostos e botões grandes demais.

- **Pacote visual:** 40 ícones [Lucide](https://lucide.dev/), licenciados, com SVG editáveis em `assets/icons/svg/` e PNG transparentes em `assets/icons/png/` para executar offline no LÖVE.
- **Barra lateral:** apenas ícones, com nomes das ferramentas exibidos como dicas ao passar o mouse; sem rótulos invadindo controles vizinhos.
- **Rodapé:** dock central com oito botões compactos, indicadores de ferramenta/camadas e realce coral de seleção.
- **Área de trabalho:** cabeçalho discreto, grade suavizada, canvas em destaque e dois controles compactos flutuantes para espessura e opacidade.
- **Botões superiores:** seis ações reunidas numa barra compacta, eliminando círculos exagerados.
- **Tela inicial e galeria:** tema Paint Lua e cartões de acesso/obras com hierarquia visual mais consistente.

Os novos componentes de interface ficam em `src/ui_theme.lua`, `src/editor_layout.lua` e `src/icon_pack.lua`. Ícones podem ser atualizados com `python -m pip install cairosvg` e `python tools/rebuild_icons.py`; já estão armazenados como PNGs, portanto **Python não é necessário para executar o aplicativo**.

A identidade de salvamento do LÖVE passou a ser `paint-lua`. Preferências anteriores de `ibis-lua-fidelity` não são migradas automaticamente. O projeto continua uma simulação sem motor de pintura e **não foi validado como cópia 1:1** de ibisPaint Windows 14.1.4.

Execute `testar.bat` na raiz do repositório. A suíte GitHub Actions captura **35 estados**, incluindo `editor_square` com tela 1000 × 1000, e testa navegação em duas resoluções.
