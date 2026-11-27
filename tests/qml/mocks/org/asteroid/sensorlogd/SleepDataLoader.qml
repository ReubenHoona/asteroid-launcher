// Test double for asteroid-sensorlogd's SleepDataLoader: SensorlogdFixture.night (none by default: the Sleep tile's
// empty card); dataChanged with the fixture's changed()
import QtQuick

QtObject {
    signal dataChanged()
    function lastNight() { return SensorlogdFixture.night }
    property Connections _c: Connections {
        target: SensorlogdFixture
        function onChangedSignal() { dataChanged() }
    }
}
