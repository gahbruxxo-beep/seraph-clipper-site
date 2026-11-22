# Continuidade do Clipper — 22/11/2026

O histórico completo de implementação, erros, validações e próximos passos está no repositório da fonte:

[docs/CONTINUIDADE-2026-11-22.md](https://github.com/gahbruxxo-beep/seraph-clipper/blob/main/docs/CONTINUIDADE-2026-11-22.md)

Estado da distribuição neste registro:

- Versão publicada e instalação no PC confirmada: **2026.11.22.032230**.
- Fonte do pacote: `20c55d6ab39cfb50e816de577486e433a8bec02b`.
- Commit de distribuição: `a46a3cf`.
- Manifesto: `clipper/versao.json`; aplicativo: `download/VisusClipper.zip`.
- Atualizador manual: `download/Atualizar-Clipper.bat`, auxiliar com nome/hash fixado no BAT.
- Site público: https://visusclipper.online; painel servido pelo PC: https://painel.visusclipper.online.
- Upload Meta em 0% continua em investigação, inclusive fora da automação. Não anunciar como resolvido.
- GitHub Actions estava bloqueado por cobrança; publicação pelo GitHub Pages funcionou.

A atualização documental não regenera o ZIP nem altera a versão do aplicativo.
Para uma próxima versão de código, seguir `docs/desenvolvimento.md` na fonte e executar
`python scripts/verificar_pacote.py` neste repositório antes de publicar.
Não adicionar logs privados, credenciais, perfis de navegador ou bancos do usuário ao site.
