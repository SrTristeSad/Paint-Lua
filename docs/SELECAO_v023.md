# Seleções — integração Paint-Lua v0.23

## Ferramentas da casca

O menu superior **Selection Area** abre cinco comandos: Retângulo (arrastar), Laço livre (arrastar o contorno), Varinha mágica (clicar na região), Selecionar tudo e Desmarcar. O laço e a varinha também ficam disponíveis na barra lateral. **Ctrl+A** seleciona todo o documento; **Ctrl+D** desmarca; **Esc** cancela um gesto ou job de seleção e, quando não há painel aberto, desmarca a seleção atual. **Ctrl+Z/Y** desfaz/refaz alterações de seleção e pintura.

Pincel, borracha e balde respeitam **os pixels exatos da seleção**, mesmo em laços e regiões descontínuas em termos de bounding box. A seleção é aplicada ao documento, não à ferramenta; a geometria é independente do zoom e da rotação da UI. O balde continua o algoritmo de regiões contíguas existente.

## Formas e limites

- Retângulo: coordenadas inteiras inclusivas ao arrastar; mantém compatibilidade de serialização NPNT1–NPNT4.
- Laço: polígono amostrado ao arrastar (até 4096 vértices); preenchimento geométrico por ray casting no centro dos pixels.
- Varinha: região conexa da **camada ativa**, distância máxima por canal RGBA (tolerância 0,08), processada em coroutine por pequenos lotes. Não usa todas as camadas combinadas. Limite de segurança de **2 milhões de pixels selecionados**; ao exceder, informa erro e deixa a seleção anterior intocada.
- Contornos: retângulo e polígono exibem a região exata; a varinha exibe contornos exatos quando a área delimitadora é até 262.144 px e tem até 4096 segmentos. Caso contrário, mostra só a moldura delimitadora, **mas as ações sobre pixels continuam usando a máscara exata**.
- Máscara da varinha: ImageData por tile de 256 × 256, criada somente para tiles ocupados pela seleção; não duplicada a cada pincelada. Há custo de memória temporária e serialização PNG.

## Salvar e abrir

O formato **NPNT5** foi introduzido apenas quando a seleção ativa é de laço ou varinha. É um acréscimo versionado ao container NPNT4, com forma e máscara de seleção anexadas após as camadas. Ao salvar um retângulo, o projeto continua usando o formato antigo adequado aos recursos existentes. O leitor continua aceitando NPNT1–NPNT4; leitores antigos que não suportam NPNT5 não podem abrir esses arquivos novos. O histórico de undo/redo não é gravado no arquivo, como antes.

## Testes e limites não resolvidos

O motor tem testes regressivos e casos novos para seleção, brush, fill, máscara, histórico e roundtrip NPNT5; há também teste de integração de ferramentas no LÖVE 11.5 real (Linux em display virtual). Não equivale a medições de FPS, RAM efetiva ou validação em Windows, tablet e caneta. Seleção com antialiasing, feather, bordas dinâmicas estilo *marching ants*, inversão/combinação de seleções e transformações do conteúdo são etapas futuras.
