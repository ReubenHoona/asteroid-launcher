/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls

/* The date of the setup (setup-wizard-04), when the phone did not set the clock: the stock style date picker
 * (W1-qa-pickers) with its Next and confirm buttons. `date` starts the columns; `picked` carries the choice. */
Item {
    id: page
    objectName: "setupDate"

    property date date: new Date()
    signal picked(int year, int month, int day)

    readonly property alias picker: picker

    // a start that changes after the page was made (the picker reads it at its start)
    onDateChanged: picker.setDate(date, false)

    Rectangle {
        anchors.fill: parent
        color: Theme.color.background
    }

    DatePicker {
        id: picker
        objectName: "setupDatePicker"
        anchors.fill: parent
        date: page.date
        onConfirmed: (y, m, d) => page.picked(y, m, d)
    }
}
