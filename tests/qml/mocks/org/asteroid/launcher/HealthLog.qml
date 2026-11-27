// Test double for the launcher QML tests: src/healthlog.h (asteroid-sensorlogd's log), no data
import QtQuick
QtObject {
    property string sensor
    property int buckets: 1
    property bool active: false
    property int windowMinutes: 0
    readonly property bool hasData: false
    readonly property int lastValue: 0
    readonly property var lastTime: null
    readonly property int minValue: 0
    readonly property int maxValue: 0
    readonly property var values: []
    readonly property var lows: []
    readonly property var highs: []
    signal changed()
}
