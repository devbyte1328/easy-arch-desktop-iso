"""
spec_html -- render the Az'arch component set as ONE self-contained, interactive
HTML page (documentation/SPECIFICATIONS_COMPONENTS_NAVIGATE_FULL.html).

This is the interactive twin of the SVG (spec_svg): the same layered map -- seven
horizontal bands from the kernel at the bottom up to the leaf applications at the
top, every component drawn as a box coloured by category and marked by edition --
but you can actually *use* it. Click any component to open a detail panel with its
plain-language purpose, version, edition, category, layer, size and upstream link;
the map then highlights everything it requires (below it) and everything that
requires it (above it), so you see its place in the stack at a glance. Search by
name, filter by category and edition, and the bands re-flow live.

Unlike the SVG (which draws a readable subset per band), this page shows ALL
components, because its job is to let a developer decide what to add or pull out.

The file is fully self-contained: all data is embedded as JSON and all CSS/JS is
inlined, so it opens straight from disk in any browser with no server and no
network. The plain-language descriptions are the official Arch package %DESC%
strings (same source as the full-text spec), so nothing is hand-written or drifts.
"""

import html
import json

import spec_classify as K
import spec_svg as S

# Same seven layers as the SVG, bottom (0) -> top (6).
LAYER_DEFS = S.LAYER_DEFS


def _fmt_size(nbytes):
    if nbytes >= 1024 ** 3:
        return f"{nbytes / 1024 ** 3:.2f} GiB"
    if nbytes >= 1024 ** 2:
        return f"{nbytes / 1024 ** 2:.1f} MiB"
    if nbytes >= 1024:
        return f"{nbytes / 1024:.0f} KiB"
    return f"{nbytes} B"


EDITION_LABEL = {
    "az'arch": "Az'arch-modified",
    "arch-selected": "Explicitly selected",
    "arch-dep": "Dependency",
}


def _build_payload(packages, resolved, tiers, tags, glance):
    """Assemble the JSON payload the page's JavaScript renders from."""
    closure = resolved["closure"]
    heights = tiers["heights"]
    edges = resolved["edges"]
    rev = tiers["rev"]

    comps = {}
    for p in sorted(closure):
        rec = packages.get(p, {})
        tag = tags[p]
        layer = S.layer_of(p, tag["category"], heights[p])
        comps[p] = {
            "name": p,
            "version": rec.get("version", "?"),
            "repo": rec.get("repo", "?"),
            "desc": rec.get("desc") or "(no description in the Arch package DB)",
            "url": rec.get("url") or "",
            "size": _fmt_size(rec.get("isize", 0)),
            "isize": rec.get("isize", 0),
            "license": rec.get("license") or "",
            "edition": tag["edition"],
            "editionLabel": EDITION_LABEL[tag["edition"]],
            "category": tag["category"],
            "layer": layer,
            "azarch": tag.get("azarch_note") or "",
            "removed": bool(tag.get("removed")),
            "requires": sorted(edges.get(p, ())),
            "requiredBy": sorted(rev.get(p, ())),
            "transDeps": tiers["trans_deps"][p],
            "transDependents": tiers["trans_dependents"][p],
            "optdepends": rec.get("optdepends", []) or [],
        }

    # Per-category colour + canonical order, straight from spec_classify so the
    # HTML and the SVG use identical colours.
    present_cats = [c for c in K.CATEGORY_ORDER
                    if any(tags[p]["category"] == c for p in closure)]
    cat_colors = {c: K.CATEGORY_COLORS.get(c, "#8892a0") for c in present_cats}

    layers = [{"idx": i, "title": t, "subtitle": st}
              for i, (t, st) in enumerate(LAYER_DEFS)]

    return {
        "components": comps,
        "order": sorted(comps),
        "layers": layers,
        "categories": present_cats,
        "catColors": cat_colors,
        "editionLabels": EDITION_LABEL,
        "glance": {
            "base": glance["base"],
            "desktop": glance["desktop"],
            "kernel": glance["kernel"],
            "init": glance["init"],
            "ram": glance["ram"],
            "closure": glance["closure"],
            "byRepo": glance["by_repo"],
            "azarch": glance["azarch"],
            "selected": glance["selected"],
            "dep": glance["dep"],
            "maxHeight": glance["max_height"],
            "size": glance["size"],
            "isoVersion": glance["iso_version"],
        },
    }


