# Origem e licenças

- **Interface:** [SrTristeSad/Ibis-Lua](https://github.com/SrTristeSad/Ibis-Lua), fixado como submódulo em `vendor/Ibis-Lua/`. A UI foi desenvolvida separadamente como protótipo visual, com ícones Lucide e seus avisos de licença em `vendor/Ibis-Lua/assets/icons/LICENSE-LUCIDE.txt`. A interface não é o ibisPaint oficial.
- **Motor:** núcleo de pintura v0.21, implementado em Lua a partir de referências técnicas do [PhotoCraft](https://github.com/storytold/photocraft). Veja o aviso de licença MIT em `LICENSE-PHOTOCRAFT-MIT.txt`. Conceitos adaptados incluem pincéis, mistura de cores, histórico, composição por tiles, máscaras e grupos.
- **Referência funcional:** [ibisPaint](https://ibispaint.com/), sem inclusão de código, logotipos ou arquivos proprietários.
- **Bono-Lua/DragonBones:** não usado; possibilidade futura que não faz parte da implementação atual.

A integração entre UI e motor foi construída de forma incremental. Nem todas as opções simuladas da interface têm comportamento real; não há garantia de correspondência visual 1:1 nem de compatibilidade com arquivos proprietários.
