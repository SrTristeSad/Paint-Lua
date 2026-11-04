# Design do Paint Lua

A revisão responde à captura do editor em que o rail de 59 px mostrava
rótulos de duas linhas invadindo os ícones. Não basta trocar imagens:
o layout precisa reservar espaços independentes para cada ação.

## Componentes

- `src/ui_theme.lua`: azul-tinta, coral, contraste, bordas e espaçamento
- `src/editor_layout.lua`: geometria da barra lateral, barra superior,
  dock e controles do canvas, preservando Left/Right/Popup
- `src/icon_pack.lua`: mapeamento de nomes estáveis para Lucide
- `assets/icons/svg/`: 40 ícones editáveis (fontes abertas)
- `assets/icons/png/`: 40 imagens de 96 px utilizadas offline

## Princípios

O canvas domina a superfície. Ferramentas são ícones de tamanho constante,
com dica contextual quando o mouse passa sobre eles; rótulos não ocupam
espaço vertical no rail. O dock concentra ações gerais, enquanto ajuste
de espessura/opacidade fica sobre o canvas. Seleção ativa é coral;
controles inativos permanecem discretos.

## Limitações

A identidade Paint Lua é independente. Não são ícones oficiais do ibisPaint.
Não existe motor de pintura e a composição ainda não foi confrontada
pixel a pixel com capturas certificadas do Windows 14.1.4.
