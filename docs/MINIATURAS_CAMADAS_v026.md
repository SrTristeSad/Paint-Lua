# Paint-Lua v0.26 — Miniaturas e organização de camadas

## O que mudou

A interface unificada inclui **miniaturas de pixels reais**, com cache de ImageData por identidade e revisões dos tiles. O painel **Layer** mostra uma miniatura RGBA 40×40 de cada camada. Quando a camada tem máscara, aparece também a miniatura de cobertura efetiva 19×19. A janela **Grupos / Máscaras** exibe um retrato maior da fonte escolhida, inclusive máscara de grupo.

A interface mantém o quadriculado para indicar pixels transparentes; ele não faz parte do arquivo de imagem. As miniaturas preservam a proporção do canvas e mostram o conteúdo bruto de cada camada (não o resultado mesclado com todas as outras). Mudanças de cor, máscara, inversão, undo/redo e substituição do ImageData invalidam a miniatura correspondente. O renderer trabalha sobre a quantidade de pixels da prévia, não precisa abrir uma imagem monolítica do documento.

## Como reorganizar

1. Abra **Layer**. Os botões **↑** e **↓** movem a camada selecionada uma posição na pilha (mais perto do topo/da base). Também é possível **arrastar uma linha até outra linha visível**.
2. A lista rola com a roda do mouse; assim, documentos com mais de três camadas continuam acessíveis.
3. Para mover **um grupo inteiro**, vá a **Layer → Grupos / Máscaras → Grupos** e escolha **Subir grupo / Descer grupo**. Um grupo sempre atravessa seu irmão completo — outra camada solta ou outro grupo, inclusive grupos aninhados.
4. Use **Ctrl+Z** / **Ctrl+Y** para desfazer/refazer. A ordem final fica gravada normalmente no formato **NPNT5**, sem criar uma sexta versão do arquivo.

## Integridade e restrições

- `core/layers.lua` valida a posição de origem/destino, confirma que ambas pertencem ao mesmo grupo imediato e rejeita movimentos que quebrariam contiguidade ou alterariam a camada base do clipping. Um movimento rejeitado **não** grava histórico nem muda a seleção.
- `core/groups.lua` move um bloco completo de folhas do mesmo grupo, preservando seus descendentes e máscaras; apenas irmãos são destinos válidos. A transação cria uma única ação no histórico.
- O cache de miniaturas usa **referência e revisão** das imagens, pois o sinal `dirty` pode ser consumido por outras rotinas de desenho. Código externo que editar diretamente os pixels deve chamar `Doc.markDirty` ou `Mask.markDirty` para forçar a reconstrução.
- A prévia usa `nearest-neighbor` e **não deve ser confundida com exportação final**. Ela pode não revelar detalhes muito finos em imagens enormes. Grupos inteiros ainda não têm miniatura mesclada.
- A reordenação não muda pixels nem recalcula os pincéis. Alpha Lock e bloqueio de camada ainda não são persistidos em NPNT.
- A publicação é testada com Lua simulado e LÖVE 11.5 no Linux com display virtual. Teste manual Windows, mesa digitalizadora e medição de RAM/FPS ainda estão pendentes.

## Testes

`texlua tests/test_core.lua` ou `lua5.4 tests/test_core.lua`: **1.008 verificações** na v0.26. Exercitam as miniaturas, revisões, máscaras invertidas, movimentos inválidos, grupos aninhados, histórico, seleção estável e reabertura NPNT5.

CI: além dos testes de núcleo, `PAINT_LUA_BRIDGE_E2E=1 love .` usa `ImageData` real para miniaturas de pixels e máscara e valida a ordem com undo/redo e persistência. `PAINT_LUA_LAYER_E2E=1 love .` exercita os **controles reais** de arraste, ↑/↓ e rolagem no painel Layer.
