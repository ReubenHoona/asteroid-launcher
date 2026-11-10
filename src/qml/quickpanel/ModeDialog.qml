/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls

/*
 * The stock quick settings' question before a mode comes on (SysUI's
 * Do Not Disturb, Bedtime, Theater and Battery Saver dialogs): a title, a
 * message, "Don't show again" and the round ✕ and ✓ of Wear Material, over
 * the whole screen; taps outside the buttons do nothing.
 *
 *   modeDialog.ask(title, message, function (dontShowAgain) { ... })
 */
Item {
    id: dialog

    property string title: ""
    property string message: ""
    property bool dontShowAgain: false
    property var _accept: null
    readonly property bool shown: visible

    anchors.fill: parent
    visible: false
    opacity: 0
    z: 900

    function ask(title, message, onAccept) {
        dialog.title = title || ""
        dialog.message = message || ""
        dontShowAgain = false
        _accept = onAccept || null
        visible = true
        flick.contentY = 0
        fadeIn.restart()
    }
    function accept() {
        var f = _accept
        var dont = dontShowAgain
        close()
        if (f)
            f(dont)
    }
    function close() {
        _accept = null
        visible = false
        opacity = 0
    }

    NumberAnimation { id: fadeIn; target: dialog; property: "opacity"; from: 0; to: 1; duration: 150 }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
    }
    // every touch is the dialog's while it is up (no swipe to another panel)
    MouseArea {
        anchors.fill: parent
        preventStealing: true
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: Math.max(height, content.height + Dims.h(24))
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.DragOverBounds

        Column {
            id: content
            y: Math.max(Dims.h(14), (flick.height - height) / 2)
            anchors.horizontalCenter: parent.horizontalCenter
            width: Dims.w(76)
            spacing: Dims.h(3)
            Label {
                objectName: "modeDialogTitle"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                clip: false
                text: dialog.title
                font.pixelSize: Dims.l(7.4)
                font.styleName: "SemiCondensed Medium"
            }
            Label {
                objectName: "modeDialogMessage"
                visible: text !== ""
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                clip: false
                color: Theme.color.onSurfaceVariant
                text: dialog.message
                font.pixelSize: Dims.l(6.2)
            }
            // Wear Material's check box row
            MouseArea {
                id: dont
                objectName: "modeDialogDontShow"
                anchors.horizontalCenter: parent.horizontalCenter
                width: dontRow.width + Dims.w(6)
                height: Dims.h(12)
                onClicked: dialog.dontShowAgain = !dialog.dontShowAgain
                Row {
                    id: dontRow
                    anchors.centerIn: parent
                    spacing: Dims.w(3)
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Dims.l(6.2)
                        height: width
                        radius: Dims.l(1.2)
                        color: dialog.dontShowAgain ? Theme.color.primary : "transparent"
                        border.width: dialog.dontShowAgain ? 0 : Math.max(1, Dims.l(0.6))
                        border.color: Theme.color.outline
                        Icon {
                            anchors.centerIn: parent
                            visible: dialog.dontShowAgain
                            width: parent.width * 0.9
                            height: width
                            name: "ios-checkmark"
                            color: Theme.color.onPrimary
                        }
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        //% "Don't show again"
                        text: qsTrId("id-dont-show-again")
                        font.pixelSize: Dims.l(6.2)
                    }
                }
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Dims.w(6)

                MouseArea {
                    id: no
                    objectName: "modeDialogNo"
                    width: Dims.l(19)
                    height: width
                    onClicked: dialog.close()
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: no.pressed ? Qt.tint(Theme.color.surfaceContainer, Qt.alpha(Theme.color.onSurface, Theme.alpha.pressed)) : Theme.color.surfaceContainer
                    }
                    Icon {
                        anchors.centerIn: parent
                        width: parent.width * 0.5
                        height: width
                        name: "ios-close"
                    }
                }
                MouseArea {
                    id: yes
                    objectName: "modeDialogYes"
                    width: Dims.l(19)
                    height: width
                    onClicked: dialog.accept()
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: yes.pressed ? Theme.color.primaryDim : Theme.color.primary
                    }
                    Icon {
                        anchors.centerIn: parent
                        width: parent.width * 0.5
                        height: width
                        name: "ios-checkmark"
                        color: Theme.color.onPrimary
                    }
                }
            }
        }
    }
}
