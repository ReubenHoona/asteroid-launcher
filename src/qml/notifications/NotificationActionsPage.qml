/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import org.asteroid.launcher

/*
 * The actions panel of the AsteroidOS layout's notification strip (NotificationsPanel,
 * the cell under a notification's view): the same content as an open card of the Wear
 * layout (NotificationActions: reply row, replies, the app's actions, Open on phone) on
 * a page of its own, with its own keyboard layers and result dialogs. The Wear layout's
 * stream does not use it.
 */
Item {
    id: page

    property QtObject panelsGrid
    property QtObject notification
    property QtObject notificationModel

    property bool forbidLeft:  true
    property bool forbidRight: true
    property bool forbidBottom: false

    property string timestampStr: ""

    // the keyboard on top covers the whole screen
    readonly property bool fullScreenLayer: layerStack.currentLayer ? layerStack.currentLayer.fullScreen === true : false

    NotificationRemote {
        id: transport
        anchors.fill: parent
        z: 100
        isActive: function (id) { return page.notification !== null && page.notification !== undefined }
    }

    function updateTimestamp() {
        if (!notification)
            return
        var delta = (new Date().getTime() - notification.timestamp.getTime())
        if (delta < 60 * 1000) {
            //% "Now"
            timestampStr = qsTrId("id-now") + localeManager.changesObserver
        } else {
            delta = parseInt(delta / (1000 * 60))
            if (delta < 60) {
                //% "m"
                timestampStr = delta + qsTrId("id-minute-abbrev") + localeManager.changesObserver
            } else {
                delta = parseInt(delta / 60)
                if (delta < 24) {
                    //% "h"
                    timestampStr = delta + qsTrId("id-hour-abbrev") + localeManager.changesObserver
                } else {
                    delta = parseInt(delta / 24)
                    //% "d"
                    timestampStr = delta + qsTrId("id-day-abbrev") + localeManager.changesObserver
                }
            }
        }
    }
    onNotificationChanged: updateTimestamp()

    Connections {
        target: panelsGrid
        function onCurrentHorizontalPosChanged() {
            // Not when the panels were only renumbered around this one
            if (page.forbidBottom && !panelsGrid.following)
                layerStack.pop(layerStack.currentLayer)
            page.updateTimestamp()
        }
    }

    LayerStack {
        id: layerStack
        win: null
        firstPage: actionsComponent
        onLayersChanged: {
            page.forbidBottom = layers.length > 0
            leftIndicator.visible = layers.length > 0
            leftIndicator.animateFar()
            if (panelsGrid !== null)
                panelsGrid.changeAllowedDirections()
        }
    }

    Component {
        id: actionsComponent

        Item {
            Flickable {
                id: flick
                anchors.fill: parent
                contentHeight: Math.max(height, content.y + content.height + Dims.h(18))
                interactive: contentHeight > height + 1
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.DragOverBounds

                NotificationActions {
                    id: content
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.max(Dims.h(14), (flick.height - height) / 2)
                    width: Dims.w(76)
                    notification: page.notification
                    remote: transport
                    layerHost: layerStack
                }
            }
        }
    }

    Row {
        visible: layerStack.layers.length === 0
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Dims.h(3)
        anchors.horizontalCenter: parent.horizontalCenter

        Icon {
            name: {
                if (!page.notification)
                    return ""
                function noicon(str) { return str === "" || str === null || str === undefined }
                // icon for asteroid internal, appIcon for notifications from android
                if (noicon(page.notification.icon) && noicon(page.notification.appIcon))
                    return "ios-mail-outline"
                if (noicon(page.notification.icon))
                    return page.notification.appIcon
                return page.notification.icon
            }
            height: timestamp.height
            width: height
        }

        Label {
            id: timestamp
            color: "#b0b0b0"
            text: page.timestampStr
            font.pixelSize: Theme.type.bodySmall.pixelSize
        }
    }

    Indicator { id: leftIndicator; edge: Qt.LeftEdge }
}
