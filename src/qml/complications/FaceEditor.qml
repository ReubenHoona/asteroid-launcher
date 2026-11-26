/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import Nemo.KeepAlive
import org.asteroid.controls
import ".."
import "faceeditor.js" as FE
import "complications.js" as C

/*
 * The watch face editor, as stock Wear OS's (SysUI watchfaceeditor, W3-launcher-
 * face-editor): a full-screen layer over the face. It opens from the pencil chip
 * of the face picker; the picker under it hides itself 500 ms later, so leaving
 * shows the face. Layers, bottom to top: black, the face at full size, the bottom
 * fader (clear to 65.1 %, #a3000000 at 82.3 %, black at 100 %), a horizontal pager
 * (SnapOneItem, pages without titles) and the page dots. Pages, in stock's order:
 * a page per list setting (Always-on: Dimmed, Outline: EditorListPage), then
 * "Complications" when the face has slots (EditorSlotsPage with the provider
 * chooser, EditorProviderList), then "Other options" with the boolean settings
 * three to a page (EditorBoolPage: Date, Seconds).
 *
 * Changes apply at once: there is no Done or Save. The editor is left by the
 * crown button (back on the face from anywhere, as stock pops the whole stack),
 * by a swipe right on the first page, or after 15 s without a touch or a crown
 * turn; the choices are kept. The display is held on while the editor is open
 * (stock FLAG_KEEP_SCREEN_ON) and the editor closes when it goes dark. The page
 * it was left on is the page it opens on next time. The face is a favourite's own
 * (FaceStyle for the options, the favourite id as the complications' key).
 *
 * Battery (M1): no timer runs while the editor is hidden or a finger is down;
 * the pulse of the highlights runs only on the complications page with the
 * display on; nothing is polled.
 */
