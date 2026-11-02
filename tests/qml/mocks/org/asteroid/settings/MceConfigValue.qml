// Test double for the launcher QML tests (copied from asteroid-settings tests/mocks; see tests/qml/tst_quickpanel.qml)
// the Settings app's MceConfigValue on Backend.mce
import QtQuick
import LauncherTest
QtObject {
    id: mv
    property string key
    property var value
    readonly property bool valid: Backend.mce.hasOwnProperty(key)
    property bool _sync: false
    function _load() { _sync = true; value = Backend.mce[key]; _sync = false }
    onKeyChanged: _load()
    onValueChanged: if (!_sync) Backend.mceSet(key, value)
    property Connections _watch: Connections {
        target: Backend
        function onMceWritten(k) { if (k === mv.key) mv._load() }
    }
}
