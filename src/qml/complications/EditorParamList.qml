/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls

/*
 * The second page of a complication that needs a choice first (watchface-catalogue-20,
 * -21): the World clock's time zones (UTC offsets) or the App shortcut's apps, as a
 * list of chips like the provider chooser it opens from (titled with the source's
 * name, opened scrolled to the current choice). A tap gives the full source
 * ("worldclock:+0530", "app:asteroid-music"); the editor stores it and goes back to
 * the complications page. A swipe right goes back to the chooser.
 * rows: [{ value, title, icon, secondary }] (faceeditor.js worldClockRows, appRows).
 */
EditorSheet {
    id: params

    // a row was tapped: its full source id
    signal picked(string value)

    rowDelegate: Component {
        ListItem {
            id: row
            objectName: "eosEditorParamRow"
            property int index: 0
            property var modelData: ({})
            readonly property string value: modelData && modelData.value !== undefined ? String(modelData.value) : ""
            title: modelData && modelData.title !== undefined ? String(modelData.title) : ""
            iconName: modelData && modelData.icon !== undefined ? String(modelData.icon) : ""
            Binding {
                target: row.button
                property: "secondaryText"
                value: row.modelData && row.modelData.secondary !== undefined ? String(row.modelData.secondary) : ""
            }
            onClicked: params.picked(value)
        }
    }
}
