// Test double for the launcher QML tests (copied from asteroid-settings tests/mocks; see tests/qml/tst_quickpanel.qml)
import QtQuick
import LauncherTest
QtObject {
    enum State { Unknown, Charging, Discharging, NotCharging, Full }
    readonly property bool valid: true
    readonly property int value: Backend.batteryState
    // the real type's change signal of value is stateChanged (ComplicationSources)
    signal stateChanged()
    onValueChanged: stateChanged()
}
