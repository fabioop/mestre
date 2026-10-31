# Regenerates components/*/preview.html, preview/tokens.css and preview/*-{light,dark}.html
# from tokens.json and the row/icon helpers below. Run: python3 scripts/gen-previews.py design
import os, sys, json, re
D = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = 'stroke="currentColor" stroke-width="1.8" fill="none" stroke-linecap="round" stroke-linejoin="round"'
ICON = {
 'search': f'<svg viewBox="0 0 20 20" {S}><circle cx="8.5" cy="8.5" r="5.5"/><path d="M13 13l4.5 4.5"/></svg>',
 'calc': f'<svg viewBox="0 0 16 16" {S}><path d="M3 5h5M5.5 2.5v5M9 13l5-10M8 11.5h5"/></svg>',
 'cup': f'<svg viewBox="0 0 16 16" {S}><path d="M3 5h8v4a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3zM11 6h1.5a1.5 1.5 0 0 1 0 3H11M2 14h11"/></svg>',
 'moon': f'<svg viewBox="0 0 16 16" {S}><path d="M9 2a6 6 0 1 0 5 8.5A5 5 0 0 1 9 2z"/></svg>',
 'folder': f'<svg viewBox="0 0 16 16" {S}><path d="M2 4.5A1.5 1.5 0 0 1 3.5 3H6l1.5 1.5h5A1.5 1.5 0 0 1 14 6v6a1.5 1.5 0 0 1-1.5 1.5h-9A1.5 1.5 0 0 1 2 12z"/></svg>',
 'arrow': f'<svg viewBox="0 0 16 16" {S}><circle cx="8" cy="8" r="6"/><path d="M6 8h4M8.5 6l2 2-2 2"/></svg>',
 'dashed': f'<svg viewBox="0 0 16 16" {S} stroke-dasharray="2.5 2.5"><circle cx="8" cy="8" r="6"/></svg>',
 'link': f'<svg viewBox="0 0 16 16" {S}><path d="M7 9a3 3 0 0 0 4 0l2-2a3 3 0 0 0-4-4L8 4M9 7a3 3 0 0 0-4 0L3 9a3 3 0 0 0 4 4l1-1"/></svg>',
 'globe': f'<svg viewBox="0 0 16 16" {S}><circle cx="8" cy="8" r="6"/><path d="M2 8h12M8 2c2 2 2 10 0 12M8 2c-2 2-2 10 0 12"/></svg>',
 'play': f'<svg viewBox="0 0 16 16" {S}><path d="M5 3l8 5-8 5z"/></svg>',
 'finder': f'<svg viewBox="0 0 16 16" {S}><rect x="2" y="2" width="12" height="12" rx="3"/><path d="M8 2v12M5 6v1M11 6v1M5 10c1 1.5 5 1.5 6 0"/></svg>',
 'eye': f'<svg viewBox="0 0 16 16" {S}><path d="M1.5 8s2.5-4.5 6.5-4.5S14.5 8 14.5 8 12 12.5 8 12.5 1.5 8 1.5 8z"/><circle cx="8" cy="8" r="2"/></svg>',
 'copy': f'<svg viewBox="0 0 16 16" {S}><rect x="5" y="5" width="8" height="8" rx="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5"/></svg>',
 'x': f'<svg viewBox="0 0 16 16" {S}><circle cx="8" cy="8" r="6"/><path d="M6 6l4 4M10 6l-4 4"/></svg>',
 'gear': f'<svg viewBox="0 0 16 16" {S}><circle cx="8" cy="8" r="2.2"/><path d="M8 1.8v2M8 12.2v2M1.8 8h2M12.2 8h2M3.6 3.6l1.4 1.4M11 11l1.4 1.4M3.6 12.4L5 11M11 5l1.4-1.4"/></svg>',
 'clip': f'<svg viewBox="0 0 16 16" {S}><rect x="3.5" y="3" width="9" height="11" rx="1.5"/><path d="M6 3V2h4v1M6 7h4M6 10h3"/></svg>',
 'emoji': f'<svg viewBox="0 0 16 16" {S}><circle cx="8" cy="8" r="6"/><path d="M5.5 9.5c1 1.5 4 1.5 5 0M6 6.5h.01M10 6.5h.01"/></svg>',
 'file': f'<svg viewBox="0 0 16 16" {S}><path d="M4 2h5l3 3v9H4z"/><path d="M9 2v3h3"/></svg>',
 'lock': f'<svg viewBox="0 0 16 16" {S}><rect x="3.5" y="7" width="9" height="7" rx="1.5"/><path d="M5.5 7V5a2.5 2.5 0 0 1 5 0v2"/></svg>',
 'half': f'<svg viewBox="0 0 16 16" {S}><rect x="2" y="3" width="12" height="10" rx="2"/><path d="M2 8h12" opacity="0"/><rect x="2" y="3" width="6" height="10" rx="2" fill="currentColor" stroke="none"/></svg>',
}
def appicon(c1, c2, letter):
    return (f'<div class="icon app"><svg viewBox="0 0 32 32"><defs><linearGradient id="g{letter}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{c1}"/><stop offset="1" stop-color="{c2}"/></linearGradient></defs>'
            f'<rect width="32" height="32" rx="7" fill="url(#g{letter})"/><text x="16" y="21.5" text-anchor="middle" font-family="-apple-system, sans-serif" font-size="15" font-weight="700" fill="#ffffff">{letter}</text></svg></div>')
