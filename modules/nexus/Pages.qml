import QtQuick
import Burl.Config
import qs.components
import qs.modules.nexus

Item {
    id: root

    required property NexusState nState

    property int lastPageIdx
    property int animOff
    property Item currentItem
    property int requestGeneration: 0
    property bool disposing: false

    function loadPage(id: string): void {
        const generation = ++requestGeneration;
        if (currentItem) {
            currentItem.destroy();
            currentItem = null;
        }

        const comp = PageRegistry.page(id).component;
        const incubator = comp.incubateObject(container, {
            nState,
            visible: false
        });

        const finish = status => {
            if (status === Component.Ready) {
                if (root.disposing || generation !== root.requestGeneration) {
                    incubator.object.destroy();
                    return;
                }
                incubator.object.anchors.fill = container;
                incubator.object.visible = true;
                root.currentItem = incubator.object;
            } else if (status === Component.Error) {
                console.warn("Nexus: failed to load page", id);
            }
        };

        if (incubator.status === Component.Loading)
            incubator.onStatusChanged = finish;
        else
            finish(incubator.status);
    }

    Component.onDestruction: {
        disposing = true;
        requestGeneration++;
    }

    Item {
        id: container

        objectName: "PageContainer"
        anchors.fill: parent
        layer.enabled: opacity < 1
        Component.onCompleted: root.loadPage(root.nState.currentPageId)
    }

    Connections {
        function onCurrentPageIdChanged(): void {
            root.requestGeneration++;
            switchAnim.stop();
            root.animOff = root.Tokens.padding.extraLarge * (PageRegistry.indexOf(root.nState.currentPageId) > root.lastPageIdx ? 1 : -1);
            switchAnim.start();
            root.lastPageIdx = PageRegistry.indexOf(root.nState.currentPageId);
        }

        target: root.nState
    }

    SequentialAnimation {
        id: switchAnim

        Anim {
            target: container
            property: "opacity"
            to: 0
            type: Anim.DefaultEffects
        }
        ScriptAction {
            script: root.loadPage(root.nState.currentPageId)
        }
        PropertyAction {
            target: container.anchors
            property: "topMargin"
            value: root.animOff
        }
        PropertyAction {
            target: container.anchors
            property: "bottomMargin"
            value: -root.animOff
        }
        ParallelAnimation {
            Anim {
                target: container
                property: "opacity"
                from: 0
                to: 1
                type: Anim.SlowEffects
            }
            Anim {
                target: container.anchors
                properties: "topMargin,bottomMargin"
                to: 0
                type: Anim.SlowEffects
            }
        }
    }
}
