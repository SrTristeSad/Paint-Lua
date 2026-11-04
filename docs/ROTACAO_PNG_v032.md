# Paint-Lua v0.32 — bordas suaves ao rotacionar PNG

A v0.31 permitia escolher entre filtros **Suave** (bilinear, alfa pré-multiplicado) e **Pixelado** (nearest-neighbor). A v0.32 melhora a **cobertura geométrica** das bordas inclinadas no modo Suave: a suavização das cores, sozinha, não suavizava a silhueta da imagem.

## Como usar

1. Abra uma obra e importe um PNG arrastando-o para a janela ou usando **Back → Importar PNG**.
2. Escolha **Suave** para fotos e ilustrações ou **Pixelado** para pixel art.
3. Use **−15° / +15°**, os controles finos **−1° / +1°** ou **Giro 0°**. O painel mostra o ângulo e o zoom atuais. O PNG permanece numa prévia temporária.
4. **Aplicar** cria uma camada nova, registrada como uma única ação de histórico; **Cancelar** preserva a obra sem alterações.

## Implementação

- Para rotações não ortogonais no modo Suave, a rasterização usa quatro subamostras por pixel interno (grade 2×2) e dezesseis perto do contorno (4×4). A cobertura parcial é armazenada no alfa do pixel de destino.
- Acumulação de RGB **pré-multiplicado por alfa**, evitando halos criados por cores invisíveis em PNGs transparentes.
- Rotação ortogonal e transformação sem giro preservam a amostragem bilinear v0.31. O modo Pixelado continua exato (nearest-neighbor), sem antialias.
- A aplicação continua transacional: tiles temporários são construídos antes da criação da camada. Falhas de leitura ou memória não deixam camadas incompletas.
- A imagem fonte não é modificada. Exportação PNG, desfazer/refazer e projetos NPNT5 funcionam como nas versões anteriores.

## Limites e validação

A importação permanece limitada a 16 MiB no arquivo, 2.097.152 pixels na origem e na região rasterizada e 8.192 pixels por lado, conforme os limites existentes. O supersampling de rotações suaves custa mais CPU; em obras grandes, aplicar pode demorar mais. Não há interpolação bicúbica, Smart Objects, suavização das seleções ou aceleração GPU no commit. A suavização do contorno ainda é aproximada, não vetorial.

Os testes unitários cobrem bordas semitransparentes, proteção de cores em alfa zero, identidade sem giro, pixel art sem suavização, rollback, histórico e controles de ângulo. Há também um teste de pixels reais no LÖVE e um fluxo E2E para os controles da interface. A validação manual no Windows e com tablet continua pendente.
