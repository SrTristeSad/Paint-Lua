# Paint-Lua v0.39 — pausa da animação de seleção

## Como usar

No editor, abra **Back → Settings** e procure
**Animar contorno da seleção**. A opção começa **ativada**.

- **Ativada:** o contorno exibe as faixas claras e escuras móveis do
  *marching ants* da v0.38. A geometria é a seleção exata da v0.37.
- **Desativada:** o contorno vira uma linha **vermelha estática**, sem
  shader ou movimento. É útil para quem prefere menos estímulos visuais
  e para evitar o custo gráfico do shader.

A mudança é aplicada ao vivo, sem tocar na máscara, em pixels, no
NPNT5 ou no histórico. Ao desligar, o shader já alocado é liberado.
A reativação compila novamente o shader somente quando necessário.
O estado de transformação, as linhas azuis do arraste e os contornos
vazios preservam seus comportamentos.

## Persistência e compatibilidade

O editor grava a preferência em `editor-preferences.txt`, junto com
a posição da barra de ferramentas, rótulos e outras opções. A chave
é `animate_selection_outline=1` ou `=0`.

O formato permanece **`version=1`**. A chave adicional é opcional
na leitura: arquivos gerados por versões anteriores continuam
válidos e ativam a animação por padrão. Valores que não sejam
`0` ou `1`, campos desconhecidos e campos duplicados continuam
sendo recusados.

A preferência pertence ao editor e **não é gravada na obra**, para
evitar arquivos NPNT diferentes por causa de uma opção de interface.

## Testes

`tests/test_selection_pause_v039.lua` verifica preferências, formato
antigo, validação, pausa sem chamada de shader, liberação da GPU,
retomada, preservação de contornos invertidos e histórico.

`tests/test_selection_ants_love_v038.lua` agora também valida, em
LÖVE 11.5 real, que duas imagens renderizadas em tempos distintos
sejam idênticas com animação desligada e que reativar volte a usar
shader.

A CI executa `PAINT_LUA_SELECTION_PAUSE_E2E=create` e depois
`PAINT_LUA_SELECTION_PAUSE_E2E=check` em **dois processos LÖVE**. Um
arquivo temporário com nome separado evita alterar preferências de
usuários; o segundo processo confirma a restauração e elimina o
arquivo de teste depois de reativar a opção. O teste Linux não
substitui validação manual com GPU e mesa digitalizadora no Windows.
