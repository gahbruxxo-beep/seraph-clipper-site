# Visus Clipper V2 — ingestão automática e publicação API-first

A V2 é um serviço Node 24+ separado, integrado à aba **Revisar** do painel Python existente. O código está implementado e tem testes locais com APIs simuladas; publicação real e seletores dos sites precisam ser validados com as contas do proprietário. Não foram usados tokens de produção nem publicados posts de teste.

## Iniciar no Windows

1. Execute `Iniciar-V2.bat` na raiz. Instala Node LTS se necessário, instala dependências e tenta cadastrar início automático no logon. Não reinstala dependências quando o lockfile não muda.
2. Configure **uma vez** `seraph/v2/.env`, criado a partir de `.env.example`, com os aplicativos OAuth e contas abaixo. Reinicie a V2 depois de mudar a configuração. Não envie esse arquivo ao GitHub.
3. No painel normal, **Início → V2**, conecte YouTube/Twitch. A autorização inicial é exigida pelos provedores. Tokens são renovados automaticamente enquanto a autorização continuar válida.
4. A V2 verifica lives a cada dez minutos, grava, encaminha para a IA e mostra os clipes em **Revisar**. Aprovar envia à fila; rejeitar preserva o arquivo na lixeira lógica.

Também é possível executar `npm ci --ignore-scripts` e `npm start` nesta pasta. Precisa de FFmpeg/ffprobe no PATH e da `.venv` Python do Clipper, com yt-dlp, Whisper, modelos e Ollama configurados. Use FFmpeg 8.0.x no Windows existente. O instalador original de Python continua necessário; esta V2 não baixa novamente os modelos de IA.

O serviço escuta apenas `127.0.0.1:8767`. O painel normal em 8765 usa uma ponte autenticada; não precisa colar a chave no painel normal. A interface independente em `http://127.0.0.1:8767` pede a chave gerada em `config/v2-panel-token`. Mantenha PORT=8767 para a integração atual. Se o agendamento do Windows falhar, o script avisa e inicia apenas a sessão atual.

## Conectar YouTube e Twitch

**Google:** crie um cliente OAuth de aplicativo web, habilite YouTube Data API v3, configure a tela de consentimento e cadastre exatamente `http://127.0.0.1:8767/oauth/youtube/callback` como redirecionamento. Preencha GOOGLE_CLIENT_ID/SECRET/REDIRECT_URI. Em modo de teste, inclua seu usuário como testador; a validade de refresh tokens depende do estado do aplicativo. São solicitados `youtube.readonly` e `youtube.upload`. O canal conectado é o canal do usuário autorizado: detecção via `liveBroadcasts.list(mine=true)`, não busca arbitrária de canais de terceiros. Para várias contas, conecte cada uma; a publicação usa a primeira conta YouTube habilitada nesta versão.

**Twitch:** registre o aplicativo no console de desenvolvedor, com redirecionamento exatamente igual a TWITCH_REDIRECT_URI. Preencha CLIENT_ID/SECRET. Autorize o canal pelo painel. A detecção usa Helix `/streams?user_id=...`; refresh tokens são renovados pelo serviço.

As lives devem estar acessíveis ao yt-dlp. OAuth usado na detecção não concede automaticamente cookies de download para streams privados, de membros ou restritos. Uma live pode perder os minutos anteriores à primeira detecção. Segmentos têm aproximadamente 15 minutos, limitados pelos keyframes; interrupções de rede são retomadas na próxima varredura. Por padrão, interrompe a gravação se houver menos de 10 GB livres ou após 24 horas. A finalização só ocorre depois que a API confirma que a live terminou; erro de rede não é tratado como fim da live.

## Contas para publicar

- **YouTube:** usa o OAuth conectado ou YOUTUBE_REFRESH_TOKEN com o cliente Google. Upload resumível `videos.insert`. YOUTUBE_PRIVACY é `private` por padrão; configure `public` para publicar publicamente. Projetos não auditados podem ter restrições impostas pelo Google.
- **Facebook:** FACEBOOK_PAGE_ID e FACEBOOK_PAGE_TOKEN da Página, com permissões de publicação aplicáveis (`pages_manage_posts`, leitura/seleção de Páginas conforme o aplicativo). Reels: iniciar sessão, upload, finalizar e confirmar processamento. Nunca usa o compositor Business Suite.
- **Instagram:** conta profissional vinculada à Página na modalidade Facebook Login; INSTAGRAM_USER_ID e INSTAGRAM_ACCESS_TOKEN com `instagram_basic`, `instagram_content_publish` e permissões de Página pertinentes. Cria container REELS, espera FINISHED e chama `media_publish`. `postarInstagramReel()` é exportada separadamente em `PublisherService.js`.
- **TikTok:** TIKTOK_ACCESS_TOKEN e aplicativo Content Posting API autorizado. `direct` usa `video.publish`; valida opções de privacidade do criador. `inbox` usa `video.upload` e **exige finalizar no aplicativo**: nunca é marcado como publicado automaticamente. Padrão SELF_ONLY; apps não auditados têm limitações. Renovação dos tokens Meta/TikTok ainda deve ser configurada pelo operador; não há assistente OAuth desses dois provedores nesta entrega.

Facebook/Instagram precisam baixar o MP4 de uma URL HTTPS. Configure PUBLIC_BASE_URL com um endereço que encaminhe **para a porta 8767**, incluindo `/media/*`. O domínio atual do painel, se encaminha somente para 8765, não atende essa mídia automaticamente. Cada URL de vídeo tem token aleatório e validade de quatro horas; não divulgue links ou tokens. A aprovação de aplicativos e as permissões dependem dos provedores e não podem ser criadas pelo código sem acesso às contas.

## Fallback e diagnóstico

