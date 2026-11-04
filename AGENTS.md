# Instruções de continuidade — Paint-Lua

1. Leia `PROMPT_DO_PROJETO.md`, `README.md` e `ORIGENS.md` antes de editar.
2. O criador tem a decisão final. Preserve decisões, APIs e funcionalidades existentes.
3. **A UI escolhida é Ibis-Lua**, como submódulo em `vendor/Ibis-Lua/`. Não reintroduza Bono-Lua/DragonBones.
4. Mantenha `core/` (motor), `app/` (ponte) e a interface original separados.
5. Clone com `--recurse-submodules` e prepare o núcleo v0.21. Não confunda ausência de `core/` num clone novo com perda de código.
6. Testes antigos do núcleo: 777 em texlua com mocks; a integração Ibis-Lua e o LÖVE 11.5 real **precisam de validação**.
7. Avance incrementalmente: validar o canvas e o salvamento; depois integrar controles avançados, incluindo camadas, máscaras e grupos.
8. Respeite as licenças da interface e dos ícones Lucide em Ibis-Lua e as atribuições de PhotoCraft.
