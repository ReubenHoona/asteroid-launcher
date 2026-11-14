/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls

/*
 * The options of a list setting, opened by a tap on the page's chip (stock
 * fragment_list_options.xml): the setting's name as the header, a chip per
 * option, no check mark. A tap picks the option and goes back to the page.
 */
EditorSheet {
    id: sheet

    // the option names, in the order of the setting's values
    property var labels: []
    // an option was tapped
    signal picked(int index)

    model: labels.length
    rowDelegate: Component {
        ListItem {
            property int index: 0
            title: index < sheet.labels.length ? String(sheet.labels[index]) : ""
            onClicked: {
                sheet.picked(index)
                sheet.closeNow()
            }
        }
    }
}
