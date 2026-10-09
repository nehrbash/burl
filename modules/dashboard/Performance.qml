import "performance"
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import Burl.Config
import Burl.Services
import qs.components
import qs.components.containers
import qs.services

Item {
    id: root

    // Living-tree mode: every card here is already a BarkCard, like Dash, so the
    // per-file work is the same two moves as Dash: widen the gutters and force
    // each card opaque. The placeholder — the one bit of loose text outside a
    // card — grows its own plate.
    // `clusterCells` is the twig-placement contract: declared here, additive-only,
    // with no consumer yet, so a future living-tree renderer can split this row
    // into per-widget twigs off BOUGH.performance without further changes.
    property bool living: false
    readonly property var clusterCells: [
        {
            item: cpuCard,
            weight: 2
        },
        {
            item: gpuCard,
            weight: 2
        },
        {
            item: storageCard,
            weight: 1
        },
        {
            item: networkCard,
            weight: 1
        },
        {
            item: memoryCard,
            weight: 1
        },
        {
            item: batteryCard,
            weight: 1
        }
    ]

    implicitWidth: placeholder.active ? Tokens.sizes.dashboard.perfPlaceholderWidth : content.implicitWidth
    implicitHeight: placeholder.active ? placeholder.implicitHeight + Tokens.padding.extraLarge * 2 : content.implicitHeight

    Loader {
        id: placeholder

        anchors.centerIn: parent
        active: !Config.dashboard.performance.showCpu && !(Config.dashboard.performance.showGpu && Gpu.type !== Gpu.None) && !Config.dashboard.performance.showMemory && !Config.dashboard.performance.showStorage && !Config.dashboard.performance.showNetwork && !(UPower.displayDevice.isLaptopBattery && Config.dashboard.performance.showBattery)
        asynchronous: true

        // Living mode grows the placeholder a plate via a second sourceComponent,
        // rather than parameterising one BarkCard, since BarkCard's own `color`
        // binding would otherwise have to reference itself to go transparent.
        sourceComponent: root.living ? platedPlaceholder : barePlaceholder

        Component {
            id: barePlaceholder

            ColumnLayout {
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: "tune"
                    fontStyle: Tokens.font.icon.builders.extraLarge.scale(2).build()
                    color: Colours.palette.m3onSurfaceVariant
                }

                StyledText {
                    Layout.topMargin: -Tokens.spacing.small
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("No widgets enabled")
                    font: Tokens.font.title.large
                    color: Colours.palette.m3onSurface
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Enable widgets in the dashboard settings")
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }

        Component {
            id: platedPlaceholder

            BarkCard {
                id: platedPlaceholderCard

                implicitWidth: placeholderColumn.implicitWidth + Tokens.padding.extraLarge * 2
                implicitHeight: placeholderColumn.implicitHeight + Tokens.padding.extraLarge * 2
                radius: Tokens.rounding.extraLarge
                opaque: true
                grainSeed: 42

                ColumnLayout {
                    id: placeholderColumn

                    anchors.centerIn: parent
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "tune"
                        fontStyle: Tokens.font.icon.builders.extraLarge.scale(2).build()
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    StyledText {
                        Layout.topMargin: -Tokens.spacing.small
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("No widgets enabled")
                        font: Tokens.font.title.large
                        color: Colours.palette.m3onSurface
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Enable widgets in the dashboard settings")
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }
            }
        }
    }

    RowLayout {
        id: content

        anchors.left: parent.left
        anchors.right: parent.right
        spacing: root.living ? Tokens.spacing.extraLarge : Tokens.spacing.medium
        visible: !placeholder.active

        ColumnLayout {
            id: mainColumn

            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            RowLayout {
                spacing: Tokens.spacing.medium
                visible: cpuCard.active || gpuCard.active

                WrappedLoader {
                    id: cpuCard

                    active: Config.dashboard.performance.showCpu

                    sourceComponent: HeroCard {
                        icon: "memory"
                        label: qsTr("CPU")
                        subLabel: Cpu.name
                        usage: Cpu.percentage
                        temperature: Cpu.temperature
                        accent: Colours.palette.m3primary
                        // Only the leading hero wears moss; the GPU twin beside it
                        // stays bare so the pair does not read as wallpaper.
                        moss: true
                        // Distinct grain phase from the GPU twin: the two cards
                        // sit side by side at the same size, so a shared tile
                        // origin would make them one striped sheet.
                        grainSeed: 11
                        opaque: root.living

                        ServiceRef {
                            service: Cpu
                        }
                    }
                }

                WrappedLoader {
                    id: gpuCard

                    active: Config.dashboard.performance.showGpu && Gpu.type !== Gpu.None

                    sourceComponent: HeroCard {
                        icon: "desktop_windows"
                        label: qsTr("GPU")
                        subLabel: Gpu.name
                        usage: Gpu.percentage
                        temperature: Gpu.temperature
                        accent: Colours.palette.m3secondary
                        grainSeed: 12
                        opaque: root.living

                        ServiceRef {
                            service: Gpu
                        }
                    }
                }
            }

            RowLayout {
                spacing: Tokens.spacing.medium
                visible: storageCard.active || networkCard.active || memoryCard.active

                WrappedLoader {
                    id: storageCard

                    active: Config.dashboard.performance.showStorage
                    sourceComponent: StorageCard {
                        opaque: root.living
                    }
                }

                WrappedLoader {
                    id: networkCard

                    active: Config.dashboard.performance.showNetwork
                    sourceComponent: NetworkCard {
                        opaque: root.living
                    }
                }

                WrappedLoader {
                    id: memoryCard

                    active: Config.dashboard.performance.showMemory
                    sourceComponent: MemoryCard {
                        opaque: root.living
                    }
                }
            }
        }

        WrappedLoader {
            id: batteryCard

            Layout.fillWidth: false
            active: UPower.displayDevice.isLaptopBattery && Config.dashboard.performance.showBattery
            sourceComponent: BatteryTank {
                opaque: root.living
            }
        }
    }

    component WrappedLoader: Loader {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: active
    }
}