def render_html(packages, resolved, tiers, tags, glance):
    """Return the complete self-contained HTML document text."""
    payload = _build_payload(packages, resolved, tiers, tags, glance)
    data_json = json.dumps(payload, separators=(",", ":"), ensure_ascii=False)
    # Guard against an accidental </script> inside data breaking the tag.
    data_json = data_json.replace("</", "<\\/")
    return _PAGE.replace("/*__DATA__*/", data_json)


# --------------------------------------------------------------------------- #
# The page. One template; Python only injects the data JSON at /*__DATA__*/.
# Brand palette matches spec_svg (INK/PANEL/brand cyan->blue).
# --------------------------------------------------------------------------- #
_PAGE = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Az'arch -- component map</title>
<style>
:root{
  --ink:#0d1117; --panel:#161b22; --panel2:#1b222b; --line:#30363d;
  --text:#e6edf3; --dim:#9da7b3; --cyan:#03a5fc; --blue:#0065f9;
  /* rail (layer labels) and detail panel share this width so the panel overlays
     the rail exactly when a component is opened, never covering the boxes. */
  --rail-w:300px;
}
*{box-sizing:border-box}
html,body{margin:0;height:100%}
body{
  background:var(--ink); color:var(--text);
  font-family:Inter,'Segoe UI',Helvetica,Arial,sans-serif; font-size:13px;
  display:flex; flex-direction:column; height:100vh; overflow:hidden;
}
a{color:var(--cyan)}
/* ---- top bar ---- */
header{
  padding:10px 16px; border-bottom:1px solid var(--line);
  display:flex; align-items:center; gap:16px; flex-wrap:wrap; background:var(--panel);
}
.brand{font-size:20px;font-weight:800;
  background:linear-gradient(90deg,var(--cyan),var(--blue));
  -webkit-background-clip:text;background-clip:text;color:transparent;white-space:nowrap}
.sub{color:var(--dim);font-size:12px}
.glance{margin-left:auto;display:flex;gap:6px 14px;flex-wrap:wrap;align-items:center;
  color:var(--dim);font-size:11.5px}
.glance .fact{white-space:nowrap;display:inline-flex;gap:5px;align-items:baseline}
.glance .fact:not(:last-child)::after{content:"·";color:var(--line);margin-left:9px}
.glance b{color:var(--text);font-weight:600}
/* ---- controls ---- */
.controls{padding:8px 16px;border-bottom:1px solid var(--line);
  display:flex;gap:10px;align-items:center;flex-wrap:wrap;background:var(--panel2)}
.controls input[type=search]{
  background:var(--ink);border:1px solid var(--line);color:var(--text);
  border-radius:7px;padding:6px 10px;min-width:220px;font-size:13px}
.controls select{background:var(--ink);border:1px solid var(--line);color:var(--text);
  border-radius:7px;padding:6px 8px;font-size:12px}
.controls label{color:var(--dim);font-size:11.5px;margin-right:2px}
.controls .count{color:var(--dim);font-size:12px;margin-left:auto}
.btn{background:var(--ink);border:1px solid var(--line);color:var(--text);
  border-radius:7px;padding:6px 10px;cursor:pointer;font-size:12px}
.btn:hover{border-color:var(--cyan)}
/* ---- layout ---- */
/* position:relative so the detail panel can overlay the map instead of
   pushing it -- opening a component must NOT resize/reflow the graph. */
.main{flex:1;display:flex;min-height:0;position:relative}
.map{flex:1;overflow:auto;padding:14px 16px 40px}
/* ---- bands ---- */
/* Boxes on the LEFT, the layer-label rail on the RIGHT (flex order:2). The rail
   width matches the detail panel (--rail-w) so, when a component is clicked, the
   panel overlays the rail exactly and never covers the component boxes. */
