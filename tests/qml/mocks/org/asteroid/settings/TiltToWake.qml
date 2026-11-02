// Test double for the launcher QML tests (copied from asteroid-settings tests/mocks; see tests/qml/tst_quickpanel.qml)
import QtQuick
import LauncherTest
QtObject {
    id: tw
    property bool enabled: Backend.tilt
    readonly property bool available: Backend.tiltAvailable
    onEnabledChanged: if (enabled !== Backend.tilt) {
        Backend.tilt = enabled
        Backend.record("mce", "wrist_sensor_enabled", [enabled])
    }
    property Connections _sync: Connections {
        target: Backend
        function onTiltChanged() { if (tw.enabled !== Backend.tilt) tw.enabled = Backend.tilt }
    }
}
