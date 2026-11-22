# Continuidade do Clipper — 22/11/2026

O histórico completo de implementação, erros, validações e próximos passos está no repositório da fonte:

[docs/CONTINUIDADE-2026-11-22.md](https://github.com/gahbruxxo-beep/seraph-clipper/blob/main/docs/CONTINUIDADE-2026-11-22.md)

Estado da distribuição neste registro:

- Nova distribuição: **2026.11.22.211818** (manutenção autônoma, backup conferido, corte opcional e indicadores).
- Fonte do novo pacote: `86207b2c9b717403d7951aa3ec388ee8ad6ece8f`.
- SHA-256 ZIP: `3c09edf78ba7da85e09425d154c00ce6b58aa64920a64cc824b0e7ddec402e60`.
- Última versão confirmada instalada no PC: **2026.11.22.032230**, distribuição anterior `a46a3cf`.
- A versão antiga precisa receber este pacote pelo atualizador manual uma vez; depois a instalação
  Windows com versão numérica pode atualizar sozinha, preservando backup do código.
- 37 testes Python, teste de backup em PowerShell 7/Linux e interface Chromium aprovados;
  Windows/Drive real desta nova rodada ainda não confirmados.
- Manifesto: `clipper/versao.json`; aplicativo: `download/VisusClipper.zip`.
- Atualizador manual: `download/Atualizar-Clipper.bat`, auxiliar com nome/hash fixado no BAT.
- Site público: https://visusclipper.online; painel servido pelo PC: https://painel.visusclipper.online.
- Upload Meta em 0% continua em investigação, inclusive fora da automação. Não anunciar como resolvido.
- GitHub Actions estava bloqueado por cobrança; publicação pelo GitHub Pages funcionou.

Este registro acompanha a nova distribuição. Alterações posteriores apenas de documentação
não regeneram automaticamente o ZIP.
Para uma próxima versão de código, seguir `docs/desenvolvimento.md` na fonte e executar
`python scripts/verificar_pacote.py` neste repositório antes de publicar.
Não adicionar logs privados, credenciais, perfis de navegador ou bancos do usuário ao site.
