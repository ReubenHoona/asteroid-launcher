// Test double for org.nemomobile.lipstick's Lipstick singleton: the compositor's
// display signals, and the notification list model made last (the view's own)
pragma Singleton
import QtQuick

QtObject {
    property QtObject compositor: QtObject {
        property int screenOrientation: 1
        signal displayOff()
        signal displayOn()
    }
    property var notificationModel: null
}
