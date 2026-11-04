# Fontes de referência — Windows

**Versão-alvo: 14.1.4. Data da consulta: 02/11/2026.**

A presença de uma captura numa fonte relativa ao Windows **NÃO prova** que a captura representa exatamente a build 14.1.4. Sem essa confirmação, não medir dimensões como definitivas.

## R1 — Versão alvo (oficial, verificada)

- URL: https://ibispaint.com/information.jsp?newsID=313331619
- Organização: ibis inc.; comunicado datado de 28/10/2026.
- Confirma: Windows 14.1.4 e modificações nesta versão.
- Relevância visual: botão de check em algumas janelas de configuração; contagem de obras sincronizadas no topo de My Gallery; mudanças na janela Settings/login; alterações relacionadas à animação.
- Limitação: não traz atlas completo de telas, coordenadas ou imagens comparativas de todos os estados.

## R2 — Produto Windows (oficial, identidade da plataforma)

- URL: https://ibispaint.com/productWin.jsp
- Imagem da página: https://ibispaint.com/img/product/win_app.png
- Confirma: edição Windows oficial e requisitos da plataforma (resolução mínima 1024×768), não a geometria exata da versão-alvo.
- Limitação: imagem promocional com interface em monitor, não referência integral de pixels.
- NÃO incorporar imagem original ao repositório como recurso do programa.

## R3 — Microsoft Store (distribuição oficial)

- URL: https://apps.microsoft.com/detail/9pfdf2zd4z4n
- Imagens promocionais de interface Windows: pincéis, seletor, materiais, régua/texto.
- Confirma: controles e organização visual em material publicado para Windows.
- Limitação: capturas traduzidas/cortadas e sem metadados inequívocos da build. Não considerar como 14.1.4 certificada.

## R4 — Documentação funcional do fornecedor

- URL: https://ibispaint.com/newFeature.jsp
- URL: https://ibispaint.com/lecture/index.jsp?no=183
- Confirma: recursos e gestos/atalhos descritos oficialmente, com observações sobre recursos Windows/Mac.
- Limitação: material também se refere a outras plataformas; cada screenshot precisa validação adicional antes de ser usado geometricamente.

## R5 — Lançamento histórico Windows (NÃO é 14.1.4)

- URL: https://prtimes.jp/main/html/rd/p/000000010.000015594.html
- Telas históricas Windows publicadas pela empresa (ex.: 9.4.2).
- Uso autorizado nesta pesquisa: verificar **história da plataforma**, não reconstruir layout atual.
- Nunca combinar coordenadas desta versão com 14.1.4 sem comparação explícita.

## R6 — Captura de terceiros Windows (versão não confirmada)

- URL: https://ibis-paint.uptodown.com/windows
- Mostra New Canvas e My Gallery no Windows em captura publicada por terceiro.
- Limitação: versão e escala não verificadas. Não usar para afirmar layout 14.1.4.

## R7 — Inventário oficial de ferramentas (multiplataforma)

- URL: https://ibispaint.com/lecture/index.jsp?no=4
- Confirma a sequência documentada de 15 ferramentas: Transform, Magic Wand, Lasso, Filter, Brush, Eraser, Smudge, Blur, Special Pen, Bucket, Vector, Text, Frame Divider, Eyedropper e Canvas.
- Também documenta controles da toolbar principal e canto superior direito.
- Limitação: o tutorial não é uma auditoria da build Windows 14.1.4; a sequência e as dimensões de barras e ícones precisam ser conferidas no aplicativo Windows da versão-alvo.
- O modelo simulado oferece seleção lógica dessas 15 ferramentas, sem afirmar reproduzir layout ou comportamento completo.

## R8 — Registro de mudanças estruturais entre versões

- URL: https://ibispaint.com/newFeature.jsp
- Em 12.2.0, a função Collection foi removida da tela inicial e as obras baixadas passaram para uma pasta Downloads dentro de My Gallery.
- Importante: a captura histórica Windows 9.4.2 de R5 mostra três botões, mas a reconstrução não deve reutilizar o botão Collection.
- A organização geral da tela inicial com logo e menu circular tem evidência Windows histórica, mas **não** tem geometria certificada na 14.1.4.

## Evidências faltantes para construção fiel

1. Capturas integrais da versão **Windows 14.1.4**, com resolução, DPI e idioma.
2. Evidências para título, My Gallery vazia/preenchida e novo Canvas.
3. Capturas de editor com todos os painéis e estados normais, hover, pressionado, desativado.
4. Sequências da versão alvo exibindo menus, submenus e diálogos após cliques.
5. Inventário iconográfico autorizado, sem cópia de arquivos proprietários.
6. Execução do aplicativo oficial para realizar a comparação pixel a pixel.

**Conclusão:** existem evidências suficientes para confirmar plataforma, versão, termos e escopo de inventário; não existem nesta pesquisa dados suficientes para afirmar reprodução visual 1:1.
