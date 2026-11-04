# Paint-Lua

Editor de pintura experimental em **Lua / LÖVE 11.5**, organizado em um núcleo de pintura independente (v0.21) e uma primeira casca gráfica. Este repositório é o ponto de desenvolvimento do projeto.

## Como executar

Requisitos: **LÖVE 11.5**, `git`, `sh`, `base64`, `xz` e `tar`. Para a conferência SHA-256, use `sha256sum` ou `shasum`.

```sh
git clone --recurse-submodules https://github.com/SrTristeSad/Paint-Lua.git
cd Paint-Lua
sh scripts/prepare-core.sh
love .
```

O núcleo v0.21 está versionado em 12 partes no diretório `archive/core-v0.21.parts/`. O script **reconstrói os módulos Lua editáveis em `core/`**, verifica a integridade do pacote e mantém os arquivos da casca intactos. Não é necessário baixar separadamente os ZIPs da conversa para executar o projeto. Para continuar desenvolvendo o motor, edite `core/*.lua` e versione os arquivos com Git normalmente.

## Controles da casca atual

- Arrastar o botão esquerdo sobre a tela: pintar ou apagar; `B` e `E` escolhem a ferramenta.
- Botão direito ou espaço + arrastar: mover o canvas; roda do mouse: zoom; `F`: centralizar.
- `[` e `]`: diminuir ou aumentar o pincel.
- `Ctrl+S`: salvar `meu-desenho.npnt` na pasta de dados do LÖVE.
- `Ctrl+O`: reabrir o projeto dessa pasta; `Ctrl+Z` e `Ctrl+Y`: desfazer e refazer.
- Painel direito: adicionar/selecionar camadas e trocar cores.

Esta interface é **um primeiro protótipo**, não a apresentação definitiva nem um editor completo com todas as ferramentas do núcleo expostas.

## Organização

- `archive/core-v0.21.parts/`: cópia comprimida versionada do núcleo.
- `core/`: 20 módulos Lua extraídos pelo script de instalação; pintura, histórico, composição, máscaras, grupos e persistência.
- `app/editor.lua`: estado do editor, comandos e entrada do usuário.
- `ui/layout.lua`, `ui/draw.lua`: desenho e áreas interativas da casca.
- `main.lua`, `conf.lua`: entrada e configuração do LÖVE.
- `integrations/bono.lua`: ponte opcional com o `WorldClock`.
- `vendor/Bono-Lua`: submódulo Git opcional, com desenvolvimento independente.
- `scripts/prepare-core.sh`: instalação e verificação do núcleo.
- `scripts/smoke-core.lua`: teste básico que pode ser rodado com `texlua`.

## Verificação

```sh
texlua scripts/smoke-core.lua
```

Os **777 testes do núcleo v0.21** passaram em `texlua` com simulações de `ImageData` do LÖVE antes da publicação. A integridade de todas as 12 partes publicadas no GitHub também foi conferida com o pacote original. **Ainda não houve validação visual e de desempenho da casca no LÖVE 11.5 real**, nem do caminho LuaJIT/FFI ou de dispositivos móveis.

## Referências, créditos e licenças

O [PhotoCraft](https://github.com/storytold/photocraft) é referência técnica para vários conceitos reimplementados/adaptados em Lua. Seu texto de licença MIT foi preservado em `LICENSE-PHOTOCRAFT-MIT.txt`. O **ibisPaint é referência funcional**, não fonte de código; não há compatibilidade comprovada com seus formatos proprietários. Detalhes em [ORIGENS.md](ORIGENS.md).

O [Bono-Lua](https://github.com/SrTristeSad/Bono-Lua) é um projeto independente, ainda sem renderizador DragonBones completo para a casca. A ponte atual usa apenas o relógio de atualização quando disponível, sem dependência obrigatória na inicialização do editor.
