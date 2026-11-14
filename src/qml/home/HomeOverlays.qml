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
import org.nemomobile.lipstick
import org.asteroid.controls
import "../desktop.js" as Desktop
import "../tiles"
import "../firstrun"
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
    function startTutorial() {
        if (!firstRun.tutorialPending())
            return
        var coach = tutorialComponent.createObject(overlays)
        coach.done.connect(function () { coach.destroy() })
    }

    // the face picker goes without applying (an application or the assistant came up)
    function closeFacePicker() {
        if (facePickerItem.visible) facePickerItem.close()
    }

    // the drawer, the face picker and the tiles editor go
    function closeOverlays() {
        appDrawerItem.closeNow()
        recentsItem.closeNow()
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
        if (tilesEditorItem.visible || facePickerItem.visible) {
            // the face picker: the crown applies the centred face, or leaves the add list, as stock
            // (face-interaction-10); false: the editor leaves it to the home screen, which closes the picker
            if (facePickerItem.visible && !tilesEditorItem.visible && facePickerItem.crownPressed())
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
        sources: complications
        awake: desktop.displayAwake && !displayAmbient
    }
    // stock: Recents, the assistant or an application coming up closes the picker without applying
    // (face-interaction-33, ked.java:340-347)
    Connections {
        target: Lipstick.compositor
        function onHomeActiveChanged() {
            if (!Lipstick.compositor.homeActive && facePickerItem.shown)
                facePickerItem.closeNow()
        }
    }

    TilesEditor {
        id: tilesEditorItem
        z: 6
        onChanged: (tiles) => tilesRing.saveTiles(tiles)
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
