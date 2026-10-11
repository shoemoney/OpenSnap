(() => {
  const failures = [];
  const assert = (value, name) => { if (!value) failures.push(name); };
  const change = (id, value) => { document.getElementById(id).value = value; document.getElementById(id).dispatchEvent(new Event('change')); };
  const buttons = () => [...document.querySelectorAll('#thumbs button')];
  change('phase', 'all'); change('area', 'all'); change('appearance', 'all');
  assert(buttons().length === DATA.shots.length, 'all captures are visible');
  change('appearance', 'light');
  assert(buttons().length === DATA.shots.filter(s => s.appearance === 'light').length, 'appearance filter');
  change('area', 'Resize');
  assert(buttons().length === DATA.shots.filter(s => s.appearance === 'light' && s.area === 'Resize').length, 'combined filters');
  change('phase', 'After');
  if (!DATA.shots.some(s => s.phase === 'After')) {
    assert(document.getElementById('preview').hidden && document.getElementById('download').disabled, 'empty After cannot display a Before');
  } else {
    assert(document.getElementById('label').textContent.startsWith('After'), 'After shows After evidence');
  }
  change('phase', 'all'); change('area', 'all'); change('appearance', 'all');
  document.getElementById('clear').click();
  buttons()[0].click(); document.getElementById('compare').click();
  buttons()[1].click(); document.getElementById('compare').click();
  buttons()[2].click();
  assert(document.getElementById('compare').disabled && document.querySelectorAll('#comparison > div').length === 2, 'two-image comparison limit');
  buttons()[0].click(); document.getElementById('compare').click();
  assert(document.querySelectorAll('#comparison > div').length === 1, 'comparison removal');
  favoriteIds.clear(); document.getElementById('favorite').click(); document.getElementById('favorites').click();
  assert(buttons().length === 1, 'favorite filtering');
  document.getElementById('favorite').click();
  assert(buttons().length === 0 && document.getElementById('preview').hidden, 'empty favorites hide stale preview');
  document.getElementById('favorites').click();
  change('scale', 'native');
  assert(document.getElementById('preview').classList.contains('native'), 'native pixel view');
  change('scale', 'fit'); document.getElementById('clear').click();
  comparisons = DATA.defaultCompare || []; selected = DATA.defaultSelected ?? 0;
  change('phase', DATA.defaultPhase || 'all'); render();
  console.log(JSON.stringify({ galleryRuntimeFailures: failures, captures: DATA.shots.length }));
})();
