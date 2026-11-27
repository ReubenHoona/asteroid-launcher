/*
 * Copyright (C) 2026 Timo Könnecke <github.com/moWerk>
 *               2015 Florent Revest <revestflo@gmail.com>
 *               2014 Aleksi Suomalainen <suomalainen.aleksi@gmail.com>
 * All rights reserved.
 *
 * You may use this file under the terms of BSD license as follows:
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of the author nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

import QtQuick
import Nemo.Configuration
import org.nemomobile.lipstick
import org.asteroid.controls
import "../desktop.js" as Desktop
import "../tiles"
import "../complications"
import "../firstrun"
import "requests.js" as Requests
import ".."

/* What opens over the home screen (split out of MainScreen.qml): the app
 * list, the face picker, the tiles editor, the "Sent"/"Saved"
 * confirmation, the boot splash and the first-run wizard, and how the
 * crown goes back through them. Instantiated once in MainScreen as
 * `overlays` at z 5; the children keep their z of MainScreen (5, 6, 6, 8,
 * 8, 9), so they stack as before over the grid (0), the tile dots (2) and
 * the status slot (0). MainScreen forwards appDrawer, facePicker,
 * tilesEditor, confirmation and splash. Reads MainScreen's shared ids
 * (desktop, grid, faceLayer, tilesRing, complications) through the
 * context. Owned by the app list and face picker packages
 * (W2-launcher-app-list, W2-launcher-face-picker). */
