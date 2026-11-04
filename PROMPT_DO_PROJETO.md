# Continuidade — Paint-Lua unificado

**Decisão do criador:** este é **um projeto único** que incorpora diretamente a interface do Ibis-Lua e o motor do Paint-Lua. Não utilizar submódulos ou baixadores do outro repositório. Bono-Lua/DragonBones é uma possível ideia futura, NÃO é usado agora.

## Prompt para o próximo chat

Continue o desenvolvimento do repositório https://github.com/SrTristeSad/Paint-Lua. Leia este documento, README.md, AGENTS.md e ORIGENS.md, examine o código atual e os testes antes de modificar. Sou o criador e tomo as decisões finais. Colabore criticamente, preserve decisões e não reescreva funcionalidades existentes desnecessariamente.

Motor próprio v0.21: 20 módulos em core/, com pincéis, pressão, estabilização, texturas, composição por tiles, cache, histórico, preenchimento, camadas, máscaras, clipping, grupos e persistência NPNT1–NPNT5. A v0.23 incluiu `core/selection.lua`, seleção retangular, laço poligonal e varinha mágica cooperativa com máscara raster. Os controles de seleção da UI estão conectados ao núcleo; pincel e balde respeitam as seleções irregulares e o histórico as desfaz. Interface Ibis-Lua incorporada em src/, assets/ e app/ibis_main.lua. Ponte em app/paint_bridge.lua. **Nem toda opção da interface tem lógica de pintura conectada.** Na integração v0.22, balde cooperativo, conta-gotas, Alpha Lock de pincel, clipping, blending, visibilidade e histórico da UI foram ligados ao motor. Alpha Lock/bloqueio de camada não são persistidos no NPNT. Os botões do histórico são operacionais. Manter a divisão entre motor e UI.

Objetivo: editor de pintura em Lua para LÖVE 11.5, com PhotoCraft como referência técnica e ibisPaint como referência funcional, sem código nem arquivos proprietários. A interface original Ibis-Lua é do mesmo criador, mas sua cópia neste projeto é independente e editável.

Verificação: a bateria completa do núcleo agora está versionada em `tests/` com 870 testes em texlua (incluindo os novos de seleção); CI de LÖVE 11.5 no Linux com display virtual testou pincel, undo, redo, salvar/abrir NPNT. Faltam teste no Windows, tablet e medidas de desempenho. Priorizar a integração correta de propriedades das camadas, ferramentas, máscaras e grupos; corrigir erros reais, testar antes de publicar, e nunca inventar validação.

O backup da arquitetura antiga está na branch backup/pre-ibis-rebuild-2026-11-03, e a fase com submódulo permanece no histórico Git. Não restaurar essas arquiteturas sem autorização do criador.

**Próximo escopo sugerido:** seleções combinadas/invertidas e ferramentas de transformação sem destruir a camada original. Primeiro confirmar a v0.23 no Windows e corrigir problemas da interface. Leia `docs/SELECAO_v023.md`.

## Estado adicional: v0.24

O Paint-Lua tem transformação raster não destrutiva **até confirmar** em `core/transform.lua`.
A ponte expõe arraste, escala (10%), rotação (15°), aplicar e cancelar; o resultado é
recortado e colado na camada ativa com histórico único para pixels e seleção.
O limite é 1 milhão de pixels e a amostragem é nearest-neighbor. Não confundir
transformação raster aplicada com objetos flutuantes persistentes. NPNT5 continua vigente.
Os testes simulados chegaram a 926; CI com ImageData real precisa ser executado para
cada revisão. Próxima etapa: handles visuais de transformação, antialias, seleção/transformação
em outras camadas e melhorias de fluxo na UI; somente conforme pedido do criador.

## Estado adicional: v0.25

A ponte passou a integrar as APIs reais de máscaras (`core.layers`/`core.mask`), grupos hierárquicos (`core.groups`) e pinceladas em máscaras (`core.stroke`). O painel Layer abre a janela Grupos / Máscaras com três abas. Grupo pode conter uma camada ou a atual + inferior; a camada nova no topo de um grupo herda seu ID. O modo editar máscara usa B (revelar) e E (ocultar), preservando o RGBA original. As mudanças entram no histórico e persistem em NPNT5. Consulte `docs/GRUPOS_MASCARAS_v025.md`. A bateria simulada passou em 969 verificações, sem falhas. Testar no Windows e aferir FPS continuam pendentes. Os próximos candidatos são miniaturas reais, reordenação de camadas/grupos e feather/transformação suave.

