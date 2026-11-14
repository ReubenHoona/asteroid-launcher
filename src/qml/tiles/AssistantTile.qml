/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import org.asteroid.controls
import "../desktop.js" as Desktop
import "tileactions.js" as Actions

/*
 * The Assistant tile, as stock's (AssistantTileEditingActivity.java:201-226,
 * qva.java, VALUES.tsv assistant tile_*): no title, the user's action chips
 * (each runs its query), then the mic at the bottom centre. With no action
 * one chip, "Tap to add new Assistant actions" with a plus, opens the
 * editing screen (AssistantTileEditor): "Create your own" (mic or
 * keyboard) and "Or choose an action below".
 *
 * Chip: filled #303133 (tile_chip_background, a fixed colour of the stock
 * tile, not of the colour theme), a stadium at least 52 dp tall, text 15 sp
 * white up to two lines, a 24 dp icon 12 dp from the left with the text 42
 * dp from the left, 14 dp padding on the right, 4 dp between chips; at most
 * two chips fill the slot. The mic is the edge button (an icon variant).
 *
 * The chips are dconf /org/asteroidos/assistant/tile-actions (a string list;
 * unset = the three chips the tile always had). A new action goes first, so
 * it shows. A long press on a chip opens the editing screen; a long press
 * on empty black opens the carousel's editor, as on every tile.
 */
TileBase {
    id: tile
    // no title: stock's tile is chips and a mic (screenshot_tile.png)
    title: ""
    backgroundTap: false
    chipIcon: "ios-mic"
    onChipClicked: if (Desktop.compositorRoot) Desktop.compositorRoot.openAssistant("")

    ConfigurationValue { id: stored; key: "/org/asteroidos/assistant/tile-actions"; defaultValue: ["@default"] }

    function loc(id, en) {
        var s = qsTrId(id)
        return (s === id || s === "") ? en : s
    }
    // the chips of an untouched tile (and their icons)
    readonly property var suggestions: [
        { text: loc("id-tile-asst-weather", "What's the weather?"), icon: "ios-cloudy-outline" },
        { text: loc("id-tile-asst-timer", "Set a timer for 5 minutes"), icon: "ios-timer-outline" },
        { text: loc("id-tile-asst-alarm", "When is my next alarm?"), icon: "ios-alarm-outline" }
    ]
    readonly property var defaultTexts: suggestions.map(function (s) { return s.text })
    // what the stock editing screen offers and our assistant can do (tile_chip_suggestion_array)
    readonly property var offers: [
        //% "Set a 5 minute timer"
        qsTrId("id-tile-offer-timer"),
        //% "Set an alarm for 7 am"
        qsTrId("id-tile-offer-alarm"),
        //% "Send a message"
        qsTrId("id-tile-offer-message"),
        //% "What’s on my calendar?"
        qsTrId("id-tile-offer-calendar")
    ]
    readonly property var actions: Actions.parse(stored.value, defaultTexts)
    readonly property var chips: Actions.shown(actions)
    readonly property bool editing: editor.active

    // the stock sizes (VALUES.tsv assistant), px
    readonly property color chipBackground: "#303133"
    readonly property real chipMinHeight: Theme.dp(52)
    readonly property real chipIconSize: Theme.dp(24)
    readonly property real chipIconLeft: Theme.dp(12)
    readonly property real chipTextLeft: Theme.dp(42)
    readonly property real chipRight: Theme.dp(14)
    readonly property real chipGap: Theme.dp(4)

    function run(text) {
        if (Desktop.compositorRoot)
            Desktop.compositorRoot.openAssistant(text)
    }

    function add(text) {
        var r = Actions.add(actions, text)
        if (r.ok)
            stored.value = Actions.toStore(r.list)
        return r
    }

    // the editing screen goes when the tile leaves the screen
    onLiveChanged: if (!live) editor.close()

    // ---- the chips -------------------------------------------------------
    Item {
        id: chipArea
        objectName: "assistantChips"
        anchors.fill: parent

        readonly property int count: Math.max(1, tile.chips.length)
        readonly property real chipHeight: Math.min(Theme.dp(52), (height - (count - 1) * tile.chipGap) / count)

        Repeater {
            model: tile.chips.length > 0 ? tile.chips : [""]
            delegate: TileCard {
                id: chip
                objectName: "assistantChip" + index
                readonly property bool addChip: modelData === ""
                readonly property string icon: addChip ? "ios-add" : Actions.iconFor(modelData, tile.suggestions)
                width: chipArea.width
                height: chipArea.chipHeight
                y: (chipArea.height - (chipArea.count * chipArea.chipHeight + (chipArea.count - 1) * tile.chipGap)) / 2
                   + index * (chipArea.chipHeight + tile.chipGap)
                containerColor: tile.chipBackground
                contentColor: "#ffffff"
                opensCarouselEditor: false
                accessibleName: label.text
                onClicked: addChip ? editor.open() : tile.run(modelData)
                onLongPressed: editor.open()

                Icon {
                    id: glyph
                    visible: chip.icon !== ""
                    x: tile.chipIconLeft
                    anchors.verticalCenter: parent.verticalCenter
                    width: tile.chipIconSize
                    height: width
                    name: chip.icon
                    color: "#ffffff"
                }
                Label {
                    id: label
                    objectName: "assistantChipText"
                    readonly property real leftPad: glyph.visible ? tile.chipTextLeft : tile.chipRight
                    x: leftPad
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - leftPad - tile.chipRight
                    horizontalAlignment: glyph.visible ? Text.AlignLeft : Text.AlignHCenter
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    //% "Tap to add new Assistant actions"
                    text: chip.addChip ? qsTrId("id-tile-asst-add") + localeManager.changesObserver : modelData
                    // 15 sp, white (tile_chip_text_size, tile_chip_primary_text_color)
                    role: "labelMedium"
                    font.weight: Font.Medium
                    color: "#ffffff"
                }
            }
        }
    }

    // ---- the editing screen ----------------------------------------------
    // covers the tile; the mic and the chips are under it
    Loader {
        id: editor
        objectName: "assistantEditor"
        parent: tile
        z: 20
        anchors.fill: parent
        active: false
        function open() { active = true }
        function close() { active = false }
        sourceComponent: AssistantTileEditor {
            offers: tile.offers
            adder: tile.add
            onClosed: editor.close()
        }
    }
}