Item {
    id: overlays
    anchors.fill: parent
    z: 5

    readonly property Item appDrawer: appDrawerItem
    readonly property Item facePicker: facePickerItem
    readonly property Item faceEditor: faceEditorItem
    readonly property Item tilesEditor: tilesEditorItem
    readonly property Item confirmation: confirmationItem
    readonly property Item recents: recentsItem
    readonly property Item splash: splashItem

    // the boot hand-over (power-boot-warnings-07): the logo and the pill stay until the face
    // is drawn, then fade to black and the black goes
    Splash {
        id: splashItem
        z: 9
        // the face is drawn, or the setup wizard is what comes next (no face to wait for)
        ready: desktop.faceShown || (typeof firstRun !== "undefined" && firstRun !== null && firstRun.isFirstRun())
        displayOn: !Lipstick.compositor.displayAmbient
    }
    // the boot-complete feedback once the boot screen has gone (R5 B-09)
    BootFeedback {
        objectName: "bootFeedback"
        splashDone: splashItem.done
    }

    // the setup wizard (firstrun/FirstRunConfig.qml); an ambient display keeps showing its last frame, which
    // would be a frozen-looking wizard: the ambient watchface below shows instead
    Component {
        id: firstRunComponent
        FirstRunConfig {
            z: 8
            visible: !Lipstick.compositor.displayAmbient
            // awake: the display is on, not off and not the always-on screen (the setup restarts at the first
            // screen on each wake, the animations stop with the display)
            displayOn: desktop.displayAwake && !Lipstick.compositor.displayAmbient
        }
    }
    // the navigation tutorial, an interactive coach over the home screen (firstrun/Tutorial.qml)
    Component {
        id: tutorialComponent
        Tutorial {
            z: 8
            visible: !Lipstick.compositor.displayAmbient
            // awake: the display is on, not off and not the always-on screen (the setup restarts at the first
            // screen on each wake, the animations stop with the display)
            displayOn: desktop.displayAwake && !Lipstick.compositor.displayAmbient
        }
    }
    function startFirstRun() {
        var setup = firstRunComponent.createObject(overlays)
        setup.done.connect(function () {
            setup.destroy()
            startTutorial()
        })
    }
    // the coach on the screen, if any (one at a time)
    property Item tutorialCoach: null
    // force: Settings asked for it (the start-tutorial request), pending or not
    function startTutorial(force) {
        if ((force !== true && !firstRun.tutorialPending()) || tutorialCoach !== null)
            return
        var coach = tutorialComponent.createObject(overlays)
        tutorialCoach = coach
        coach.done.connect(function () {
            coach.destroy()
            if (tutorialCoach === coach)
                tutorialCoach = null
        })
    }

    /* What Settings asks of the launcher (dconf, "<route>@<ms>", requests.js: acted on only while
     * younger than 60 s; a value is acted on once):
     *  - /org/asteroidos/launcher/start-tutorial "tutorial@<ms>" (General > Start tutorial, CR-11):
     *    the tutorial is pending (the launcher's own flag, tutorialPending) and starts over the face
     *  - /org/asteroidos/launcher/open-face-picker "picker@<ms>" (Display > Change watch face, CR-12):
     *    the face, with the picker open over it (the long press' path, openFacePicker)
     * Neither while the setup wizard is up (the wizard starts the tutorial itself at its end). */
    ConfigurationValue {
        id: tutorialRequest
        key: "/org/asteroidos/launcher/start-tutorial"
        defaultValue: ""
        onValueChanged: overlays.handleTutorialRequest(String(value))
    }
    ConfigurationValue {
        id: pickerRequest
        key: "/org/asteroidos/launcher/open-face-picker"
        defaultValue: ""
        onValueChanged: overlays.handlePickerRequest(String(value))
    }
    ConfigurationValue {
        id: tutorialPendingKey
        key: "/org/asteroidos/launcher/tutorialPending"
        defaultValue: false
    }
    property string handledTutorial: ""
    property string handledPicker: ""

    // an application in front goes to the background, the overlays go: the face is what is shown
    function showFace() {
        if (!Lipstick.compositor.homeActive && Desktop.compositorRoot && Desktop.compositorRoot.leaveApp)
            Desktop.compositorRoot.leaveApp()
        closeOverlays()
        grid.moveTo(0, 0)
    }
    function handleTutorialRequest(value) {
        if (value === handledTutorial || !Requests.fresh(value, "tutorial", Date.now()))
            return
        handledTutorial = value
        if (firstRun.isFirstRun())
            return
        tutorialPendingKey.value = true
        showFace()
        startTutorial(true)
    }
    function handlePickerRequest(value) {
        if (value === handledPicker || !Requests.fresh(value, "picker", Date.now()))
            return
        handledPicker = value
        if (firstRun.isFirstRun())
            return
        showFace()
        desktop.openFacePicker()
    }

    // the face picker goes without applying (an application or the assistant came up)
    function closeFacePicker() {
        faceEditorItem.closeNow()
        worldClockChooserItem.closeNow()
        if (facePickerItem.visible) facePickerItem.close()
    }

    // the drawer, the face picker and the tiles editor go
    function closeOverlays() {
        appDrawerItem.closeNow()
        recentsItem.closeNow()
        faceEditorItem.closeNow()
        worldClockChooserItem.closeNow()
        if (facePickerItem.visible) facePickerItem.close()
        if (tilesEditorItem.visible) tilesEditorItem.close()
    }

    /* The crown button on the home screen, as Wear OS: on the watchface it
     * opens the app list; anywhere else (the app list, a tile, the
     * notifications, quick settings) it goes back to the watchface */
    function crownPressed() {
        if (splashItem.visible)
            return
        // the full screen keyboard of a reply goes first, and a picture open
        // full screen (back to its notification)
        if (Desktop.keyboard) {
            Desktop.keyboard.dismiss()
            return
        }
        if (Desktop.pictureViewer) {
            Desktop.pictureViewer.close()
            return
        }
        // the editors: one press pops the whole stack and keeps (saves)
        // what was changed, back to the face (stock SysUI pkx.java:991-1003
        // pops its whole back stack; the tile manager is an activity, the
        // crown goes Home: buttons-navigation-17)
        // the tiles editor: the crown cancels it to the watch face, from the carousel,
        // its dialog and the add list (tiles-framework-21, jif.java:196-209)
        if (tilesEditorItem.visible) {
            tilesEditorItem.crownPressed()
            return
        }
        // the face editor: the crown leaves it for the face, the choices kept (face-interaction-24)
        if (faceEditorItem.visible) {
            faceEditorItem.crownPressed()
            return
        }
        // a World clock slot's zone chooser: the crown leaves it for the face, nothing picked
        if (worldClockChooserItem.shown) {
            worldClockChooserItem.closeNow()
            return
        }
        if (facePickerItem.visible) {
            // the face picker: the crown applies the centred face, or leaves the add list, as stock
            // (face-interaction-10); false: the picker leaves it to the home screen, which closes it
            if (facePickerItem.crownPressed())
                return
            closeOverlays()
            return
        }
        // Recents goes to the face (stock Home)
        if (recentsItem.isOpen) {
            recentsItem.close()
            return
        }
        if (appDrawerItem.isOpen) {
            appDrawerItem.close()
            return
        }
        if (grid.currentHorizontalPos !== 0 || grid.currentVerticalPos !== 0) {
            grid.animateTo(0, 0)
            return
        }
        if (desktop.wearLayout)
            appDrawerItem.open()
        else
            grid.animateTo(0, 1)
    }

    /* The side button's short press (KeyRouter -> compositor.toggleRecents ->
     * MainScreen): Recents opens over whatever is on the screen, or closes
     * when it is open (the second press of a double press, which then goes
     * to the previous app). Not over the boot splash or a full screen keyboard. */
    function toggleRecents() {
        if (recentsItem.isOpen && recentsItem.progress > 0.5)
            return recentsItem.toggle()
        if (splashItem.visible || Desktop.keyboard || Desktop.pictureViewer)
            return false
        closeOverlays()
        return recentsItem.toggle()
    }

    /* "All apps" of Recents: the app list at its top over the face (an
     * application in front goes to the background first) */
    function openAppList() {
        if (!Lipstick.compositor.homeActive && Desktop.compositorRoot && Desktop.compositorRoot.leaveApp)
            Desktop.compositorRoot.leaveApp()
        closeOverlays()
        grid.moveTo(0, 0)
        appDrawerItem.reset()
        appDrawerItem.open()
    }

    // The app list is drawn once, unseen, a few seconds after the start, so
    // that its first opening does not make its textures and text then
    property bool prewarmPending: false
    function startPrewarm() {
        prewarmTimer.start()
    }
    function prewarmIfPending() {
        if (prewarmPending)
            prewarmTimer.restart()
    }
    Timer {
        id: prewarmTimer
        interval: 4000
        onTriggered: {
            overlays.prewarmPending = !(desktop.visible && desktop.displayAwake && !displayAmbient)
            if (!overlays.prewarmPending)
                appDrawerItem.prewarm()
        }
    }

    AppDrawer {
        id: appDrawerItem
        z: 5
        onIsOpenChanged: if (isOpen && launcher.item) Desktop.appLauncher = launcher.item
    }

    Recents {
        id: recentsItem
        z: 5.5
        onAllAppsRequested: overlays.openAppList()
        onAppInfoRequested: (item) => desktop.openAppInfo(item)
    }

    FacePicker {
        id: facePickerItem
        z: 6
        store: faceLayer.favourites
        liveFace: desktop.centreItem ? desktop.centreItem.activeFace : null
        // the wallpaper the face is drawn over: under the 10:09 pictures in the carousel
        background: desktop.wallpaperItem
        sources: complications
        awake: desktop.displayAwake && !displayAmbient
        previewVersion: facePreviewRenderer.version
        onEditRequested: faceEditorItem.open()
    }
    /* the 10:09 picture of each favourite of an eos face (N61-35), drawn when the favourite is new or has none yet
     * and when the editor closes on it (its style or complications may have changed); never at the picker's open */
    FacePreviewRenderer {
        id: facePreviewRenderer
        cache: typeof facePreviews !== "undefined" ? facePreviews : null
        store: faceLayer.favourites
        sources: complications
        active: desktop.displayAwake && !displayAmbient
    }
    Connections {
        target: faceLayer.favourites
        function onEntriesChanged() { if (faceLayer.favourites.ready) Qt.callLater(facePreviewRenderer.renderMissing) }
        function onReadyChanged() { if (faceLayer.favourites.ready) Qt.callLater(facePreviewRenderer.renderMissing) }
    }
    // the face editor (W3-launcher-face-editor): over the picker, which hides 500 ms after it opens
    FaceEditor {
        id: faceEditorItem
        z: 6.5
        store: faceLayer.favourites
        face: desktop.centreItem ? desktop.centreItem.activeFace : null
        sources: complications
        awake: desktop.displayAwake && !displayAmbient
        // leaving the editor shows the face (the picker is closed too, if it is still there); the favourite's
        // picture is drawn again with what was chosen
        onClosed: {
            facePickerItem.closeNow()
            facePreviewRenderer.render(faceLayer.favourites.currentId)
        }
    }
    /* A tap on a World clock slot of the face (A-13): its zone chooser, over the face, as stock's
     * complication tap opens ACTION_CHOOSE_TIMEZONE when there is no world clock app; the zone picked
     * is stored for that slot. It goes with the display (as the editor) and with the crown. */
    WorldClockChooser {
        id: worldClockChooserItem
        objectName: "eosWorldClockChooser"
        z: 6.6
        visible: shown
        sources: complications
    }
    Connections {
        target: complications
        function onWorldClockChooserRequested(faceName, slotId, current) {
            if (faceName !== "" && slotId !== "")
                worldClockChooserItem.openFor(current, faceName, slotId)
        }
    }
    Connections {
        target: desktop
        function onDisplayAwakeChanged() { if (!desktop.displayAwake) worldClockChooserItem.closeNow() }
    }
    // stock: Recents, the assistant or an application coming up closes the picker without applying
    // (face-interaction-33, ked.java:340-347)
    Connections {
        target: Lipstick.compositor
        function onHomeActiveChanged() {
            if (!Lipstick.compositor.homeActive) {
                faceEditorItem.closeNow()
                worldClockChooserItem.closeNow()
                if (facePickerItem.shown)
                    facePickerItem.closeNow()
            }
        }
    }

    TilesEditor {
        id: tilesEditorItem
        z: 6
        onChanged: (tiles) => tilesRing.saveTiles(tiles)
        // the crown: back on the watch face, under the shrinking editor
        onCancelled: grid.moveTo(0, 0)
        // back on the tile in the middle of the editor, as stock
        onFinished: (index) => {
            if (index >= 0 && desktop.wearLayout)
                Qt.callLater(function() { grid.moveTo(Math.min(index + 1, desktop.tileCount), 0) })
        }
    }

    // "Sent", "Saved"... over everything on the home screen
    Confirmation {
        id: confirmationItem
        z: 8
    }
}
