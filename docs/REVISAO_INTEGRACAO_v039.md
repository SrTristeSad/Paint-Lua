# Paint-Lua — revisão de integração v0.35–v0.39

## Situação do repositório

A linha de desenvolvimento é empilhada, ainda em revisão:
**#2 (v0.35) → #3 (v0.36) → #4 (v0.37) → #5 (v0.38) → #6 (v0.39)**.
A presente correção está no **PR #6**, em vez de abrir mais um PR.
Nenhum merge automático ou mudança em `main` faz parte desta revisão.

## Invariante de seleção corrigida

No motor, `selection=nil` sempre significa que não há restrição para
o pincel. Uma seleção que existe, mas contém zero pixels, é diferente:
deve bloquear a pintura. A v0.36 introduziu uma máscara raster vazia,
mas a lógica de inversão da v0.35 ainda convertia duas situações em
`nil`:

1. Inverter retângulo que ocupa o documento inteiro.
2. Inverter máscara raster invertida sem exceções (todo o documento
   selecionado), inclusive após serialização NPNT5.

Essas operações agora retornam **`Selection.empty(doc)`**, uma
máscara raster sem tiles e com `inverted=false`. Isso também evita
rasterizar milhões de pixels para inverter um retângulo integral.

**Novo contrato:** `Inverter` produz o complemento, enquanto
`Desmarcar` (Ctrl+D) restaura explicitamente a pintura irrestrita.
As operações Somar, Subtrair e Interseção continuam a distinguir
máscara vazia de seleção inexistente. Os dados históricos e NPNT5
permanecem compatíveis, sem mudança de formato.

## Recursos gráficos

`Bridge:drawSelection` detecta uma máscara raster positiva sem tiles
**antes** de processar contornos ou inicializar `marching ants`.
Isso evita criar shader, executar uniformes e desenhar uma borda falsa
para uma seleção sem pixels. Um gesto de arraste novo permanece
visível mesmo se a seleção anterior for vazia.

## Verificações incluídas

- Testes de inversão e reinversão: área total, máscara plena,
  seleção vazia, ausência de seleção e documento grande.
- Testes com balde e pincel, para garantir que uma máscara vazia
  não permita modificar RGBA.
- Combinação booleana a partir de seleção vazia, undo/redo e
  serialização NPNT5 sem mudança de formato.
- LÖVE 11.5 real: seleção integral → inversão → máscara vazia,
  balde, histórico, persistência e renderização GPU sem shader.
- Manutenção da bateria de regressão v0.35–v0.39, de preferências
  e da interface.

## Limites da revisão

A CI no Linux e o pacote ZIP Windows não equivalem a teste em
máquinas Windows, desempenho de canvas grandes, canetas ou mesas
digitalizadoras. Os PRs continuam *draft* até revisão do criador.

A ordem de integração sugerida é **#2, #3, #4, #5, #6**, sem pular
dependências. Após incorporar cada etapa, conferir a base do PR
seguinte; não fazer squash dos cinco PRs sem verificar os testes
sobre a `main`.

## Gate adicional de distribuição Windows

Depois do job Linux completo, o workflow `windows_release` executa
num runner `windows-latest`: baixa o mesmo artefato
`Paint-Lua-v0.39-Windows`, extrai o ZIP, valida o LÖVE 11.5 x64
portátil oficial por SHA-256 e chama `testar.bat` dentro da pasta
extraída, com `LOVE11_EXE`, `PAINT_LUA_VERIFY_ONLY=1` e
`PAINT_LUA_NO_PAUSE=1`. O modo de verificação é não interativo
e nunca inicia a janela de desenho; `testar.bat` normal continua
iniciando o editor e aguardando o usuário. O teste também elimina
temporariamente `app/selection_ants.lua` e verifica que o launcher
termina com um erro explícito antes de restaurar o arquivo.

Esse gate testa **caminhos de arquivos, extração do pacote, .bat e
presença do runtime** no Windows. Não demonstra renderização GPU,
sensibilidade à pressão nem operação com caneta. Essas validações
seguem pendentes para Windows de usuário final.
