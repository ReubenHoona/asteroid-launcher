// Test double for the launcher QML tests (copied from asteroid-settings tests/mocks; see tests/qml/tst_quickpanel.qml)
import QtQuick
import LauncherTest
QtObject {
    id: nt
    property string path
    property bool powered: Backend.wifiPowered
    readonly property bool connected: Backend.wifiConnected
    onPoweredChanged: if (powered !== Backend.wifiPowered) {
        Backend.wifiPowered = powered
        Backend.record("connman", "wifi.Powered", [powered])
    }
    property Connections _sync: Connections {
        target: Backend
        function onWifiPoweredChanged() { if (nt.powered !== Backend.wifiPowered) nt.powered = Backend.wifiPowered }
    }
}
