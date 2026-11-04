# Instruções para assistentes — Paint-Lua

Este repositório é o ponto oficial de continuidade do projeto. **Leia [PROMPT_DO_PROJETO.md](PROMPT_DO_PROJETO.md) antes de propor ou implementar mudanças.** Leia também `README.md` e `ORIGENS.md`. O documento de continuidade é um resumo das decisões anteriores, não a transcrição literal do prompt original.

Regras principais:
- O criador do projeto toma as decisões finais. Colabore e argumente, mas preserve o escopo e as decisões existentes.
- Trabalhe incrementalmente na casca LÖVE e no núcleo Lua. Não substitua o motor nem reescreva funcionalidades que já existem.
- O núcleo v0.21 é distribuído em `archive/core-v0.21.parts/`; execute `sh scripts/prepare-core.sh` para criar `core/` antes dos testes.
- Execute os testes antes e depois das alterações e diga qual foi o ambiente. **777 testes em texlua com mocks não equivalem a validação no LÖVE 11.5 real.**
- PhotoCraft é referência técnica sob licenças próprias; ibisPaint é referência funcional, não código-fonte. Consulte `ORIGENS.md`.
- Preserve a compatibilidade de projetos `.npnt` NPNT1–NPNT4 e a separação `core/`, `app/`, `ui/`.
- A prioridade seguinte é **validar e integrar a casca no LÖVE 11.5 real** e, então, expor funcionalidades já implementadas no motor. Reavalie prioridades se o criador pedir outra coisa.
- Mantenha código, testes e documentação editáveis. Nunca afirme ter validado no dispositivo, executado testes ou publicado algo que não fez.

Consulte [PROMPT_DO_PROJETO.md](PROMPT_DO_PROJETO.md) para o contexto detalhado, comandos de instalação, estado atual e sequência sugerida.
