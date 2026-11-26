/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import org.asteroid.controls
import "whatsnew.js" as WN

/*
 * What's new after an update (setup-wizard-15, CR-42; stock SysUI's what's-new
 * flow, hjw.java whats_new_cmp_*): once eos-update has published the notes of a
 * version that confirmed itself (/org/asteroidos/eos-update/whatsnew-notes and
 * whatsnew-pending true; the version is for Settings' row), the splash "Your
 * watch just got better!" shows with Next, then the notes one page at a time
 * (each "Headline: text"; the pages split at "|", whatsnew.js) with Next, Back
 * from the second page on, Done on the last. It shows once: whatsnew-pending
 * goes false when it appears. Not during setup, not over a call, a firing alarm
 * or another surface that must not be covered (`blocked`, OverlayArbiter), not
 * with the display off: it waits for the next screen on. The crown closes it (a
 * system dialog, keymap.js closeSystemDialog). Settings > General > What's new
 * shows the same pages again. Nothing runs while it is hidden; the keys are read
 * when they change.
 */
Item {
    id: whatsNew
    objectName: "eosWhatsNew"
    anchors.fill: parent
    visible: shown

    // the display is on (not off, not the always-on screen)
    property bool displayOn: true
    // a surface that must not be covered is up, or setup runs
    property bool blocked: false
    // setup has not finished (FirstRun.isFirstRun, a call: no change signal)
    property var setupRunning: function () { return typeof firstRun !== "undefined" && firstRun !== null && firstRun.isFirstRun() }

    property bool shown: false
    // -1 the splash, then the pages
    property int step: -1
    readonly property var pages: WN.pages(notesValue.value)
    readonly property bool lastPage: step >= pages.length - 1
    readonly property var page: step >= 0 && step < pages.length ? pages[step] : ({ headline: "", text: "" })

    ConfigurationValue {
        id: notesValue
        key: "/org/asteroidos/eos-update/whatsnew-notes"
        defaultValue: ""
        onValueChanged: whatsNew.check()
    }
    ConfigurationValue {
        id: pendingValue
        key: "/org/asteroidos/eos-update/whatsnew-pending"
        defaultValue: false
        onValueChanged: whatsNew.check()
    }

    onDisplayOnChanged: check()
    onBlockedChanged: check()
    Component.onCompleted: check()

    // shows when it is due and nothing keeps it away; marks it shown at once
    function check() {
        if (shown || !displayOn || blocked || setupRunning())
            return
        if (!WN.due(pendingValue.value, notesValue.value))
            return
        step = -1
        shown = true
        pendingValue.value = false
    }
    function next() {
        if (step >= pages.length - 1) {
            close()
            return
        }
        step = step + 1
        pageFlick.contentY = 0
    }
    function back() {
        if (step >= 0) {
            step = step - 1
            pageFlick.contentY = 0
        }
    }
    function close() {
        shown = false
        step = -1
    }

    Rectangle { anchors.fill: parent; color: "#000000" }
    // nothing under it takes a touch
    MouseArea { anchors.fill: parent; enabled: whatsNew.shown }

    // ---- the splash -----------------------------------------------------------------------
    Item {
        id: splash
        objectName: "whatsNewSplash"
        anchors.fill: parent
        visible: whatsNew.step < 0

        Label {
            objectName: "whatsNewSplashTitle"
            x: Math.round(parent.width * WN.LAYOUT.splashSide)
            width: parent.width - 2 * x
            y: Math.round(parent.height * WN.LAYOUT.splashTop) + Theme.dp(24)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            role: "titleMedium"
            color: Theme.color.onBackground
            //% "Your watch just got better!"
            text: qsTrId("id-whatsnew-splash") + localeManager.changesObserver
        }
        EdgeButton {
            objectName: "whatsNewSplashNext"
            visible: splash.visible
            //% "Next"
            text: qsTrId("id-whatsnew-next") + localeManager.changesObserver
            onClicked: whatsNew.next()
        }
    }

    // ---- a page of the notes ----------------------------------------------------------------
    Flickable {
        id: pageFlick
        objectName: "whatsNewPage"
        anchors.fill: parent
        visible: whatsNew.step >= 0
        interactive: visible
        contentHeight: column.height + Math.round(height * WN.LAYOUT.pageTop) + Theme.dp(48)
        clip: true

        Column {
            id: column
            x: Math.round(pageFlick.width * WN.LAYOUT.pageSide)
            y: Math.round(pageFlick.height * WN.LAYOUT.pageTop)
            width: pageFlick.width - 2 * x
            spacing: Theme.dp(WN.LAYOUT.headlineGapDp)

            Label {
                objectName: "whatsNewHeadline"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                role: "titleMedium"
                color: Theme.color.onBackground
                text: whatsNew.page.headline
                visible: text !== ""
            }
            Label {
                objectName: "whatsNewText"
                x: Math.round(pageFlick.width * WN.LAYOUT.subtextSide)
                width: parent.width - 2 * x
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                role: "bodyMedium"
                color: Theme.color.onSurface
                text: whatsNew.page.text
                visible: text !== ""
            }
            Column {
                width: parent.width
                spacing: Theme.dp(WN.LAYOUT.edgeSpacingDp)
                Button {
                    objectName: "whatsNewNext"
                    width: parent.width
                    height: Theme.dp(WN.LAYOUT.buttonDp)
                    centered: true
                    text: (whatsNew.lastPage
                           //% "Done"
                           ? qsTrId("id-whatsnew-done")
                           : qsTrId("id-whatsnew-next")) + localeManager.changesObserver
                    onClicked: whatsNew.next()
                }
                Button {
                    objectName: "whatsNewBack"
                    width: parent.width
                    height: Theme.dp(WN.LAYOUT.buttonDp)
                    visible: whatsNew.step > 0
                    variant: "tonal"
                    centered: true
                    //% "Back"
                    text: qsTrId("id-whatsnew-back") + localeManager.changesObserver
                    onClicked: whatsNew.back()
                }
            }
        }
    }
}
