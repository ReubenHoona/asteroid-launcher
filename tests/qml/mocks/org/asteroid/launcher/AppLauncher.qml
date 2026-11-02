// Test double for the launcher QML tests: an app started, recorded in Backend.calls
import QtQuick
import LauncherTest
QtObject {
    function launchApp(name) { Backend.record("launcher", "launchApp", [name]) }
}
