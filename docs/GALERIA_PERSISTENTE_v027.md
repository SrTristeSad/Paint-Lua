# Paint-Lua v0.27 — Galeria persistente

A galeria integrada mantém **pastas, nomes, hierarquia, dimensões, ordem e múltiplas obras** entre execuções do LÖVE 11.5. O projeto não precisa de Git, rede ou aplicativos adicionais para salvar e abrir seus arquivos.

## Arquivos e funcionamento

- `gallery-index-a.txt` / `gallery-index-b.txt`: cópias alternadas do catálogo, com geração, validação estrutural e checksum. Um índice interrompido pode ser recuperado pelo outro.
- `gallery/works/<id>.npnt`: documento completo por obra, com todas as camadas, grupos, máscaras, seleções e pixels do formato NPNT existente.
- `gallery/works/<id>.npnt.bak`: cópia da última versão válida antes de sobrescrever uma obra, quando disponível. A abertura tenta a cópia se o arquivo principal estiver danificado.
- O antigo `meu-desenho.npnt` é **mantido intacto** e pode ser importado uma vez para uma nova galeria vazia.
- Os nomes dos arquivos são gerados por IDs numéricos do modelo, nunca a partir do nome digitado pelo usuário. O catálogo é apenas dados: nenhum código Lua é executado ao ler um índice.

## Fluxo

1. **Nova obra**: cria um item na galeria e salva um NPNT inicial específico. Ao falhar, informa o erro, sem descartar o documento que estiver aberto.
2. **Voltar à galeria**: conclui a pincelada e salva a obra ativa; se falhar, não fecha a tela de edição.
3. **Ctrl+S**: salva a obra ativa e mantém sua identidade estável na galeria.
4. **Reabrir**: carrega o NPNT da obra selecionada; arquivo ausente ou inválido gera uma mensagem e não cria um desenho vazio no lugar.
5. **Pastas**: criação, renomeação, movimento e última pasta visitada ficam no catálogo.
6. **Fechar janela**: salva uma obra aberta; em erro bloqueia o encerramento normal do LÖVE para evitar perda silenciosa.

O armazenamento usa o diretório de dados do LÖVE associado à identidade `paint-lua`. Os arquivos da galeria não são gravados na pasta dos fontes. A importação do arquivo único da v0.26 preserva o original como segurança adicional.

## Segurança e limitações

Se **ambos** os índices do catálogo estiverem corrompidos, a gravação de novas obras fica **bloqueada** para evitar que novos IDs sobrescrevam obras que ainda estejam no disco. O usuário deve fazer uma cópia de segurança dos arquivos existentes antes de tentar recuperá-los.

O processo não oferece sincronização em nuvem, versionamento completo de documentos, remoção permanente de arquivos, prévia composta de obras na galeria, ou gravação assíncrona. Uma falha de disco também pode corromper um NPNT, por isso backups externos continuam necessários.

Testes: `tests/test_gallery_storage.lua` valida codec, segurança, recuperação de falhas e múltiplos documentos; GitHub Actions roda a criação e a reabertura via controles LÖVE em **duas execuções separadas**, para verificar persistência real.
