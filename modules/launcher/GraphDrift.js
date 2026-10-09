.pragma library

function offset(seconds, strength, index) {
    if (!strength || index < 0) return { x: 0, y: 0 };
    const phase = index * 2.3999632297;
    const rate = (index % 2 ? -1 : 1) * (0.09 + (index % 7) * 0.008);
    const radius = 1.8 + (index % 5) * 0.2;
    return { x: strength * radius * Math.cos(seconds * rate + phase),
             y: strength * radius * 0.7 * Math.sin(seconds * rate + phase) };
}
