# Visus Clipper V2 — opcional e avançado

> **A V2 vem desligada e não é necessária.** O Visus Clipper normal (fila e canais) já baixa, corta e publica tudo.
> Este guia é só para quem tem experiência técnica e quer criar os próprios aplicativos no Google e na Twitch.
> Se você não sabe o que é um aplicativo OAuth, não ative a V2.

A V2 é um serviço Node 24+ separado que verifica lives dos seus canais, grava, manda para a IA e mostra os clipes na aba **Revisar** do painel.
Ela só inicia e só aparece no painel quando a opção `v2.ativo` está ligada (`true`) na configuração local do programa. O padrão é desligada (`false`).

## Regras de segurança da conta

- **Instagram, Facebook e Kwai nunca são publicados pelo navegador**, nem pela V2. Sem a API oficial da Meta configurada, essas redes ficam manuais (Baixar + Copiar legenda no painel). O Kwai é sempre manual.
- TikTok e YouTube podem ser publicados pelas APIs oficiais. YouTube é privado e TikTok é "só eu" (SELF_ONLY) por padrão.
- Nada é publicado antes da revisão e aprovação de uma pessoa. Erros depois do envio final pedem conferência e não são repetidos sozinhos, para evitar posts duplicados.

## Ativar (avançado)

1. Ligue `v2.ativo: true` na configuração local do programa.
2. Execute `Iniciar-V2.bat` na pasta do programa. Ele instala o Node LTS se faltar, instala as dependências e cadastra o início automático no logon.
3. Preencha **uma vez** `seraph/v2/.env` (criado a partir de `.env.example`) com os dados dos seus aplicativos. Esse arquivo é secreto: não compartilhe e não envie para nenhum lugar. Reinicie a V2 depois de mudar.
4. No painel, em **Início → V2**, conecte YouTube e Twitch.

Para desligar, volte `v2.ativo` para `false` e remova a tarefa "Visus Clipper V2" do Agendador de Tarefas do Windows.

O serviço escuta apenas `127.0.0.1:8767`. O painel normal (porta 8765) conversa com ele por uma ponte autenticada.

## Conectar YouTube e Twitch

**Google:** crie um cliente OAuth de aplicativo web, habilite a YouTube Data API v3, configure a tela de consentimento e cadastre exatamente `http://127.0.0.1:8767/oauth/youtube/callback` como redirecionamento. Preencha GOOGLE_CLIENT_ID/SECRET/REDIRECT_URI. Em modo de teste, inclua seu usuário como testador. São pedidos `youtube.readonly` e `youtube.upload`. A detecção vale só para o canal da conta autorizada.

**Twitch:** registre o aplicativo no console de desenvolvedor, com redirecionamento igual a TWITCH_REDIRECT_URI. Preencha CLIENT_ID/SECRET e autorize o canal pelo painel.

As lives precisam estar acessíveis ao yt-dlp (lives privadas ou só para membros não funcionam). A gravação para se houver menos de 10 GB livres ou depois de 24 horas.

## Publicação pelas APIs oficiais

- **YouTube:** usa a conta conectada. YOUTUBE_PRIVACY é `private` por padrão. O YouTube limita os envios por dia; verificar o canal em youtube.com/verify aumenta o limite.
- **TikTok:** TIKTOK_ACCESS_TOKEN de um aplicativo Content Posting API autorizado. O modo `inbox` exige finalizar no aplicativo do TikTok e nunca é marcado como publicado sozinho.
- **Instagram e Facebook:** só com a API oficial da Meta (aplicativo aprovado, Página e conta profissional, e um endereço HTTPS que entregue o vídeo ao serviço). Sem isso, ficam manuais. Nunca há tentativa pelo navegador.

## Dados e disco

- Clipes ficam em `storage/clips`; a revisão funciona igual ao painel normal.
- O backup do Visus Clipper **não inclui** os dados da V2.
- Converter vídeos usa bastante o processador. Não rode dois serviços V2 sobre a mesma pasta.

## Testar

`npm test` (na pasta `seraph/v2`) roda os testes locais com APIs simuladas, sem rede.
