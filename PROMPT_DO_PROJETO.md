# Continuidade do Paint-Lua

> Decisão mais recente do criador (03/11/2026): **substituir a antiga casca por Ibis-Lua**. DragonBones/Bono-Lua **não participa** da versão atual.

## Prompt para um próximo chat

Continue meu editor **Paint-Lua**, repositório oficial https://github.com/SrTristeSad/Paint-Lua. Leia este arquivo, `README.md`, `AGENTS.md` e `ORIGENS.md` e examine o código antes de mudar a arquitetura. O criador toma as decisões finais; você participa criticamente, preserva os recursos funcionais, testa o que modifica e informa limitações.

O objetivo é construir um editor de pintura em **Lua/LÖVE 11.5**, com um **núcleo de pintura próprio** (v0.21) e a **casca visual Ibis-Lua**, disponibilizada em https://github.com/SrTristeSad/Ibis-Lua. A UI original é um submódulo em `vendor/Ibis-Lua`. A ponte em `app/paint_bridge.lua` integra os recursos básicos. Preserve a independência entre núcleo e interface.

PhotoCraft (Rust) é **referência técnica** para conceitos reimplementados em Lua. ibisPaint é **referência funcional**, não uma fonte de código ou de assets proprietários. Mantenha créditos/licenças.

## Estado técnico

- Motor v0.21: pincéis com pressão, estabilização, texturas, simetria, mistura de tinta simplificada; camadas, máscaras, mesclagens, grupos aninhados, histórico, preenchimento e composição por tiles e cache; formato `.npnt` (NPNT1–NPNT4).
- **777 testes históricos em texlua com mocks**. A integração nova também passou em CI com **LÖVE 11.5 real no Linux headless** (UI, pincel, undo/redo e NPNT). Windows, latência, FPS e dispositivos móveis não foram validados.
- Interface Ibis-Lua: galeria, novo canvas, ferramentas e painéis, com muitas operações **ainda simuladas**.
- Integração inicial: canvas real, mouse/borracha, cores/tamanho/opacidade, camadas básicas e atalhos para histórico e salvar/abrir. Não afirmar que todas as ferramentas do Ibis-Lua estão integradas ao motor.
- Próxima prioridade: executar no LÖVE 11.5 real, corrigir a integração, adicionar testes de ponta a ponta e conectar opções do painel ao motor de forma incremental.

## Como preparar

```sh
git clone --recurse-submodules https://github.com/SrTristeSad/Paint-Lua.git
cd Paint-Lua
sh scripts/prepare-core.sh # Windows: executar testar.bat, que prepara automaticamente
love .
```

O núcleo é armazenado em 12 partes compactadas por limitações anteriores da publicação; os arquivos editáveis são criados em `core/`. Em futuras melhorias, considerar versionar os fontes diretamente, sem perder testes e atribuições.

**Backup da antiga main:** branch `backup/pre-ibis-rebuild-2026-11-03`. Não restaurar a casca antiga nem o submódulo Bono-Lua sem uma decisão explícita do criador.
