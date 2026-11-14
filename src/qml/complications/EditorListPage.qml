/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "faceeditor.js" as FE

/*
 * A list setting page of the face editor, as stock's (fragment_list_type.xml,
 * face-interaction-22): nothing but a small chip at the bottom with the name
 * of the current option (20 dp tall, 10 dp side padding, 12 dp text, 29 dp
 * above the bottom, up to 140 dp wide; a name wider than 120 dp scrolls once
 * after 2 s), the face behind. The crown steps through the options, one per
 * detent: the page carries a transparent vertical ListView of one 96 px item
 * per option that is the crown's target (RotaryInput steps a view that
 * enforces its highlight range, with the crown haptic of a step and the limit
 * bump at the ends, as in every list), and a selector on the right edge shows
 * the position. A tap on the chip opens the list of the options.
 */
Item {
    id: page

    // the setting: its spoken name, the option values and their names
    property string settingName: ""
    property var values: []
    property var labels: []
    property string current: ""
    // this page is the one on screen
    property bool active: true

    // an option was chosen with the crown (or a list)
    signal picked(string value)
    // the chip was tapped
    signal openOptions()
    // the crown moved: restart the editor's idle timer
    signal poked()

    readonly property real dp: Theme.dp(1)
    readonly property int index: Math.max(0, values.indexOf(current))
    readonly property string currentLabel: index < labels.length ? String(labels[index]) : ""
    readonly property Item stepper: steps
    readonly property Item chip: chipBox
    readonly property Item selector: selectorItem
    readonly property real step: Theme.dp(FE.STEP_PX / 2)

    // the crown's target: one transparent item per option
    ListView {
        id: steps
        objectName: "eosEditorSteps"
        anchors.fill: parent
        orientation: ListView.Vertical
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: (height - page.step) / 2
        preferredHighlightEnd: (height + page.step) / 2
        highlightMoveDuration: 200
        boundsBehavior: Flickable.StopAtBounds
        interactive: page.active && page.values.length > 1
        model: page.values.length
        delegate: Item { width: steps.width; height: page.step }
        onCurrentIndexChanged: {
            if (currentIndex === page.index || currentIndex < 0 || currentIndex >= page.values.length)
                return
            page.poked()
            page.picked(String(page.values[currentIndex]))
        }
    }
    // the stepper is for the crown only: a finger on it moves nothing (the pager above takes the swipes)
    MouseArea { anchors.fill: parent }
    onIndexChanged: if (steps.currentIndex !== index) steps.currentIndex = index
    onValuesChanged: syncSteps()
    Component.onCompleted: syncSteps()
    function syncSteps() {
        steps.currentIndex = index
        steps.positionViewAtIndex(index, ListView.Center)
    }

    // the option on the right edge
    EditorSelector {
        id: selectorItem
        objectName: "eosEditorSelector"
        count: page.values.length
        index: page.index
    }

    // the chip with the current option
    Item {
        id: chipBox
        objectName: "eosEditorChip"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: FE.CHIP_BOTTOM_DP * page.dp
        height: FE.CHIP_HEIGHT_DP * page.dp
        width: FE.chipWidth(label.implicitWidth, page.dp)
        Accessible.role: Accessible.Button
        Accessible.name: page.settingName + ": " + page.currentLabel

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Theme.color.surfaceContainer
        }
        Item {
            id: clipBox
            anchors.fill: parent
            anchors.leftMargin: FE.CHIP_PADDING_DP * page.dp
            anchors.rightMargin: FE.CHIP_PADDING_DP * page.dp
            clip: true
            Label {
                id: label
                objectName: "eosEditorChipText"
                readonly property bool marquee: FE.needsMarquee(implicitWidth, page.dp)
                property real scrolled: 0
                // short names sit in the middle; a long one starts at the left and scrolls
                x: marquee ? scrolled : (parent.width - width) / 2
                anchors.verticalCenter: parent.verticalCenter
                text: page.currentLabel
                font.pixelSize: FE.CHIP_TEXT_DP * page.dp
                font.weight: Font.Medium
                color: Theme.color.onSurface
                wrapMode: Text.NoWrap
                maximumLineCount: 1
                onTextChanged: chipBox.restartMarquee()
                onMarqueeChanged: chipBox.restartMarquee()
            }
        }
        function restartMarquee() {
            slide.stop()
            label.scrolled = 0
            if (label.marquee && page.active)
                slide.restart()
        }
        // after 2 s the text scrolls once to its end, at 30 dp/s (a TextView marquee)
        SequentialAnimation {
            id: slide
            objectName: "eosEditorMarquee"
            PauseAnimation { duration: Motion.duration(FE.MARQUEE_DELAY_MS) }
            NumberAnimation {
                target: label; property: "scrolled"
                to: -FE.marqueeDistance(label.implicitWidth, page.dp)
                duration: Motion.duration(FE.marqueeDistance(label.implicitWidth, page.dp) / (30 * page.dp) * 1000)
            }
        }
        Connections {
            target: page
            function onActiveChanged() { chipBox.restartMarquee() }
        }
    }
    // the tap target: 50 dp tall and 22 dp wider each side than the chip
    MouseArea {
        id: chipTap
        objectName: "eosEditorChipTap"
        anchors.centerIn: chipBox
        width: chipBox.width + 2 * FE.CHIP_TAP_PAD_DP * page.dp
        height: FE.CHIP_TAP_HEIGHT_DP * page.dp
        enabled: page.active && page.values.length > 1
        onClicked: page.openOptions()
    }
}
