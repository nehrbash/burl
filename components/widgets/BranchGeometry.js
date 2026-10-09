.pragma library

function point(b, t) {
    const u = 1 - t;
    return { x: u*u*u*b[0] + 3*u*u*t*b[2] + 3*u*t*t*b[4] + t*t*t*b[6],
             y: u*u*u*b[1] + 3*u*u*t*b[3] + 3*u*t*t*b[5] + t*t*t*b[7] };
}

function ribbon(ctx, b, width, progress, colour) {
    if (progress <= 0) return;
    const left = [], right = [];
    const steps = Math.max(4, Math.ceil(32 * progress));
    for (let i = 0; i <= steps; ++i) {
        const t = progress * i / steps;
        const p = point(b, t), q = point(b, Math.min(1, t + 0.002));
        const prev = point(b, Math.max(0, t - 0.002));
        const dx = q.x - prev.x, dy = q.y - prev.y;
        const length = Math.max(0.001, Math.hypot(dx, dy));
        const r = width * Math.pow(1 - t, 1.15) / 2 + 0.00035;
        left.push([p.x - dy / length * r, p.y + dx / length * r]);
        right.push([p.x + dy / length * r, p.y - dx / length * r]);
    }
    ctx.fillStyle = colour;
    ctx.beginPath();
    ctx.moveTo(left[0][0], left[0][1]);
    for (let i = 1; i < left.length; ++i) ctx.lineTo(left[i][0], left[i][1]);
    for (let i = right.length - 1; i >= 0; --i) ctx.lineTo(right[i][0], right[i][1]);
    ctx.closePath();
    ctx.fill();
}

function partialCurve(ctx, b, t) {
    const p = point(b, t), u = 1 - t;
    ctx.moveTo(b[0], b[1]);
    ctx.bezierCurveTo(b[0] + (b[2]-b[0])*t, b[1] + (b[3]-b[1])*t,
        u*u*b[0] + 2*u*t*b[2] + t*t*b[4],
        u*u*b[1] + 2*u*t*b[3] + t*t*b[5], p.x, p.y);
}

function random(seed) {
    const n = Math.sin(seed*127.1+311.7)*43758.5453;
    return n-Math.floor(n);
}

function roughPoint(b,t,width,seed,taper) {
    const p = point(b,t), q = point(b,Math.min(1,t+0.002));
    const before = point(b,Math.max(0,t-0.002));
    const dx = q.x-before.x, dy = q.y-before.y;
    const norm = Math.max(0.00001,Math.hypot(dx,dy));
    const nx = -dy/norm, ny = dx/norm;
    const knot = Math.sin(t*23+seed)*Math.sin(t*9+seed*0.7);
    const corner = Math.floor(t*9), blend = t*9-corner;
    const crooked = (random(seed+corner*17)-0.5)*(1-blend)+(random(seed+(corner+1)*17)-0.5)*blend;
    const bend = (width*0.32*crooked+0.003*knot)*Math.sin(Math.PI*t);
    return { x:p.x+nx*bend,y:p.y+ny*bend,nx:nx,ny:ny,
        r:width*0.5*Math.pow(1-t,taper === undefined ? 0.82 : taper)*(0.89+0.18*crooked+0.035*knot)+0.00014 };
}

