// Test double for the launcher QML tests: the alarms of timed that every AlarmsModel lists. A test sets
// alarms to plain objects with an alarm object's fields (id, hour, minute, second, daysOfWeek, enabled,
// countdown, triggerTime in s, elapsed); each change is a model reset.
pragma Singleton
import QtQuick

QtObject {
    property var alarms: []
}
