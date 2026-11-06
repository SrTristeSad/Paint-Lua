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

## Prévia de transformação, PNG e arraste com alterações de camadas pendentes

Um estado da interface que ainda não havia sido coberto: `Bridge:sync`
adiava mudanças de camadas durante balde e varinha, mas permitia
alterar o documento enquanto havia uma transformação em prévia, uma
importação de PNG em prévia ou um retângulo/laço sendo arrastado.
Isso podia redirecionar a camada ativa, modificar propriedades antes
do commit do gesto e produzir uma ordem inesperada de undo/redo.

Agora `sync` também adia mudanças de quantidade, nome, visibilidade,
mesclagem, recorte, opacidade e camada ativa durante essas três
interações. Uma sincronização sem diferenças segue normalmente, para
não bloquear renderização da prévia. O estado pendente fica no modelo
da interface e pode ser aplicado depois que o gesto for confirmado
ou cancelado, em uma transação independente quando houver mudança
estrutural. `canEditStructure` preserva a mensagem do bloqueio de
`sync`, em vez de informar incorretamente que não há documento aberto.

O teste `tests/test_pending_preview_sync_v039.lua` cobre sessões
reais de transformação e prévia PNG, arraste de seleção, sincronização
adiada, cancelamento e confirmação, além da ordem de undo/redo. A
correção não acrescenta ferramentas e não modifica NPNT.

## Ctrl+D durante seleção ainda em arraste (revisão v0.39)

`Bridge:clearSelection` descartava `selectionDrag` antes de chamar
`Bridge:applySelection(nil)`. A proteção central então não via mais
o gesto e aceitava `Desmarcar` / `Ctrl+D` no meio de um arraste,
removendo a seleção anterior e gravando um snapshot de histórico.
Isso contradizia o bloqueio já aplicado a Ctrl+A, Inverter e
Combinar e podia destruir o gesto sem que o usuário o confirmasse.

`clearSelection` agora encaminha a ação diretamente para
`applySelection`, preservando o arraste ao recusar uma operação
concorrente. A tecla Escape continua sendo o cancelamento explícito
da seleção. Após confirmar ou cancelar o gesto, Desmarcar volta
a funcionar normalmente e o undo/redo permanece coerente.

Além disso, `invertSelection` e `combineSelection` verificam
`doc.history._fillLock` **antes** de calcular máscaras invertidas
ou operações booleanas: um balde cooperativo iniciado fora da
ponte não dispara trabalho caro de seleção que acabaria rejeitado
na última etapa.

`tests/test_selection_clear_during_drag_v039.lua` acrescenta
27 verificações com histórico real e redo pendente, botão do
painel e atalho Ctrl+D, gesto confirmado e cancelado, seleção
ausente, bloqueio externo e recusa precoce da rasterização.
Nenhum formato ou ferramenta foi alterado.

## Confirmação de PNG com edições pendentes no painel (v0.39)

A prévia de importação bloqueava corretamente a sincronização de nome,
visibilidade, mesclagem, opacidade e seleção de camada enquanto a imagem
era posicionada. Porém, confirmar o PNG chamava `refreshModel(model)`
após inserir a nova camada: a rotina reescrevia as entradas da interface
com as propriedades antigas do documento, apagando **alterações
pendentes do painel** que o usuário havia feito durante a prévia. Uma
camada adicionada apenas no modelo também desaparecia.

`Bridge:applyPNGImport` agora copia as entradas pendentes antes da
inserção, sem tocar no documento durante uma prévia que ainda pode
falhar. Após `PNGImport.insert` confirmar a nova camada e registrar
seu snapshot, a ponte reconstrói a interface, conserva a nova camada
PNG e reaplica as alterações de camadas e ordem capturadas. Se não
houve mudança explícita da camada ativa, a camada PNG segue selecionada;
se o usuário escolheu outra camada durante a prévia, essa seleção é
respeitada. A sincronização final registra alterações estruturais
como **uma segunda ação**: Ctrl+Z desfaz primeiro as edições do painel
e depois a importação, enquanto Ctrl+Y refaz na mesma ordem.

A falha de importação preserva a prévia e deixa as edições no modelo
para serem aplicadas depois do cancelamento. A ausência de mudanças
pendentes não cria snapshot extra. `tests/test_png_import_pending_commit_v039.lua`
contém **28 verificações** para cenários normais, propriedades,
adição de camada, IDs estáveis, isolamento de undo/redo e erro de PNG
totalmente transparente. Os formatos PNG e NPNT permanecem intactos.

