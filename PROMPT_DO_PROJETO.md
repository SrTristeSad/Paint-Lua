# PROMPT DO PROJETO — Paint-Lua

> **Documento de continuidade (atualizado em 03/11/2026).** Este texto consolida decisões e resultados das conversas anteriores. **Não é uma transcrição do prompt original**, que não está disponível no repositório. Em caso de conflito com uma decisão posterior do criador, prevalece a decisão mais recente.

## Prompt pronto para colar em um próximo chat

> Continue o desenvolvimento do meu projeto **Paint-Lua**, cujo repositório oficial é **https://github.com/SrTristeSad/Paint-Lua**. Leia primeiro `PROMPT_DO_PROJETO.md`, `AGENTS.md`, `README.md` e `ORIGENS.md`, e examine o código do repositório antes de implementar qualquer mudança.
>
> Sou o criador do projeto e tomo as decisões finais. Você é meu colaborador técnico e criativo: discuta mudanças de direção quando necessário, mas execute as tarefas que eu pedir. Não descarte, reescreva ou substitua funcionalidades existentes sem necessidade. Preserve a identidade do Paint-Lua, as APIs compatíveis, o histórico e a editabilidade do código.
>
> **Objetivo:** construir um editor de pintura digital em Lua, baseado no LÖVE 11.5, com núcleo modular próprio e funcionalidades/experiência progressivamente comparáveis às de editores como o ibisPaint. O projeto **PhotoCraft** (https://github.com/storytold/photocraft), feito em Rust, é uma **referência técnica de algoritmos e arquitetura** para adaptar e reimplementar em Lua; o ibisPaint é **referência funcional**, não código-fonte nem promessa de compatibilidade com seus formatos proprietários. Respeite licenças e atribuições.
>
> O núcleo chegou à **v0.21**, com **777 testes aprovados em texlua com simulações das APIs do LÖVE**. Isso **não prova** funcionamento, FPS ou desempenho no LÖVE 11.5 real, no LuaJIT/FFI ou em celulares. A primeira casca LÖVE já está no repositório. Antes de adicionar muitos recursos, verifique sua inicialização e o fluxo desenhar → camadas → desfazer/refazer → salvar → reabrir no LÖVE real, reportando separadamente o que foi efetivamente testado e o que permanece pendente.
>
> Consulte a seção «Como continuar» abaixo. Ao alterar arquivos, rode testes, documente mudanças e publique no repositório quando eu solicitar. Não afirme que testou, publicou ou validou algo que não executou.

## Identidade e escopo

- **Repositório oficial e ponto de continuidade:** https://github.com/SrTristeSad/Paint-Lua
- **Linguagem:** Lua; **framework-alvo:** LÖVE 11.5; LuaJIT/FFI é um caminho que ainda precisa de testes reais.
- **Arquitetura:** núcleo de rasterização e processamento em `core/` separado da casca de aplicação em `app/` e `ui/`. Não colocar lógica de rasterização na interface.
- **Objetivo:** motor de pintura próprio e sustentável, com código legível, editável, testes e histórico de decisões. Não fazer cópia visual automática do ibisPaint.
- **Referência técnica:** https://github.com/storytold/photocraft (Rust; licenças MIT/Apache-2.0). Consultar `ORIGENS.md` e `LICENSE-PHOTOCRAFT-MIT.txt`.
- **Integração opcional:** https://github.com/SrTristeSad/Bono-Lua como submódulo em `vendor/Bono-Lua`. É um porte de DragonBones em andamento, **não uma biblioteca de widgets**; a ponte atual em `integrations/bono.lua` usa apenas `WorldClock` quando disponível.

## Estado do projeto em 03/11/2026

**Motor v0.21:**
- Pincéis com pressão e curvas de resposta, estabilização de traço, espaçamento, pontas texturizadas, pincel duplo, inclinação (tilt), dispersão e simetria.
- Fluxo de tinta, mistura de cores simplificada, reservatório/tinta úmida simplificados e borracha.
- Camadas, opacidade, visibilidade, diversos modos de mesclagem, máscaras de camada, máscaras de recorte e pintura em máscaras.
- Grupos aninhados (limite implementado de 8 níveis), máscaras de grupo e composição hierárquica.
- Histórico com desfazer/refazer, orçamento nominal de snapshots e salvamento protegido durante operações incompletas.
- Preenchimento de área scanline, inclusive modo cooperativo/cancelável.
- Composição por tiles e regiões, streaming, caches LRU e índice de camadas que contribuem para tiles.
- Formato nativo `.npnt`, com leitura de NPNT1–NPNT4; **isso não significa** compatibilidade com arquivos proprietários do ibisPaint.

**Casca existente:** `main.lua`, `conf.lua`, `app/editor.lua`, `ui/layout.lua` e `ui/draw.lua`. Interface inicial com canvas, pincel/borracha, zoom, deslocamento, cores, painel de camadas, desfazer/refazer e gravação/abertura de `meu-desenho.npnt` no diretório de dados do LÖVE. É uma **casca experimental**, não o editor completo nem design definitivo.

**Verificação registrada:** 777 testes do núcleo executados em `texlua` com mocks/simulações; smoke test do núcleo e integridade das 12 partes do pacote foram verificados durante a publicação. **Pendências importantes:** execução/validação visual no LÖVE 11.5 real, LuaJIT/FFI, estabilidade em sessões longas, latência de caneta, medição de RAM/FPS e testes em dispositivos móveis. Benchmarks anteriores são sintéticos, não garantias de desempenho real.

## Como encontrar, instalar e executar

O repositório armazena o núcleo v0.21 de forma comprimida em **12 partes** em `archive/core-v0.21.parts/`. **Um clone novo pode não ter `core/` até a extração.** Não conclua que o motor desapareceu por isso.

```sh
git clone --recurse-submodules https://github.com/SrTristeSad/Paint-Lua.git
cd Paint-Lua
sh scripts/prepare-core.sh
texlua scripts/smoke-core.lua   # se texlua estiver instalado
love .                          # requer LÖVE 11.5; validar na máquina real
```

O script `scripts/prepare-core.sh` reconstrói os módulos em `core/` e confere a integridade do arquivo. Se `core/doc.lua` já existir, o script não sobrescreve o núcleo. Para alterações futuras no motor, **não atualize só `archive/` ou só arquivos locais**: defina uma estratégia de versionamento clara (preferencialmente fontes Lua diretamente rastreadas no Git), sem perder a capacidade de reproduzir o pacote. Preserve o submódulo Bono-Lua e as atribuições.

## Como continuar com segurança

1. **Leia e inspecione o estado atual do GitHub**, incluindo commits recentes, arquivos, README e issues. Não presuma que este documento ainda é o estado mais novo.
2. **Prepare o núcleo e rode os testes existentes** antes de editar. Registre exatamente o ambiente (`texlua`, LÖVE real etc.).
3. **Priorize validar a casca existente no LÖVE 11.5 real**, corrigindo falhas de integração no menor escopo possível. Verifique desenho, borracha, camadas, zoom, histórico, salvar e abrir. Não reimplemente o que já existe no núcleo.
4. Depois da validação, **exponha progressivamente na interface** recursos existentes (máscaras, grupos, configurações de pincéis e preenchimento). Considere melhorias de desempenho e atualizações de índice/cache somente quando houver medidas e testes que justifiquem.
5. Preserve comportamento padrão e APIs anteriores; adicione testes para novos recursos, regressões e arquivos `.npnt` antigos. Toda mudança de formato deve ter versionamento e testes de migração/leitura.
6. Documente decisões, limitações e resultados honestamente. Mantenha os códigos-fonte editáveis e o projeto independente do assistente.

## Regras de colaboração e continuidade

- O **criador decide** o objetivo e aprova mudanças de direção. Faça críticas técnicas e proponha alternativas, mas não transforme uma sugestão em decisão oficial.
- Preserve nomes, características, escopo e decisões já estabelecidas; não misture o Paint-Lua com outros projetos.
- Não reescreva o motor ou a casca do zero quando uma integração incremental resolver.
- Ao usar PhotoCraft, adapte algoritmos à realidade do LÖVE/Lua e mantenha as licenças/avisos de atribuição aplicáveis.
- Não apresente como concluído aquilo que só funciona em teste simulado. Registre claramente o que foi implementado, testado, não testado e quais arquivos foram modificados.
- Se houver conflito entre este resumo e instruções novas do usuário, confirme apenas o ponto material e siga a decisão mais recente.

## Arquivos de referência rápida

- `README.md`: instalação, controles e organização.
- `AGENTS.md`: instruções curtas para assistentes de programação.
- `ORIGENS.md`: referências técnicas, proveniência e licenças.
- `scripts/prepare-core.sh`: extração do núcleo v0.21.
- `scripts/smoke-core.lua`: verificação básica de documento, camadas e histórico.
- `app/editor.lua`: integração da casca com o núcleo.
- `ui/layout.lua`, `ui/draw.lua`: interface experimental.

**Para começar a próxima conversa:** forneça o link deste arquivo e diga a tarefa que deseja executar agora. Não é necessário recontar todas as versões anteriores.
