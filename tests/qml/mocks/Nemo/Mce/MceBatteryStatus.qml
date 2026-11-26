// Test double for the launcher QML tests: Full while Backend.batteryState is Full (MceBatteryState), else Ok
import QtQuick
import LauncherTest
QtObject {
    enum Status { Empty, Low, Ok, Full }
    readonly property bool valid: true
    readonly property int status: Backend.batteryState === 4 ? 3 : 2
}
