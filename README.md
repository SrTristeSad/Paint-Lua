# Paint-Lua

**Editor experimental de pintura digital em Lua e LÖVE 11.5.** O projeto combina a interface do **[Ibis-Lua](https://github.com/SrTristeSad/Ibis-Lua)** com o núcleo próprio de pintura **v0.21**. Este repositório é a base do projeto.

> Continue em outro chat: leia [PROMPT_DO_PROJETO.md](PROMPT_DO_PROJETO.md) e [AGENTS.md](AGENTS.md).

## Estado atual

- **Interface:** o Ibis-Lua fornece tela inicial, galeria, novo canvas e painéis de pincel, cor e camadas. Está incluído como **submódulo Git fixado numa revisão**; o código original permanece no repositório Ibis-Lua.
- **Motor:** os pixels reais, pincel, borracha, composição e histórico usam o núcleo Lua v0.21. A ponte inicial está em `app/paint_bridge.lua` e a adaptação da interface em `app/ibis_main.lua`.
- **Atualmente integrados:** criação de documento, pintura básica com mouse, borracha, cores, espessura/opacidade da interface, camadas básicas, zoom/rotação/pan da UI, salvar/abrir o arquivo `meu-desenho.npnt` no diretório de dados do LÖVE, Ctrl+Z/Ctrl+Y para o traço.
- **Ainda demonstrativos ou parciais:** galeria não salva todas as obras; filtros, transformações, texturas avançadas, algumas opções do painel de camadas, máscaras e grupos ainda precisam de conexão própria à interface. A integração não garante fidelidade visual ao ibisPaint proprietário.

## Instalar no Windows

Instale [Git](https://git-scm.com/) e [LÖVE 11.5](https://love2d.org/). No terminal:

```bat
git clone --recurse-submodules https://github.com/SrTristeSad/Paint-Lua.git
cd Paint-Lua
testar.bat
```

O `testar.bat` prepara `core/` automaticamente pelo PowerShell na primeira execução. Use um clone, não o botão **Download ZIP** do GitHub: o ZIP padrão não contém o código dos submódulos.

## Linux/macOS

```sh
git clone --recurse-submodules https://github.com/SrTristeSad/Paint-Lua.git
cd Paint-Lua
sh scripts/prepare-core.sh
love .
```

No Windows também é possível executar o script `scripts/prepare-core.ps1` manualmente. `core/` será criado com 20 módulos Lua a partir de `archive/core-v0.21.parts/` (12 partes, verificação SHA-256). Não há dependência de DragonBones ou Bono-Lua.

## Organização

| Caminho | Função |
| --- | --- |
| `vendor/Ibis-Lua/` | Interface original mantida como submódulo |
| `src/icon_pack.lua` | Adaptador local para carregar ícones do submódulo |
| `app/ibis_main.lua` | Integração incremental dos callbacks Ibis-Lua |
| `app/paint_bridge.lua` | Ponte de ferramentas e documento com o núcleo |
| `core/` | Motor v0.21 gerado pelos scripts |
| `archive/core-v0.21.parts/` | Núcleo compactado versionado |
| `scripts/` | Preparação e smoke test |

## Qualidade, proveniência e limites

O núcleo v0.21 registrou **777 testes históricos em `texlua` com mocks**. Além disso, o **GitHub Actions passou em LÖVE 11.5 real, sob display virtual Linux**, verificando abertura da UI, pincel com `ImageData` real, desfazer/refazer e salvamento/reabertura `.npnt`. Isso **não comprova desempenho nem funcionamento no Windows ou em dispositivos móveis**: faça testes manuais antes de confiar em trabalhos importantes.

[PhotoCraft](https://github.com/storytold/photocraft) é referência técnica e [ibisPaint](https://ibispaint.com/) é referência funcional; ambos são projetos diferentes. O Ibis-Lua é um projeto do mesmo criador, não o aplicativo oficial. Consulte [ORIGENS.md](ORIGENS.md), as licenças de ícones Lucide em `vendor/Ibis-Lua/assets/icons/LICENSE-LUCIDE.txt` e `LICENSE-PHOTOCRAFT-MIT.txt`.
