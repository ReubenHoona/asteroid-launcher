// Test double for the launcher QML tests: the alarms of timed that every AlarmsModel lists. A test sets
// alarms to plain objects with an alarm object's fields (id, hour, minute, second, daysOfWeek, enabled,
// countdown, triggerTime in s, elapsed); each change is a model reset.
// creatable: AlarmsModel.createAlarm() gives an alarm object whose save() adds it to `alarms` (a countdown
// that is enabled gets its triggerTime, as nemo's) and whose deleteAlarm() takes it out (default off: no
// test starts a timer by accident).
pragma Singleton
import QtQuick

QtObject {
    property var alarms: []
    property bool creatable: false
    property int lastId: 1000

    function save(a) {
        if (a.countdown && a.enabled && !(a.triggerTime > 0))
            a.triggerTime = Math.floor(Date.now() / 1000) + a.hour * 3600 + a.minute * 60 + a.second
        var list = alarms.slice()
        if (list.indexOf(a) < 0)
            list.push(a)
        alarms = list
    }
    function remove(a) {
        alarms = alarms.filter(function (x) { return x !== a && x.id !== a.id })
    }
    // a plain alarm object as a test writes one, with save() and deleteAlarm()
    function make(fields) {
        var a = { id: ++lastId, hour: 0, minute: 0, second: 0, daysOfWeek: "", enabled: false, countdown: false,
                  triggerTime: 0, elapsed: 0, title: "" }
        for (var k in fields)
            a[k] = fields[k]
        a.save = function () { save(a) }
        a.deleteAlarm = function () { remove(a) }
        return a
    }
}