## Atualização v0.26
Miniaturas reais de camadas/máscaras com cache de revisões (`core/thumbnail.lua`), ordenação de camadas atômica (`core/layers.lua`) e movimentação de grupos inteiros entre irmãos (`core/groups.lua`). O painel Layer suporta scroll, ↑/↓ e arraste de linhas visíveis; o painel avançado tem ↑/↓ de grupos. Sem alterar NPNT5. Movimentos inválidos são bloqueados, histórico e IDs permanecem corretos. Próximos trabalhos: miniatura composta de grupos, scroll/drag refinados e desempenho no Windows.

## v0.27 — Persistência da My Gallery

A decisão de prioridade foi implementar **salvamento de múltiplas obras sem nuvem e sem repositórios extras**. O módulo `src/gallery_storage.lua` grava dois catálogos alternados e um NPNT por ID de obra em `gallery/works/`. `app/ibis_main.lua` contém autosave ao sair do editor, na criação e no encerramento; `app/paint_bridge.lua` mantém o vínculo entre ID e documento. A migração do antigo `meu-desenho.npnt` nunca o apaga. Leia `docs/GALERIA_PERSISTENTE_v027.md` e os testes correspondentes antes de mudar persistência; evitar destruir desenhos, sobrescrever IDs ou abrir uma tela vazia no lugar de uma obra ausente.


### Atualização v0.28
A galeria agora usa miniaturas PNG derivadas dos arquivos `.npnt` e exporta composição PNG sem destruir as obras. `src/artwork_preview.lua` gera prévias por tiles sem alocar canvas inteiro; `src/png_export.lua` gera PNG até 4.194.304 pixels; `src/gallery_storage.lua` gerencia cache persistente por ID; `app/ibis_main.lua` oferece comandos de UI. Testes em `tests/test_gallery_preview_v028.lua`, `tests/test_core.lua`, e na CI de persistência da galeria. Não afirmar que suporta JPEG/PSD ou que o desempenho no Windows foi medido.


### Atualização v0.29 — PNG como camada raster
`src/png_import.lua` valida assinatura e IHDR, dimensões e tamanho antes de decodificar via `love.image.newImageData` com `FileData`. `PNGImport.insert` prepara tiles de uma camada desconectada antes de gravar um único snapshot estrutural (`core.layers.add`), preservando os pixels antigos e undo/redo. `Bridge:importPNGBytes` e `Bridge:importPNGFromFolder` conectam a API ao editor. A UI aceita `love.filedropped` (arraste do Explorador) e o painel Back > Importar PNG / Ctrl+I para arquivos de `imports/`. Não redimensiona a imagem, centraliza e recorta à tela; limites de 16 MiB de bytes e 2.097.152 pixels. Não há file-picker nativo nem JPEG/PSD. Continuar utilizando NPNT5; não reintroduzir submódulos. Testes mock em `tests/test_png_import_v029.lua` e reais em `tests/test_bridge_love.lua`. Consulte `docs/IMPORTACAO_PNG_v029.md`.


## Evolução v0.30
A importação PNG (v0.29) agora oferece prévia posicionável com escala/rotação antes do commit. A API `Import.insert` permanece disponível; a UI chama `Bridge:importPNGBytes` para iniciar a sessão e `Bridge:applyPNGImport` ou `Bridge:cancelPNGImport` para concluir. Geometria reusada de `core.transform`. O commit do PNG é uma única ação no histórico. Não reverter para importação imediata sem discussão com o criador. Teste no LÖVE e manual Windows ainda são prioridades.

## Estado v0.31

Importação PNG com prévia ajustável de v0.30 agora possui filtro Suave (bilinear
pré-multiplicado por alfa) e Pixelado (nearest) no painel. A interface inicia em
Suave; a API `PNGImport.insert` sem sessão mantém Pixelado por compatibilidade.
A prévia na GPU e a rasterização final CPU usam o mesmo modo. Ver
`docs/INTERPOLACAO_PNG_v031.md`. Não trocar filtro de transformações de
seleção ou do canvas, nem reescrever o núcleo.

## Atualização v0.32 — importação PNG

A rasterização suave de PNGs com rotação oblíqua aplica antialias por subamostragem com acumulação de RGB premultiplicada por alfa (`src/png_import.lua`). A importação pixelada e a transformação de seleções permanecem inalteradas. A UI expõe −1°, +1° e reset de giro; validar via `tests/test_png_rotation_aa_v032.lua`, E2E no LÖVE e documentação `docs/ROTACAO_PNG_v032.md`.

## Atualização v0.33 — ferramenta Transformar com dois filtros

