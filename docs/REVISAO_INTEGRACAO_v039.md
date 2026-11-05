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

## Testes executáveis do aplicativo no Windows

O workflow passou a tentar abrir a interface no Windows real
(Windows Server hospedado pelo GitHub, LÖVE 11.5, `lovec.exe`).
`scripts/windows-love-e2e.ps1` usa apenas os arquivos do
`Paint-Lua-v0.39-Windows.zip` extraído. O modo `smoke` valida
que a inicialização da interface gerou um PNG real; o modo `bridge`
executa os testes de integração com renderização gráfica, NPNT5,
seleções e histórico. Os testes têm timeout e capturam logs.

O Windows Server 2025 hospedado pelo GitHub forneceu **OpenGL 1.1
GDI Generic**, incompatível com o mínimo **OpenGL 2.1** do LÖVE.
O modo de CI `-AllowMissingGraphics` emite uma advertência
**SKIP: GPU insuficiente**, registrada no sumário do job, somente
quando esse erro for identificado na saída do runtime. A verificação
do ZIP e do inicializador continua obrigatória; outras falhas ou
timeouts continuam fatais. O `bridge` é dispensado somente se o
`smoke` comprovou essa limitação. O resultado não é teste gráfico
Windows aprovado.

O teste pode ser executado em um Windows com driver gráfico adequado,
após extrair o ZIP e informar onde está o `lovec.exe` do LÖVE 11.5:

```powershell
./scripts/windows-love-e2e.ps1 -LoveConsole "C:\LOVE\lovec.exe" -ProjectDirectory "." -Mode smoke
./scripts/windows-love-e2e.ps1 -LoveConsole "C:\LOVE\lovec.exe" -ProjectDirectory "." -Mode bridge
```

O caminho acima é apenas um exemplo; utilize o caminho real do seu
runtime. Executar **sem** `-AllowMissingGraphics` mantém a validação
estrita. Testes manuais com caneta, pressão e performance permanecem
pendentes.

## Operações de seleção concorrentes (revisão v0.39)

Uma inconsistência foi corrigida em `Bridge:applySelection`: o
atalho **Selecionar tudo** (Ctrl+A) usava um caminho mais permissivo
que **Inverter** e **Combinar**. Durante um arraste de seleção ainda
não confirmado, prévia de importação PNG ou traço ativo no histórico,
isso poderia criar um snapshot estrutural prematuro e alterar o
estado de seleção no meio de outra operação.

Agora `applySelection` é o bloqueio comum de todas as operações
de seleção: recusa mutação durante pincelada, trabalho cooperativo,
transformação, arraste, prévia PNG ou `history.stroke`. A seleção
anterior e o histórico ficam inalterados, e o usuário recebe a
mensagem para concluir a operação atual. O comportamento explícito
de **Desmarcar** que cancela um arraste de seleção continua preservado.

`tests/test_selection_operation_lock_v039.lua` acrescenta 21
verificações das rotas `selectAll`, `applySelection`, `combineSelection`,
`invertSelection`, `clearSelection`, liberação dos bloqueios e
desfazer/refazer após concluir a operação. Não há alteração de NPNT,
pixels ou preferência visual. Essa revisão permanece no PR #6.

## Bloqueio de seleção durante preenchimento cooperativo

A última revisão incluiu o lock transacional `doc.history._fillLock` do
balde cooperativo nas entradas `Bridge:applySelection`,
`Bridge:canEditStructure` e na sincronização de propriedades
`Bridge:sync`. Antes, uma operação externa de `Fill.newJob`
podia deixar o histórico bloqueado sem criar `bridge.job`; atalhos
como Ctrl+A e alterações de camada chegavam a
`History.recordStructure` e lançavam um erro, em vez de recusar
a ação sem alterar o documento.

Agora seleção, camada e histórico são preservados enquanto a
transação estiver suspensa, inclusive após os primeiros pixels
temporários. Se a UI modificar o nome de uma camada durante a
transação, `sync` adia a alteração até que o balde termine ou seja
cancelado. Após cancelar, o preenchimento reverte os pixels parciais,
o lock é liberado e as operações voltam a funcionar normalmente.

A bateria `tests/test_selection_fill_lock_v039.lua` cobre essas rotas
com um trabalho `Fill.newJob` autêntico, incluindo cancelamento,
histórico, Ctrl+A, desmarcar, inversão, combinação e sincronização.
Não há alteração do formato NPNT ou do comportamento de desenho.

## Atalhos de histórico durante gestos (revisão v0.39)

Foi detectada outra divergência: `Bridge:historyStep` apagava
`selectionDrag` antes de aplicar Ctrl+Z/Ctrl+Y. Isso podia cancelar
silenciosamente uma seleção em andamento e desfazer ou refazer uma
ação anterior que o usuário não pretendia alterar. O histórico agora
**recusa os atalhos durante o arraste**, mantém o objeto do gesto e
orienta a concluí-lo ou cancelá-lo explicitamente.

