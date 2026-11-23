// Test double of lipstick's Compositor element (the QML side of LipstickCompositor, the root
// of compositor/AppLifecycle.qml): the display and window signals, homeActive and windowForId.
// A test adds its fake windows to `windows` by id.
import QtQuick

QtObject {
    property bool homeActive: true
    property var windows: ({})
    signal displayOff()
    signal displayAboutToBeOn()
    signal displayOn()
    signal windowAdded(var window)
    signal windowRaised(var window)
    signal windowRemoved(var window)
    function windowForId(id) { return windows[id] || null }
}