Agora a transformação de seleções retangulares, laços e varinhas oferece
**Suave** (bilinear RGBA + cobertura subpixel) e **Pixelado** (nearest de
compatibilidade). A UI começa suave; chamadas diretas antigas a
`Transform.begin` continuam pixeladas. Aplicar confirma pixels e seleção em um
único undo/redo. Cancelar não modifica tiles. O NPNT5 não mudou.
Consulte `docs/TRANSFORMACAO_SUAVE_v033.md`,
`tests/test_transform_smooth_v033.lua` e `tests/test_bridge_love.lua`.
A bateria local da v0.33 passou em 1.140 verificações simuladas; testar a
integração no LÖVE real via CI e manualmente no Windows.

### Integração v0.34

As alças de Transformar são calculadas em `core/transform.lua` e usadas em `app/paint_bridge.lua`; manter hit-test e desenho sincronizados. Arrastar cantos preserva a proporção e o canto oposto. Alças ficam ocultas se a seleção ocupar menos de 28 px em tela. Veja `docs/ALCAS_TRANSFORMACAO_v034.md` e a suíte de testes.

### Estado v0.35

Inverter seleção: máscaras esparsas com `mask.inverted` e NPNT5,
desfazer/refazer estrutural, nenhum pixel modificado. Controlado no
Selection Area e em Ctrl+Shift+I (não modificar Ctrl+I, importação PNG).
Bloqueia imagens muito grandes ao rasterizar a seleção original.
Seleções combinadas e feather ainda não estão implementados.

### Estado v0.36 — combinação de seleções

A v0.36 permite escolher Nova, Somar, Subtrair ou Interseção para a
próxima seleção criada por retângulo, laço ou varinha. As máscaras
booleanas mantêm compatibilidade NPNT5 e inversões da v0.35.
Uma interseção vazia NÃO vira `nil` (pintura sem restrições), mas
uma seleção vazia com máscara raster explícita. O limite de 2 milhões
de pixels / 256 tiles protege do custo de combinação. Cada gesto entra
no histórico como uma operação, sem mexer nos pixels. Regressão da
UI e dos atalhos de importação PNG continua prioridade.

### Estado v0.37 — contorno de seleção fiel

O desenho da seleção raster substitui o fallback de bbox para regiões
grandes e máscaras invertidas por um processamento incremental apenas
nos tiles materializados. O perímetro de máscaras invertidas é calculado
exatamente, inclusive quando os furos alcançam as bordas. Cache persiste
entre pan, rotação e zoom. Um limite de pontos/segmentos por quadro
evita travamentos; contornos parciais são sempre linhas verdadeiras.
Pixels, histórico, formato NPNT5 e APIs de seleção anteriores não mudam.
Consulte `docs/CONTORNOS_SELECAO_v037.md`.

### Estado v0.38 — marching ants

A v0.38 aplica animação claro/escuro ao contorno geométrico real das
seleções com shader em coordenadas de tela. O padrão de faixa mede
5 px e se desloca 24 px/s, com ciclo curto para manter precisão. O
shader é cacheado por Bridge e libera recursos no reset da GPU. 
Sem suporte a shader o contorno anterior permanece estático. O drag
continua azul, a prévia de transformação mantém seu desenho próprio
e documentos/NPNT/histórico/pintura não são alterados. Testar no LÖVE
real, inclusive diferença temporal de pixels capturados da GPU.

### Estado v0.39 — animação configurável

Settings tem uma opção persistente **Animar contorno da seleção**,
inicialmente ativa. Quando desligada, a seleção volta ao contorno
vermelho estático da v0.37 sem shader; a GPU é liberada imediatamente
e só recompilada ao reativar. O campo opcional
`animate_selection_outline=0|1` é aceito nos arquivos de preferências
versão 1, mantendo os arquivos antigos válidos. Essa mudança visual
não faz parte do NPNT nem do histórico do documento.

### Revisão de integração da v0.39

A combinação de seleções da v0.36 exige distinguir "máscara vazia"
(`kind='wand'`, sem tiles, `inverted=false`) de ausência de seleção
(`nil` = pintura irrestrita). Corrigimos a inversão de retângulo
integral e máscara integral invertida: ambas devem resultar numa
máscara vazia, nunca limpar a seleção. Isso inclui obras grandes,
NPNT5 e undo/redo. O desenho ignora uma máscara vazia antes do shader,
sem ocultar o arraste de uma seleção em andamento. Revisar a cadeia
de PRs #2–#6 antes de novos recursos; não modificar `main` sem decisão.