O histórico também verifica o lock transacional de um preenchimento
iniciado fora do controlador (`doc.history._fillLock`) antes de
sincronizar camadas. `Bridge:beginSelection` impede iniciar tanto
retângulos/laços quanto a varinha mágica enquanto esse lock ou um
traço do histórico estiver ativo: a varinha não pode selecionar com
base em pixels provisórios que serão revertidos pelo balde.

`tests/test_selection_lifecycle_v039.lua` acrescenta 23 testes:
Ctrl+Z/Ctrl+Y com um arraste e pilhas reais de undo/redo, gesto
confirmado, lock externo antes e depois de pixels parciais, rollback
do balde e reinício seguro da varinha e da seleção retangular. A
mudança não modifica NPNT, os pixels do documento nem os formatos de
preferências. Permanece no PR #6, com `main` intocada.

## Liberação de memória ao trocar de obra (revisão v0.39)

`Bridge:attachDocument`, utilizado ao abrir uma pintura existente da
galeria, não limpava o mapa `uiByLayer` anterior. Como suas chaves são
fortes, as referências a camadas e `ImageData` das pinturas anteriores
podiam permanecer vivas após fechar a obra. `Bridge:dropImages`
tampouco liberava `selectionOutline`: a seleção raster e o cálculo
incremental de contorno permaneciam associados à obra antiga mesmo
após a troca para uma tela sem seleção.

A troca de documento agora limpa o cache de contornos junto aos demais
caches de imagem; `attachDocument` recria `uiByLayer`, reinicia
`selectionMode='replace'` e descarta o modo de job anterior, alinhando
a abertura pela galeria ao comportamento já usado por `sync(fresh)`.
Nenhum pixel ou histórico é transportado entre documentos. Um balde
ainda ativo na obra anterior é cancelado com rollback antes da troca.

`tests/test_document_switch_v039.lua` cobre abertura de arquivo NPNT
real, cancelamento de preenchimento cooperativo parcial, isolamento de
camadas e históricos, limpeza do cache incremental, modo de seleção
reiniciado, primeiro gesto e undo/redo na nova obra, além de nova
tela criada depois. Não há mudança no formato NPNT ou nos arquivos.

## Sincronização de opacidade e camada ativa durante jobs (v0.39)

Foi encontrada uma omissão no bloqueio de `Bridge:sync`: o caminho
anterior verificava somente alterações estruturais (nome, visibilidade,
modo de mesclagem, recorte, ordem e quantidade de camadas). Entretanto,
alterar **somente a opacidade** ou **somente a camada ativa** contornava
a condição de bloqueio e modificava o documento durante um balde
cooperativo, inclusive com pixels parciais e o token
`doc.history._fillLock` em uso. O mesmo era possível durante um job
de varinha iniciado pela ponte.

A sincronização agora distingue `changed` (mudanças que precisam de
snapshot estrutural) de `pending` (qualquer mudança de propriedade,
inclusive opacidade e índice da camada ativa). Enquanto houver lock
de preenchimento, gesto transacional externo ou job da ponte,
`pending` é adiado sem tocar no documento ou gravar undo/redo.
`uiByLayer` também só é atualizado depois que o bloqueio termina.
Assim, nenhuma referência de camada é trocada sob um job em andamento.

A regra já estabelecida foi preservada: movimentos do controle de
opacidade e mudanças da camada ativa **não criam snapshots a cada
frame**. Renomear uma camada continua criando exatamente um snapshot.
`tests/test_layer_sync_during_jobs_v039.lua` cobre o trabalho real
do balde antes e depois de produzir pixels, cancelamento com rollback,
a varinha, propriedades pendentes e histórico após liberar o job.

## Exportação PNG protegida contra pixels provisórios (v0.39)

O histórico já bloqueava o salvamento NPNT durante um preenchimento
cooperativo, mas `PNGExport.save` não verificava o token
`doc.history._fillLock`. Um balde criado diretamente por `Fill.newJob`,
sem estar registrado em `Bridge.job`, podia deixar pixels parciais no
documento; um comando de exportação PNG compunha e gravava esses pixels
mesmo que o balde fosse cancelado depois. Era possível exportar também
durante uma pincelada externa aberta (`doc.history.stroke`).

A API de exportação agora retorna erro claro **antes** de renderizar,
criar o diretório ou gravar bytes quando existe uma transação ativa.
`Bridge:exportPNG` recusa também essas operações externas e verifica
o retorno de `Bridge:sync(model)`; antes, mesmo que a sincronização
falhasse, exportava a versão anterior das propriedades da camada.
Depois de cancelar o trabalho, a exportação aplica as propriedades
pendentes e preserva o comportamento já existente de criar nomes
incrementais, sem sobrescrever imagens anteriores.

`tests/test_png_export_operation_lock_v039.lua` contém 19 verificações
com o balde cooperativo real, pixels parciais e rollback, controle de
opacidade pendente, pincelada externa, saída PNG real via mock de
filesystem e rejeição de exportação quando o modelo está fora do
editor. Não há mudança do formato PNG ou NPNT.
