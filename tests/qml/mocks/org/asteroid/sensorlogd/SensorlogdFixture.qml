// Test double for the launcher QML tests: the data every org.asteroid.sensorlogd double reads (M4 WO-10). A test sets
// `workouts` (WorkoutLoader rows: id, startMs, endMs, activeS, type, distanceM, kcal, azm, ended, ...; any order) and
// `summaries` ({ "YYYY-MM-DD": HealthMetricsLoader.summary() map }), then calls changed() as sensorlogd's HealthChanged
// would; the counters say how many loaders live and how often they were read
pragma Singleton
import QtQuick

QtObject {
    property var workouts: []
    property var summaries: ({})
    // R5 E-09: { "YYYY-MM-DD": HealthMetricsLoader.cardioLoad() map }
    property var cardio: ({})
    property int alive: 0
    property int reads: 0
    signal changedSignal()
    function changed() { changedSignal() }
    function reset() {
        workouts = []
        summaries = ({})
        cardio = ({})
        reads = 0
    }
    function dayKey(d) {
        return d.getFullYear() + "-" + (d.getMonth() < 9 ? "0" : "") + (d.getMonth() + 1) + "-" + (d.getDate() < 10 ? "0" : "") + d.getDate()
    }
    // newest first, as health.db's readers (deleted rows are not there)
    function sorted() {
        return workouts.filter(function (w) { return w.deleted !== true }).sort(function (a, b) { return b.startMs - a.startMs })
    }
}
