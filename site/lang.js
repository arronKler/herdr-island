/* Language routing for the Herdr Island site.
   English lives at the root; Chinese lives under /zh/. The counterpart page
   is declared on <html data-counterpart="…">. An explicit switcher choice is
   remembered; otherwise the first Chinese browser language wins. Everything
   else falls back to English. */
(() => {
  'use strict';

  const root = document.documentElement;
  const counterpart = root.getAttribute('data-counterpart');
  const current = (root.getAttribute('lang') || 'en').toLowerCase();
  const isChinese = current.indexOf('zh') === 0;
  const key = 'herdr-island-language';

  let preference = null;
  try {
    preference = window.localStorage.getItem(key);
  } catch (_) {}

  const go = (target) => {
    if (!target) return;
    window.location.replace(target);
  };

  if (preference === 'zh' && !isChinese) {
    go(counterpart);
    return;
  }
  if (preference === 'en' && isChinese) {
    go(counterpart);
    return;
  }
  if (preference === 'zh' || preference === 'en') return;

  const languages = navigator.languages && navigator.languages.length
    ? navigator.languages
    : [navigator.language || 'en'];
  const wantsChinese = languages.some((language) => /^zh([-_]|$)/i.test(language));

  if (wantsChinese && !isChinese) {
    go(counterpart);
    return;
  }
  if (!wantsChinese && isChinese) {
    go(counterpart);
  }
})();

document.addEventListener('DOMContentLoaded', () => {
  document.querySelectorAll('[data-language]').forEach((link) => {
    link.addEventListener('click', () => {
      try {
        window.localStorage.setItem(
          'herdr-island-language',
          link.getAttribute('data-language')
        );
      } catch (_) {}
    });
  });
});
