/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls

/*
 * The in-call keypad (calls-11): the digits typed on one line at the top
 * (the start is elided when they run long), 12 keys of 44 x 36 dp between
 * the guides at 15.6 % and 84.3 % of the width, the first row 9.38 % of
 * the height below the top (fragment_incall_keypad_responsive.xml,
 * keypad_shared_view_responsive.xml, VALUES.tsv dialpad_button_width 44dp,
 * dialpad_button_height 36dp). A key sends its tone (DTMF); a swipe right
 * closes the keypad.
 */
Item {
    id: pad
    objectName: "inCallKeypad"
    anchors.fill: parent

    // The digits sent so far
    property string digits: ""
    signal tone(string key)
    signal closeRequested()

    readonly property real keyWidth: Theme.dp(44)
    readonly property real keyHeight: Theme.dp(36)
    readonly property real leftGuide: 0.156 * width
    readonly property real rightGuide: 0.843 * width
    readonly property var keys: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"]

    BackSwipeArea {
        id: swipe
        anchors.fill: parent
        onFinished: {
            var go = committed
            reset()
            if (go)
                pad.closeRequested()
        }

        Item {
            width: parent.width
            height: parent.height
            x: swipe.value

            Rectangle {
                anchors.fill: parent
                color: "#000000"
            }

            Label {
                id: typed
                objectName: "keypadDigits"
                x: pad.leftGuide
                y: Math.round(0.0938 * pad.height)
                width: pad.rightGuide - pad.leftGuide
                horizontalAlignment: Text.AlignHCenter
                role: "titleMedium"
                elide: Text.ElideLeft
                maximumLineCount: 1
                text: pad.digits
            }

            Grid {
                id: grid
                columns: 3
                x: pad.leftGuide
                y: typed.y + Theme.type.titleMedium.lineHeight
                columnSpacing: Math.max(0, ((pad.rightGuide - pad.leftGuide) - 3 * pad.keyWidth) / 2)
                rowSpacing: 0

                Repeater {
                    model: pad.keys
                    delegate: Button {
                        objectName: "key" + modelData
                        width: pad.keyWidth
                        height: pad.keyHeight
                        minimumHeight: pad.keyHeight
                        variant: "tonal"
                        centered: true
                        horizontalPadding: 0
                        verticalPadding: 0
                        text: modelData
                        labelRole: "labelLarge"
                        onClicked: {
                            pad.digits += modelData
                            pad.tone(modelData)
                        }
                    }
                }
            }
        }
    }
}
