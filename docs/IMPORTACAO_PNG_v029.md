# Paint-Lua v0.29 — Importação PNG como camadas

Editor único em Lua / LÖVE 11.5. O importador usa o decodificador PNG do LÖVE e as camadas, tiles e histórico já existentes no núcleo.

## Windows: como importar

Abra uma obra no Paint-Lua. Há duas opções:

1. **Arrastar e soltar:** arraste um arquivo PNG do Explorador do Windows sobre a janela aberta do editor. Ele aparece em uma nova camada.
2. **Painel Back → Importar PNG (Ctrl+I):** coloque o arquivo em %APPDATA%\LOVE\paint-lua\imports e escolha o nome no painel. A pasta é criada ao abrir o painel, e o botão Atualizar recarrega a lista.

O programa não altera o PNG original nem o move de lugar. O diretório de dados do LÖVE é diferente da pasta que contém o arquivo .bat.

## Comportamento

- Cria **uma camada nova acima da atual**, sem substituir as camadas ou os grupos preexistentes.
- Posiciona o PNG no **centro do canvas**, sem ampliar ou reduzir; recorta a região que ultrapassa o canvas.
- Mantém a transparência original RGBA; pixels completamente transparentes não criam tiles.
- **Ctrl+Z** desfaz toda a importação e **Ctrl+Y** refaz como uma única ação.
- Salvar o projeto com Ctrl+S ou retornar à galeria grava a nova camada no formato **NPNT5**.
- Decodifica e prepara a imagem antes de alterar o documento; arquivos corrompidos não geram camadas parciais.
- Durante edição de máscara, volte a **Pintar pixels** antes de importar.

## Limites

O PNG deve ter até **16 MiB de dados**, no máximo **2.097.152 pixels** e até **8.192 pixels por lado**. O tamanho é validado pelo cabeçalho IHDR antes da decodificação. PNGs muito grandes podem causar uma pausa temporária; a importação ainda não é cooperativa.

Não há ainda diálogo nativo de seleção de arquivo, suporte a JPEG/PSD/SVG, importação de objetos vinculados, ou validação manual do uso no Windows. Os testes locais são executados com texlua e os testes gráficos pela CI do GitHub com LÖVE 11.5 em Linux sob display virtual.
