/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "setup.js" as Setup

/* How to pair (setup-wizard-02 c, -13): a scrolling column as stock's CompanionDetailsScreen, with
 * "On your phone, download & open:", the app's name, its icon (58 dp), "In the app, connect to", the
 * watch's Bluetooth name highlighted and the "Need help?" button. Sides 5.2 %, top 10 %, bottom 35.4 % of
 * the screen. There is no "Lock info" (stock's is about the phone's lock: out of reach here). */
Item {
    id: page
    objectName: "setupInstructions"

    property string appName: "Gadgetbridge"
    // the watch's Bluetooth name (what the phone app lists)
    property string watchName: ""
    signal needHelp()

    readonly property alias list: list
    readonly property var rows: ["download", "app", "icon", "connect", "name", "help"]

    Rectangle {
        anchors.fill: parent
        color: Theme.color.background
    }

    Component {
        id: textRow
        Label {
            property int index
            property var modelData
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            role: modelData === "app" ? "titleMedium" : "bodyMedium"
            color: Theme.color.onBackground
            text: modelData === "download"
                  //% "On your phone, download & open:"
                  ? qsTrId("id-setup-download-open") + localeManager.changesObserver
                  : (modelData === "app" ? page.appName
                                         //% "In the app, connect to"
                                         : qsTrId("id-setup-connect-to") + localeManager.changesObserver)
            objectName: "setupRow_" + modelData
        }
    }

    Component {
        id: iconRow
        Item {
            property int index
            property var modelData
            objectName: "setupRow_icon"
            height: Theme.dp(Setup.instructions.iconDp)
            Rectangle {
                id: appIcon
                objectName: "setupAppIcon"
                anchors.horizontalCenter: parent.horizontalCenter
                width: Theme.dp(Setup.instructions.iconDp)
                height: width
                radius: width * 0.28
                color: Theme.color.surfaceContainerHigh
                Icon {
                    anchors.centerIn: parent
                    width: parent.width * 0.6
                    height: width
                    name: "ios-watch"
                    color: Theme.color.primary
                }
            }
        }
    }

    Component {
        id: nameRow
        // the name, highlighted: primary on a tonal pill
        Item {
            property int index
            property var modelData
            objectName: "setupRow_name"
            height: nameLabel.height + Theme.dp(12)
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Theme.color.surfaceContainer
            }
            Label {
                id: nameLabel
                anchors.centerIn: parent
                width: parent.width - Theme.dp(24)
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1
                role: "titleMedium"
                color: Theme.color.primary
                text: page.watchName
                objectName: "setupWatchName"
            }
        }
    }

    Component {
        id: helpRow
        FilledTonalButton {
            property int index
            property var modelData
            objectName: "setupHelpButton"
            //% "Need help?"
            text: qsTrId("id-setup-need-help") + localeManager.changesObserver
            centered: true
            onClicked: page.needHelp()
        }
    }

    ScalingList {
        id: list
        objectName: "setupInstructionsList"
        anchors.fill: parent
        model: page.rows
        topMargin: Math.round(page.height * Setup.instructions.top)
        bottomMargin: Math.round(page.height * Setup.instructions.bottom)
        sideMargin: Math.round(page.width * Setup.instructions.side)
        spacing: Theme.dp(Setup.instructions.downloadGapDp)

        itemDelegate: Loader {
            property int index
            property var modelData
            sourceComponent: modelData === "icon" ? iconRow : (modelData === "name" ? nameRow
                             : (modelData === "help" ? helpRow : textRow))
            onLoaded: {
                item.modelData = Qt.binding(function () { return modelData })
                item.index = Qt.binding(function () { return index })
            }
        }
    }
}
