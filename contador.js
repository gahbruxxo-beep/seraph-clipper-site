// contador.js — conta visitas e downloads do visusclipper.online, SEM cookies e sem dados pessoais.
// Manda só contagens anônimas ("alguém viu a página X", "alguém baixou Y") para o banco do Visus;
// os números aparecem no painel do Visus Clipper (tela Estatísticas).
(function () {
  'use strict';
  var URL_RPC = 'https://ivczfmvlrbyyrlffhjmt.supabase.co/rest/v1/rpc/visus_contar';
  var CHAVE = 'sb_publishable_R8qHo5cBc4obChEG3rT5oQ_CN-NhjzN'; // chave pública (só pode chamar a função de contar)
  if (navigator.webdriver || /bot|crawl|spider|slurp|preview/i.test(navigator.userAgent)) return;

  function limpo(s) { return String(s || '').toLowerCase().replace(/[^a-z0-9._/-]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 60); }
  function enviar(chaves) {
    chaves = chaves.filter(Boolean).slice(0, 8);
    if (!chaves.length) return;
    try {
      fetch(URL_RPC, {
        method: 'POST', keepalive: true, mode: 'cors', credentials: 'omit',
        headers: { apikey: CHAVE, 'Content-Type': 'application/json' },
        body: JSON.stringify({ p_chaves: chaves })
      }).catch(function () {});
    } catch (e) { /* sem contagem não atrapalha o site */ }
  }

  // ---- visita
  var arq = location.pathname.split('/').pop() || 'index.html';
  var pagina = limpo(arq.replace(/\.html?$/, '')) || 'inicio';
  if (pagina === 'index') pagina = 'inicio';
  var celular = /Android|iPhone|iPad|Mobile/i.test(navigator.userAgent);
  var chaves = ['v:' + pagina, 'm:' + (celular ? 'celular' : 'pc')];
  var ref = '';
  try { ref = document.referrer ? new URL(document.referrer).hostname : ''; } catch (e) { ref = ''; }
  if (ref !== location.hostname) {           // navegar dentro do site não conta como "origem"
    var origens = [['google', 'google'], ['bing', 'bing'], ['instagram', 'instagram'], ['facebook', 'facebook'],
      ['fb.', 'facebook'], ['youtube', 'youtube'], ['youtu.be', 'youtube'], ['tiktok', 'tiktok'], ['t.co', 'x'],
      ['twitter', 'x'], ['x.com', 'x'], ['whatsapp', 'whatsapp'], ['wa.me', 'whatsapp'], ['kick.com', 'kick'],
      ['twitch', 'twitch'], ['radiowebzs', 'radio-rdw'], ['duckdns', 'voxvisus'], ['github', 'github']];
    var origem = ref ? 'outro' : 'direto';
    for (var i = 0; i < origens.length; i++) if (ref.indexOf(origens[i][0]) !== -1) { origem = origens[i][1]; break; }
    chaves.push('o:' + origem);
  }
  try {                                      // visitante do dia: só um aviso "já contei hoje" no aparelho
    var hoje = new Date().toISOString().slice(0, 10);
    if (localStorage.getItem('visus_contado') !== hoje) {
      localStorage.setItem('visus_contado', hoje);
      chaves.push('u:site');
    }
  } catch (e) { /* navegador sem armazenamento: só não conta como visitante novo */ }
  enviar(chaves);

  // ---- projetos vistos (cada seção da página inicial que a pessoa rolou até ver), uma vez por visita
  if ('IntersectionObserver' in window) {
    var vistos = {};
    var obs = new IntersectionObserver(function (itens) {
      itens.forEach(function (it) {
        var id = it.target.id;
        if (it.isIntersecting && !vistos[id]) { vistos[id] = 1; enviar(['s:' + limpo(id)]); obs.unobserve(it.target); }
      });
    }, { threshold: 0.35 });
    document.querySelectorAll('section[id]').forEach(function (s) { obs.observe(s); });
  }

  // ---- downloads e links para os projetos
  var NOMES = [[/VisusClipper\.zip/i, 'clipper'], [/Atualizar-Clipper/i, 'clipper-atualizador'],
    [/VisusTV\.apk/i, 'visustv-android'], [/RokuVisusTV/i, 'visustv-roku'], [/VisusTV-PC/i, 'visustv-pc'],
    [/Wattcha-Instalador/i, 'wattcha'], [/\.apk$/i, 'outro-apk']];
  document.addEventListener('click', function (ev) {
    var a = ev.target.closest && ev.target.closest('a[href]');
    if (!a) return;
    var href = a.getAttribute('href') || '';
    for (var i = 0; i < NOMES.length; i++) if (NOMES[i][0].test(href)) { enviar(['d:' + NOMES[i][1]]); return; }
    var host = '';
    try { host = new URL(a.href).hostname; } catch (e) { return; }
    if (host && host !== location.hostname) {
      var proj = /radiowebzs/.test(host) ? 'radio-rdw' : /duckdns/.test(host) ? 'voxvisus' : /painel\./.test(host) ? 'painel-clipper' : '';
      if (proj) enviar(['l:' + proj]);
    }
  }, true);
})();
