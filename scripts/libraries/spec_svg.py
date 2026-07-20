"""
spec_svg -- render the Az'arch dependency graph as a single self-contained SVG.

The SVG is the navigable, at-a-glance view the Markdown tables cannot be: seven
horizontal layers stacked from the kernel at the bottom to the leaf applications
at the top. Each layer is a labelled band; inside it sit the most load-bearing
packages of that layer as boxes, coloured by their human-language category and
marked with their edition (stock-Arch dep, Arch package Az'arch selected, or a
package Az'arch itself modifies).

No external tooling (no Graphviz, no rsvg): we emit plain SVG text, so it renders
in any browser/IDE and diffs in git. The full 1300-package detail lives in the
Markdown appendix; here we deliberately draw a readable subset per layer plus the
per-layer counts, so the shape of the distribution is legible instead of a wall
of 1300 boxes.

Layer assignment is by real dependency depth (longest chain down to a sink), not
by category -- so a package's height in the image is its true position in the
dependency stack. Category only drives colour.
"""

import html

import spec_classify as K

# Az'arch brand gradient (sampled from the fastfetch logo asset): cyan -> blue.
BRAND_CYAN = "#03a5fc"
BRAND_BLUE = "#0065f9"
INK = "#0d1117"
PANEL = "#161b22"
PANEL_LINE = "#30363d"
TEXT = "#e6edf3"
TEXT_DIM = "#9da7b3"

# The seven layers, bottom (0) to top (6). (id -> (title, subtitle)).
LAYER_DEFS = [
    ("Kernel & firmware", "the floor: linux + microcode + firmware"),
    ("Base / sinks", "depend on nothing else in the set"),
    ("Core libraries", "libc, compression, crypto primitives"),
    ("System libraries & services", "dbus, systemd, X/Wayland, mesa, networking"),
    ("Frameworks & toolkits", "Qt6, KDE Frameworks, GTK, language runtimes"),
    ("Desktop & session", "Plasma shell, compositor, session services"),
    ("Applications", "top / leaves -- nothing depends on these"),
]

# Edition marker glyphs drawn on each box corner.
EDITION_MARK = {
    "az'arch":       ("★", BRAND_CYAN),   # Az'arch modifies this package
    "arch-selected": ("●", "#e6edf3"),    # explicitly chosen into the manifest
    "arch-dep":      ("",  None),          # pulled in as a dependency
}


def layer_of(pkg, category, height):
    """Map a package to one of the 7 layers by category(kernel) + dependency height."""
    if category == "Kernel & firmware":
        return 0
    if height == 0:
        return 1
    if height <= 4:
        return 2
    if height <= 12:
        return 3
    if height <= 22:
        return 4
    if height <= 33:
        return 5
    return 6


def _esc(s):
    return html.escape(str(s), quote=True)


def _representatives(pkgs, layer_idx, tiers, per_layer):
    """Pick which packages to actually draw in a layer.

    Top layer (apps): show the leaves themselves, by how much they pull in.
    Every other layer: show the most load-bearing (highest transitive dependents),
    because those are the packages the rest of the layer above rests on.
    """
    trans_dep = tiers["trans_dependents"]
    trans_deps = tiers["trans_deps"]
    indeg = tiers["indeg"]
    if layer_idx == 6:
        leaves = [p for p in pkgs if indeg.get(p, 0) == 0] or pkgs
        return sorted(leaves, key=lambda p: (-trans_deps[p], p))[:per_layer]
    return sorted(pkgs, key=lambda p: (-trans_dep[p], p))[:per_layer]


