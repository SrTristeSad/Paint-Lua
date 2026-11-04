# Referências e atribuições — Paint-Lua

## Núcleo de pintura v0.21

O motor presente em `core/` vem do pacote `nucleo-pintura-v0.21-photocraft-lua.zip`, desenvolvido em Lua para LÖVE 11.5. A cópia de transporte versionada está em `archive/core-v0.21.parts/`; o comando `sh scripts/prepare-core.sh` reconstrói os arquivos Lua sem alterá-los.

## PhotoCraft (referência técnica)

Repositório original: https://github.com/storytold/photocraft

O projeto Lua utiliza e reimplementa, em escala menor, conceitos encontrados no PhotoCraft, especialmente:

- `crates/paint/src/brush.rs`, `dynamics.rs`, `curve.rs`, `render.rs`, `tile.rs` e `symmetry.rs`: comportamento de pincéis, pressão, estabilização, ponta texturizada, cobertura e simetria;
- `crates/paint/src/mixer.rs`: conceito de reservatório de tinta, mistura e coleta de pigmentos;
- `crates/compose/src/composite.rs` e `crates/color/src/blend.rs`: composição, grupos, máscaras e modos de mesclagem;
- `book/src/architecture/rendering.md`: composição por regiões, tiles esparsos, redução de trabalho e cache.

Essas implementações Lua são simplificadas e não reproduzem todos os algoritmos, formatos e componentes de GPU do PhotoCraft. O código do PhotoCraft é licenciado alternativamente sob MIT ou Apache-2.0; a atribuição e o texto MIT correspondente estão em `LICENSE-PHOTOCRAFT-MIT.txt`.

## ibisPaint (referência funcional)

O ibisPaint é referência para a experiência de pintura e para a seleção de recursos, **não é fonte do código**. O Paint-Lua não tem compatibilidade comprovada com arquivos proprietários do ibisPaint; seu formato nativo é `.npnt` (NPNT1–NPNT4).

## Bono-Lua (submódulo opcional)

https://github.com/SrTristeSad/Bono-Lua

O Bono-Lua é um projeto separado. A casca atual apenas tenta integrar seu `WorldClock`, sem assumir que exista um sistema de widgets ou renderizador DragonBones completo. Preserve os avisos de licença presentes no repositório do Bono-Lua.

## Limites de validação

O núcleo v0.21 registrou 777 testes aprovados usando mocks de `ImageData` em `texlua`. A integração visual no LÖVE 11.5 real, o LuaJIT/FFI e o desempenho em dispositivos móveis ainda não foram comprovados.
