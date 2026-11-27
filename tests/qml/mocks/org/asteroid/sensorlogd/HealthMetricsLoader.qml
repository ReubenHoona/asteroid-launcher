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
    function daily(date) { return ({}) }
    property Connections _c: Connections {
        target: SensorlogdFixture
        function onChangedSignal() { dataChanged() }
    }
    Component.onCompleted: SensorlogdFixture.alive++
    Component.onDestruction: SensorlogdFixture.alive--
}
