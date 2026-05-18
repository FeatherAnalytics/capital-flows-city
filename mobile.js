/* ── Mobile responsive helpers ── */

// Clamp a tooltip DOM element so it stays within the viewport.
// Call inside requestAnimationFrame after setting left/top.
function clampTooltip(el) {
  requestAnimationFrame(function () {
    var r = el.getBoundingClientRect();
    if (r.right > window.innerWidth)
      el.style.left = Math.max(8, window.innerWidth - r.width - 8) + 'px';
    if (r.bottom > window.innerHeight)
      el.style.top = Math.max(8, window.innerHeight - r.height - 8) + 'px';
  });
}

// Return clamped {x, y} for a tooltip with known width/height.
// Use when tipX/tipY are computed before assignment.
function clampTipPosition(tipX, tipY, tipW, tipH) {
  var x = tipX;
  var y = tipY;
  if (x < 8) x = 8;
  if (y < 8) y = 8;
  if (x + tipW > window.innerWidth) x = Math.max(8, window.innerWidth - tipW - 8);
  if (y + tipH > window.innerHeight) y = Math.max(8, window.innerHeight - tipH - 8);
  return { x: x, y: y };
}

// Mobile panel toggles — collapse legend & stats behind h3 taps
document.addEventListener('DOMContentLoaded', function () {
  var mq = window.matchMedia('(max-width: 768px)');
  var legendH3 = document.querySelector('#legend h3');
  var statsH3 = document.querySelector('#stats h3');
  var legendEl = document.getElementById('legend');
  var statsEl = document.getElementById('stats');

  if (!legendH3 || !statsH3 || !legendEl || !statsEl) return;

  function onLegendClick(e) {
    e.stopPropagation();
    legendEl.classList.toggle('legend-expanded');
  }
  function onStatsClick(e) {
    e.stopPropagation();
    statsEl.classList.toggle('stats-expanded');
  }

  function applyMobile(matches) {
    if (matches) {
      legendH3.addEventListener('click', onLegendClick);
      statsH3.addEventListener('click', onStatsClick);
      legendEl.classList.remove('legend-expanded');
      statsEl.classList.remove('stats-expanded');
    } else {
      legendH3.removeEventListener('click', onLegendClick);
      statsH3.removeEventListener('click', onStatsClick);
      legendEl.classList.remove('legend-expanded');
      statsEl.classList.remove('stats-expanded');
    }
  }

  applyMobile(mq.matches);
  mq.addEventListener('change', function (e) { applyMobile(e.matches); });
});
