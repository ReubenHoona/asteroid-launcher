/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Qt5Compat.GraphicalEffects
import Nemo.DBus
import org.asteroid.controls
import org.nemomobile.lipstick

/*
 * The picture of a notification from the phone, as Wear OS shows the picture
 * of a message: the whole width, the picture's own aspect, rounded corners, a
 * placeholder of its size while it loads. asteroid-btsyncd names the file in
 * the hint x-asteroid-picture (there, or still on its way from the phone) and
 * its size in x-asteroid-picture-size ("WxH"), and says on the session bus
 * when it arrives or will not (PictureChanged, PictureState).
 *   maxHeight  a taller picture is cropped to it (cards, the heads-up); the
 *              full view shows the whole picture
 *   showError  when it will not come: Wear OS's "Can't display image" (the
 *              full view) instead of nothing (cards, the heads-up)
 *   tappable   a tap on it says tapped() (the full view opens it full screen)
 * Nothing of it on the always-on display (the space stays).
 */
Item {
    id: pic

    property QtObject notification
    property real maxHeight: width * 2
    property real radius: Dims.l(8)
    property bool showError: false
    // a tap on it opens it (the full view); elsewhere the tap is the card's
    property bool tappable: false
    // 0 on its way, 1 shown, 2 will not come
    property int pictureState: 0
    // a new load of the same file (the file arrived after a failed load)
    property int attempt: 0

    signal tapped()

    readonly property string path: {
        var h = notification && notification.hints ? notification.hints["x-asteroid-picture"] : undefined
        return h ? String(h) : ""
    }
    // height / width: of the picture once loaded, else of the size the phone said
    readonly property real hintAspect: {
        var h = notification && notification.hints ? notification.hints["x-asteroid-picture-size"] : undefined
        var m = h ? String(h).match(/^(\d+)x(\d+)$/) : null
        return m && Number(m[1]) > 0 && Number(m[2]) > 0 ? Number(m[2]) / Number(m[1]) : 0
    }
    readonly property real aspect: image.status === Image.Ready && image.implicitWidth > 0
                                   ? image.implicitHeight / image.implicitWidth
                                   : (hintAspect > 0 ? hintAspect : 0.75)
    readonly property bool wanted: path !== ""
    readonly property bool failed: pictureState === 2
    readonly property bool ambient: Lipstick.compositor.displayAmbient

    visible: wanted && (!failed || showError)
    height: !visible ? 0 : failed ? errorColumn.height : Math.round(Math.min(maxHeight, width * aspect))

    onPathChanged: {
        pictureState = 0
        attempt = 0
    }

    // asteroid-btsyncd's word on the picture (also called by the tests)
    function pictureChanged(changedPath, available) {
        if (changedPath !== pic.path || pictureState === 1)
            return
        if (available) {
            pictureState = 0
            attempt++
        } else {
            pictureState = 2
        }
    }

    // The file did not load: on its way, or not to be had
    function askState() {
        if (!busLoader.item)
            return
        busLoader.item.typedCall("PictureState", [{ "type": "s", "value": pic.path }], function (state) {
            if (state === 1 && pic.attempt < 3)
                pic.attempt++        // it arrived in the meantime
            else if (state === 2 || state === 1)
                pic.pictureState = 2
        }, function () { pic.pictureState = 2 })
    }

    Loader {
        id: busLoader
        active: pic.wanted
        sourceComponent: DBusInterface {
            bus: DBus.SessionBus
            service: "org.asteroidos.btsyncd"
            path: "/org/asteroidos/btsyncd/notifications"
            iface: "org.asteroidos.btsyncd.Notifications"
            signalsEnabled: pic.pictureState !== 1
            function rcPictureChanged(path: string, available: bool) { pic.pictureChanged(path, available) }
        }
    }

    // The placeholder: the picture's size, dim (Wear OS: "Loading Image")
    Rectangle {
        anchors.fill: parent
        visible: pic.wanted && pic.pictureState === 0 && !pic.ambient
        radius: pic.radius
        color: "#1affffff"
        Icon {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height) * 0.3
            height: width
            name: "ios-image-outline"
            opacity: 0.35
        }
    }

    Item {
        id: frame
        anchors.fill: parent
        visible: pic.pictureState === 1 && !pic.ambient
        layer.enabled: visible
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: frame.width
                height: frame.height
                radius: pic.radius
            }
        }

        Image {
            id: image
            anchors.fill: parent
            source: pic.path !== "" ? "file://" + pic.path + (pic.attempt > 0 ? "?" + pic.attempt : "") : ""
            asynchronous: true
            cache: false
            fillMode: Image.PreserveAspectCrop
            onStatusChanged: {
                if (status === Image.Ready)
                    pic.pictureState = 1
                else if (status === Image.Error && pic.pictureState !== 2)
                    pic.askState()
            }
        }
    }

    // Wear OS's load error: an icon and "Can't display image"
    Column {
        id: errorColumn
        width: parent.width
        visible: pic.failed && pic.showError && !pic.ambient
        spacing: Dims.h(1)
        topPadding: Dims.h(2)
        bottomPadding: Dims.h(2)
        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Dims.l(10)
            height: width
            name: "ios-image-outline"
            opacity: 0.6
        }
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            //% "Can't display image"
            text: qsTrId("id-picture-error") + localeManager.changesObserver
            opacity: 0.6
            font.pixelSize: Dims.l(5.2)
        }
    }

    TapHandler {
        enabled: pic.tappable && pic.pictureState === 1
        onTapped: pic.tapped()
    }
}
