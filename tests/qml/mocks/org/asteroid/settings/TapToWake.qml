// Test double for the launcher QML tests (copied from asteroid-settings tests/mocks; see tests/qml/tst_quickpanel.qml)
import QtQuick
import LauncherTest
QtObject {
    id: tp
    property bool enabled: Backend.tap
    onEnabledChanged: if (enabled !== Backend.tap) {
        Backend.tap = enabled
        Backend.record("mce", "actions_gesture4", [enabled ? "unblank" : ""])
    }
    property Connections _sync: Connections {
        target: Backend
        function onTapChanged() { if (tp.enabled !== Backend.tap) tp.enabled = Backend.tap }
    }
}
