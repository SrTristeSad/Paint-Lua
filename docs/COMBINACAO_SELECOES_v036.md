# Paint-Lua v0.36 — combinar seleções

## Uso

Abra **Selection Area** e selecione o modo do **próximo gesto**:
**Nova** (substituir), **Somar**, **Subtrair** ou **Interseção**.
Em seguida escolha Retângulo, Laço livre ou Varinha mágica e crie a
região no canvas. O modo permanece ativo para os gestos posteriores
até ser trocado. Os botões Selecionar tudo, Inverter seleção e
Desmarcar continuam independentes do modo escolhido.

- **Nova**: substitui a seleção antiga, como nas versões anteriores.
- **Somar**: união de pixels selecionados.
- **Subtrair**: retira pixels da seleção existente.
- **Interseção**: preserva só os pixels presentes em ambas.
 
Se não houver seleção anterior, Somar inicia uma nova; Subtrair e
Interseção são recusados sem histórico. Se a operação produzir zero
pixels selecionados, o programa preserva uma **máscara vazia ativa**:
a pintura não afeta pixels. Desmarcar (Ctrl+D) restaura a edição livre.
Esse detalhe evita confundir máscara vazia com a ausência de seleção.

## Implementação

`core/selection.lua` oferece `Selection.combine(doc,old,new,mode)`,
que aplica operações booleanas por pixel **apenas nos tiles
candidatos**. Retângulos e laços contribuem com tiles de suas áreas
delimitadoras; varinhas e máscaras invertidas contribuem com os
tiles já materializados. O resultado pode usar a inversão de
`core.mask` como valor padrão, evitando percorrer o canvas inteiro
quando os operandos são complementos.

Máscaras invertidas fornecidas pelo editor abrangem o canvas completo;
a combinação de máscaras invertidas parciais (fora desse invariante)
é recusada em vez de dar resultado silenciosamente incorreto.
Cada cálculo é limitado a **2.000.000 pixels** e **256 tiles**;
a recusa deixa intactos a seleção anterior, pixels e histórico.
Não é uma medição de desempenho nem promessa de tempo constante.

`Bridge:combineSelection` registra **um snapshot estrutural** apenas
depois de calcular o resultado. A varinha cooperativa só combina ao
concluir o job; cancelar não aplica seleção parcial. O modo é capturado
no início do gesto de mouse ou do job, de modo que mudanças posteriores
do controle não alterem aquele gesto. A serialização permanece **NPNT5**.

## Verificação

`tests/test_selection_combine_v036.lua` cobre união, diferença,
interseção, laço, varinha, complementos, NPNT5, máscara vazia,
limites, histórico e cancelamento de job. `tests/test_bridge_love.lua`
exercita pixels reais, undo/redo e roundtrip NPNT5.
A execução `PAINT_LUA_SELECTION_COMBINE_E2E=1 love .` percorre os
botões e gestos de mouse da interface real. Windows, mesa
digitalizadora e desempenho em documentos grandes continuam pendentes.
