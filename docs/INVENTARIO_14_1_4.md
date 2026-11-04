# Inventário inicial — versão Windows 14.1.4

Legenda:
- **Confirmado 14.1.4** = comunicado específico da versão comprova a existência/alteração.
- **Evidência Windows sem versão** = captura real ou material de promoção da edição PC, ainda não validado na build alvo.
- **Pendente** = requer captura integral, estados e medidas antes de implementação.

| Interface/estado | Evidência disponível | Status visual 14.1.4 |
| --- | --- | --- |
| Tela inicial / título | R2 (promo), R5 (histórico) | Pendente |
| My Gallery e gerenciamento | R1 (sincronização), R6 (imagem antiga), tutorial oficial Artworks Folder (no=193) | Navegação e pastas demonstrativas implementadas; geometria/ícones Windows 14.1.4 e nuvem pendentes |
| Novo Canvas / dimensões | R6 e W12 (screenshot Windows de versão desconhecida) | Presets/DPI e painel lateral demonstrativos; geometria 14.1.4 não verificada |
| Editor e barras | R2, R3 | Evidência Windows sem versão; medidas pendentes |
| Pincel e opções | R3, W14 (captura Windows Microsoft Store) | Biblioteca clara e parâmetros escuros reconstruídos parcialmente; medidas/ícones 14.1.4 pendentes |
| Borracha | R3 | Evidência Windows sem versão |
| Cor / seletor / paleta | R3 | Evidência Windows sem versão |
| Camadas e blending | R4, R6 e Layer Window Details oficial (no=156) | Janela e controles interativos demonstrativos; composição real e geometria 14.1.4 pendentes |
| Transformação / seleção | R3, R4 | Pendente |
| Preenchimento / filtros | R3, R4 | Pendente |
| Texto / formas / réguas | R3, R4 | Pendente |
| Materiais | R3 | Evidência Windows sem versão |
| Vetor | R3, R4 | Pendente |
| Animação / áudio / modo vídeo | R1 | Funcionalidades confirmadas, UI pendente |
| Configurações gerais / login | R1 | Alteração confirmada, geometria pendente |
| Menus contextuais e submenus | Sem série integral de capturas | Pendente |
| Pop-ups e botões de check | R1 | Alguns novos botões confirmados; localização pendente |
| View Menu / Grid Settings | Tutorial oficial no=168; capturas multiplataforma | Estados e guias demonstrativos implementados; geometria Windows 14.1.4 pendente |
| Hover, disabled, loading | R1 (mudanças gerais) | Pendente |
| Iconografia ferramenta por ferramenta | R3 (visão parcial) | Pendente |

## Situação de renderização (02/11/2026)

- Título: **desenho vetorial experimental** de logo e botões guiado pela captura antiga Windows 9.4.2; não foi comparado com 14.1.4.
- My Gallery: navegação e botão + funcionais; geometria provisória baseada em fonte Windows sem confirmação da versão.
- Novo Canvas: formulário funcional simulado; medidas e rótulos aguardam referência Windows 14.1.4.
- Editor: área de canvas e controles documentados, porém interface visual aproximada e incompleta, sem motor de pintura.
- Ícones: desenhos vetoriais próprios e preliminares para várias ferramentas e menus. **Nenhum conjunto foi aprovado como visualmente equivalente aos ícones oficiais**.
- Resultado: nenhuma tela aprovada como fidelidade 1:1.

## Escopo do modelo Lua

O modelo puro em src/model.lua implementa **simulação de estado**, não renderização ou comprovação de comportamento oficial. Inclui navegação conceitual título -> galeria -> diálogo novo canvas -> editor, escolha de pincel/borracha, painéis básicos, cores, espessura e camadas demonstrativas. Os testes comprovam apenas o funcionamento deste modelo.

## Regra de passagem para UI

Nenhuma tela passa a 'concluída' enquanto não forem registrados:
versão exata; origem e licença das capturas; resolução; escala DPI; idioma; normal/hover/selecionado/disabled; medidas; captura renderizada pelo LÖVE; overlay/diff; desvios conhecidos.

## Tool Select Position — etapa implementada

Estado simulado e navegável: esquerda, direita, Popup com 1/2/3 colunas, rótulos visíveis/ocultos, mensagens de desfazer e direção da roda do mouse. Abrir pela ação Back → Settings. Referências oficiais: manuais no=4 e no=81. Capturas de Windows 14.1.4, DPI, idioma e tipografia originais continuam pendentes; **não classificar a tela como concluída**.

## Color Window — etapa v14

O tutorial oficial no=11 e as notas da versão 14.0.0 sustentam a existência de seleção HSB/RGB/HEX, Current/Previous, opacidade, múltiplas paletas e janela flutuante. Em Ibis-Lua há implementação **funcional demonstrativa** desses controles, sem pintura, QR export, importação ou persistência de paletas. Geometria Windows 14.1.4 ainda não validada. Não alterar o status global do projeto para "cópia fiel".
