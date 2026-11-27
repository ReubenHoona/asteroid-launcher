// Test double for asteroid-sensorlogd's HealthMetricsLoader (qmlplugin/healthMetricsLoader.h): a day's summary from
// SensorlogdFixture.summaries ({} for a day without one)
import QtQuick

QtObject {
    signal dataChanged()
    readonly property int stepGoal: 10000
    readonly property int azmWeeklyGoal: 150
    function summary(date) {
        SensorlogdFixture.reads++
        var s = SensorlogdFixture.summaries[SensorlogdFixture.dayKey(date)]
        return s ? s : ({})
    }
    function restingHrOf(date) { return -1 }
    // R5 E-09: SensorlogdFixture.cardio's map of the day, else no load and no target yet
    function cardioLoad(date) {
        SensorlogdFixture.reads++
        var c = SensorlogdFixture.cardio[SensorlogdFixture.dayKey(date)]
        return c ? c : ({ load: 0, hasTarget: false, low: 0, high: 0, daysLeft: 7, state: "", week: [] })
    }
    function daily(date) { return ({}) }
    property Connections _c: Connections {
        target: SensorlogdFixture
        function onChangedSignal() { dataChanged() }
    }
    Component.onCompleted: SensorlogdFixture.alive++
    Component.onDestruction: SensorlogdFixture.alive--
}
