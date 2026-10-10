.pragma library
.import "../SearchRanking.js" as Ranking
.import "CommandArguments.js" as Arguments

function literalScore(value, query) {
    const text = Ranking.normalize(value);
    const q = Ranking.normalize(query);
    return q.split(" ").every(word => text.includes(word)) ? Ranking.score(text, q, []) : 0;
}

function query(actions, text, fuzzy) {
    const search = text.trim();
    if (!search) return Array.from(actions);
    const head = search.split(/\s+/)[0].toLowerCase();
    const exact = Array.from(actions).filter(action => Arguments.aliasesFor(action).includes(head));
    if (exact.length) {
        return exact.sort((a, b) => Number(Arguments.keywordFor(b).toLowerCase() === head)
            - Number(Arguments.keywordFor(a).toLowerCase() === head));
    }
    const score = fuzzy ? (value, q) => Ranking.score(value, q, []) : literalScore;
    return Array.from(actions).map((action, index) => {
        const keyword = Arguments.keywordFor(action);
        const executable = Arguments.supportsArguments(action) ? Arguments.executableFor(action) : "";
        const value = Math.max(score(keyword, search) * 4,
            score(action.name ?? "", search) * 3,
            score(executable, search) * 2,
            score(action.description ?? action.desc ?? "", search));
        return {action, index, value};
    }).filter(item => item.value > 0)
        .sort((a, b) => b.value - a.value || a.index - b.index)
        .map(item => item.action);
}