.band{border:1px solid var(--line);border-radius:12px;background:var(--panel);
  margin-bottom:14px;display:flex;min-height:96px}
.rail{width:var(--rail-w);flex:none;padding:12px 14px;border-left:1px solid var(--line);order:2}
.rail .t{font-size:15px;font-weight:700}
.rail .s{font-size:11px;color:var(--dim);margin-top:3px;line-height:1.3}
.rail .n{margin-top:8px;font-size:12px;font-weight:700;
  background:linear-gradient(90deg,var(--cyan),var(--blue));
  -webkit-background-clip:text;background-clip:text;color:transparent}
.rail .arrow{margin-top:6px;font-size:10px;color:var(--dim)}
.boxes{flex:1;padding:12px;display:flex;flex-wrap:wrap;gap:7px;align-content:flex-start}
/* ---- component box ---- */
.box{position:relative;width:150px;border-radius:7px;padding:7px 9px;cursor:pointer;
  border:1px solid var(--bc,#555);background:color-mix(in srgb,var(--bc,#555) 16%,transparent);
  transition:transform .05s ease, box-shadow .1s ease, opacity .1s ease}
.box:hover{transform:translateY(-1px);box-shadow:0 3px 12px rgba(0,0,0,.5)}
.box .bn{font-weight:600;font-size:12px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.box .bv{font-size:10px;color:var(--dim);margin-top:1px}
.box .mark{position:absolute;top:5px;right:7px;font-size:11px;line-height:1}
.box.selected{outline:2px solid var(--cyan);outline-offset:1px}
.box.req{outline:2px solid #eab308;outline-offset:1px}
.box.reqby{outline:2px solid #22c55e;outline-offset:1px}
.box.dim{opacity:.16}
.box.hidden{display:none}
.band.empty{display:none}
.emptynote{color:var(--dim);font-size:12px;padding:6px 2px}
/* ---- detail panel ---- */
/* Overlays the RIGHT edge of the map (position:absolute), the same width as the
   band rails (--rail-w) so it sits exactly on top of the "Foundation / 71 pkgs"
   labels and never covers the component boxes. It does NOT resize or reflow the
   graph -- the boxes underneath are only dimmed. */
.panel{position:absolute;top:0;right:0;height:100%;width:var(--rail-w);z-index:5;
  border-left:1px solid var(--line);background:var(--panel2);
  box-shadow:-8px 0 24px rgba(0,0,0,.45);
  overflow:auto;padding:0;display:flex;flex-direction:column}
.panel.hidden{display:none}
.panel .ph{padding:14px 16px;border-bottom:1px solid var(--line);position:sticky;top:0;background:var(--panel2)}
.panel .ph .close{float:right;cursor:pointer;color:var(--dim);font-size:18px;line-height:1}
.panel .ph .close:hover{color:var(--text)}
.panel h2{margin:0;font-size:18px;word-break:break-all}
.panel .ver{color:var(--dim);font-size:12px;margin-top:2px}
.panel .body{padding:14px 16px}
.panel .purpose{font-size:14px;line-height:1.5;margin:0 0 12px}
.chips{display:flex;gap:6px;flex-wrap:wrap;margin-bottom:12px}
.chip{font-size:11px;padding:3px 8px;border-radius:999px;border:1px solid var(--line);color:var(--text)}
.chip.cat{}
.chip.ed-az{border-color:var(--cyan);color:var(--cyan)}
.chip.ed-sel{border-color:#9da7b3}
.kv{display:grid;grid-template-columns:auto 1fr;gap:3px 12px;font-size:12px;margin-bottom:12px}
.kv .k{color:var(--dim)}
.azbox{border:1px solid var(--cyan);border-radius:8px;padding:8px 10px;margin-bottom:12px;
  background:color-mix(in srgb,var(--cyan) 10%,transparent);font-size:12.5px;line-height:1.4}
.azbox .h{color:var(--cyan);font-weight:700;font-size:11px;text-transform:uppercase;letter-spacing:.04em;margin-bottom:3px}
.dl{margin:0 0 12px}
.dl .h{font-size:11px;text-transform:uppercase;letter-spacing:.04em;color:var(--dim);margin-bottom:5px;font-weight:700}
.dl .h.req{color:#eab308}
.dl .h.reqby{color:#22c55e}
.pill-wrap{display:flex;flex-wrap:wrap;gap:5px}
.pill{font-size:11px;padding:2px 7px;border-radius:6px;background:var(--ink);border:1px solid var(--line);
  cursor:pointer;white-space:nowrap}
.pill:hover{border-color:var(--cyan);color:var(--cyan)}
.pill.none{opacity:.6;cursor:default;border-style:dashed}
.pill.none:hover{border-color:var(--line);color:var(--dim)}
.opt{font-size:11.5px;color:var(--dim);line-height:1.5}
.opt b{color:var(--text);font-weight:600}
/* ---- collapsible bands ---- */
.rail .t{cursor:pointer;user-select:none}
.rail .t::before{content:"▾ ";color:var(--dim);font-size:12px}
.band.collapsed .rail .t::before{content:"▸ ";}
.band.collapsed .boxes{display:none}
.band.collapsed{min-height:0}
.band.collapsed .rail{border-left:none;width:100%;display:flex;align-items:baseline;gap:14px}
.band.collapsed .rail .s{margin-top:0}
.band.collapsed .rail .n{margin-top:0}
.band.collapsed .rail .arrow{display:none}
/* ---- legend (collapsible footer) ---- */
/* The toggle sits just ABOVE the legend's top border, pinned to the right, so it
   never overlaps the legend's own text (and stays clear of the detail panel,
   which opens on the left). When hidden it drops to the bottom-right corner. */
.legend-toggle{position:fixed;right:14px;bottom:calc(var(--legend-h,150px) + 6px);z-index:6;
  background:var(--ink);border:1px solid var(--line);color:var(--dim);
  border-radius:7px;padding:5px 10px;font-size:11.5px;cursor:pointer}
.legend-toggle.down{bottom:10px}
.legend-toggle:hover{border-color:var(--cyan);color:var(--text)}
.legend{border-top:1px solid var(--line);background:var(--panel);padding:8px 16px;
  display:flex;gap:16px;flex-wrap:wrap;align-items:center;font-size:11.5px;color:var(--dim)}
.legend.hidden{display:none}
.legend .sw{display:inline-block;width:11px;height:11px;border-radius:3px;margin-right:5px;vertical-align:-1px}
.legend .grp{display:flex;gap:12px;flex-wrap:wrap;align-items:center}
.legend .grp.how{flex-basis:100%;color:var(--text)}
.legend .cats{display:flex;gap:10px;flex-wrap:wrap}
kbd{background:var(--ink);border:1px solid var(--line);border-radius:4px;padding:1px 5px;font-size:11px}
</style>
</head>
<body>
<header>
  <span class="brand">Az&#39;arch</span>
  <span class="sub">interactive component map</span>
  <div class="glance" id="glance"></div>
</header>
<div class="controls">
  <input type="search" id="q" placeholder="Search components&hellip;  (press /)" autocomplete="off"/>
  <label>Jump to layer</label><select id="jump" title="Scroll to a layer (press 1-7; 1 = top)"></select>
  <label>Category</label><select id="fcat"></select>
  <label>Edition</label><select id="fed">
    <option value="">all</option>
    <option value="az'arch">Az'arch-modified</option>
    <option value="arch-selected">Explicitly selected</option>
    <option value="arch-dep">Dependency</option>
  </select>
  <label>Sort</label><select id="sort" title="How boxes are ordered within each layer">
    <option value="load">Most load-bearing</option>
    <option value="name">Name (A-Z)</option>
    <option value="size">Installed size</option>
    <option value="deps">Most dependencies</option>
  </select>
  <button class="btn" id="collapse" title="Collapse / expand all layers (press z)">Collapse all</button>
  <button class="btn" id="reset">Reset</button>
  <span class="count" id="count"></span>
</div>
<div class="main">
  <div class="map" id="map"></div>
  <aside class="panel hidden" id="panel"></aside>
</div>
<button class="legend-toggle" id="legendToggle" title="Show / hide the legend (press l)">Hide legend ▾</button>
<div class="legend" id="legend"></div>

<script id="data" type="application/json">/*__DATA__*/</script>
<script>
"use strict";
const DATA = JSON.parse(document.getElementById('data').textContent);
const C = DATA.components, ORDER = DATA.order, CATCOLORS = DATA.catColors;
const EDITION_MARK = {"az'arch":"★","arch-selected":"●","arch-dep":""};
const map = document.getElementById('map');
const panel = document.getElementById('panel');
let selected = null;
let filterCat = "", filterEd = "", query = "";

// ---- glance strip ----
(function(){
  const g = DATA.glance, el = document.getElementById('glance');
  const items = [
    ["Kernel", "linux "+g.kernel],
    ["Init", "systemd "+g.init],
    ["Components", g.closure],
    ["Az'arch / selected / dep", g.azarch+" / "+g.selected+" / "+g.dep],
    ["Deepest chain", g.maxHeight+" hops"],
    ["Installed size", g.size],
  ];
  // Each fact is ONE inline <span> so it never splits across lines: the glance
  // strip is a flex row, and without wrapping each fact the label and its value
  // would become separate flex items and wrap independently.
  el.innerHTML = items.map(([k,v])=>
    `<span class="fact">${esc(k)}: <b>${esc(v)}</b></span>`).join("");
})();

// ---- category filter options ----
(function(){
  const sel = document.getElementById('fcat');
  sel.innerHTML = '<option value="">all</option>' +
    DATA.categories.map(c=>`<option value="${esc(c)}">${esc(c)}</option>`).join("");
})();

// Display layer number: 1 = the TOP layer (leaves), counting down to the bottom.
// Internally layers are 0 (sinks/foundation) .. N-1 (leaves); invert for display.
const NLAYERS = DATA.layers.length;
function dispNum(i){ return NLAYERS - i; }        // internal idx -> shown number
function idxFromDisp(n){ return NLAYERS - n; }    // shown number -> internal idx

// ---- layer jump options (top layer first, matching the on-screen order) ----
(function(){
  const sel = document.getElementById('jump');
  const opts = ['<option value="">go to&hellip;</option>'];
  for(let i=DATA.layers.length-1;i>=0;i--){
    opts.push(`<option value="${i}">${dispNum(i)} &middot; ${esc(DATA.layers[i].title)}</option>`);
  }
  sel.innerHTML = opts.join("");
})();

// ---- legend ----
(function(){
  const el = document.getElementById('legend');
  const cats = DATA.categories.map(c=>
    `<span><span class="sw" style="background:${CATCOLORS[c]}66;border:1px solid ${CATCOLORS[c]}"></span>${esc(c)}</span>`
  ).join("");
  el.innerHTML =
    `<div class="grp how">Foundation / sinks (bottom) &#8594; leaf apps (top) `+
    `&#183; click any component to inspect it</div>`+
    `<div class="grp"><b style="color:var(--text)">Edition:</b>`+
    `<span><span style="color:var(--cyan)">★</span> Az'arch-modified</span>`+
    `<span>● Explicitly selected</span>`+
    `<span style="opacity:.7">(no mark) dependency</span></div>`+
    `<div class="cats">${cats}</div>`+
    `<div class="grp"><span style="color:#eab308">■ requires</span>`+
    `<span style="color:#22c55e">■ required by</span></div>`+
    `<div class="grp" style="margin-left:auto">Keys: `+
    `<kbd>/</kbd> search <kbd>1</kbd>&ndash;<kbd>7</kbd> jump to layer `+
    `<kbd>z</kbd> collapse all <kbd>l</kbd> legend <kbd>Esc</kbd> close</div>`;
})();

function esc(s){return String(s).replace(/[&<>"]/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[m]));}

// within-layer ordering strategies for the Sort control
const SORTS = {
  load: (a,b)=> C[b].transDependents-C[a].transDependents || (a<b?-1:1),
  name: (a,b)=> a<b?-1:(a>b?1:0),
  size: (a,b)=> C[b].isize-C[a].isize || (a<b?-1:1),
  deps: (a,b)=> C[b].requires.length-C[a].requires.length || (a<b?-1:1),
};
let sortMode = "load";

// ---- build the bands + boxes once ----
function buildMap(){
  map.innerHTML = "";
  // group components by layer
  const byLayer = DATA.layers.map(()=>[]);
  for(const name of ORDER){ byLayer[C[name].layer].push(name); }
  for(const arr of byLayer){ arr.sort(SORTS[sortMode]); }
  // draw top layer first (6 -> 0)
  for(let i=DATA.layers.length-1;i>=0;i--){
    const L = DATA.layers[i], names = byLayer[i];
    const band = document.createElement('div'); band.className='band'; band.dataset.layer=i;
    band.id = 'layer-'+i;
    const rail = document.createElement('div'); rail.className='rail';
    rail.innerHTML = `<div class="t" title="click to collapse / expand this layer">${esc(L.title)}</div>`+
      `<div class="s">${esc(L.subtitle)}</div>`+
      `<div class="n" data-n>${names.length} pkgs</div>`+
      (i>0?`<div class="arrow">depends on layer(s) below ↓</div>`:``);
    rail.querySelector('.t').addEventListener('click',()=>band.classList.toggle('collapsed'));
    const boxes = document.createElement('div'); boxes.className='boxes';
    for(const name of names){ boxes.appendChild(makeBox(name)); }
    band.appendChild(rail); band.appendChild(boxes);
    map.appendChild(band);
  }
}

// re-sort boxes in place without losing the current filter/selection state
function resort(){
  const byLayer = DATA.layers.map(()=>[]);
  for(const name of ORDER){ byLayer[C[name].layer].push(name); }
  for(let i=0;i<DATA.layers.length;i++){
    byLayer[i].sort(SORTS[sortMode]);
    const band = document.getElementById('layer-'+i);
    if(!band) continue;
    const boxes = band.querySelector('.boxes');
    for(const name of byLayer[i]){
      const el = boxes.querySelector(`.box[data-name="${cssEsc(name)}"]`);
      if(el) boxes.appendChild(el); // appendChild moves it to the new position
    }
  }
  applyFilters();
  if(selected) highlight(selected);
}

// scroll a given layer into view (used by the Jump control + number keys)
function jumpToLayer(i){
  const band = document.getElementById('layer-'+i);
  if(band){ band.classList.remove('collapsed');
    if(band.scrollIntoView) band.scrollIntoView({behavior:'smooth',block:'start'}); }
}

function makeBox(name){
  const c = C[name];
  const color = CATCOLORS[c.category] || "#8892a0";
  const b = document.createElement('div');
  b.className='box'; b.dataset.name=name; b.style.setProperty('--bc',color);
  const mark = EDITION_MARK[c.edition];
  const markColor = c.edition==="az'arch" ? "var(--cyan)" : "var(--text)";
  b.innerHTML = `<div class="bn">${esc(name)}</div>`+
    `<div class="bv">${esc(c.version.split('-')[0])}</div>`+
    (mark?`<div class="mark" style="color:${markColor}">${mark}</div>`:``);
  b.addEventListener('click',()=>select(name));
  return b;
}

// ---- filtering ----
function matches(name){
  const c = C[name];
  if(filterCat && c.category!==filterCat) return false;
  if(filterEd && c.edition!==filterEd) return false;
  if(query && !name.toLowerCase().includes(query)) return false;
  return true;
}
function applyFilters(){
  let shown=0;
  for(const b of map.querySelectorAll('.box')){
    const ok = matches(b.dataset.name);
    b.classList.toggle('hidden', !ok);
    if(ok) shown++;
  }
  // per-band counts + hide empty bands
  for(const band of map.querySelectorAll('.band')){
    const vis = band.querySelectorAll('.box:not(.hidden)').length;
    band.classList.toggle('empty', vis===0);
    const n = band.querySelector('[data-n]');
    const total = band.querySelectorAll('.box').length;
    n.textContent = (vis===total? `${total} pkgs` : `${vis} / ${total} pkgs`);
  }
  document.getElementById('count').textContent = `${shown} / ${ORDER.length} shown`;
  if(selected) highlight(selected); // keep highlight consistent
}

// ---- selection + dependency highlight ----
// reveal=false (a direct click on a box): keep the map exactly where it is --
// just dim the others and open the side panel. reveal=true (following a pill in
// the panel): scroll the newly-selected box into view since it may be off-screen.
function select(name, reveal){
  selected = name;
  openPanel(name);
  highlight(name);
  if(reveal){
    const el = map.querySelector(`.box[data-name="${cssEsc(name)}"]`);
    if(el && el.scrollIntoView) el.scrollIntoView({block:'nearest',behavior:'smooth'});
  }
}
function cssEsc(s){ return (window.CSS && CSS.escape)? CSS.escape(s) : s.replace(/["\\]/g,'\\$&'); }

function highlight(name){
  const c = C[name];
  const req = new Set(c.requires), reqby = new Set(c.requiredBy);
  for(const b of map.querySelectorAll('.box')){
    const n = b.dataset.name;
    b.classList.remove('selected','req','reqby','dim');
    if(n===name){ b.classList.add('selected'); }
    else if(req.has(n)){ b.classList.add('req'); }
    else if(reqby.has(n)){ b.classList.add('reqby'); }
    else { b.classList.add('dim'); }
  }
}
function clearHighlight(){
  selected=null;
  for(const b of map.querySelectorAll('.box'))
    b.classList.remove('selected','req','reqby','dim');
}

// ---- detail panel ----
function openPanel(name){
  const c = C[name];
  const edClass = c.edition==="az'arch"?"ed-az":(c.edition==="arch-selected"?"ed-sel":"");
  const layer = DATA.layers[c.layer];
  const reqPills = pills(c.requires, "req");
  const reqbyPills = pills(c.requiredBy, "reqby");
  const opt = c.optdepends.length? `<div class="dl"><div class="h">Optional dependencies (${c.optdepends.length})</div>`+
      `<div class="opt">`+c.optdepends.map(o=>{
        const i=o.indexOf(':'); return i>0? `<div><b>${esc(o.slice(0,i))}</b>${esc(o.slice(i))}</div>`:`<div>${esc(o)}</div>`;
      }).join("")+`</div></div>` : "";
  panel.classList.remove('hidden');
  panel.innerHTML =
    `<div class="ph"><span class="close" title="close (Esc)">×</span>`+
      `<h2>${esc(name)}</h2><div class="ver">${esc(c.version)} &#183; ${esc(c.repo)} &#183; ${esc(c.size)}</div></div>`+
    `<div class="body">`+
      `<p class="purpose">${esc(c.desc)}</p>`+
      `<div class="chips">`+
        `<span class="chip cat" style="border-color:${CATCOLORS[c.category]};color:${CATCOLORS[c.category]}">${esc(c.category)}</span>`+
        `<span class="chip ${edClass}">${EDITION_MARK[c.edition]||''} ${esc(c.editionLabel)}</span>`+
        `<span class="chip">Layer ${dispNum(c.layer)}: ${esc(layer.title)}</span>`+
        (c.removed?`<span class="chip" style="border-color:#f85149;color:#f85149">removed from ISO</span>`:``)+
      `</div>`+
      (c.azarch? `<div class="azbox"><div class="h">What Az'arch changes</div>${esc(c.azarch)}</div>`:``)+
      `<div class="kv">`+
        `<span class="k">Upstream</span><span>${c.url?`<a href="${esc(c.url)}" target="_blank" rel="noopener">${esc(c.url)}</a>`:'&mdash;'}</span>`+
        `<span class="k">License</span><span>${esc(c.license||'—')}</span>`+
        `<span class="k">Pulls in below</span><span>${c.transDeps} packages (transitively)</span>`+
        `<span class="k">Relied on by above</span><span>${c.transDependents} packages (transitively)</span>`+
      `</div>`+
      `<div class="dl"><div class="h req">Requires ↓ (${c.requires.length}) &mdash; direct dependencies</div>${reqPills}</div>`+
      `<div class="dl"><div class="h reqby">Required by ↑ (${c.requiredBy.length}) &mdash; things that need it</div>${reqbyPills}</div>`+
      opt+
    `</div>`;
  panel.querySelector('.close').addEventListener('click',closePanel);
  for(const p of panel.querySelectorAll('.pill[data-go]'))
    p.addEventListener('click',()=>select(p.dataset.go, true));
}
function pills(names, kind){
  if(!names.length) return `<div class="pill-wrap"><span class="pill none">none &mdash; ${kind==='req'?'a base / sink package':'a top / leaf package'}</span></div>`;
  return `<div class="pill-wrap">`+names.map(n=>`<span class="pill" data-go="${esc(n)}">${esc(n)}</span>`).join("")+`</div>`;
}
function closePanel(){ panel.classList.add('hidden'); panel.innerHTML=""; clearHighlight(); }

// ---- controls wiring ----
const q = document.getElementById('q');
const jumpSel = document.getElementById('jump');
const sortSel = document.getElementById('sort');
const collapseBtn = document.getElementById('collapse');
const legendEl = document.getElementById('legend');
const legendBtn = document.getElementById('legendToggle');
let allCollapsed = false;

q.addEventListener('input',()=>{ query=q.value.trim().toLowerCase(); applyFilters(); });
document.getElementById('fcat').addEventListener('change',e=>{ filterCat=e.target.value; applyFilters(); });
document.getElementById('fed').addEventListener('change',e=>{ filterEd=e.target.value; applyFilters(); });
jumpSel.addEventListener('change',e=>{ if(e.target.value!=="") jumpToLayer(+e.target.value); e.target.value=""; });
sortSel.addEventListener('change',e=>{ sortMode=e.target.value; resort(); });

function setCollapsed(state){
  allCollapsed = state;
  for(const band of map.querySelectorAll('.band')) band.classList.toggle('collapsed', state);
  collapseBtn.textContent = state ? 'Expand all' : 'Collapse all';
}
collapseBtn.addEventListener('click',()=>setCollapsed(!allCollapsed));

function setLegend(show){
  legendEl.classList.toggle('hidden', !show);
  legendBtn.textContent = show ? 'Hide legend ▾' : 'Show legend ▴';
  // Park the button ABOVE the legend when it's shown (so it never covers the
  // legend text), or drop it to the bottom-right corner when the legend is hidden.
  legendBtn.classList.toggle('down', !show);
  if(show){
    // pin the button just above the actual rendered legend height
    document.documentElement.style.setProperty('--legend-h', legendEl.offsetHeight + 'px');
  }
}
legendBtn.addEventListener('click',()=>setLegend(legendEl.classList.contains('hidden')));

document.getElementById('reset').addEventListener('click',()=>{
  filterCat=filterEd=query=""; q.value="";
  document.getElementById('fcat').value=""; document.getElementById('fed').value="";
  sortMode="load"; sortSel.value="load"; resort();
  setCollapsed(false);
  applyFilters(); closePanel();
});

document.addEventListener('keydown',e=>{
  const typing = document.activeElement===q;
  if(e.key==='/' && !typing){ e.preventDefault(); q.focus(); }
  else if(e.key==='Escape'){ if(!panel.classList.contains('hidden')) closePanel(); else if(typing){ q.blur(); } }
  else if(typing){ /* let the search field keep other keys */ }
  else if(e.key>='1' && e.key<=String(NLAYERS)){ jumpToLayer(idxFromDisp(+e.key)); }
  else if(e.key==='z'){ setCollapsed(!allCollapsed); }
  else if(e.key==='l'){ setLegend(legendEl.classList.contains('hidden')); }
});

buildMap();
applyFilters();
setLegend(true);            // position the legend toggle above the legend on load
window.addEventListener('resize',()=>{ if(!legendEl.classList.contains('hidden')) setLegend(true); });
</script>
</body>
</html>
"""
