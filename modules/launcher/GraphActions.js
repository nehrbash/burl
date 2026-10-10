function emacsAction(name, icon, description, expression, context, createFrame = true) {
    if (!context.emacsEnabled || !expression)
        return null;
    const command = createFrame ? ["emacsclient", "-c", "-n", "-e", expression] : ["emacsclient", "-n", "-e", expression];
    return { name, icon, desc: description || "", command };
}

function calendarExpression(event, context) {
    if (!context.agendaFile || !event.title)
        return "";
    return `(progn (find-file ${JSON.stringify(context.agendaFile)}) (goto-char (point-min)) (when (search-forward ${JSON.stringify(event.title)} nil t) (org-back-to-heading t) (org-show-entry)))`;
}

function primary(kind, source, context) {
    if (!source)
        return null;
    const quote = JSON.stringify;
    let expression = "";
    switch (kind) {
    case "file":
        return source.path ? { name: "Open", icon: "open_in_new", desc: source.path, command: ["xdg-open", source.path] } : null;
    case "recent":
        if (source.path && context.emacsEnabled)
            return { name: "Open", icon: "open_in_new", desc: source.path, command: ["emacsclient", "-n", source.path] };
        break;
    case "bookmark":
        if (source.name) expression = `(bookmark-jump ${quote(source.name)})`;
        break;
    case "roam":
        if (source.id) expression = `(org-roam-node-visit (org-roam-node-from-id ${quote(source.id)}))`;
        break;
    case "project":
        if (source.root) expression = `(project-switch-project ${quote(source.root)})`;
        break;
    case "mail":
        if (source.id) expression = `(mu4e-view-message-with-message-id ${quote(source.id)})`;
        break;
    case "event":
        expression = calendarExpression(source, context);
        break;
    }
    return emacsAction("Open", "open_in_new", "", expression, context);
}

function secondary(node, context) {
    if (!node)
        return [];
    const source = node.source || {};
    const quote = JSON.stringify;
    const emacs = (name, icon, description, expression, createFrame = true) => emacsAction(name, icon, description, expression, context, createFrame);
    const copy = (name, value) => value ? { name, icon: "content_copy", desc: value, command: ["wl-copy", value] } : null;
    let actions = [];
    switch (node.kind) {
    case "file":
        if (!source.path) break;
        actions = [
            { name: "Open folder", icon: "folder_open", desc: "Containing directory", command: ["xdg-open", source.path.replace(/\/[^/]*$/, "/")] },
            copy("Copy path", source.path),
            context.emacsEnabled ? { name: "Open in Emacs", icon: "edit", desc: source.path, command: ["emacsclient", "-n", source.path] } : null
        ];
        break;
    case "recent":
        if (!source.path) break;
        actions = [
            emacs("Open other window", "splitscreen_right", source.path, `(find-file-other-window ${quote(source.path)})`, false),
            emacs("Open in Dired", "folder_open", "Containing directory", `(dired ${quote(source.path.replace(/\/[^/]*$/, "/"))})`),
            copy("Copy path", source.path),
            emacs("Git log (magit)", "history", "VC history for file", `(progn (find-file ${quote(source.path)}) (magit-log-buffer-file))`)
        ];
        break;
    case "project":
        if (!source.root) break;
        actions = [
            emacs("Magit status", "commit", source.root, `(magit-status ${quote(source.root)})`),
            emacs("Dired", "folder_open", source.root, `(dired ${quote(source.root)})`),
            emacs("Compile", "build", "project-compile", `(let ((default-directory ${quote(source.root)})) (project-compile))`)
        ];
        break;
    case "mail":
        actions = [
            source.id ? emacs("Open in mu4e", "open_in_new", source.subject, `(mu4e-view-message-with-message-id ${quote(source.id)})`) : null,
            copy("Copy sender", source.fromEmail)
        ];
        break;
    case "event":
        actions = [
            emacs("Open agenda", "calendar_month", "org-agenda", '(org-agenda nil "a")'),
            emacs("Go to entry", "event", source.title, calendarExpression(source, context))
        ];
        break;
    case "roam":
        if (source.id) actions = [emacs("Open other window", "splitscreen_right", source.title,
            `(org-roam-node-open (org-roam-node-from-id ${quote(source.id)}))`)];
        break;
    case "app":
        if (node.entry) actions = [{ name: "New window", icon: "open_in_new", desc: node.label, entry: node.entry }];
        break;
    case "client":
        if (node.clientAddress) actions = [{ name: "Close window", icon: "close", desc: node.label,
            dispatch: `hl.dsp.window.kill({ window = ${quote("address:" + node.clientAddress)} })` }];
        break;
    }
    return actions.filter(action => action !== null);
}

function execute(action, context, visibility) {
    if (!action)
        return false;
    if (action.command)
        context.execute(action.command);
    else if (action.entry)
        context.launch(action.entry);
    else if (action.dispatch)
        context.dispatch(action.dispatch);
    else
        return false;
    if (visibility)
        visibility.launcher = false;
    return true;
}