def render_svg(packages, resolved, tiers, tags, glance):
    """Return the SVG document text.

    packages : name -> record
    resolved : closure/roots/edges (from spec_resolve)
    tiers    : graph metrics (from spec_resolve.compute_tiers)
    tags     : name -> {edition, category, ...} (from spec_classify.classify)
    glance   : dict of at-a-glance facts (kernel, ram, closure size, ...)
    """
    closure = resolved["closure"]
    heights = tiers["heights"]

    # bucket packages into layers
    layers = [[] for _ in LAYER_DEFS]
    for p in closure:
        layers[layer_of(p, tags[p]["category"], heights[p])].append(p)

    # categories actually present, for the legend, in canonical order
    present_cats = [c for c in K.CATEGORY_ORDER
                    if any(tags[p]["category"] == c for p in closure)]

    # ---- geometry -------------------------------------------------------- #
    W = 1600
    margin = 32
    header_h = 210
    legend_h = 150
    band_gap = 14
    band_h = 150
    inner_w = W - 2 * margin
    per_layer = 22            # boxes drawn per band
    box_w, box_h, box_gap = 128, 40, 8
    cols = max(1, (inner_w - 220) // (box_w + box_gap))

    total_h = header_h + len(LAYER_DEFS) * (band_h + band_gap) + legend_h + margin
    H = total_h

    s = []
    a = s.append
    a(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
      f'viewBox="0 0 {W} {H}" font-family="Inter, Segoe UI, Helvetica, Arial, sans-serif">')

    # defs: brand gradient
    a('<defs>')
    a(f'<linearGradient id="brand" x1="0" y1="0" x2="1" y2="0">'
      f'<stop offset="0" stop-color="{BRAND_CYAN}"/>'
      f'<stop offset="1" stop-color="{BRAND_BLUE}"/></linearGradient>')
    a('</defs>')

    a(f'<rect width="{W}" height="{H}" fill="{INK}"/>')

    # ---- header / at-a-glance ------------------------------------------- #
    a(f'<text x="{margin}" y="52" font-size="34" font-weight="700" '
      f'fill="url(#brand)">Az&#39;arch</text>')
    a(f'<text x="{margin+168}" y="52" font-size="26" font-weight="600" '
      f'fill="{TEXT}">Distribution dependency graph</text>')
    a(f'<text x="{margin}" y="78" font-size="13" fill="{TEXT_DIM}">'
      f'base (kernel, bottom) to top (leaf applications) &#183; layer = real '
      f'dependency depth &#183; colour = category &#183; mark = edition</text>')

    facts = [
        ("Base", glance["base"]),
        ("Desktop", glance["desktop"]),
        ("Kernel", f'linux {glance["kernel"]}'),
        ("Init", f'systemd {glance["init"]}'),
        ("ISO version scheme", glance["iso_version"]),
        ("Live-session RAM (cow_spacesize)", glance["ram"]),
        ("Packages (full closure)", str(glance["closure"])),
        ("Explicitly selected / Az'arch-modified", f'{glance["selected"]} / {glance["azarch"]}'),
        ("Deepest chain (leaf -> base)", f'{glance["max_height"]} hops'),
        ("Installed size", glance["size"]),
    ]
    fx = margin
    fy = 108
    col_w = (inner_w) // 2
    for i, (k, v) in enumerate(facts):
        cx = fx + (i % 2) * col_w
        cy = fy + (i // 2) * 20
        a(f'<text x="{cx}" y="{cy}" font-size="13" fill="{TEXT_DIM}">{_esc(k)}:</text>')
        a(f'<text x="{cx+260}" y="{cy}" font-size="13" font-weight="600" '
          f'fill="{TEXT}">{_esc(v)}</text>')

    # ---- layer bands (top layer drawn first = at the top of the image) --- #
    y = header_h
    for idx in reversed(range(len(LAYER_DEFS))):
        title, subtitle = LAYER_DEFS[idx]
        band_pkgs = layers[idx]
        # band background
        a(f'<rect x="{margin}" y="{y}" width="{inner_w}" height="{band_h}" '
          f'rx="10" fill="{PANEL}" stroke="{PANEL_LINE}"/>')
        # layer index chip + title on the left rail
        a(f'<text x="{margin+16}" y="{y+34}" font-size="18" font-weight="700" '
          f'fill="{TEXT}">{_esc(title)}</text>')
        a(f'<text x="{margin+16}" y="{y+54}" font-size="11" fill="{TEXT_DIM}">'
          f'{_esc(subtitle)}</text>')
        a(f'<text x="{margin+16}" y="{y+86}" font-size="13" font-weight="700" '
          f'fill="url(#brand)">{len(band_pkgs)} pkgs</text>')
        # arrow hint (deps flow downward)
        if idx > 0:
            a(f'<text x="{margin+16}" y="{y+band_h-14}" font-size="10" '
              f'fill="{TEXT_DIM}">depends on layer(s) below ↓</text>')

        # boxes
        reps = _representatives(band_pkgs, idx, tiers, per_layer)
        bx0 = margin + 200
        by0 = y + 16
        for i, p in enumerate(reps):
            r = i // cols
            c = i % cols
            bx = bx0 + c * (box_w + box_gap)
            by = by0 + r * (box_h + box_gap)
            if by + box_h > y + band_h - 6:
                break
            cat = tags[p]["category"]
            fill = K.CATEGORY_COLORS.get(cat, "#555")
            a(f'<rect x="{bx}" y="{by}" width="{box_w}" height="{box_h}" rx="6" '
              f'fill="{fill}" fill-opacity="0.22" stroke="{fill}" stroke-width="1.4"/>')
            name = p if len(p) <= 17 else p[:16] + "…"
            a(f'<text x="{bx+8}" y="{by+17}" font-size="11.5" font-weight="600" '
              f'fill="{TEXT}">{_esc(name)}</text>')
            ver = packages[p]["version"].split("-")[0]
            ver = ver if len(ver) <= 14 else ver[:13] + "…"
            a(f'<text x="{bx+8}" y="{by+31}" font-size="9" fill="{TEXT_DIM}">'
              f'{_esc(ver)}</text>')
            glyph, gcol = EDITION_MARK[tags[p]["edition"]]
            if glyph:
                a(f'<text x="{bx+box_w-13}" y="{by+15}" font-size="11" '
                  f'fill="{gcol}">{glyph}</text>')
        # "+N more" hint if the band has more than we drew
        drawn = min(len(reps), (cols * ((band_h - 22) // (box_h + box_gap))))
        if len(band_pkgs) > drawn:
            a(f'<text x="{W-margin-12}" y="{y+band_h-12}" font-size="11" '
              f'text-anchor="end" fill="{TEXT_DIM}">+{len(band_pkgs)-drawn} more '
              f'in this layer</text>')
        y += band_h + band_gap

    # ---- legend ---------------------------------------------------------- #
    ly = y + 4
    a(f'<text x="{margin}" y="{ly+4}" font-size="14" font-weight="700" '
      f'fill="{TEXT}">Category</text>')
    lx = margin
    lyy = ly + 24
    per_row = 6
    cw = inner_w // per_row
    for i, cat in enumerate(present_cats):
        col = i % per_row
        row = i // per_row
        px = margin + col * cw
        py = lyy + row * 22
        color = K.CATEGORY_COLORS.get(cat, "#555")
        a(f'<rect x="{px}" y="{py-11}" width="12" height="12" rx="3" '
          f'fill="{color}" fill-opacity="0.35" stroke="{color}"/>')
        a(f'<text x="{px+18}" y="{py}" font-size="11" fill="{TEXT}">{_esc(cat)}</text>')

    # edition legend on the far right of the first legend row
    ex = margin
    ey = lyy + ((len(present_cats) + per_row - 1) // per_row) * 22 + 10
    a(f'<text x="{ex}" y="{ey+4}" font-size="14" font-weight="700" '
      f'fill="{TEXT}">Edition</text>')
    items = [
        (f'{EDITION_MARK["az\'arch"][0]} az’arch',
         "package Az’arch modifies (config / branding / theme / removed)", BRAND_CYAN),
        (f'{EDITION_MARK["arch-selected"][0]} arch-selected',
         "stock Arch, explicitly listed in the Az’arch manifest", TEXT),
        ("arch-dep",
         "stock Arch, pulled in only as a transitive dependency", TEXT_DIM),
    ]
    exx = margin + 90
    for label, desc, col in items:
        a(f'<text x="{exx}" y="{ey+4}" font-size="11.5" font-weight="700" '
          f'fill="{col}">{_esc(label)}</text>')
        a(f'<text x="{exx+120}" y="{ey+4}" font-size="11" fill="{TEXT_DIM}">'
          f'{_esc(desc)}</text>')
        ey += 20

    a('</svg>')
    return "\n".join(s) + "\n"
