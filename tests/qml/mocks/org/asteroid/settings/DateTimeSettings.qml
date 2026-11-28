// Test double for the launcher QML tests (C-23, tst_setupupdate.qml): qml-asteroid's DateTimeSettings as the setup
// (firstrun/FirstRunConfig.qml) uses it: the zone (Backend.timezone), setTime and setDate (recorded)
import QtQuick
import LauncherTest
QtObject {
    function currentTimezone() { return Backend.timezone }
    function setTime(hour, minute) { Backend.record("timedate", "setTime", [hour, minute]) }
    function setDate(date) { Backend.record("timedate", "setDate", [date]) }
}