def tile(name, sel=False):
    return f'<div class="icon tile{" selected" if sel else ""}">{ICON[name]}</div>'
def cap(k): return f'<span class="cap key-cap">{k}</span>'
def hint(label, k): return f'<span class="hint"><span class="footer">{label}</span>{cap(k)}</span>'
def row(icon, title, sub=None, sel=False, running=False, kind=None, hints=None, meta=False):
    if meta and not sel: sub=None
    t = f'<div class="title row-title">{title}{"<span class=\"dot\" title=\"Running\"></span>" if running else ""}</div>'
    s = f'<div class="subtitle">{sub}</div>' if sub else ''
    tr = f'<div class="trailing"><span class="kind">{kind}</span></div>' if kind else ''
    return f'<div class="row{" selected" if sel else ""}">{icon}<div class="main">{t}{s}</div>{tr}</div>'
def footer(context=None, hints=None):
    h = ''.join(hint(l,k) for l,k in (hints or []))
    return f'<div class="divider"></div><div class="footer footer"><span class="context">{ICON["search"]}<span>{context or "Mestre"}</span></span><span class="spacer"></span>{h}</div>'
def section(t): return f'<div class="section section">{t}</div>'
def query(text=None, placeholder='Search apps, or pick a feature below…'):
    inner = f'<div class="text query placeholder">{placeholder}</div>' if text is None else f'<div class="text query">{text}<span class="caret"></span></div>'
    return f'<div class="query-row"><div class="glyph">{ICON["search"]}</div>{inner}</div>'
def doc(marker, body, title, extra_css=''):
    extra_css = '.footer .context svg{width:12px;height:12px}' + extra_css
    return (f'<!-- @dsCard {marker} -->\n<!doctype html>\n<html lang="en">\n<head><meta charset="utf-8"><title>{title} — Mestre</title>'
            f'<style>{extra_css}</style></head>\n<body>\n<div class="ground">\n{body}\n</div>\n</body>\n</html>\n')
def write(comp, marker, body, extra_css=''):
    os.makedirs(f'{D}/components/{comp}', exist_ok=True)
    open(f'{D}/components/{comp}/preview.html','w').write(doc(marker, body, comp, extra_css))

SAFARI = appicon('#2fb3ff','#0a5cd6','S')
STP = appicon('#7a5cff','#2a1b8f','S')
FINDER = appicon('#5ac8fa','#1c6dd0','F')