## Reabertura NPNT durante gestos inacabados (v0.39)

O atalho `Ctrl+O` chama `Bridge:load(model)` para reabrir a obra
já salva. Antes, `load` decodificava o arquivo e chamava
`attachDocument` sem verificar operações pendentes. Esse caminho
descartava silenciosamente seleção em arraste, prévia de importação
PNG, prévia de transformação, pinceladas e trabalhos de balde/varinha.
Particularmente, um `Fill.newJob` criado diretamente pelo motor
mantém `doc.history._fillLock` mesmo sem `Bridge.job`;
reabrir durante o preenchimento substituía o documento e deixava
pixels provisórios e o trabalho vivos no documento abandonado.

`Bridge:load` agora recusa **antes de ler o disco** se houver
`self.stroke`, `self.job`, `self.selectionDrag`,
`self.transform`, `self.pngPreview`, `doc.history.stroke` ou
`doc.history._fillLock`. A sessão e as pilhas de undo/redo são
preservadas, com uma mensagem orientando concluir/cancelar. Depois
que o trabalho terminar, Ctrl+O continua reabrindo normalmente
o projeto NPNT ou a pintura atual da galeria.

O bloqueio vale para **recarregar o arquivo atual**, não muda
`attachDocument`: abrir deliberadamente uma obra diferente na
galeria continua usando o fluxo que cancela operações pertencentes
à ponte ao trocar de documento.

`tests/test_reload_during_operations_v039.lua` acrescenta
32 verificações cobrindo atalho Ctrl+O, retângulo, transformação
real, prévia PNG, varinha, balde cooperativo externo antes/depois
de pixels parciais, pinceladas internas/externas, rollback,
reabertura NPNT e caminho de galeria. O projeto salvo não muda
durante uma recusa.

## Confirmação de seleções após aquisição tardia de bloqueio (v0.39)

Havia uma janela entre iniciar um retângulo/laço e soltar o mouse:
`Bridge:finishSelection` fazia `self.selectionDrag=nil` antes de
chamar `combineSelection`. Se nesse intervalo um balde cooperativo
externo, uma pincelada direta no histórico ou um job concorrente
ativasse a proteção, a combinação era recusada e **o arraste já
havia sido descartado**, embora a seleção e o histórico antigos
continuassem intactos.

A confirmação agora verifica primeiro `self.stroke`,
`self.job`, `self.transform`, `self.pngPreview` e os estados
`doc.history._fillLock`/`doc.history.stroke`. Enquanto a operação
concorrente não termina, os pontos e o modo original do gesto,
a seleção anterior e as pilhas de undo/redo são preservados.
Depois de liberar o lock, o gesto pode ser confirmado normalmente,
criando um único snapshot. O cancelamento explícito com Escape
continua disponível; laços degenerados sem lock continuam a
ser descartados, como antes.

A regressão `tests/test_selection_finish_race_v039.lua` contém
31 verificações: retângulo iniciado antes de um balde externo,
preenchimento antes/depois de produzir pixels provisórios, rollback,
histórico com redo pendente, laço em modo Adicionar com uma pincelada
externa, job da ponte e o comportamento de um laço incompleto.

## Pincelada interna e atualização pendente de camadas (v0.39)

`Bridge:sync` já protegia o documento contra um balde externo,
uma varinha e prévias visuais. Porém, a condição
`doc.history.stroke and not self.stroke` **excluía a própria
pincelada do editor**. Durante um traço ativo, opacidade e troca
da camada selecionada eram aplicadas imediatamente; renomeação,
visibilidade ou alteração estrutural podiam chamar
`self:finish(false)` implicitamente e registrar snapshots sem
a soltura do mouse.

Agora toda alteração de camada é adiada quando `self.stroke`
ou `doc.history.stroke` estiver ativo. A referência à camada
original, os pixels provisórios e o histórico do pincel permanecem
íntegros. Soltar confirma apenas o traço; a sincronização seguinte
aplica as edições pendentes, registrando um snapshot separado
quando houver mudança estrutural. Cancelar o traço restaura os
pixels, sem criar histórico, e libera as mudanças leves.

Havia ainda um efeito colateral anterior: `Bridge:toCanvas`
retornava `nil` quando `sync` adiava uma mudança, interrompendo
o movimento do pincel, do arraste de seleção e de prévias.
Agora o gesto já ativo pode continuar convertendo coordenadas
**somente** quando o modelo ainda referencia a mesma obra aberta
no editor e não há `_fillLock` externo; nunca usa a geometria
de outro documento. Isso não permite novas operações de edição,
nem ignora as proteções de histórico.

