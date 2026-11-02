// Test double for the launcher QML tests: ngfd feedback, recorded in Backend.calls
import QtQuick
import LauncherTest
QtObject {
    property string event
    function play() { Backend.record("ngfd", event, []) }
    function stop() {}
}
