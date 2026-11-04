# Grupos e máscaras — Paint-Lua v0.25

Este painel **opera sobre o núcleo de pintura**, não apenas sobre a aparência da interface. A interface foi inspirada no trabalho do projeto Ibis-Lua, agora incorporado diretamente ao Paint-Lua.

## Como acessar

No editor, abra **Layer** (`L`), depois clique na faixa **Grupos / Máscaras >** acima da lista de camadas. A janela contém três abas: **Grupos**, **Máscara camada** e **Máscara grupo**. Funciona também em janelas menores, sem necessidade de rolagem para encontrar esses comandos.

Na aba **Grupos**, `Grupo 1 camada` envolve a camada selecionada em um grupo; `Grupo 2 camadas` envolve a selecionada **e a imediatamente inferior**, quando elas são irmãs e a operação não separa uma máscara de recorte. `Desagrupar` remove o grupo imediato, preservando os pixels dos filhos. Também é possível alternar a visibilidade e mudar a opacidade em passos de 10%. O núcleo suporta até **8 níveis de grupos**.

Nas abas de máscaras, use **Adicionar** para criar uma máscara branca que inicialmente revela toda a pintura; **Remover** a elimina; **Ativar** mostra ou ignora seu efeito; **Inverter** troca revelar/esconder. Em **Editar máscara**, feche o painel, use **Pincel (B)** para revelar (branco) e **Borracha (E)** para esconder (preto). `Pintar pixels` sai do modo de máscara. A seleção ativa também limita a pincelada na máscara.

A máscara de camada atua só na camada selecionada. A máscara de grupo atua sobre a **composição isolada de todos os seus filhos**. Os pixels originais ficam intactos quando se pinta uma máscara. `[M]` e `[G]` na lista de camadas identificam máscaras e participação em grupos; as miniaturas ainda são ilustrativas.

## Integridade, histórico e arquivos

Adicionar, remover, ativar, inverter, pintar e desagrupar são ações **desfazíveis**. As propriedades dos grupos, máscaras e tiles de cobertura são persistidas no arquivo `.npnt`, no formato NPNT5 atual. A leitura dos formatos NPNT1–NPNT4 continua disponível.

Não é permitido alterar a estrutura durante uma pincelada, uma tarefa de preenchimento/varinha ou uma prévia de transformação. Se a criação de grupo for inválida, a operação é rejeitada sem modificar a hierarquia. Uma nova camada adicionada ao **final da pilha**, quando a anterior pertence ao grupo, herda esse grupo. Não há neste momento reorganização livre da árvore por arrastar nem edição de máscaras por miniaturas reais.

## Limitações e validação

As máscaras são raster, sem feather e sem visualização em miniatura própria. Grupos são representados por camadas planas com `groupId` e sua contiguidade é validada pelo núcleo. Na v0.25 foram acrescentados testes simulados de máscara e grupos ao conjunto de 969 verificações. O CI deverá validar também a edição no LÖVE 11.5 real (Linux/display virtual); isso não equivale a medições de desempenho, nem a testes manuais no Windows.
