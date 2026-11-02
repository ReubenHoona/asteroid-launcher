// Test double for the launcher QML tests (copied from asteroid-settings tests/mocks; see tests/qml/tst_quickpanel.qml)
import QtQuick
import LauncherTest
QtObject {
    id: bs
    property bool powered: Backend.btPowered
    readonly property bool connected: Backend.btConnected && Backend.btPowered
    onPoweredChanged: if (powered !== Backend.btPowered) {
        Backend.btPowered = powered
        Backend.record("bluez", "Adapter1.Powered", [powered])
    }
    property Connections _sync: Connections {
        target: Backend
        function onBtPoweredChanged() { if (bs.powered !== Backend.btPowered) bs.powered = Backend.btPowered }
    }
}
