// Test double of Nemo.Alarms' AlarmsModel for the launcher QML tests (the tiles): rowCount(), index() and
// data(index, role) give AlarmsMock's alarms (only the countdowns with onlyCountdown); createAlarm() gives
// nothing unless AlarmsMock.creatable (then an alarm object that save() adds), so no test starts a timer
// by accident.
import QtQuick

QtObject {
    id: model
    property bool onlyCountdown: false
    property bool populated: true
    readonly property var rows: AlarmsMock.alarms.filter(function (a) { return model.onlyCountdown ? a.countdown === true : true })
    signal rowsInserted(var parent, int first, int last)
    signal rowsRemoved(var parent, int first, int last)
    signal dataChanged()
    signal modelReset()
    onRowsChanged: modelReset()
    function rowCount() { return rows.length }
    function index(row, column) { return row }
    function data(index, role) { return rows[index] }
    function createAlarm() { return AlarmsMock.creatable ? AlarmsMock.make({}) : null }
}
