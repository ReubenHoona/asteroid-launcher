/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "faceeditor.js" as FE

/*
 * An "Other options" page of the face editor, as stock's (fragment_bool_type.xml,
 * editor_transparent_chip.xml, face-interaction-23): up to three transparent
 * toggle chips, centred vertically, at least 48 dp (96 px) tall, 12 dp from each
 * side, two lines at most, over the face. No title. Spoken "<name> On" or
 * "<name> Off".
 */
Item {
    id: page

    // the settings on this page: [{id, label, value}], at most three
    property var settings: []
    property bool active: true

    // a chip was toggled
    signal toggled(string id, bool value)

    readonly property real dp: Theme.dp(1)
    readonly property alias chips: column

    Column {
        id: column
        objectName: "eosEditorBoolColumn"
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width

        Repeater {
            model: page.settings
            delegate: SwitchButton {
                id: chip
                objectName: "eosEditorToggle"
                readonly property var setting: modelData
                x: FE.BOOL_MARGIN_DP * page.dp
                width: column.width - 2 * FE.BOOL_MARGIN_DP * page.dp
                minimumHeight: FE.BOOL_CHIP_HEIGHT_DP * page.dp
                maximumLineCount: 2
                text: setting.label
                checked: setting.value === true
                // transparent, whether on or off (WearChipButtonTransparent)
                containerColor: "transparent"
                enabled: page.active
                //% "%1 On"
                readonly property string onText: qsTrId("id-face-toggle-on") + localeManager.changesObserver
                //% "%1 Off"
                readonly property string offText: qsTrId("id-face-toggle-off") + localeManager.changesObserver
                Accessible.name: (checked ? onText : offText).replace("%1", setting.label)
                onToggled: (value) => page.toggled(setting.id, value)
            }
        }
    }
}
