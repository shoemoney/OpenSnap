#!/usr/bin/env python3
"""Rebuild the offline navigator comparison from the original guarded PNGs."""
from pathlib import Path
import base64
import json

here = Path(__file__).resolve().parent
records = json.loads((here / "results.json").read_text())
images = []
for phase in ("before", "after"):
    for appearance in ("light", "dark"):
        path = here / phase / "raw-sf" / f"S07-actual-size-{appearance}.png"
        images.append({"id": len(images), "phase": phase, "appearance": appearance,
                       "source": records[phase]["source"],
                       "label": f"{phase.title()} · {appearance.title()}",
                       "url": "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode()})
html = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>OpenSnap · Overview clarity</title><style>
:root{font:20px/1.5 system-ui,sans-serif;color-scheme:light dark;background:#131820;color:#f5f7fc}
*{box-sizing:border-box}body{margin:0;padding:24px;max-width:1600px;margin:auto}h1{font-size:36px;line-height:1.2;margin:0 0 16px}h2{font-size:26px}p{max-width:1000px}button,select,a{font:inherit;font-size:20px;color:inherit}button,select{padding:10px 14px;background:#283345;border:1px solid #7f90a8;border-radius:10px;cursor:pointer}button:focus-visible,select:focus-visible,a:focus-visible{outline:3px solid #ffc94e;outline-offset:3px}button[aria-pressed=true]{border:2px solid #ffc94e;background:#3d3a2d}a{display:inline-block;padding:8px}label{display:flex;gap:10px;align-items:center;flex-wrap:wrap}.controls{display:flex;gap:14px;flex-wrap:wrap;margin:22px 0}.thumbs{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:14px}.card{background:#202a39;padding:16px;border-radius:14px;min-width:0}.card img{display:block;width:100%;height:150px;object-fit:contain;background:#090d13}.card button{width:100%;margin-top:8px}.metadata{font-size:18px;overflow-wrap:anywhere}.preview{background:#090d13;border:1px solid #56667e;border-radius:14px;overflow:auto;margin:14px 0}.preview img{display:block;width:100%;height:auto}.preview.detail{height:460px;position:relative;overflow:auto}.preview.detail img{position:absolute;bottom:0;left:0;width:auto;max-width:none}.compare{display:grid;grid-template-columns:1fr 1fr;gap:16px}.compare>div{min-width:0}#notice{font-size:18px} @media(max-width:760px){body{padding:16px}.thumbs{grid-template-columns:1fr 1fr}.compare{grid-template-columns:1fr}h1{font-size:30px}}
</style><style>button[aria-pressed=true]{background:var(--accent-surface,#3d3a2d);color:var(--accent-surface-foreground,#f5f7fc)}@media(min-width:651px){.compare{grid-template-columns:1fr 1fr}}</style><h1>OpenSnap · Overview clarity</h1><p>The Actual Size overview now renders for its display area and backing scale. The viewport outline and navigation stay the same. These are guarded app captures; display migration and physical hover remain manual checks.</p>
<div class="controls"><label>Appearance <select id="appearance"><option value="all">Light and dark</option><option value="light">Light</option><option value="dark">Dark</option></select></label><button id="favorites" aria-pressed="false">Show favorites</button><button id="detail" aria-pressed="false">Enlarge overview detail</button></div>
<div id="thumbs" class="thumbs"></div><p id="notice" role="status"></p><h2 id="title"></h2><p id="source" class="metadata"></p><a id="download" download>Download original PNG</a><div id="preview" class="preview"><img id="hero" alt="Selected OpenSnap Actual Size capture"></div>
<h2>Compare captures</h2><div class="compare"><div><label>Left <select id="left"></select></label><div class="preview compare-image"><img id="leftImage" alt="Left comparison capture"></div></div><div><label>Right <select id="right"></select></label><div class="preview compare-image"><img id="rightImage" alt="Right comparison capture"></div></div></div>
<script>const images=DATA;let selected=2,onlyFavorites=false,detail=false;const favorites=new Set;const el=id=>document.getElementById(id);
function pick(id){selected=id;const item=images[id];el('title').textContent=item.label;el('source').textContent='Source: '+item.source;el('hero').src=item.url;el('download').href=item.url;el('download').download='OpenSnap-overview-'+item.phase+'-'+item.appearance+'.png'}
function render(){const visible=images.filter(i=>(el('appearance').value==='all'||i.appearance===el('appearance').value)&&(!onlyFavorites||favorites.has(i.id)));el('thumbs').replaceChildren();for(const item of visible){const card=document.createElement('div');card.className='card';const img=document.createElement('img');img.src=item.url;img.alt=item.label;const choose=document.createElement('button');choose.textContent=item.label;choose.onclick=()=>pick(item.id);const favorite=document.createElement('button');favorite.textContent=favorites.has(item.id)?'Remove favorite':'Favorite';favorite.setAttribute('aria-pressed',favorites.has(item.id));favorite.onclick=()=>{favorites.has(item.id)?favorites.delete(item.id):favorites.add(item.id);render()};card.append(img,choose,favorite);el('thumbs').append(card)}el('notice').textContent=visible.length?'Choose a capture, favorite it, or compare below.':'No favorites match this appearance.';const has=visible.length>0;for(const id of ['title','source','download','preview'])el(id).hidden=!has;if(has&&!visible.some(i=>i.id===selected))pick(visible[0].id)}
for(const id of ['left','right']){for(const item of images){const option=document.createElement('option');option.value=item.id;option.textContent=item.label;el(id).append(option)}el(id).value=id==='left'?'0':'2';el(id).onchange=()=>el(id+'Image').src=images[Number(el(id).value)].url;el(id).onchange()}
el('appearance').onchange=render;el('favorites').onclick=()=>{onlyFavorites=!onlyFavorites;el('favorites').setAttribute('aria-pressed',onlyFavorites);render()};el('detail').onclick=()=>{detail=!detail;el('detail').setAttribute('aria-pressed',detail);for(const node of document.querySelectorAll('.preview'))node.classList.toggle('detail',detail)};pick(selected);render();</script></html>'''.replace("DATA", json.dumps(images))
target = here.parents[1] / "navigator-retina-gallery.html"
target.write_text(html)
inline = html
for item in images:
    path = here / item["phase"] / "raw-sf" / f"S07-actual-size-{item['appearance']}.png"
    inline = inline.replace(item["url"], str(path))
inline = inline.replace("<h1>OpenSnap · Overview clarity</h1>", "")
inline = inline.replace("</html>", "<style>:root{background:transparent;color:var(--foreground,#f5f7fc)}body{padding:0!important}.card{background:var(--card,#202a39)}button,select{background:var(--secondary,#283345);color:var(--foreground,#f5f7fc)}</style></html>")
Path("/tmp/opensnap-retina-gallery-inline.html").write_text(inline)
print(target)
