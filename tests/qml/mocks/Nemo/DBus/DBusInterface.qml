// Test double for the launcher QML tests (copied from asteroid-settings tests/mocks; see tests/qml/tst_quickpanel.qml)
// Nemo.DBus' DBusInterface: records each call in Backend.calls (target the
// service, method "interface.method", args the plain values) and answers
// with Backend.replies["interface.method"], or calls the error callback when
// Backend.errors["interface.method"] is set
import QtQuick
import LauncherTest

QtObject {
    id: self
    property int bus
    property string service
    property string path
    property string iface
    property bool signalsEnabled: false
    // Like Nemo.DBus: while signals are enabled the object takes the bus signals of its service and
    // interface, and calls the handler named "rc" + the signal name (Backend.emitSignal plays the bus).
    // A function with any other name is never called.
    onSignalsEnabledChanged: signalsEnabled ? Backend.listen(self) : Backend.unlisten(self)
    Component.onCompleted: if (signalsEnabled) Backend.listen(self)
    Component.onDestruction: Backend.unlisten(self)
    function typedCall(method, args, callback, errorCallback) {
        var plain = []
        if (args)
            for (var i = 0; i < args.length; i++)
                plain.push(args[i] !== null && typeof args[i] === "object" && args[i].hasOwnProperty("value") ? args[i].value : args[i])
        Backend.record(service, iface + "." + method, plain)
        var error = Backend.errors ? Backend.errors[iface + "." + method] : undefined
        if (error !== undefined) {
            if (errorCallback)
                errorCallback(error, "")
            return
        }
        var reply = Backend.replies[iface + "." + method]
        if (callback)
            callback(reply === undefined ? true : reply)
    }
    function call(method, args, callback, errorCallback) {
        typedCall(method, args, callback, errorCallback)
    }
}
