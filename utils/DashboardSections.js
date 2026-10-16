.pragma library

var sections = [
    { id: "dashboard", enabledKey: "showDashboard", iconName: "dashboard", labelKey: "Dashboard" },
    { id: "media", enabledKey: "showMedia", iconName: "queue_music", labelKey: "Media" },
    { id: "performance", enabledKey: "showPerformance", iconName: "speed", labelKey: "Performance" },
    { id: "weather", enabledKey: "showWeather", iconName: "cloud", labelKey: "Weather" },
    { id: "tasks", enabledKey: "", iconName: "checklist", labelKey: "Tasks" }
];

function enabledIds(config) {
    return sections.filter(section => !section.enabledKey || config[section.enabledKey]).map(section => section.id);
}

function sectionFlag(id) {
    const section = sections.find(section => section.id === id);
    return section ? section.enabledKey : "";
}