# Panel
write('Panel', 'group="Panel" height=340', f'''
<div class="panel">
 {query('saf')}
 <div class="divider"></div>
 <div class="list">
  {row(SAFARI,'Safari','alias ff · /Applications',sel=True,running=True,kind='App')}
  {row(STP,'Safari Technology Preview','/Applications',kind='App',meta=True)}
  {row(tile('globe'),'Open saf','Address',kind='Web',meta=True)}
  {row(tile('search'),'Search the web for “saf”','https://duckduckgo.com/?q=saf',kind='Web',meta=True)}
 </div>
 {footer(None,[('Switch','↩'),('Actions','⌘K')])}
</div>''')

# QueryField
write('QueryField', 'group="Panel" height=170', f'''
<div class="panel inline">{query()}</div>
<div class="panel inline">{query('2^10 + 7')}</div>''')

# ResultRow
write('ResultRow', 'group="Results" height=230', f'''
<div class="panel inline"><div class="list">
 {row(SAFARI,'Safari','/Applications',kind='App',meta=True)}
 {row(SAFARI,'Safari','alias ff · /Applications',sel=True,running=True,kind='App')}
 {row(tile('calc'),'1031','2^10 + 7',kind='Calculator')}
 {row(FINDER,'Projects/','~/Documents',kind='File',meta=True)}
</div></div>''')

# IconTile
write('IconTile', 'group="Results" height=90', f'''
<div class="swatch-row">{tile('cup')}{tile('cup',True)}{tile('dashed')}{SAFARI}<div class="icon" style="background:#ff8800;border-radius:var(--radius-action);box-shadow:inset 0 0 0 1px var(--hairline)"></div></div>
<div class="note">unselected · selected · fallback circle.dashed · app icon as-is · colour swatch (radius-action, inset 2)</div>''')

# SectionHeader
write('SectionHeader', 'group="Results" height=120', f'''
<div class="panel inline"><div class="list">{section('Recent')}{row(SAFARI,'Safari','/Applications',kind='App',meta=True)}{section('Features')}</div></div>''')

# KindBadge
write('KindBadge', 'group="Results" height=60', '''
<div class="swatch-row" style="gap:20px"><span class="kind kind">App</span><span class="kind kind">File</span><span class="kind kind">Calculator</span><span class="kind kind">Command</span><span class="kind kind">Clipboard</span><span class="kind kind">Snippet</span><span class="kind kind">Window</span><span class="kind kind">Web</span></div>''')

# KeyHint
write('KeyHint', 'group="Keys" height=90', f'''
<div class="swatch-row" style="gap:20px">{hint('Open','↩')}{hint('Actions','⌘K')}{hint('Show in Finder','⌘↩')}{hint('Copy Path','⌘⇧C')}{hint('Close','esc')}</div>
<div class="swatch-row">{cap('⌃')}{cap('⌥')}{cap('⇧')}{cap('⌘')}{cap('↑')}{cap('↓')}{cap('⇥')}{cap('⌫')}{cap('Space')}{cap('F12')}</div>''')

# ActionsMenu
write('ActionsMenu', 'group="Panel" height=380', f'''
<div class="panel">
 {query('saf')}
 <div class="divider"></div>
 <div class="list">{row(SAFARI,'Safari','/Applications',sel=True,running=True,kind='App')}</div>
 <div class="divider"></div>
 <div class="actions">
  {section('Actions')}
  <div class="action selected"><span class="sym">{ICON['arrow']}</span><span class="label action">Switch</span>{cap('↩')}</div>
  <div class="action"><span class="sym">{ICON['x']}</span><span class="label action">Quit</span>{cap('⌘Q')}</div>
  <div class="action"><span class="sym">{ICON['eye']}</span><span class="label action">Hide</span>{cap('⌘H')}</div>
  <div class="action"><span class="sym">{ICON['finder']}</span><span class="label action">Show in Finder</span>{cap('⌘↩')}</div>
  <div class="action"><span class="sym">{ICON['copy']}</span><span class="label action">Copy Path</span>{cap('⌘⇧C')}</div>
 </div>
 {footer(None,[('Switch','↩'),('Actions','⌘K')])}
</div>''')

