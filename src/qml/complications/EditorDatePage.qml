/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "faceeditor.js" as FE

/*
 * The second page of "Countdown to date" (watchface-catalogue-20): the system date
 * picker (DatePicker, the Wear OS Material 3 one of Settings' Set date: Day, Month,
 * Year, Next then Confirm), opened on the slot's day or today. Confirm gives the full
 * source ("countdown:2026-12-25"); the editor stores it and goes back to the
 * complications page. A swipe right from the left edge goes back to the chooser. The picker is made
 * when the page opens and goes when it closes (nothing runs while it is hidden).
 */
Item {
    id: page

    property bool shown: false
    // the day the picker opens on
    property date date: new Date()
    readonly property alias picker: pickerLoader.item

    // Confirm: the full source id
    signal picked(string value)
    // the page went back (swipe right)
    signal backRequested()
    // a touch (the editor's idle timer restarts)
    signal poked()

    anchors.fill: parent
    visible: shown

    function open(day) {
        date = day
        shown = true
    }
    function closeNow() {
        shown = false
    }
    function back() {
        if (!shown)
            return
        closeNow()
        backRequested()
    }

    Rectangle { anchors.fill: parent; color: "#000000" }
    // nothing under the page takes a touch
    MouseArea {
        anchors.fill: parent
        enabled: page.shown
        onPressed: page.poked()
    }

    Loader {
        id: pickerLoader
        anchors.fill: parent
        active: page.shown
        sourceComponent: DatePicker {
            objectName: "eosEditorDatePicker"
            date: page.date
            onConfirmed: (year, month, day) => page.picked(FE.countdownParam(year, month, day))
        }
    }

    // swipe right from the left edge: back (the system's edge, DeviceSpecs.borderGestureWidth
    // 0.1, as an app's BorderGestureArea; the picker's columns take the drags elsewhere), with
    // the stock decision rule of the back swipe (EditorSheet)
    Item {
        id: edge
        objectName: "eosEditorDateEdge"
        width: Math.round(page.width * 0.1)
        height: page.height
        enabled: page.shown
        DragHandler {
            target: null
            yAxis.enabled: false
            grabPermissions: PointerHandler.CanTakeOverFromAnything
            property real lastDx: 0
            property real dx: 0
            property real v: 0
            onTranslationChanged: {
                lastDx = translation.x - dx
                dx = translation.x
                v = centroid.velocity.x
            }
            onActiveChanged: {
                if (active) {
                    dx = 0
                    lastDx = 0
                    v = 0
                    page.poked()
                } else if (Motion.backShouldCommit(dx, v, lastDx, page.width, Theme.dp(1))) {
                    page.back()
                }
            }
        }
    }
}
