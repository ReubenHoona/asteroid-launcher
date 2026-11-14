/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls

/* The time of the setup (setup-wizard-04), when the phone did not set the clock: the stock style time
 * picker (W1-qa-pickers), 12 hour or 24 hour as the time format setting says (12 hour is the default here),
 * and its own confirm button. `hour` and `minute` start the columns; `picked` carries the choice. */
Item {
    id: page
    objectName: "setupTime"

    property int hour: 12
    property int minute: 0
    signal picked(int hour, int minute)

    readonly property alias picker: picker

    // a start that changes after the page was made (the pickers read it at their start)
    onHourChanged: picker.setTime(hour, minute, 0, false)
    onMinuteChanged: picker.setTime(hour, minute, 0, false)

    Rectangle {
        anchors.fill: parent
        color: Theme.color.background
    }

    TimePicker {
        id: picker
        objectName: "setupTimePicker"
        anchors.fill: parent
        hour: page.hour
        minute: page.minute
        onConfirmed: (h, m, s) => page.picked(h, m)
    }
}
