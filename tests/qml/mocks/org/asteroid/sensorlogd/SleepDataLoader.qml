// Test double for asteroid-sensorlogd's SleepDataLoader: no night (the Sleep tile's empty card)
import QtQuick

QtObject {
    signal dataChanged()
    function lastNight() { return ({}) }
}
