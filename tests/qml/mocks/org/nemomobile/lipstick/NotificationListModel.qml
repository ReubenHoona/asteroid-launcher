// Test double for org.nemomobile.lipstick's NotificationListModel: the test adds
// and removes notifications (objects with replacesId, summary, body, hints,
// timestamp and actionInvoked()) and says when the model is populated, as
// lipstick does after restoring its stored notifications at start
import QtQuick
import org.nemomobile.lipstick

QtObject {
    id: model
    property bool populated: false
    property var items: []
    readonly property int itemCount: items.length
    signal itemAdded(QtObject item)
    signal itemRemoved(QtObject item)

    function get(i) { return items[i] }
    // newest first, as lipstick sorts
    function add(n) {
        var l = items.slice()
        l.unshift(n)
        items = l
        itemAdded(n)
    }
    function remove(n) {
        var l = items.slice()
        var i = l.indexOf(n)
        if (i < 0)
            return
        l.splice(i, 1)
        items = l
        itemRemoved(n)
    }
    Component.onCompleted: Lipstick.notificationModel = model
}
