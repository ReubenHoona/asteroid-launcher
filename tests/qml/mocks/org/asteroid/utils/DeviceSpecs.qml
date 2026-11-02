// Test double for the launcher QML tests (copied from asteroid-settings tests/mocks; see tests/qml/tst_quickpanel.qml)
// org.asteroid.utils' DeviceSpecs as eos' machine.conf says
pragma Singleton
import QtQuick
QtObject {
    readonly property bool hasRoundScreen: true
    readonly property real borderGestureWidth: 0.1
    readonly property int flatTireHeight: 0
    readonly property bool needsBurnInProtection: true
    readonly property bool hasWlan: true
    readonly property bool hasSpeaker: true
    readonly property string hostname: "asteroid"
    readonly property string machineName: "eos"
    readonly property string buildID: "20261102035103"
}
