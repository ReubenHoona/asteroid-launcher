// Test double for the launcher QML tests (copied from asteroid-settings tests/mocks; see tests/qml/tst_quickpanel.qml)
// Nemo.DBus' DBusInterface: records each call in Backend.calls (target the
// service, method "interface.method", args the plain values) and answers
// with Backend.replies["interface.method"]
import QtQuick
import LauncherTest

QtObject {
    property int bus
    property string service
    property string path
    property string iface
    property bool signalsEnabled: false
    function typedCall(method, args, callback, errorCallback) {
        var plain = []
        if (args)
            for (var i = 0; i < args.length; i++)
                plain.push(args[i] !== null && typeof args[i] === "object" && args[i].hasOwnProperty("value") ? args[i].value : args[i])
        Backend.record(service, iface + "." + method, plain)
        var reply = Backend.replies[iface + "." + method]
        if (callback)
            callback(reply === undefined ? true : reply)
    }
    function call(method, args, callback, errorCallback) {
        typedCall(method, args, callback, errorCallback)
    }
}
