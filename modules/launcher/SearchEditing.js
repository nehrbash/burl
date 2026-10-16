var wordPattern = null;
try {
    wordPattern = new RegExp('[\\p{L}\\p{N}\\p{M}_]', 'u');
} catch (error) {
    // Older QML engines lack Unicode property escapes.
}

function nextCharacter(text, position) {
    if (position >= text.length) return text.length;
    const first = text.charCodeAt(position);
    const second = text.charCodeAt(position + 1);
    return position + (first >= 0xd800 && first <= 0xdbff && second >= 0xdc00 && second <= 0xdfff ? 2 : 1);
}

function previousCharacter(text, position) {
    if (position <= 0) return 0;
    const last = text.charCodeAt(position - 1);
    const first = text.charCodeAt(position - 2);
    return position - (last >= 0xdc00 && last <= 0xdfff && first >= 0xd800 && first <= 0xdbff ? 2 : 1);
}

function isWord(text, position) {
    const character = text.slice(position, nextCharacter(text, position));
    if (wordPattern) return wordPattern.test(character);
    if (/^[A-Za-z0-9_]$/.test(character)) return true;
    if (!character || character.charCodeAt(0) < 0x80) return false;
    return !/[\s\u00a0-\u00bf\u2000-\u206f\u2190-\u2bff\u3000-\u303f\ud800-\udfff\ufe00-\ufe6f\uff00-\uff0f\uff1a-\uff20\uff3b-\uff40\uff5b-\uff65]/.test(character);
}

function previousWord(text, position) {
    while (position > 0 && !isWord(text, previousCharacter(text, position)))
        position = previousCharacter(text, position);
    while (position > 0 && isWord(text, previousCharacter(text, position)))
        position = previousCharacter(text, position);
    return position;
}

function nextWord(text, position) {
    while (position < text.length && !isWord(text, position))
        position = nextCharacter(text, position);
    while (position < text.length && isWord(text, position))
        position = nextCharacter(text, position);
    return position;
}

function apply(field, command, state) {
    const text = field.text;
    const cursor = field.cursorPosition;
    let target = cursor;
    switch (command) {
    case 'C-a': target = 0; break;
    case 'C-e': target = text.length; break;
    case 'C-b': target = previousCharacter(text, cursor); break;
    case 'C-f': target = nextCharacter(text, cursor); break;
    case 'M-b': target = previousWord(text, cursor); break;
    case 'M-f': target = nextWord(text, cursor); break;
    case 'C-k': case 'C-u': case 'C-w': case 'C-h': case 'C-d':
    case 'M-Backspace': case 'M-d': case 'C-y': break;
    default: return false;
    }
    if (['C-a', 'C-e', 'C-b', 'C-f', 'M-b', 'M-f'].indexOf(command) !== -1) {
        field.deselect();
        field.cursorPosition = target;
        return true;
    }
    let start = Math.min(field.selectionStart, field.selectionEnd);
    let end = Math.max(field.selectionStart, field.selectionEnd);
    const selected = start !== end;
    if (!selected) {
        start = cursor;
        end = cursor;
    }
    if (command === 'C-y') {
        const killed = state.kill || '';
        if (!killed) return true;
        if (selected) field.remove(start, end);
        field.insert(start, killed);
        field.deselect();
        field.cursorPosition = start + killed.length;
        return true;
    }
    if (!selected) {
        switch (command) {
        case 'C-k': end = text.length; break;
        case 'C-u': start = 0; break;
        case 'C-w': case 'M-Backspace': start = previousWord(text, cursor); break;
        case 'M-d': end = nextWord(text, cursor); break;
        case 'C-h': start = previousCharacter(text, cursor); break;
        case 'C-d': end = nextCharacter(text, cursor); break;
        }
    }
    if (start !== end) {
        if (command !== 'C-h' && command !== 'C-d') state.kill = text.slice(start, end);
        field.remove(start, end);
    }
    field.deselect();
    field.cursorPosition = start;
    return true;
}
