// revela as seções ao rolar e marca o item do menu da seção visível
(function () {
  var els = document.querySelectorAll('.revela');
  if (!('IntersectionObserver' in window)) {
    els.forEach(function (e) { e.classList.add('visivel'); });
    return;
  }
  var io = new IntersectionObserver(function (es) {
    es.forEach(function (e) {
      if (e.isIntersecting) { e.target.classList.add('visivel'); io.unobserve(e.target); }
    });
  }, { threshold: 0.15 });
  els.forEach(function (e) { io.observe(e); });

  var links = document.querySelectorAll('.topo nav a');
  var nav = new IntersectionObserver(function (es) {
    es.forEach(function (e) {
      if (!e.isIntersecting) return;
      links.forEach(function (a) { a.classList.toggle('ativo', a.getAttribute('href') === '#' + e.target.id); });
    });
  }, { rootMargin: '-45% 0px -50% 0px' });
  document.querySelectorAll('.projeto').forEach(function (s) { nav.observe(s); });
})();
