#!/bin/sh
# Re-measure the world-tree orb anchors after editing assets/images/worldtree.png.
#
# The orb positions in modules/dashboard/tree/LivingTree.qml are (u,v) fractions of
# the painting's own box, found by isolating the near-black pockets from the
# warm-brown atmosphere. Re-export the art from an image editor and they WILL be
# wrong — the same standing cost already documented for root-turnup.png's burl seats.
#
# Prints a ready-to-paste QML `orbAnchors` block. Verify by eye afterwards: two
# earlier threshold guesses found root gaps and the vignette instead, and the
# numbers alone reported both as success.
#
#   scripts/qs-orb-anchors.sh [path-to-worldtree.png] [threshold-percent]
set -eu
ART="${1:-assets/images/worldtree.png}"
THR="${2:-6}"
[ -f "$ART" ] || { echo "no such art: $ART" >&2; exit 1; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# upper 64% only — below that is the root system, whose gaps are not orb pockets
convert "$ART" -gravity North -crop 100%x64%+0+0 +repage -colorspace Gray -blur 0x3 \
        -resize 200x256! -threshold "${THR}%" -negate "gray:$TMP/m.raw"

python3 - "$TMP/m.raw" <<'PY'
import sys
W,H=200,256
d=open(sys.argv[1],'rb').read()
seen=bytearray(W*H); blobs=[]
for i in range(W*H):
    if d[i]<128 or seen[i]: continue
    st=[i]; seen[i]=1; px=[]; touch=False
    while st:
        p=st.pop(); px.append(p); x,y=p%W,p//W
        if x in (0,W-1) or y in (0,H-1): touch=True   # border-connected = vignette
        for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)):
            nx,ny=x+dx,y+dy
            if 0<=nx<W and 0<=ny<H:
                q=ny*W+nx
                if not seen[q] and d[q]>=128: seen[q]=1; st.append(q)
    if touch or len(px)<30: continue
    xs=[p%W for p in px]; ys=[p//W for p in px]
    cx,cy=sum(xs)/len(xs),sum(ys)/len(ys)
    r=min(max(xs)-cx,cx-min(xs),max(ys)-cy,cy-min(ys))
    blobs.append((len(px),cx/W,cy/H*0.64,r/W))
blobs.sort(reverse=True)
sel=[]
for a,u,v,r in blobs:
    if v<0.06 or v>0.60 or abs(u-0.5)<0.07: continue      # skip the trunk column
    if all((u-su)**2+(v-sv)**2 > 0.13**2 for _,su,sv,_ in sel): sel.append((a,u,v,r))
    if len(sel)==6: break
sel.sort(key=lambda b:(b[2],b[1]))
if len(sel)<6:
    print("/* WARNING: only %d pockets found — the art needs clearer gaps, or retune the threshold */" % len(sel))
print("    readonly property var orbAnchors: [")
for k,(a,u,v,r) in enumerate(sel):
    print("        {")
    print("            u: %.4f," % u)
    print("            v: %.4f," % v)
    print("            r: %.4f" % r)
    print("        }%s" % ("," if k < len(sel)-1 else ""))
print("    ]")
PY
