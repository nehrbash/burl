#!/usr/bin/env bash
# qs-lint.sh — make qmllint actually work on burl.
#
# Plain `qmllint modules/.../Foo.qml` reports NOTHING but "Failed to import
# qs.components" for every qs.* import, because quickshell's directory-as-module
# namespace has no qmldir files anywhere in files/burl. Result: qmllint has never
# had type information for this project, so every missing-import and
# missing-property defect went straight to a deploy.
#
# Fix: copy the tree, GENERATE a qmldir per directory, then lint with -I.
# ~6s for the whole tree; the copy is disposable, the repo is never touched.
#
#   qs-lint.sh                              # lint everything
#   qs-lint.sh modules/dashboard/Content.qml modules/dashboard/tree/LivingTree.qml
set -uo pipefail
ROOT=${QS_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}
QMLDIR_QT=$(dirname "$(readlink -f "$(command -v qmllint)")")/../lib/qt6/qml
WORK=$(mktemp -d "${TMPDIR:-/tmp}/qs-lint.XXXXXX"); trap 'rm -rf "$WORK"' EXIT
cp -rL "$ROOT" "$WORK/qs" 2>/dev/null

python3 - "$WORK/qs" <<'PY'
import os, sys
root = sys.argv[1]
for dirpath, dirs, files in os.walk(root):
    if 'plugin' in os.path.relpath(dirpath, root).split(os.sep): continue
    qmls = sorted(f for f in files if f.endswith('.qml') and f[0].isupper())
    if not qmls: continue
    rel = os.path.relpath(dirpath, root)
    mod = 'qs' if rel == '.' else 'qs.' + rel.replace(os.sep, '.')
    out = ['module ' + mod]
    for f in qmls:
        head = open(os.path.join(dirpath, f)).read(4000)
        out.append(('singleton ' if 'pragma Singleton' in head else '') + f'{f[:-4]} 1.0 {f}')
    open(os.path.join(dirpath, 'qmldir'), 'w').write('\n'.join(out) + '\n')
PY

cd "$WORK/qs" || exit 2
if (($#)); then TARGETS=("$@"); else mapfile -t TARGETS < <(find . -name '*.qml' -not -path './plugin/*' | sed 's|^\./||'); fi
qmllint -I "$WORK" -I "$QMLDIR_QT" --unused-imports info "${TARGETS[@]}" 2>&1 |
    grep -vE '^\s*$|^\^+$|^---$'