`PublisherService.publish(platform, videoPath, meta)` também aceita `(platform, videoPath, title, description)`. Sempre normaliza antes de tentar API. Somente falhas anteriores à etapa que pode publicar permitem fallback. Timeout depois da publicação gera `needs_review`, para conferir a rede antes de repetir; evita posts duplicados.

Facebook usa `facebook.com/reels/create` e exige a identidade exata de FACEBOOK_PAGE_NAME (Visus Clips por padrão). Instagram usa `instagram.com`. Perfis separados `fb-bot-profile` e `ig-bot-profile` começam limpos e depois preservam login; extensões são bloqueadas. Workers e cache antigos são removidos antes da execução, mas a Meta pode registrar o worker novo necessário ao upload. `npm run connect:facebook` / `connect:instagram` abrem o perfil para o primeiro login. Os seletores podem exigir ajuste quando as plataformas mudarem a interface; se a Página não for confirmada, o bot para em vez de postar no perfil pessoal. YouTube/TikTok têm ponte para os conectores Playwright Python existentes, com perfis separados.

No Facebook, a identidade ativa é confirmada pelo texto do compositor da própria Página
(por exemplo, “No que você está pensando, Visus Clips?”) ou pelo seletor explícito. Um
simples atalho para a Página não é aceito. Se o endereço direto voltar à home, o robô usa
“Criar reel” e só aceita o input de arquivo depois de confirmar o compositor de Reels.
Depois de anexar, o robô confere nome e tamanho do arquivo, acompanha a requisição de
upload e exige uma prévia real. A mensagem “Carregue o vídeo para ver uma prévia” bloqueia
Avançar/Publicar e gera erro seguro, anterior à publicação.

`RESET_BROWSER_EACH_RUN=true` limpa cookies, IndexedDB, Cache Storage e service workers antes de cada abertura do navegador Meta. **Isso perde o login e impede autonomia até autenticar novamente.** O padrão preserva a sessão em um perfil novo, sem reutilizar o IndexedDB do Business Suite. Para recuperação pontual, execute `node --env-file-if-exists=.env src/connect.js facebook --reset`.

O upload espera input anexado, dispara change, espera preview e não avança com percentual incompleto. Falhas `rupload`/`blob:` e códigos `net::ERR_*` vão para eventos; logs omitem cookies, query strings e tokens. `logs/v2.log` contém logs do serviço Windows. A interface independente mostra as filas; eventos detalhados estão em `/api/events` (autenticado). Erros posteriores ao clique final pedem confirmação, não repetem silenciosamente.

## Fluxo e dados

- `LiveIngestorService`: canais OAuth → `storage/raw/{liveId}/*.ts` → `ready_for_clipping`.
- `ClippingService`: concatena segmentos e chama `scripts/v2_clip.py`, reaproveitando Whisper, IA e reframe existentes, com cortes de 20–60 s. Não há coleta de chat nem detector novo de risadas/gritos nesta entrega: a seleção usa os sinais disponíveis na IA existente.
- `TranscodeService`: H.264 High 4.2, yuv420p, 1080×1920, 30 fps, AAC 128k e faststart. Usa escala proporcional com preenchimento para não deformar vídeo horizontal; adiciona áudio silencioso quando necessário. Original preservado; cache validado por ffprobe. A fila Python antiga também passa obrigatoriamente pela conversão.
- `storage/clips/{clipId}.mp4`: `pending_review` → `approved` ou `rejected`. Aprovação cria jobs por plataforma; não publica antes da revisão.
- SQLite `storage/v2.sqlite`: channels, lives, clips, publish_jobs, eventos, estados OAuth e links temporários. Tokens dos canais criptografados com AES-256-GCM. A chave fica em `config/v2-token-key` ou TOKEN_ENCRYPTION_KEY. Não apagar a chave mantendo o banco.
- Jobs: queued → publishing → published/failed/needs_review, além de cancelled. `retry_count`, `remote_id`, `error_log` e eventos registram cada tentativa. Ao reiniciar, publicações interrompidas requerem conferência. Reaprovar um clipe não duplica jobs. Rejeição/undo não cancela publicação já em andamento.

A fila de publicações antiga continua separada; não são migrados nem republicados os posts antigos. Clipes novos da V2 aparecem no painel normal; a fila detalhada e lixeira V2 estão na interface da porta 8767, e um resumo aparece em Início. O processamento de IA usa a trava e os controles de pausa do pipeline existente; captura de live e chamadas de API têm ciclo próprio. Conversão libx264 usa CPU. Não execute dois serviços sobre o mesmo storage.

O backup anterior do Clipper **não inclui automaticamente** o banco e arquivos novos da V2. Para backup completo, pare a V2 e copie storage, config/v2-token-key, config/v2-panel-token e .env para local protegido. Não copiar apenas v2.sqlite com o serviço ativo (WAL). Limpeza automática de gravações antigas e integração do backup V2 continuam pendentes.

## Testar

`npm test` executa testes locais, conversão real com FFmpeg, APIs simuladas, autenticação, estados da fila e prevenção de duplicação. Na raiz, `.venv/bin/python -m unittest discover -s tests` (Windows: `.venv\Scripts\python.exe`) inclui conversão real de HEVC para H.264/AAC.

Para validar Live → Clip → Review → Publicação: configure OAuth; conecte seu canal; faça uma live acessível; aguarde uma varredura e o fim da transmissão; confira arquivos raw, clipes e revisão; escolha uma plataforma e use o modo ensaio da interface independente antes de publicar. Ensaio não chama o compartilhamento final, mas Meta pode receber um container de teste. Por fim, aprove um clipe de teste autorizado e confira o resultado na rede. Isso exige suas credenciais e não foi executado nas contas reais nesta entrega.