# EmptyState
write('EmptyState', 'group="Panel" height=260', f'''
<div class="panel inline">{query('xqz')}<div class="divider"></div><div class="empty action">No apps match “xqz”</div></div>
<div class="panel inline">{query('awake 4')}<div class="divider"></div><div class="empty action">Keep awake: 45m, 2h, until 18:30, off</div></div>''')

# HomeScreen
write('HomeScreen', 'group="Panel" height=480', f'''
<div class="panel">
 {query()}
 <div class="divider"></div>
 <div class="list">
  {section('Recent')}
  {row(SAFARI,'Safari','/Applications',sel=True,running=True,kind='App')}
  {row(FINDER,'Finder','/System/Library/CoreServices',kind='App',meta=True)}
  {section('Features')}
  {row(tile('calc'),'Calculator','Type 2^10, sqrt(2), 15 % 4, pi*2. Return copies',kind='Feature')}
  {row(tile('cup'),'Keep Awake','Until stopped, for a while, or until a time',kind='Feature')}
  {row(tile('clip'),'Clipboard History','clip',kind='Feature')}
  {section('Commands')}
  {row(tile('moon'),'Sleep',None,kind='Command')}
  {row(tile('lock'),'Lock Screen',None,kind='Command')}
 </div>
 {footer(None,[('Switch','↩'),('Actions','⌘K')])}
</div>''')

# Footer
write('Footer', 'group="Panel" height=150', f'''
<div class="panel inline">{footer(None,[('Open','↩'),('Actions','⌘K')])}</div>
<div class="panel inline">{footer('Clipboard History',[('Paste','↩'),('Actions','⌘K')])}</div>
<div class="panel inline">{footer('Calculator',[('Copy Result','↩')])}</div>''')

# MenuBarMenu
write('MenuBarMenu', 'group="Windows" height=230', f'''
<div class="menu action">
 <div class="item"><span>Open Mestre</span><span class="key">⌥Space</span></div>
 <div class="item"><span>Rebuild App Index</span><span class="key">R</span></div>
 <div class="sep"></div>
 <div class="item selected"><span>Settings…</span><span class="key">,</span></div>
 <div class="item"><span>Edit Config File</span></div>
 <div class="item"><span>Welcome Guide</span></div>
 <div class="sep"></div>
 <div class="item"><span>Quit Mestre</span><span class="key">Q</span></div>
</div>''')

# HotKeyRecorder
write('HotKeyRecorder', 'group="Settings" height=90', f'''
<div class="swatch-row" style="gap:20px"><div class="recorder action">⌥Space</div><div class="recorder recording action">Type shortcut…</div></div>''')

# SettingsRow
write('SettingsRow', 'group="Settings" height=230', f'''
<div class="window" style="width:420px;padding:12px 16px">
 <div class="form-row action"><span>Width</span><span class="swatch-row" style="gap:6px"><input class="field number field-mono" value="680"><span class="caption callout">pt</span></span></div>
 <div class="form-row action"><span>Rows before scrolling</span><span class="swatch-row" style="gap:6px"><input class="field number field-mono" value="8"><span class="caption callout">rows</span></span></div>
 <div class="form-row action"><span>Accent colour</span><input class="field field-mono" style="width:220px" placeholder="system" value="#ff8800"></div>
 <div class="form-row action" style="flex-direction:column;align-items:flex-start;gap:4px;border-top:0;padding-top:0"><span class="caption error callout">Not a colour; using the system accent.</span><span class="caption callout">Every field writes straight to ~/.config/mestre/config.json.</span></div>
</div>''')

