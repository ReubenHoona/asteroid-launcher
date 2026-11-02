// Test double for the launcher QML tests (copied from asteroid-settings tests/mocks; see tests/qml/tst_quickpanel.qml)
import QtQuick
import LauncherTest
QtObject {
    enum Type { None, USB, DCP, HVDCP, CDP, Wireless, Other }
    readonly property bool valid: true
    readonly property int type: Backend.chargerType
}
