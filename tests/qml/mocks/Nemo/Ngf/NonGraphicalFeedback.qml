// Test double for the launcher QML tests: ngfd feedback, recorded in Backend.calls (target "ngfd", method the
// event, args [the request's properties]: Nemo.Ngf's list of NgfProperty as a name -> value map, {} for none)
import QtQuick
import LauncherTest
QtObject {
    property string event
    property list<QtObject> properties
    function play() {
        var p = {}
        for (var i = 0; i < properties.length; i++)
            p[properties[i].name] = properties[i].value
        Backend.record("ngfd", event, [p])
    }
    function stop() {}
}
