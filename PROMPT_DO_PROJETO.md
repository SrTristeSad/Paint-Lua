# Continuidade — Paint-Lua unificado

**Decisão do criador:** este é **um projeto único** que incorpora diretamente a interface do Ibis-Lua e o motor do Paint-Lua. Não utilizar submódulos ou baixadores do outro repositório. Bono-Lua/DragonBones é uma possível ideia futura, NÃO é usado agora.

## Prompt para o próximo chat

Continue o desenvolvimento do repositório https://github.com/SrTristeSad/Paint-Lua. Leia este documento, README.md, AGENTS.md e ORIGENS.md, examine o código atual e os testes antes de modificar. Sou o criador e tomo as decisões finais. Colabore criticamente, preserve decisões e não reescreva funcionalidades existentes desnecessariamente.

Motor próprio v0.21: 20 módulos em core/, com pincéis, pressão, estabilização, texturas, composição por tiles, cache, histórico, preenchimento, camadas, máscaras, clipping, grupos e persistência NPNT1–NPNT4. Interface Ibis-Lua incorporada em src/, assets/ e app/ibis_main.lua. Ponte em app/paint_bridge.lua. **Nem toda opção da interface tem lógica de pintura conectada.** Manter a divisão entre motor e UI.

Objetivo: editor de pintura em Lua para LÖVE 11.5, com PhotoCraft como referência técnica e ibisPaint como referência funcional, sem código nem arquivos proprietários. A interface original Ibis-Lua é do mesmo criador, mas sua cópia neste projeto é independente e editável.

Verificação: 777 testes históricos no motor com simulações; CI de LÖVE 11.5 no Linux com display virtual testou pincel, undo, redo, salvar/abrir NPNT. Faltam teste no Windows, tablet e medidas de desempenho. Priorizar a integração correta de propriedades das camadas, ferramentas, máscaras e grupos; corrigir erros reais, testar antes de publicar, e nunca inventar validação.

O backup da arquitetura antiga está na branch backup/pre-ibis-rebuild-2026-11-03, e a fase com submódulo permanece no histórico Git. Não restaurar essas arquiteturas sem autorização do criador.
