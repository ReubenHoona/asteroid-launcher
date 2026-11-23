// Test double for org.nemomobile.lipstick's Lipstick singleton: the compositor's
// display signals, and the notification list model made last (the view's own)
pragma Singleton
import QtQuick

QtObject {
    property QtObject compositor: QtObject {
        property int screenOrientation: 1
        property bool displayAmbient: false
        property bool displayDimmed: false
        signal displayOff()
        signal displayOn()
        signal displayAboutToBeOn()
        signal displayAboutToBeOff()
        signal displayAmbientUpdate()
    }
    property var notificationModel: null
}
