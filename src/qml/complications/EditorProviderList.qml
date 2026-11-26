/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "faceeditor.js" as FE

/*
 * The complication provider chooser of stock's editor (ProviderChooserFragment,
 * face-interaction-27): a list titled "Complications", "Empty" first and then the
 * data sources alphabetically by name, a chip each with the source's icon, its
 * name and a second line with the app that provides it. It opens scrolled to the
 * source in the slot; there is no check mark. Choosing a source goes back to the
 * complications page (the editor does that on `chosen`). World clock, Countdown to
 * date and App shortcut are listed too: `chosen` gives their kind and the editor
 * opens their second page (watchface-catalogue-20, -21).
 */
EditorSheet {
    id: chooser

    // the home screen's ComplicationSources: all, name(id), info(id)
    property QtObject sources: null
    // the sources in the order shown, and the app names (id -> text)
    property var order: []
    property var appNames: ({})
    // the source in the slot being edited
    property string currentSource: "empty"
    // a source was tapped
    signal chosen(string source)

    model: order

    function refresh() {
        if (!sources) {
            order = []
            return
        }
        order = FE.chooserOrder(sources.all.concat(sources.parameterised), function (id) { return sources.name(id) })
    }
    function openFor(source) {
        refresh()
        currentSource = source
        open(FE.chooserIndex(order, source))
    }

    rowDelegate: Component {
        ListItem {
            id: row
            objectName: "eosEditorProviderRow"
            property int index: 0
            property var modelData: ""
            readonly property string source: String(modelData)
            title: chooser.sources && source !== "" ? chooser.sources.name(source) + localeManager.changesObserver : ""
            iconName: source === "empty" ? "ios-remove-circle-outline"
                                         : (chooser.sources && source !== "" ? chooser.sources.info(source).icon : "")
            Binding {
                target: row.button
                property: "secondaryText"
                value: source === "empty" || source === "" ? "" : String(chooser.appNames[FE.appOf(source)] || "")
            }
            onClicked: chooser.chosen(source)
        }
    }
}
