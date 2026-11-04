# Continuidade — Paint-Lua unificado

**Decisão do criador:** este é **um projeto único** que incorpora diretamente a interface do Ibis-Lua e o motor do Paint-Lua. Não utilizar submódulos ou baixadores do outro repositório. Bono-Lua/DragonBones é uma possível ideia futura, NÃO é usado agora.

## Prompt para o próximo chat

Continue o desenvolvimento do repositório https://github.com/SrTristeSad/Paint-Lua. Leia este documento, README.md, AGENTS.md e ORIGENS.md, examine o código atual e os testes antes de modificar. Sou o criador e tomo as decisões finais. Colabore criticamente, preserve decisões e não reescreva funcionalidades existentes desnecessariamente.

Motor próprio v0.21: 20 módulos em core/, com pincéis, pressão, estabilização, texturas, composição por tiles, cache, histórico, preenchimento, camadas, máscaras, clipping, grupos e persistência NPNT1–NPNT5. A v0.23 incluiu `core/selection.lua`, seleção retangular, laço poligonal e varinha mágica cooperativa com máscara raster. Os controles de seleção da UI estão conectados ao núcleo; pincel e balde respeitam as seleções irregulares e o histórico as desfaz. Interface Ibis-Lua incorporada em src/, assets/ e app/ibis_main.lua. Ponte em app/paint_bridge.lua. **Nem toda opção da interface tem lógica de pintura conectada.** Na integração v0.22, balde cooperativo, conta-gotas, Alpha Lock de pincel, clipping, blending, visibilidade e histórico da UI foram ligados ao motor. Alpha Lock/bloqueio de camada não são persistidos no NPNT. Os botões do histórico são operacionais. Manter a divisão entre motor e UI.

Objetivo: editor de pintura em Lua para LÖVE 11.5, com PhotoCraft como referência técnica e ibisPaint como referência funcional, sem código nem arquivos proprietários. A interface original Ibis-Lua é do mesmo criador, mas sua cópia neste projeto é independente e editável.

Verificação: a bateria completa do núcleo agora está versionada em `tests/` com 870 testes em texlua (incluindo os novos de seleção); CI de LÖVE 11.5 no Linux com display virtual testou pincel, undo, redo, salvar/abrir NPNT. Faltam teste no Windows, tablet e medidas de desempenho. Priorizar a integração correta de propriedades das camadas, ferramentas, máscaras e grupos; corrigir erros reais, testar antes de publicar, e nunca inventar validação.

O backup da arquitetura antiga está na branch backup/pre-ibis-rebuild-2026-11-03, e a fase com submódulo permanece no histórico Git. Não restaurar essas arquiteturas sem autorização do criador.

**Próximo escopo sugerido:** seleções combinadas/invertidas e ferramentas de transformação sem destruir a camada original. Primeiro confirmar a v0.23 no Windows e corrigir problemas da interface. Leia `docs/SELECAO_v023.md`.

## Estado adicional: v0.24

O Paint-Lua tem transformação raster não destrutiva **até confirmar** em `core/transform.lua`.
A ponte expõe arraste, escala (10%), rotação (15°), aplicar e cancelar; o resultado é
recortado e colado na camada ativa com histórico único para pixels e seleção.
O limite é 1 milhão de pixels e a amostragem é nearest-neighbor. Não confundir
transformação raster aplicada com objetos flutuantes persistentes. NPNT5 continua vigente.
Os testes simulados chegaram a 926; CI com ImageData real precisa ser executado para
cada revisão. Próxima etapa: handles visuais de transformação, antialias, seleção/transformação
em outras camadas e melhorias de fluxo na UI; somente conforme pedido do criador.

## Estado adicional: v0.25

A ponte passou a integrar as APIs reais de máscaras (`core.layers`/`core.mask`), grupos hierárquicos (`core.groups`) e pinceladas em máscaras (`core.stroke`). O painel Layer abre a janela Grupos / Máscaras com três abas. Grupo pode conter uma camada ou a atual + inferior; a camada nova no topo de um grupo herda seu ID. O modo editar máscara usa B (revelar) e E (ocultar), preservando o RGBA original. As mudanças entram no histórico e persistem em NPNT5. Consulte `docs/GRUPOS_MASCARAS_v025.md`. A bateria simulada passou em 969 verificações, sem falhas. Testar no Windows e aferir FPS continuam pendentes. Os próximos candidatos são miniaturas reais, reordenação de camadas/grupos e feather/transformação suave.
