# Paint-Lua

Editor de pintura experimental em **Lua / LÖVE 11.5**, com o núcleo de pintura v0.21 e uma primeira casca de interface. A interface e o motor são módulos separados.

## Executar

```sh
git clone --recurse-submodules https://github.com/SrTristeSad/Paint-Lua.git
cd Paint-Lua
sh scripts/prepare-core.sh
love .
```

A versão distribuída em ZIP já inclui `core/`. No GitHub, a cópia comprimida do motor pode ser expandida com `scripts/prepare-core.sh` antes da execução.

## Controles da primeira casca

- Arrastar com botão esquerdo no canvas: pintar / apagar (ferramenta `P` / `E`).
- Botão do meio: mover o canvas; roda do mouse: zoom.
- `Ctrl+S`: salvar `meu-desenho.npnt` na pasta de dados do LÖVE (não no diretório do código).
- `Ctrl+O`: abrir esse projeto da pasta de dados; `Ctrl+Z` / `Ctrl+Y`: desfazer / refazer.
- `B`, `E`, `[` e `]`, `F`: pincel, borracha, tamanho, centralizar.
- Painel direito: selecionar / adicionar camadas e escolher cores.

## Organização

- `core/`: núcleo de pintura v0.21, mantido sem mudanças nesta integração.
- `app/`: estado e interação do editor; usa o núcleo, não o modifica.
- `ui/`: layout e desenho da casca no LÖVE.
- `integrations/bono.lua`: integração opcional e conservadora com `WorldClock`.
- `vendor/Bono-Lua`: submódulo Git de [SrTristeSad/Bono-Lua](https://github.com/SrTristeSad/Bono-Lua).
- `tests/`: testes do núcleo e novos testes da casca.

## Estado real da integração com Bono-Lua

O Bono-Lua é um porte em andamento do DragonBonesJS, **não uma biblioteca de widgets**. O runtime de armaduras/skins e o renderizador LÖVE ainda não estão completos. Esta casca utiliza widgets próprios desenhados pelo LÖVE e disponibiliza uma ponte para o relógio de animação do Bono-Lua. Não há reprodução de animações DragonBones nesta etapa.

## Verificação

Os 777 testes do núcleo v0.21 passaram em `texlua` e mocks do LÖVE; a nova casca tem testes próprios de fluxo de eventos. Validação visual e de desempenho no LÖVE real segue pendente.

## Créditos e licenças

O código do núcleo mantém `LICENSE-PHOTOCRAFT-MIT.txt` e `ORIGENS.md`. O Bono-Lua permanece em repositório separado com sua licença original (`LICENSE-DRAGONBONES`). Dependências e códigos não devem ser confundidos com implementações próprias do Paint-Lua.
