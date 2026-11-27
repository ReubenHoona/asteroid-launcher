// Test double for asteroid-sensorlogd's WorkoutLoader (qmlplugin/workoutLoader.h) on SensorlogdFixture's rows: the same
// selection as the plugin's (workouts(from, to): the local days [from, to], newest first; last(): the newest that
// ended of the newest two)
import QtQuick

QtObject {
    signal dataChanged()
    readonly property int seq: 0
    function workouts(from, to) {
        SensorlogdFixture.reads++
        var a = new Date(from.getFullYear(), from.getMonth(), from.getDate()).getTime()
        var b = new Date(to.getFullYear(), to.getMonth(), to.getDate() + 1).getTime()
        return SensorlogdFixture.sorted().filter(function (w) { return w.startMs >= a && w.startMs < b })
    }
    function recent(n) {
        SensorlogdFixture.reads++
        return SensorlogdFixture.sorted().slice(0, n)
    }
    function last() {
        SensorlogdFixture.reads++
        var l = SensorlogdFixture.sorted().slice(0, 2)
        for (var i = 0; i < l.length; i++)
            if (l[i].ended !== false)
                return l[i]
        return {}
    }
    property Connections _c: Connections {
        target: SensorlogdFixture
        function onChangedSignal() { dataChanged() }
    }
    Component.onCompleted: SensorlogdFixture.alive++
    Component.onDestruction: SensorlogdFixture.alive--
}
