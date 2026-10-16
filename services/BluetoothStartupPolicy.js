function apply(adapters, previous, autoEnable) {
    const current = adapters.filter(adapter => adapter !== null);
    if (autoEnable) {
        for (const adapter of current) {
            if (previous.indexOf(adapter) === -1 && !adapter.enabled)
                adapter.enabled = true;
        }
    }
    return current.slice();
}
