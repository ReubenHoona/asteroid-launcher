// Test double for the launcher QML tests (copied from asteroid-settings tests/mocks; see tests/qml/tst_quickpanel.qml)
import QtQuick
import LauncherTest
QtObject {
    id: vc
    property int volume: Backend.volume
    onVolumeChanged: if (volume !== Backend.volume) {
        Backend.volume = volume
        Backend.record("pulse", "MainVolume2.CurrentStep", [volume])
    }
    property Connections _sync: Connections {
        target: Backend
        function onVolumeChanged() { if (vc.volume !== Backend.volume) vc.volume = Backend.volume }
    }
}