function gnarled(ctx,b,width,progress,seed,dark,mid,light,depth,cache) {
    const steps = Math.max(5,Math.ceil(100*progress));
    const samples = [];
    const tipLength = 0.09*Math.min(1,(1-progress)/0.12);
    for (let j = 0; j <= steps; ++j) {
        const t = progress*j/steps;
        const p = roughPoint(b,t,width,seed,depth === 0 ? 0.82 : 1.45);
        if (tipLength > 0) {
            const f = Math.min(1,(progress-t)/tipLength);
            p.r *= f*f*(3-2*f);
        }
        samples.push(p);
    }
    const shade = depth === 0 ? ctx.createLinearGradient(b[0]-width,b[1],b[0]+width,b[1])
        : ctx.createLinearGradient(b[0],b[1],b[6],b[7]);
    shade.addColorStop(0,depth === 0 ? dark : mid);
    shade.addColorStop(depth === 0 ? 0.52 : 0.22,mid);
    shade.addColorStop(1,dark);
    ctx.fillStyle = shade;
    ctx.beginPath();
    for (let j = 0; j <= steps; ++j) {
        const p = samples[j], tooth = 0.97+random(seed+j*7)*0.06;
        const x = p.x+p.nx*p.r*tooth, y = p.y+p.ny*p.r*tooth;
        if (!j) ctx.moveTo(x,y); else ctx.lineTo(x,y);
    }
    for (let j = steps; j >= 0; --j) {
        const p = samples[j], tooth = 0.96+random(seed+j*3)*0.07;
        ctx.lineTo(p.x-p.nx*p.r*tooth,p.y-p.ny*p.r*tooth);
    }
    ctx.closePath();
    ctx.fill();
    if (depth > 2) return;
    ctx.save();
    if (tipLength > 0) ctx.clip();
    const geometry = cache || {};
    if (!geometry.ridges) geometry.ridges = barkGeometry(b,width,seed,depth);
    const ridges = geometry.ridges;
    ctx.lineCap = "round";
    for (let k = 0; k < ridges.length; ++k) {
        const ridge = ridges[k];
        if (progress <= ridge.begin) continue;
        ctx.strokeStyle = ridge.bright ? light : dark;
        ctx.globalAlpha = ridge.alpha;
        ctx.lineWidth = ridge.width;
        ctx.beginPath();
        const points = ridge.points;
        ctx.moveTo(points[0].x,points[0].y);
        for (let j = 1; j < points.length; ++j) {
            const p = points[j], previous = points[j-1];
            if (p.t > progress) {
                const f = (progress-previous.t)/(p.t-previous.t);
                ctx.lineTo(previous.x+(p.x-previous.x)*f,previous.y+(p.y-previous.y)*f);
                break;
            }
            ctx.lineTo(p.x,p.y);
        }
        ctx.stroke();
    }
    ctx.globalAlpha = 1;
    if (depth === 0) {
        for (let k = 0; k < 3; ++k) {
            const t = 0.22+k*0.22;
            if (progress < t+0.06) continue;
            const p = roughPoint(b,t,width,seed), side = k%2 ? -0.45 : 0.42;
            ctx.save();
            ctx.translate(p.x+p.nx*p.r*side,p.y+p.ny*p.r*side);
            ctx.rotate(Math.atan2(p.ny,p.nx));
            ctx.fillStyle = dark;
            ctx.beginPath();
            ctx.ellipse(-p.r*0.08,-p.r*0.425,p.r*0.16,p.r*0.85);
            ctx.fill();
            ctx.strokeStyle = light;
            ctx.globalAlpha = 0.35;
            ctx.lineWidth = 0.0007;
            ctx.stroke();
            ctx.restore();
        }
    }
    ctx.restore();
}

function barkGeometry(b,width,seed,depth) {
    const ridges = depth <= 0 ? 430 : 18;
    const result = [];
    for (let k = 0; k < ridges; ++k) {
        const n = seed+k*19;
        const offset = (random(n+3)-0.5)*1.72;
        const begin = random(n)*0.95;
        const end = Math.min(1,begin+0.014+random(n+9)*0.12);
        const bright = k%3 === 0;
        const points = [];
        const alpha = bright ? (depth <= 0 ? 0.40+random(n+7)*0.5 : 0.16) : 0.4+random(n+11)*0.4;
        const lineWidth = width*(bright ? 0.001+random(n+5)*0.003 : 0.002+random(n+5)*0.006);
        for (let j = 0; j <= 17; ++j) {
            const t = begin+(end-begin)*j/17;
            const p = roughPoint(b,t,width,seed,depth === 0 ? 0.82 : 1.45);
            let twist = offset+0.05*Math.sin(t*81+n)+0.03*Math.sin(t*139+n);
            for (let knot = 0; knot < 3; ++knot) {
                const kt = 0.22+knot*0.22, side = knot%2 ? -0.45 : 0.42;
                const proximity = Math.exp(-Math.pow((t-kt)/0.035,2));
                twist += (offset < side ? -1 : 1)*0.17*proximity*Math.exp(-Math.pow((offset-side)/0.24,2));
            }
            const x = p.x+p.nx*p.r*twist, y = p.y+p.ny*p.r*twist;
            points.push({ x:x,y:y,t:t });
        }
        result.push({ points:points,begin:begin,end:end,bright:bright,alpha:alpha,width:lineWidth });
    }
    return result;
}
