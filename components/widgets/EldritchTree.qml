pragma ComponentBehavior: Bound

import "BranchGeometry.js" as Branch
import "PaintedTreePaths.js" as PaintedPaths
import QtQuick
import qs.components
import qs.services

Item {
    id: root

    property bool renderedTrunk: true
    property var anchorsData: []
    property var rootAnchorsData: []
    property var rootLimbs: []
    property var rootCradles: []
    property int hoveredRoot: -1
    property real growth: 1
    property int selected: -1
    property int hovered: -1
    property bool animated: true
    property real reveal: 0
    property var limbs: []
    property var orbLimbs: []
    readonly property color woodDark: Woodland.mix(Woodland.barkEdge, Colours.palette.m3surface, 0.55)
    readonly property color woodMid: Woodland.mix(Woodland.barkShaded, Colours.palette.m3secondary, 0.03)
    readonly property color woodLight: Woodland.mix(Woodland.barkLit, Woodland.parchmentEdge, 0.45)
    signal pulseArrived(int index)
    signal rootPulseArrived(int index)

    function paintedRoute(isRoot: bool, index: int): var {
        return (isRoot ? PaintedPaths.roots : PaintedPaths.orbs)[index] ?? null;
    }

    function routePoint(route: var, progress: real): var {
        if (!route || !route.points.length) return { x:0.5,y:0.91 };
        const points = route.points, t = Math.max(0,Math.min(1,progress));
        for (let i = 1; i < points.length; ++i) {
            const p = points[i], previous = points[i-1];
            if (p[2] >= t) {
                const f = (t-previous[2])/Math.max(0.000001,p[2]-previous[2]);
                return { x:previous[0]+(p[0]-previous[0])*f,y:previous[1]+(p[1]-previous[1])*f };
            }
        }
        return { x:points[points.length-1][0],y:points[points.length-1][1] };
    }

    function rootProgress(index: int): real {
        const route = renderedTrunk ? paintedRoute(true,index) : null;
        if (route) return Math.max(0,Math.min(1,0.65+0.35*(reveal/route.arrival-0.85)/0.15));
        const limb = rootLimbs[index];
        return limb ? Math.max(0,Math.min(1,(reveal-limb.start)/limb.span)) : 0;
    }

    function rootEndpoint(index: int): var {
        const route = renderedTrunk ? paintedRoute(true,index) : null;
        if (route) return routePoint(route,reveal/route.arrival);
        const limb = rootLimbs[index];
        return limb ? Branch.point(limb.b,rootProgress(index)) : { x:0.5,y:0.88 };
    }

    function orbProgress(index: int): real {
        const route = renderedTrunk ? paintedRoute(false,index) : null;
        if (route) return Math.max(0,Math.min(1,(reveal/route.arrival-0.85)/0.15));
        const limb = orbLimbs[index];
        return limb ? Math.max(0, Math.min(1, (reveal-limb.start)/limb.span)) : 0;
    }

    function orbEndpoint(index: int): var {
        const route = renderedTrunk ? paintedRoute(false,index) : null;
        if (route) return routePoint(route,reveal/route.arrival);
        const limb = orbLimbs[index];
        return limb ? Branch.point(limb.b, orbProgress(index)) : { x: 0.5, y: 0.94 };
    }

    function rebuild(): void {
        const branches = [], terminals = [], actionRoots = [], cradles = [];
        const trunk = [0.51,1.04, 0.40,0.70, 0.52,0.55, 0.63,0.31];
        function noise(n) { return Branch.random(n); }
        function limb(b, w, start, span, depth, seed, owner, roots) {
            const entry = { b: b, w: w, start: start, span: span, depth: depth,
                seed: seed, owner: owner, roots: roots, geometry: {} };
            branches.push(entry);
            return entry;
        }
        function fork(b, w, start, span, depth, seed, owner) {
            const entry = limb(b, w, start, span, depth, seed, owner, false);
            branches.pop();
            if (renderedTrunk || depth >= 3) { branches.push(entry); return entry; }
            const count = depth === 1 ? 4 : 2;
            for (let j = 0; j < count; ++j) {
                const n = seed*11+j*37;
                const t = 0.36+j*0.16+noise(n)*0.06;
                const p = Branch.point(b,t), q = Branch.point(b,Math.min(1,t+0.03));
                const sign = (j+seed)%2 ? 1 : -1;
                let a = Math.atan2(q.y-p.y,q.x-p.x)+sign*(0.45+noise(n+5)*0.7);
                const len = (0.10+noise(n+9)*0.10)*Math.pow(0.57,depth-1);
                const elbow = a-sign*0.44;
                const ex = Math.max(0.025,Math.min(0.975,p.x+Math.cos(a)*len));
                const ey = Math.max(0.035,Math.min(0.88,p.y+Math.sin(a)*len));
                fork([p.x,p.y,Math.max(0.025,Math.min(0.975,p.x+Math.cos(elbow)*len*0.4)),Math.max(0.035,p.y+Math.sin(elbow)*len*0.4),
                    Math.max(0.025,Math.min(0.975,ex-Math.cos(a+sign*0.65)*len*0.24)),Math.max(0.035,ey-Math.sin(a+sign*0.65)*len*0.24),ex,ey],
                    w*Math.pow(1-t,1.45)*(0.70+noise(n+3)*0.22),start+span*t,span*0.54,depth+1,n,owner);
            }
            branches.push(entry);
            return entry;
        }
        for (let i = 0; i < rootAnchorsData.length; ++i) {
            const anchor = rootAnchorsData[i];
            const route = renderedTrunk ? paintedRoute(true,i) : null;
            const a = route ? { u:route.wood[0],v:route.wood[1],ru:anchor.ru,rv:anchor.rv } : anchor;
            const side = a.u < 0.5 ? -1 : 1;
            const start = 0.06+i*0.018, span = 0.42+Math.abs(a.u-0.5)*0.20;
            const b = [0.5,0.84,0.5+side*0.055,0.94,a.u-side*0.08,a.v+0.02,a.u,a.v];
            const entry = limb(b,0.042,start,span,1,301+i,-1,true);
            entry.actionRoot = i;
            actionRoots.push(entry);
            const rx = a.ru*1.18, ry = a.rv*1.18;
            for (let side = -1; side <= 1; side += 2) {
                cradles.push({ b:[a.u,a.v+ry*0.94,a.u+side*rx*1.55,a.v+ry*0.90,
                    a.u+side*rx*1.25,a.v-ry*0.74,a.u+side*rx*(side < 0 ? 0.82 : 0.30),a.v-ry*(side < 0 ? 0.58 : 1.12)],
                    w:side < 0 ? 0.012 : 0.007,start:route ? route.arrival*0.85 : start+span*0.80,span:route ? route.arrival*0.15+0.08 : 0.26,owner:i });
            }
        }
        const bole = { b:trunk,w:0.245,start:0,span:0.72,depth:0,seed:83,owner:-1,roots:false,geometry:{} };
        const endpoints = [[0.06,0.44],[0.14,0.22],[0.27,0.07],[0.40,0.085],
            [0.59,0.075],[0.74,0.13],[0.94,0.32],[0.87,0.51]];
        for (let k = 0; k < endpoints.length; ++k) {
            const end = endpoints[k], side = end[0]<0.5 ? -1 : 1;
            const t = 0.30+(k%4)*0.12, p = Branch.point(trunk,t);
            fork([p.x,p.y,p.x+side*0.05,p.y-0.15,end[0]-side*0.11,end[1]+0.11,end[0],end[1]],
                0.075-(k%4)*0.010,t*0.72,0.38,1,k+11,-1);
        }
        for (let i = 0; i < anchorsData.length; ++i) {
            const a = anchorsData[i], side = a.u<0.5 ? -1 : 1;
            const t = 0.29+Math.max(0,0.6-a.v)*0.60, p = Branch.point(trunk,t);
            const span = 0.42, start = t*0.72;
            terminals.push(fork([p.x,p.y,p.x+side*0.085,p.y-0.07,
                a.u-side*0.10,a.v+0.12,a.u,a.v],0.044,start,span,1,i+151,i));
        }
        const leftJoin = Branch.point(trunk,0.66);
        const rightJoin = Branch.point(trunk,0.79);
        fork([leftJoin.x,leftJoin.y,0.40,0.45,0.31,0.40,0.24,0.20],
            0.102,0.66*0.72,0.32,1,233,-1).core = true;
        fork([rightJoin.x,rightJoin.y,0.60,0.38,0.60,0.26,0.75,0.19],
            0.073,0.79*0.72,0.30,1,257,-1).core = true;
        branches.push(bole);
        limbs = branches;
        orbLimbs = terminals;
        rootLimbs = actionRoots;
        rootCradles = cradles;
        wood.requestPaint();
    }

    Component.onCompleted: { rebuild(); reveal = growth; }
    onGrowthChanged: reveal = growth
    onRenderedTrunkChanged: rebuild()
    onAnchorsDataChanged: rebuild()
    onRootAnchorsDataChanged: rebuild()
    onHoveredRootChanged: wood.requestPaint()
    onSelectedChanged: wood.requestPaint()
    onHoveredChanged: wood.requestPaint()
    onRevealChanged: wood.requestPaint()
    onWoodDarkChanged: wood.requestPaint()
    onWidthChanged: wood.requestPaint()
    onHeightChanged: wood.requestPaint()

    Behavior on reveal {
        enabled: root.animated && Ambience.grow && !GameMode.enabled
        NumberAnimation { duration: 1900; easing.type: Easing.InOutCubic }
    }

    PaintedTree {
        anchors.fill: parent
        visible: root.renderedTrunk
        growth: root.reveal
        animated: root.animated
    }

    Canvas {
        id: wood
        anchors.fill: parent
        antialiasing: true
        renderStrategy: Canvas.Threaded
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.scale(width,height);
            for (let i = 0; !root.renderedTrunk && i < root.limbs.length; ++i) {
                const l = root.limbs[i];
                const p = Math.max(0,Math.min(1,(root.reveal-l.start)/l.span));
                if (p <= 0) continue;
                const lit = l.actionRoot !== undefined ? root.hoveredRoot === l.actionRoot
                    : l.owner >= 0 && (l.owner === root.selected || l.owner === root.hovered);
                Branch.gnarled(ctx,l.b,l.w,p,l.seed,Qt.darker(root.woodDark,1.9),l.depth === 0 || l.core || l.actionRoot !== undefined ? Woodland.mix(root.woodMid,Woodland.barkLit,0.30) : Qt.darker(root.woodDark,1.45),root.woodLight,l.core ? -1 : l.depth,l.geometry);
                if (lit) {
                    ctx.strokeStyle = Qt.alpha(Colours.palette.m3primary,0.52);
                    ctx.lineWidth = 0.0012;
                    ctx.beginPath();
                    Branch.partialCurve(ctx,l.b,p);
                    ctx.stroke();
                }
            }
            if (root.renderedTrunk) {
                const routes = [root.paintedRoute(false,root.selected),root.paintedRoute(false,root.hovered),
                    root.paintedRoute(true,root.hoveredRoot)];
                ctx.lineWidth = 0.0008;
                ctx.strokeStyle = Qt.alpha(Colours.palette.m3primary,0.30);
                for (let r = 0; r < routes.length; ++r) {
                    const route = routes[r];
                    if (!route) continue;
                    const progress = Math.min(1,root.reveal/route.arrival), points = route.points;
                    ctx.beginPath();
                    ctx.moveTo(points[0][0],points[0][1]);
                    for (let j = 1; j < points.length; ++j) {
                        if (points[j][2] > progress) break;
                        ctx.lineTo(points[j][0],points[j][1]);
                    }
                    const tip = root.routePoint(route,progress);
                    ctx.lineTo(tip.x,tip.y);
                    ctx.stroke();
                }
            }
            for (let i = 0; i < root.rootCradles.length; ++i) {
                const c = root.rootCradles[i];
                const p = Math.max(0,Math.min(1,(root.reveal-c.start)/c.span));
                if (p <= 0) continue;
                Branch.ribbon(ctx,c.b,c.w,p,root.woodDark);
                Branch.ribbon(ctx,c.b,c.w*0.60,p,Woodland.mix(root.woodMid,root.woodLight,0.25));
                ctx.lineWidth = 0.00065;
                ctx.strokeStyle = root.hoveredRoot === c.owner ? Colours.palette.m3primary : root.woodLight;
                ctx.globalAlpha = root.hoveredRoot === c.owner ? 0.85 : 0.5;
                ctx.beginPath();
                Branch.partialCurve(ctx,c.b,p);
                ctx.stroke();
                ctx.globalAlpha = 1;
            }
        }
    }

    Repeater {
        model: root.orbLimbs.length+root.rootLimbs.length
        delegate: Item {
            id: spark
            required property int index
            property real travel: 0
            readonly property bool isRoot: index >= root.orbLimbs.length
            readonly property int routeIndex: isRoot ? index-root.orbLimbs.length : index
            readonly property var limb: isRoot ? root.rootLimbs[routeIndex] : root.orbLimbs[routeIndex]
            readonly property var location: root.renderedTrunk ? root.routePoint(root.paintedRoute(isRoot,routeIndex),travel) : Branch.point(limb.b,travel)
            readonly property bool active: isRoot ? root.hoveredRoot === routeIndex : root.selected === routeIndex || root.hovered === routeIndex
            x: location.x*root.width-width/2
            y: location.y*root.height-height/2
            width: 12
            height: 12
            opacity: Math.sin(travel*Math.PI)*(active ? 0.95 : 0.45)
            visible: root.visible && (isRoot ? root.rootProgress(routeIndex) : root.orbProgress(routeIndex)) > 0.98 && root.animated && Ambience.sway && !GameMode.enabled
            Rectangle {
                anchors.fill: parent
                radius: width/2
                color: Qt.alpha(Colours.palette.m3primary,0.13)
            }
            Rectangle {
                anchors.centerIn: parent
                width: spark.active ? 4 : 2
                height: width
                radius: width/2
                color: Colours.palette.m3primary
            }
            SequentialAnimation on travel {
                running: spark.visible
                loops: Animation.Infinite
                PauseAnimation { duration: spark.active ? 180 : 1100+spark.index*230 }
                NumberAnimation { from: 0; to: 1; duration: spark.active ? 1800 : 3200+spark.index*110; easing.type: Easing.InOutSine }
                ScriptAction { script: spark.isRoot ? root.rootPulseArrived(spark.routeIndex) : root.pulseArrived(spark.routeIndex) }
            }
        }
    }
}
