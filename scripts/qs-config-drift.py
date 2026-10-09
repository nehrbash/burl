#!/usr/bin/env python3
"""Compare compiled Burl defaults with the live shell configuration."""
import json, os, re, sys

BURL = (os.path.join(os.environ["QS_REPO"], "files/burl")
        if os.environ.get("QS_REPO")
        else os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
PLUGIN = os.path.join(BURL, "plugin/src/Burl/Config")
LIVE = os.path.expanduser("~/.config/burl/shell.json")

prop = re.compile(r'CONFIG_PROPERTY\(\s*([A-Za-z0-9_:<>]+)\s*,\s*(\w+)\s*,\s*(.+?)\s*\)\s*$')
defaults = {}
for f in sorted(os.listdir(PLUGIN)):
    if not f.endswith('.hpp'):
        continue
    section = f[:-len('config.hpp')] if f.endswith('config.hpp') else f[:-4]
    for line in open(os.path.join(PLUGIN, f)):
        m = prop.search(line.strip())
        if not m:
            continue
        _, name, dflt = m.groups()
        dflt = re.sub(r'QStringLiteral\(\s*"(.*?)"\s*\)', r'\1', dflt).strip()
        defaults.setdefault(section, {})[name] = dflt

live = json.load(open(LIVE))
drift = []
for section, props in defaults.items():
    livesec = live.get(section, {})
    if not isinstance(livesec, dict):
        continue
    for name, dflt in props.items():
        if name not in livesec:
            continue
        lv = livesec[name]
        lvs = 'true' if lv is True else 'false' if lv is False else str(lv)
        if lvs != dflt.strip('"'):
            drift.append((section, name, dflt, lvs))

for section, name, dflt, lv in sorted(drift):
    print(f"DRIFT {section}.{name}: compiled={dflt!r} live={lv!r}")
print(f"\n{len(drift)} drifted of {sum(len(v) for v in defaults.values())} compiled properties", file=sys.stderr)
