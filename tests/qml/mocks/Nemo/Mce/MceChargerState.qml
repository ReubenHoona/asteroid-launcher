// Test double for the launcher QML tests: charging while Backend.batteryState is Charging (MceBatteryState)
import QtQuick
import LauncherTest
QtObject {
    readonly property bool valid: true
    readonly property bool charging: Backend.batteryState === 1
}