`tests/test_stroke_pending_layer_sync_v039.lua` acrescenta
29 verificações usando `Stroke.new` real, pixels, commit e
rollback, coordenadas de mouse, opacidade, troca/renomeação/
visibilidade de camadas, undo/redo, arraste de seleção,
prévia PNG e saída do editor. Formatos NPNT/PNG e ferramentas
permanecem inalterados.

## Salvamento NPNT com alterações de camada pendentes (v0.39)

O atalho `Ctrl+S` antes executava `Bridge:sync(model)` mas
ignorava seu retorno; em seguida chamava `Bridge:save()`. Se
a interface mantinha alterações pendentes durante uma pincelada,
`sync` as adiava, mas `save` concluía o traço e gravava um
arquivo NPNT **sem o nome, a opacidade ou a camada ativa novos**.
O usuário recebia a confirmação de salvamento apesar das
alterações não persistirem. O fluxo de voltar à galeria usava
o mesmo padrão, com risco de sair do editor antes da gravação
dessas propriedades.

Agora `Bridge:save(model)` realiza a transação na ordem correta:
recusa prévias, seleção e jobs pendentes; bloqueia explicitamente
`doc.history._fillLock` e pinceladas externas antes de tocar no
arquivo; confirma a pincelada que pertence à própria ponte,
preservando o comportamento anterior; sincroniza o modelo atual
**após** a confirmação; e só grava NPNT se a sincronização tiver
concluído com sucesso. Também recusa um modelo de outra obra
ou fora do editor, sem trocar acidentalmente o documento.
Chamadas sem argumento `save()` permanecem compatíveis para
APIs que já sincronizaram o documento.

O atalho `Bridge:key('s')` e os salvamentos de criação/retorno
da galeria agora passam o modelo à mesma API de salvamento,
em vez de ignorar o resultado de uma sincronização separada.
As mudanças estruturais pendentes são registradas como uma
ação de histórico após a pincelada, preservando undo/redo.

`tests/test_save_pending_sync_v039.lua` adiciona **33 verificações**
com NPNT real decodificado, Ctrl+S e pincelada real, propriedades
e camada ativa, histórico, balde externo antes/depois de pixels
parciais, rollback, pincelada externa, prévias, modelo antigo,
galeria e compatibilidade com `save()`.

## Entrada das ferramentas sob seleção pendente ou Fill externo (v0.39)

`Bridge:press` não considerava `selectionDrag` nem o token
`doc.history._fillLock` antes de iniciar pincel, borracha,
balde ou conta-gotas. Se a ferramenta fosse trocada no meio de um
retângulo/laço, uma segunda operação poderia começar sobre a obra
enquanto o primeiro gesto continuava aberto. Se um
`Fill.newJob` criado fora da ponte pintasse pixels ainda
provisórios, o conta-gotas podia **amostrar cores não confirmadas**
por não passar pela proteção de histórico.

Um guarda único `canUsePaintTool` agora atende o evento
`press` e também as APIs diretas `pick`/`bucket`. Ele recusa
um gesto em andamento (pincel, seleção, transformação, prévia PNG
ou job da ponte), além de `doc.history.stroke` e
`doc.history._fillLock` vindos do motor. A recusa acontece
antes de converter coordenadas no evento de mouse e antes de
compor qualquer pixel no conta-gotas ou adquirir o token do
balde. As APIs diretas também não trabalham em outro documento
ou fora do editor.

`tests/test_paint_tool_operation_lock_v039.lua` registra
**41 verificações**, cobrindo troca de ferramenta durante
retângulo, API direta, conta-gotas sem leitura durante balde
externo antes/depois de pixels provisórios, rollback,
History.stroke externo, job interno, prévias, retomada do
pincel e do balde com undo/redo e documento/tela inválidos.
Os formatos NPNT e PNG não mudaram.

## Falha na confirmação de pincelada antes de persistir (revisão do PR #6)

`Bridge:finish(false)` capturava uma exceção de `Stroke:finish`,
tentava cancelar a transação e apenas registrava uma mensagem de status.
Os chamadores continuavam normalmente, podendo salvar NPNT, exportar PNG
ou avançar o histórico apesar de a pincelada não ter sido confirmada.