Item {
    id: editor
    objectName: "eosFaceEditor"
    anchors.fill: parent
    visible: shown

    // the favourites (FaceLayer's FaceFavourites), the face item on the home screen,
    // the home screen's ComplicationSources
    property QtObject store: null
    property Item face: null
    property QtObject sources: null
    // the display is on (not asleep, not the always-on screen)
    property bool awake: true

    // the favourite being edited: its id names the options (FaceStyle) and the complications' key
    readonly property string faceId: store ? store.currentId : ""
    readonly property string faceName: sources ? sources.faceName(faceId) : ""
    property bool shown: false
    // the page index of the last close (the next open starts there)
    property int lastPage: 0
    // a finger is down (the idle timer waits)
    property bool touching: false

    readonly property var slots: sources && face ? sources.slotsOf(face) : []
    readonly property bool hasSlots: slots.length > 0
    // a face with a schema (W3-launcher-faces: its eosOptions) has its own settings
    readonly property var schema: face && face.eosOptions !== undefined ? face.eosOptions : null
    readonly property var pageSpecs: schema ? FE.pages(FE.schemaLists(schema), FE.schemaBools(schema), hasSlots)
                                            : FE.pages(FE.LIST_SETTINGS, FE.BOOL_SETTINGS, hasSlots)
    readonly property int pageCount: pageSpecs.length
    readonly property int pageIndex: pager.currentIndex
    readonly property var pageKinds: pageSpecs.map(function (p) { return p.kind })
    readonly property bool choosing: chooser.shown
    // the second page of a source that needs a choice first is up (world clock, countdown, app)
    readonly property bool choosingValue: paramList.shown || datePage.shown
    readonly property bool listing: optionsList.shown
    readonly property Item pagerView: pager
    readonly property Item chooserSheet: chooser
    readonly property Item paramSheet: paramList
    readonly property Item dateSheet: datePage
    readonly property Item optionsSheet: optionsList
    readonly property Item dotsItem: pageDots
    readonly property Item faderItem: fader

    signal opened()
    signal closed()

    // what the crown steers: the open list, else the stepper of a list setting page; none on the
    // other pages (RotaryInput: a null target leaves the crown nothing to turn)
    property Item rotaryTarget: paramList.shown ? paramList.list
                                : datePage.shown ? (datePage.picker ? datePage.picker.rotaryTarget : null)
                                : chooser.shown ? chooser.list : (optionsList.shown ? optionsList.list
                                : (pager.currentItem ? pager.currentItem.stepper : null))

    // ---- the options of the favourite (applied at once: FaceLayer reads them) -------------
    FaceStyle {
        id: style
        faceId: editor.faceId
        schema: editor.schema ? editor.schema : []
    }
    readonly property var ambientLabels: [
        //% "Dimmed"
        qsTrId("id-face-ambient-dim") + localeManager.changesObserver,
        //% "Outline"
        qsTrId("id-face-ambient-outline") + localeManager.changesObserver
    ]
    function labelsOf(setting) {
        if (setting.id === "ambient-style")
            return ambientLabels
        return setting.labels !== undefined ? setting.labels : setting.options
    }
    function nameOf(setting) {
        //% "Always-on"
        if (setting.id === "ambient-style")
            return qsTrId("id-face-ambient") + localeManager.changesObserver
        //% "Date"
        if (setting.id === "show-date")
            return qsTrId("id-face-show-date") + localeManager.changesObserver
        //% "Seconds"
        if (setting.id === "show-seconds" || setting.id === "seconds")
            return qsTrId("id-face-show-seconds") + localeManager.changesObserver
        //% "Color"
        if (setting.id === "color")
            return qsTrId("id-face-opt-color") + localeManager.changesObserver
        //% "Layout"
        if (setting.id === "layout")
            return qsTrId("id-face-opt-layout") + localeManager.changesObserver
        //% "Styles"
        if (setting.id === "styles")
            return qsTrId("id-face-opt-styles") + localeManager.changesObserver
        //% "Fonts"
        if (setting.id === "fonts")
            return qsTrId("id-face-opt-fonts") + localeManager.changesObserver
        //% "Bold Time"
        if (setting.id === "boldTime")
            return qsTrId("id-face-opt-bold-time") + localeManager.changesObserver
        //% "Photo"
        if (setting.id === "photo")
            return qsTrId("id-face-opt-photo") + localeManager.changesObserver
        return setting.id
    }
    function valueOf(setting) {
        // a face with a schema knows the value in force (its choice, else its default)
        if (schema && face && face.opt)
            return face.opt(setting.id)
        switch (setting.id) {
        case "ambient-style": return style.ambientStyle
        case "show-date": return style.showDate
        case "show-seconds": return style.showSeconds
        }
        return ""
    }
    function setOption(id, value) {
        if (style.faceId === "")
            return
        style.set(FE.storeKey(id), value)
    }
    // the bool settings of a page with their names and values (chips read this)
    function boolChips(settings) {
        var out = []
        for (var i = 0; i < settings.length; i++)
            out.push({ id: settings[i].id, label: nameOf(settings[i]), value: valueOf(settings[i]) === true })
        return out
    }

    // ---- the complications of the favourite ----------------------------------------------
    ConfigurationValue {
        id: config
        key: editor.sources ? editor.sources.configKey(editor.faceName) : ""
        defaultValue: []
    }
    function sourceOf(slot) {
        return slot && sources ? sources.sourceOf(config.value, slot.slotId, slot.defaultSource || "empty") : "empty"
    }
    property Item chosenSlot: null
    function chooseSource(source) {
        if (chosenSlot && sources)
            config.value = sources.withSource(config.value, chosenSlot.slotId, source)
        chosenSlot = null
        paramList.closeNow()
        datePage.closeNow()
        chooser.closeNow()
        poke()
    }
    /* A row of the chooser. World clock, Countdown to date and App shortcut need a choice
     * first (watchface-catalogue-20, -21): their second page opens over the chooser, on the
     * slot's choice when it has one of that kind; its choice is the source stored. */
    function pickSource(source) {
        if (!sources || sources.parameterised.indexOf(source) < 0) {
            chooseSource(source)
            return
        }
        var cur = chosenSlot ? sourceOf(chosenSlot) : ""
        var p = C.split(cur)
        var mine = p.kind === source ? p.param : ""
        poke()
        if (source === "countdown") {
            datePage.open(FE.countdownDay(mine, new Date()))
            return
        }
        var rows = []
        var at = 0
        if (source === "worldclock") {
            rows = FE.worldClockRows()
            var off = mine !== "" ? C.offsetMinutes(mine) : null
            at = FE.offsetIndex(off !== null ? off : -new Date().getTimezoneOffset())
        } else {
            var items = []
            var m = sources.apps
            for (var i = 0; m && i < m.itemCount; i++) {
                var it = m.get(i)
                items.push(it && it.object ? it.object : it)
            }
            rows = FE.appRows(items)
            at = FE.rowIndex(rows, cur)
        }
        paramList.title = sources.name(source)
        paramList.model = rows
        paramList.open(at)
    }

    // ---- open, close, leave ---------------------------------------------------------------
    function open() {
        if (shown)
            return
        paramList.closeNow()
        datePage.closeNow()
        chooser.closeNow()
        optionsList.closeNow()
        chosenSlot = null
        pager.currentIndex = FE.openPage(lastPage, pageCount)
        pager.positionViewAtIndex(pager.currentIndex, ListView.Beginning)
        // at once: the editor's theme has no window animation (motion K8)
        opacity = 1
        shown = true
        idleTimer.restart()
        opened()
    }
    // the editor goes (the choices stay): the face shows under it
    function close() {
        if (!shown)
            return
        closeNow()
        closed()
    }
    function closeNow() {
        idleTimer.stop()
        paramList.closeNow()
        datePage.closeNow()
        chooser.closeNow()
        optionsList.closeNow()
        chosenSlot = null
        shown = false
        opacity = 1
    }
    // the crown button: back on the face from anywhere, the choices kept (stock pops the whole stack)
    function crownPressed() {
        if (!shown)
            return false
        close()
        return true
    }
    // a swipe right out of a list, or the way back from the chooser to the complications page
    function back() {
        if (paramList.shown) {
            paramList.back()
            return true
        }
        if (datePage.shown) {
            datePage.back()
            return true
        }
        if (chooser.shown) {
            chooser.back()
            return true
        }
        if (optionsList.shown) {
            optionsList.back()
            return true
        }
        return false
    }
    // a pull to the right past the first page, let go with `velocity` px/s: leave, as stock's back swipe
    function pullEnded(over, velocity) {
        if (!shown || pager.currentIndex !== 0 || over <= 0)
            return false
        if (!Motion.backShouldCommit(over, velocity, over, editor.width, Theme.dp(1)))
            return false
        close()
        return true
    }
    // the display went dark: the editor ends there (the faces draw the always-on screen)
    onAwakeChanged: if (!awake && shown) close()

    // ---- 15 s idle ------------------------------------------------------------------------
    function poke() { if (shown) idleTimer.restart() }
    Timer {
        id: idleTimer
        objectName: "eosEditorIdle"
        interval: FE.IDLE_MS
        running: FE.idleRunning(editor.shown, editor.touching, editor.awake)
        onTriggered: editor.close()
    }
    // the display stays on while the editor is open (FLAG_KEEP_SCREEN_ON)
    Loader {
        id: keepOn
        objectName: "eosEditorKeepOn"
        active: editor.shown
        sourceComponent: Component { DisplayBlanking { preventBlanking: editor.shown && editor.awake } }
    }
    readonly property bool holdingDisplay: keepOn.active && editor.awake

    // ---- the layers -----------------------------------------------------------------------
    Rectangle { anchors.fill: parent; color: "#000000" }
    // nothing under the editor takes a touch
    MouseArea { anchors.fill: parent; enabled: editor.shown }

    // the face at full size (a live copy of the home screen's face item)
    ShaderEffectSource {
        id: preview
        objectName: "eosEditorPreview"
        anchors.fill: parent
        sourceItem: editor.face
        live: editor.shown
        hideSource: false
        smooth: true
        visible: editor.shown && editor.face !== null
    }

    // the bottom fader
    Rectangle {
        id: fader
        objectName: "eosEditorFader"
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: FE.FADER[0].at; color: FE.FADER[0].color }
            GradientStop { position: FE.FADER[1].at; color: FE.FADER[1].color }
            GradientStop { position: FE.FADER[2].at; color: FE.FADER[2].color }
            GradientStop { position: FE.FADER[3].at; color: FE.FADER[3].color }
        }
    }

    // ---- the pager ------------------------------------------------------------------------
    ListView {
        id: pager
        objectName: "eosEditorPager"
        anchors.fill: parent
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        highlightMoveDuration: 250
        // pulled past the first page the editor leaves (see pullEnded); elsewhere the ends hold
        boundsBehavior: Flickable.DragOverBounds
        interactive: editor.shown && !chooser.shown && !optionsList.shown
        cacheBuffer: width
        model: editor.pageSpecs
        onCurrentIndexChanged: if (editor.shown) editor.lastPage = currentIndex
        onDragEnded: editor.pullEnded(-horizontalOvershoot, -horizontalVelocity)
        onMovementStarted: editor.poke()

        delegate: Item {
            id: cell
            objectName: "eosEditorPage"
            required property int index
            required property var modelData
            width: pager.width
            height: pager.height
            readonly property bool current: ListView.isCurrentItem
            readonly property string kind: modelData.kind
            readonly property Item page: loader.item
            readonly property Item stepper: page && page.stepper ? page.stepper : null
            readonly property bool active: current && editor.shown && editor.awake

            Loader {
                id: loader
                anchors.fill: parent
                sourceComponent: cell.kind === "list" ? listPage : (cell.kind === "slots" ? slotsPage : boolPage)
                onLoaded: if (item && item.spec !== undefined) item.spec = cell.modelData
            }

            // the page's spoken name (stock: no title on screen, TalkBack only)
            Accessible.role: Accessible.Pane
            //% "Complications"
            Accessible.name: kind === "slots" ? qsTrId("id-face-complications") + localeManager.changesObserver
                                              //% "Other options"
                                              : (kind === "bool" ? qsTrId("id-face-other-options") + localeManager.changesObserver
                                                                 : (modelData.setting ? editor.nameOf(modelData.setting) : ""))

            Component {
                id: listPage
                EditorListPage {
                    id: lp
                    property var spec: null
                    settingName: spec ? editor.nameOf(spec.setting) : ""
                    values: spec ? spec.setting.options : []
                    labels: spec ? editor.labelsOf(spec.setting) : []
                    current: spec ? String(editor.valueOf(spec.setting)) : ""
                    active: cell.active
                    onPicked: (value) => editor.setOption(spec.setting.id, value)
                    onPoked: editor.poke()
                    onOpenOptions: {
                        optionsList.pageItem = lp
                        optionsList.title = lp.settingName
                        optionsList.labels = lp.labels
                        optionsList.open(lp.index)
                    }
                }
            }
            Component {
                id: slotsPage
                EditorSlotsPage {
                    property var spec: null
                    face: editor.face
                    slots: editor.slots
                    sources: editor.sources
                    sourceOf: editor.sourceOf
                    active: cell.active && !chooser.shown
                    onSlotTapped: (slot) => {
                        editor.chosenSlot = slot
                        editor.poke()
                        chooser.openFor(editor.sourceOf(slot))
                    }
                }
            }
            Component {
                id: boolPage
                EditorBoolPage {
                    property var spec: null
                    settings: spec ? editor.boolChips(spec.settings) : []
                    active: cell.active
                    onToggled: (id, value) => { editor.setOption(id, value); editor.poke() }
                }
            }
        }
    }

    EditorDots {
        id: pageDots
        objectName: "eosEditorDots"
        count: editor.pageCount
        position: pager.width > 0 ? Math.max(0, pager.contentX - pager.originX) / pager.width : 0
        visible: count > 1 && !chooser.shown && !optionsList.shown
    }

    // ---- the lists over the pages ---------------------------------------------------------
    EditorOptionsList {
        id: optionsList
        objectName: "eosEditorOptions"
        property Item pageItem: null
        onPicked: (index) => {
            if (pageItem) {
                pageItem.picked(String(pageItem.values[index]))
                editor.poke()
            }
        }
        onPoked: editor.poke()
    }
    EditorProviderList {
        id: chooser
        objectName: "eosEditorChooser"
        sources: editor.sources
        appNames: editor.appNames
        //% "Complications"
        title: qsTrId("id-face-complications") + localeManager.changesObserver
        onChosen: (source) => editor.pickSource(source)
        onBackRequested: editor.chosenSlot = null
        onPoked: editor.poke()
    }
    // the second pages: back goes to the chooser under them
    EditorParamList {
        id: paramList
        objectName: "eosEditorParams"
        onPicked: (value) => editor.chooseSource(value)
        onPoked: editor.poke()
    }
    EditorDatePage {
        id: datePage
        objectName: "eosEditorDate"
        onPicked: (value) => editor.chooseSource(value)
        onPoked: editor.poke()
    }
    // the app each source belongs to, the chooser's second line
    readonly property var appNames: ({
        //% "Settings"
        "settings": qsTrId("id-face-app-settings") + localeManager.changesObserver,
        //% "Health"
        "health": qsTrId("id-face-app-health") + localeManager.changesObserver,
        //% "Weather"
        "weather": qsTrId("id-face-app-weather") + localeManager.changesObserver,
        //% "Calendar"
        "calendar": qsTrId("id-face-app-calendar") + localeManager.changesObserver,
        //% "Clock"
        "clock": qsTrId("id-face-app-clock") + localeManager.changesObserver,
        //% "Media controls"
        "media": qsTrId("id-face-app-media") + localeManager.changesObserver,
        //% "Assistant"
        "assistant": qsTrId("id-face-app-assistant") + localeManager.changesObserver
    })

    // ---- touches: the idle timer's eyes (above everything, passive) -----------------------
    Item {
        anchors.fill: parent
        z: 2000
        PointHandler {
            acceptedDevices: PointerDevice.TouchScreen | PointerDevice.Mouse
            onActiveChanged: {
                editor.touching = active
                if (!active)
                    editor.poke()
            }
        }
    }
}