# Welcome
write('Welcome', 'group="Windows" height=330', f'''
<div class="window" style="width:460px;padding:var(--space-7);display:flex;flex-direction:column;gap:var(--space-5);align-items:center;text-align:center">
 <svg width="64" height="64" viewBox="0 0 100 100"><defs><linearGradient id="gm" x1="0" y1="1" x2="0.5" y2="0"><stop offset="0" stop-color="var(--mark-indigo)"/><stop offset="1" stop-color="var(--mark-violet)"/></linearGradient></defs><rect x="10" y="10" width="80" height="80" rx="18" fill="url(#gm)"/><path d="M30.8 66V34l19.2 20.6L69.2 34v32" fill="none" stroke="var(--on-mark)" stroke-width="7.5" stroke-linecap="round" stroke-linejoin="round"/><path d="M74 70v8M70 74h8" stroke="var(--mark-spark)" stroke-width="3" stroke-linecap="round"/></svg>
 <div><div class="window-title">Welcome to Mestre</div><div class="caption action" style="margin-top:6px">A launcher that lives in your menu bar.</div></div>
 <div class="swatch-row" style="gap:10px"><span class="hotkey-display" style="padding:6px 14px;background:var(--ink-quaternary);border-radius:var(--radius-tile)">⌥ Space</span><span class="action">opens Mestre from any app. Esc closes it.</span></div>
 <div class="swatch-row" style="gap:12px"><span class="field action" style="border-color:var(--hairline)">Settings…</span><span class="caption callout">~/.config/mestre/config.json</span><span class="action" style="background:var(--accent);color:#fff;padding:3px 14px;border-radius:var(--radius-field)">Get Started</span></div>
</div>''')
print('previews written')

# ---- compile tokens.css and the standalone preview pages
t=json.load(open(f'{D}/tokens.json'))
themes=[x['id'] for x in t['color']['themes']]
def esc(n): return n.replace('.','\\.')
def val(tok,th):
    v=tok['value']; v = v if isinstance(v,str) else v.get(th, v[themes[0]])
    m=re.fullmatch(r'\{(.+)\}',v); return f'var(--{esc(m.group(1))})' if m else v
css=['/* Mestre — compiled from ../tokens.json; regenerate with scripts/gen-previews.py after editing tokens */']
for th in themes:
    sel = f':root, [data-theme="{th}"]' if th==themes[0] else f'[data-theme="{th}"]'
    lines=[f'--{esc(x["name"])}: {val(x,th)};' for x in t['color']['tokens']]+[f'--{esc(x["name"])}: {val(x,th)};' for x in t.get('shadow',{}).get('tokens',[])]
    css.append(sel+' {\n  '+'\n  '.join(lines)+'\n}')
root=[]
for fam in ('spacing','radius','size'): root+=[f'--{esc(x["name"])}: {x["value"]};' for x in t[fam]['tokens']]
root+=[f'--font-{k}: {v};' for k,v in t['type']['families'].items()]
css.append(':root {\n  '+'\n  '.join(root)+'\n}')
for g in t['type']['groups']:
    for st in g['styles']:
        props=[f'font-family: var(--font-{g["family"]})', f'font-size: {st["fontSize"]}', f'line-height: {st["lineHeight"]}', f'font-weight: {st["fontWeight"]}']
        if 'letterSpacing' in st: props.append(f'letter-spacing: {st["letterSpacing"]}')
        css.append(f'.{esc(st["name"])} {{ '+'; '.join(props)+'; }')
os.makedirs(f'{D}/preview', exist_ok=True)
open(f'{D}/preview/tokens.css','w').write('\n'.join(css))
for comp in sorted(os.listdir(f'{D}/components')):
    p=f'{D}/components/{comp}/preview.html'
    if not os.path.exists(p): continue
    for th in themes:
        h=open(p).read().replace('<html lang="en">',f'<html lang="en" data-theme="{th}">',1).replace('<head>','<head><link rel="stylesheet" href="./tokens.css"><link rel="stylesheet" href="../components/bundle.css">',1)
        open(f'{D}/preview/{comp}-{th}.html','w').write(h)
print('preview pages written')