Agora uma **falha explícita** de finalização é propagada como retorno
`false, motivo`. `Bridge:save` e `Bridge:exportPNG` interrompem a
operação **antes de escrever arquivos**; `Bridge:historyStep` não
executa undo/redo nessa situação. Finalizações normais mantêm o retorno
anterior, inclusive a API de `Bridge:finish` usada pela interface.
O cancelamento/rollback da pincelada continua sendo tentado após a falha.

`tests/test_stroke_finish_failure_v039.lua` injeta uma falha na
finalização de um `Stroke` real e verifica NPNT anterior intacto,
ausência de PNG novo, histórico inalterado, rollback e recuperação
posterior por salvamento/exportação/desfazer. Não altera NPNT1–NPNT5.

## Seleção em arraste após recusa de combinação (revisão do PR #6)

Ao soltar um retângulo ou laço no modo Adicionar/Subtrair/Interseção,
`Bridge:finishSelection` descartava `selectionDrag` **antes** de validar
a geometria e combinar a máscara. Se o limite de 2 milhões de pixels /
256 tiles fosse excedido (ou se o laço tivesse pontos inválidos), não
havia seleção confirmada, mas o gesto já estava perdido.

Agora a geometria é construída com tratamento de erro antes de liberar
o arraste. Durante a aplicação o gesto é liberado temporariamente,
mantendo a proteção contra mutações concorrentes de `combineSelection`.
Se a operação for recusada, o arraste, o modo capturado, a seleção
anterior e as pilhas de undo/redo permanecem disponíveis. Escape segue
cancelando o gesto na interface. Se a geometria for genuinamente
vazia, a política anterior é mantida: não cria snapshot e descarta
o arraste degenerado.

`tests/test_selection_commit_rejection_v039.lua` exercita o limite real
em um documento 4096×4096 sem rasterizar a tela inteira, recuperação
após cancelamento, retângulo/laço inválidos, confirmação posterior e
undo/redo. O núcleo de seleção, o limite de processamento e o formato
NPNT1–NPNT5 não foram alterados.

## Troca de documento durante transações externas (PR #6)

Um preenchimento `Fill.newJob` iniciado diretamente no motor conserva
`doc.history._fillLock`, mas não possui referência em `Bridge.job`.
Antes desta revisão, `Bridge:sync(model)` ao criar uma tela nova e
`Bridge:attachDocument(model,doc,id)` ao abrir outra obra podiam
descartar as referências da ponte enquanto esse job ainda alterava
pixels provisórios da obra anterior. O mesmo era possível com uma
`History.begin` externa à ponte.

As duas vias de troca agora recusam a substituição antes de limpar
caches, seleção ou referências quando uma transação **não controlada
pela ponte** estiver aberta. A mensagem pede concluir ou cancelar a
operação externa. A obra e seu histórico permanecem disponíveis
para que o dono da operação a encerre; depois disso, a troca
prossegue normalmente.

Os preenchimentos pertencentes à própria ponte continuam sendo
cancelados por `Bridge:cancelJob`, inclusive com rollback, como
antes. Não há mudança em NPNT1–NPNT5 nem na política da galeria
para operações pertencentes à ponte. Regressão:
`tests/test_external_transaction_document_switch_v039.lua`,
executada na suíte principal.

## Compatibilidade de compilação com LuaJIT no Windows (PR #6)

Um teste real em Windows identificou um erro bloqueador na inicialização:
`app/ibis_main.lua:2496: function at line 1462 has more than 60 upvalues`.
O compilador Lua 5.4 usado na verificação de sintaxe da CI não impõe
o limite de 60 upvalues por função do LuaJIT utilizado pelo LÖVE 11.5.
Por isso o arquivo era empacotado e os testes automatizados passavam,
mas a interface não conseguia carregar no ambiente do usuário.

A função `draw_editor_panel` foi dividida sem alterar o desenho
nem as ações de interface: o conteúdo do painel de cores agora está
em `draw_color_panel(x,y,w,h)`, com escopo de upvalues próprio. A
CI foi reforçada com compilação de `main.lua` e dos arquivos Lua de
produção (`core/`, `app/`, `src/`) via `luajit -b`, além da
validação anterior por `luac5.4`. O gate deve falhar antes do
empacotamento se reaparecer esse erro de inicialização.

A correção requer validação no Windows real pelo usuário, que foi
quem detectou a incompatibilidade. A CI Windows ainda não executa
renderização GPU com OpenGL compatível; seu resultado não deve ser
interpretado como teste gráfico aprovado.
