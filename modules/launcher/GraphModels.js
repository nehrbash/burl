function sync(model, nodes, indices) {
    const wanted = indices.filter(i => nodes[i] !== undefined);
    const ids = new Set(wanted.map(i => nodes[i].id));
    for (let row = model.count - 1; row >= 0; --row)
        if (!ids.has(model.get(row).nodeId)) model.remove(row);

    for (let row = 0; row < wanted.length; ++row) {
        const nodeIndex = wanted[row];
        const nodeId = nodes[nodeIndex].id;
        if (row >= model.count || model.get(row).nodeId !== nodeId) {
            let existing = row + 1;
            while (existing < model.count && model.get(existing).nodeId !== nodeId) ++existing;
            if (existing < model.count) model.move(existing, row, 1);
            else model.insert(row, { nodeId, nodeIndex });
        }
        if (model.get(row).nodeIndex !== nodeIndex)
            model.setProperty(row, "nodeIndex", nodeIndex);
    }
}
