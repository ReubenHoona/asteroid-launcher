/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import "facekit.js" as Kit

/*
 * A run of digits in the face's two weights (watchface-catalogue-25): the
 * interactive weight (Light, Bold Time Medium) and the always-on weight (Thin,
 * Bold Time Light), cross-faded by `blend` (stock changes the weight of one
 * variable font; the image has static Roboto weights, so two layers fade). The
 * always-on layer carries the sensor hub's name (hubName: "eosHubHour",
 * "eosHubMinute", or "" for the colon): it is the item the hub draws from, in
 * Roboto (tabular digits) with NativeRendering, in the colour and opacity it
 * has when the face is always-on.
 */
Item {
    id: num

    property string text: ""
    property string hubName: ""
    property real pixelSize: 112        // px on this screen
    property bool bold: false
    property color color: "white"
    property color ambientColor: "#b3b3b3"
    property real blend: 0
    // the weights of the two layers (a face whose always-on look is its awake one gives the same twice)
    property int liveWeight: Kit.weight(bold, false)
    property int ambientWeight: Kit.weight(bold, true)
    property string family: Kit.FONT
    property int horizontalAlignment: Text.AlignHCenter

    implicitWidth: ambientText.implicitWidth
    implicitHeight: ambientText.implicitHeight
    width: implicitWidth
    height: implicitHeight

    readonly property Item interactiveItem: liveText
    readonly property Item ambientItem: ambientText

    Text {
        id: liveText
        objectName: ""
        anchors.horizontalCenter: parent.horizontalCenter
        visible: num.blend < 1
        opacity: 1 - num.blend
        text: num.text
        color: num.color
        renderType: Text.NativeRendering
        font.family: num.family
        font.pixelSize: Math.round(num.pixelSize)
        font.weight: num.liveWeight
    }
    Text {
        id: ambientText
        objectName: num.hubName
        anchors.horizontalCenter: parent.horizontalCenter
        visible: num.blend > 0
        opacity: num.blend
        text: num.text
        color: num.ambientColor
        renderType: Text.NativeRendering
        font.family: num.family
        font.pixelSize: Math.round(num.pixelSize)
        font.weight: num.ambientWeight
    }
}
