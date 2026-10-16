.pragma library

function workspaceFullscreen(workspace) {
    return workspace?.toplevels?.values?.some(toplevel => toplevel?.lastIpcObject?.fullscreen > 1) ?? false;
}

function normalFullscreenFor(monitor) {
    return workspaceFullscreen(monitor?.activeWorkspace);
}

function visibleFullscreenFor(monitor, workspaces) {
    const specialName = monitor?.lastIpcObject?.specialWorkspace?.name;
    if (specialName)
        return workspaceFullscreen((workspaces ?? []).find(workspace => workspace.name === specialName));
    return normalFullscreenFor(monitor);
}

function anyNormalFullscreen(monitors) {
    return (monitors ?? []).some(normalFullscreenFor);
}
