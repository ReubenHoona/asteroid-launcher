/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "../desktop.js" as Desktop

/*
 * The editing screen of the Assistant tile (AssistantTileEditingActivity.java:
 * 201-226, VALUES.tsv assistant tile_edit_*): "Create your own" with a mic
 * and a keyboard button, "Or choose an action below" and the suggestions
 * (Set a 5 minute timer, Set an alarm for 7 am, Send a message, What's on my
 * calendar?). A choice calls adder(text) -> { ok, reason }: "Added" (the
 * confirmation) and the screen closes, or "Chip already exists" and it stays.
 *
 * It covers the tile it belongs to; a stock Activity closes on a back swipe,
 * which a tile cannot take (the carousel owns the swipe), so the end of the
 * list has an edge button "Done"; the tile also closes it when it leaves the
 * screen.
 */
Item {
    id: editor

    // the suggestion texts (the tile's translated strings)
    property var offers: []
    // function(text) -> { ok, reason }
    property var adder: null
    readonly property alias list: list
    readonly property alias confirmation: confirmation
    readonly property alias keyboardLoader: keyboardLoader

    signal closed()

    // layout, px (tile_editing_*: 34 dp vertical padding at the top)
    readonly property real sideMargin: Theme.dp(10)
    readonly property real topPad: Theme.dp(34)
    readonly property real itemGap: Theme.dp(4)
    readonly property real chipHeight: Theme.dp(52)
    readonly property color chipBackground: "#303133"

    function choose(text) {
        if (!adder)
            return
        var r = adder(text)
        if (r.ok) {
            // "Added": the confirmation, then the screen goes
            //% "Added"
            confirmation.show(qsTrId("id-tile-asst-added"), true)
        } else if (r.reason === "exists") {
            //% "Chip already exists"
            confirmation.show(qsTrId("id-tile-asst-exists"), false)
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "#000000"
    }
    // nothing under it takes a touch
    MouseArea { anchors.fill: parent }

    Flickable {
        id: list
        objectName: "assistantEditorList"
        anchors.fill: parent
        topMargin: editor.topPad
        bottomMargin: done.contentPadding
        contentWidth: width
        contentHeight: column.height
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: column
            x: editor.sideMargin
            width: list.width - 2 * editor.sideMargin
            spacing: editor.itemGap

            Label {
                objectName: "editorCreate"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                //% "Create your own"
                text: qsTrId("id-tile-asst-create") + localeManager.changesObserver
                role: "titleSmall"
                color: Theme.color.onSurface
                maximumLineCount: 1
            }

            // the voice and the keyboard way in
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.dp(4)
                Repeater {
                    model: [{ name: "voice", icon: "ios-mic" }, { name: "keyboard", icon: "ios-keypad" }]
                    delegate: TileCard {
                        objectName: "editorInput_" + modelData.name
                        width: editor.chipHeight
                        height: editor.chipHeight
                        containerColor: editor.chipBackground
                        contentColor: "#ffffff"
                        opensCarouselEditor: false
                        accessibleName: modelData.name
                        onClicked: editor.openInput(modelData.name)
                        Icon {
                            anchors.centerIn: parent
                            width: Theme.dp(24)
                            height: width
                            name: modelData.icon
                            color: "#ffffff"
                        }
                    }
                }
            }

            Label {
                objectName: "editorChoose"
                width: parent.width
                topPadding: Theme.dp(4)
                horizontalAlignment: Text.AlignHCenter
                //% "Or choose an action below"
                text: qsTrId("id-tile-asst-choose") + localeManager.changesObserver
                role: "labelSmall"
                color: Theme.color.onSurfaceVariant
                maximumLineCount: 2
            }

            Repeater {
                model: editor.offers
                delegate: TileCard {
                    objectName: "editorOffer" + index
                    width: column.width
                    height: editor.chipHeight
                    containerColor: editor.chipBackground
                    contentColor: "#ffffff"
                    opensCarouselEditor: false
                    accessibleName: modelData
                    onClicked: editor.choose(modelData)
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        x: Theme.dp(14)
                        width: parent.width - 2 * Theme.dp(14)
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        role: "labelMedium"
                        font.weight: Font.Medium
                        color: "#ffffff"
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                    }
                }
            }
        }
    }

    EdgeButton {
        id: done
        objectName: "editorDone"
        flickable: list
        preferredHeight: Theme.size.edgeButtonExtraSmall
        //% "Done"
        text: qsTrId("id-tile-asst-done") + localeManager.changesObserver
        onClicked: editor.closed()
    }

    // ---- "Create your own": the keyboard, or the voice page of it ---------
    function openInput(kind) {
        keyboardLoader.mode = kind
        keyboardLoader.active = true
    }

    Loader {
        id: keyboardLoader
        objectName: "editorKeyboard"
        property string mode: "keyboard"
        anchors.fill: parent
        z: 5
        active: false
        sourceComponent: Component {
            WearKeyboard {
                id: keyboard
                actionKey: "done"
                emojiEnabled: false
                inputMethodHints: Qt.ImhNone
                startPage: keyboardLoader.mode === "voice" ? "voice" : ""
                onAccepted: (text) => {
                    keyboardLoader.active = false
                    editor.choose(String(text))
                }
                onDismissed: keyboardLoader.active = false
                Component.onCompleted: {
                    Desktop.keyboard = keyboard
                    forceActiveFocus()
                }
                Component.onDestruction: if (Desktop.keyboard === keyboard) Desktop.keyboard = null
            }
        }
    }

    Confirmation {
        id: confirmation
        objectName: "editorConfirmation"
        z: 8
        // "Added" closes the screen once it has been seen
        property bool wasAdded: false
        onFinished: if (type === "success") editor.closed()
    }
}
