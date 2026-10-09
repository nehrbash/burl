import QtQuick

QtObject {
    property string currentName
    property bool hasCurrent
    property int workspaceId: -1
    // Opened deliberately (keyboard / click) rather than by hover, so it must
    // survive the pointer leaving the shell window
    property bool pinned

    // Popout contents only ever see this state object, not the Wrapper, so
    // dismissing from inside a popout has to go through here. Wrapper.close()
    // delegates and additionally drops any detached mode.
    function close(): void {
        hasCurrent = false;
        pinned = false;
    }

    signal detachRequested(mode: string)
}
