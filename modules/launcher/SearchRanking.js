.pragma library

function normalize(value) {
    return String(value ?? "").normalize("NFD").replace(/[\u0300-\u036f]/g, "")
        .toLowerCase().trim().replace(/\s+/g, " ");
}

function boundary(text, index) {
    return index === 0 || /[\s\-_/.:()]/.test(text[index - 1]);
}

function oneEdit(a, b) {
    if (Math.abs(a.length - b.length) > 1) return false;
    let i = 0;
    while (i < a.length && i < b.length && a[i] === b[i]) ++i;
    if (a.length === b.length) {
        return a.slice(i + 1) === b.slice(i + 1)
            || (a[i] === b[i + 1] && a[i + 1] === b[i]
                && a.slice(i + 2) === b.slice(i + 2));
    }
    return a.length > b.length ? a.slice(i + 1) === b.slice(i)
                              : a.slice(i) === b.slice(i + 1);
}

function tokenScore(text, token, fuzzy) {
    if (text === token) return 100;
    if (text.startsWith(token)) return 85 + 5 * token.length / text.length;
    let at = text.indexOf(token);
    if (at >= 0) {
        let best = 0;
        while (at >= 0) {
            best = Math.max(best, (boundary(text, at) ? 75 : 60)
                + 5 * token.length / text.length);
            at = text.indexOf(token, at + 1);
        }
        return best;
    }
    if (!fuzzy) return 0;

    let best = 0;
    for (let start = text.indexOf(token[0]); start >= 0;
         start = text.indexOf(token[0], start + 1)) {
        let cursor = start;
        let boundaries = boundary(text, start) ? 1 : 0;
        let matched = true;
        for (let i = 1; i < token.length; ++i) {
            cursor = text.indexOf(token[i], cursor + 1);
            if (cursor < 0) { matched = false; break; }
            if (boundary(text, cursor)) ++boundaries;
        }
        if (matched) {
            const density = token.length / (cursor - start + 1);
            best = Math.max(best, 20 + 15 * density + 5 * boundaries / token.length);
        }
    }
    if (best > 0) return best;
    // Short tokens are too ambiguous for typo correction.
    if (token.length >= 5) {
        const words = text.split(/[\s\-_/.:()]+/);
        for (const word of words)
            if (oneEdit(token, word)) return 15;
    }
    return 0;
}

function score(label, query, metadata) {
    const text = normalize(label);
    const q = normalize(query);
    if (!q) return 0;
    const fields = (metadata ?? []).map(normalize).filter(Boolean);
    const tokens = q.split(" ");
    let total = 0;
    let allName = true;
    for (const token of tokens) {
        const nameScore = tokenScore(text, token, true);
        let value = nameScore;
        // Metadata only admits literal matches so descriptions cannot flood results.
        for (const field of fields)
            value = Math.max(value, tokenScore(field, token, false) * 0.1);
        if (value === 0) return 0;
        if (nameScore === 0) allName = false;
        total += value;
    }
    return total / tokens.length + (allName ? tokenScore(text, q, false) : 0);
}
