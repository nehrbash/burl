pragma Singleton

import QtQuick
import qs.modules.nexus.common
import qs.modules.nexus.pages
import qs.modules.nexus.pages.apps
import qs.modules.nexus.pages.display
import qs.modules.nexus.pages.audio
import qs.modules.nexus.pages.bluetooth
import qs.modules.nexus.pages.network
import qs.modules.nexus.pages.panels
import qs.modules.nexus.pages.services
import qs.modules.nexus.pages.wallandstyle
import qs.modules.nexus.pages.panels.taskbar

QtObject {
    id: root

    function page(id: string): var {
        return pages.find(entry => entry.id === id) ?? pages[0];
    }

    function indexOf(id: string): int {
        return pages.findIndex(entry => entry.id === id);
    }

    readonly property list<var> pages: [
        {
            id: "appearance",
            component: root.appearancePage,
            label: qsTr("Wallpaper & style"),
            icon: "palette",
            description: qsTr("Wallpaper, fonts, colours"),
            category: "appearance"
        },

        {
            id: "display",
            component: root.displayPage,
            label: qsTr("Display"),
            icon: "monitor",
            description: qsTr("Output configuration"),
            category: "connectivity"
        },
        {
            id: "network",
            component: root.networkPage,
            label: qsTr("Network"),
            icon: "wifi",
            description: qsTr("Wi-Fi, ethernet"),
            category: "connectivity"
        },
        {
            id: "bluetooth",
            component: root.bluetoothPage,
            label: qsTr("Connected devices"),
            icon: "devices_other",
            description: qsTr("Bluetooth, pairing"),
            category: "connectivity",
            noFill: true
        },
        {
            id: "audio",
            component: root.audioPage,
            label: qsTr("Audio"),
            icon: "volume_up",
            description: qsTr("App volumes, sound devices"),
            category: "connectivity"
        },

        {
            id: "guix",
            component: root.guixPage,
            label: qsTr("Guix"),
            icon: "deployed_code",
            description: qsTr("Channels, rebuild, store"),
            category: "system"
        },

        {
            id: "panels",
            component: root.panelsPage,
            label: qsTr("Panels"),
            icon: "dock_to_bottom",
            description: qsTr("Dashboard, taskbar, launcher, sidebar"),
            category: "shell"
        },
        {
            id: "apps",
            component: root.appsPage,
            label: qsTr("Apps"),
            icon: "apps",
            description: qsTr("Burl launch preferences, favourites, hidden apps"),
            category: "shell"
        },
        {
            id: "services",
            component: root.servicesPage,
            label: qsTr("Services"),
            icon: "build",
            description: qsTr("Poll intervals, lyrics backend"),
            category: "shell"
        },
        {
            id: "language",
            component: root.languagePage,
            label: qsTr("Language & region"),
            icon: "globe",
            description: qsTr("System locale, weather location, display units"),
            category: "shell"
        },

        {
            id: "about",
            component: root.aboutPage,
            label: qsTr("About"),
            icon: "info",
            description: qsTr("System information, credits"),
            category: "about"
        },
    ]

    readonly property Component appearancePage: Component {
        StackPage {
            Component {
                WallpaperAndStyle {}
            }
            Component {
                WallpaperSelect {}
            }
            Component {
                WallpaperCategory {}
            }
            Component {
                ColourSelect {}
            }
        }
    }

    readonly property Component displayPage: Component {
        DisplayPage {}
    }

    readonly property Component networkPage: Component {
        StackPage {
            Component {
                NetworkPage {}
            }
            Component {
                EthernetDetailPage {}
            }
        }
    }

    readonly property Component bluetoothPage: Component {
        StackPage {
            Component {
                BluetoothPage {}
            }
            Component {
                BtDeviceInfo {}
            }
            Component {
                BluetoothPairing {}
            }
        }
    }

    readonly property Component audioPage: Component {
        StackPage {
            Component {
                AudioPage {}
            }
            Component {
                AppVolumes {}
            }
        }
    }

    readonly property Component guixPage: Component {
        GuixPage {}
    }

    readonly property Component panelsPage: Component {
        StackPage {
            Component {
                PanelsPage {}
            }
            Component {
                DashboardPanel {}
            }
            Component {
                TaskbarPanel {}
            }
            Component {
                LauncherPanel {}
            }
            Component {
                SidebarPanel {}
            }

            Component {
                BarWorkspaces {}
            }
            Component {
                BarActiveWindow {}
            }
            Component {
                BarTray {}
            }
            Component {
                BarStatusIcons {}
            }
            Component {
                BarClock {}
            }
        }
    }

    readonly property Component appsPage: Component {
        StackPage {
            Component {
                AppsPage {}
            }
            Component {
                AllApps {}
            }
            Component {
                AppInfo {}
            }
        }
    }

    readonly property Component servicesPage: Component {
        StackPage {
            Component {
                ServicesPage {}
            }
            Component {
                NotificationsPage {}
            }
        }
    }

    readonly property Component languagePage: Component {
        StackPage {
            Component {
                LanguageAndRegion {}
            }
        }
    }

    readonly property Component aboutPage: Component {
        StackPage {
            Component {
                AboutPage {}
            }
        }
    }
}
