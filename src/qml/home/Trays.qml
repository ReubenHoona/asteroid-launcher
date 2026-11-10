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
import org.asteroid.controls
import "../desktop.js" as Desktop
import ".."

/* The panels around the watch face (split out of MainScreen.qml), as the
 * grid holds them, and which layout: the Wear OS home screen (dconf
 * /org/asteroidos/ux/home-layout "wear", the default; "asteroid" for the
 * AsteroidOS one; read at start): watchface in the middle, quick settings
 * above, the notification stream below (swipe up), the tiles to the right
 * (swipe left), the app list over it all on the crown button (or a swipe
 * right). Instantiated once in MainScreen as `trays`; the grid calls
 * build() when it is complete. Reads MainScreen's shared ids (desktop,
 * grid, faceLayer, appDrawer, statusSlot and the indicators) through the
 * context. Owned by W2-launcher-trays (quick settings, stream). */
Item {
    id: trays

    ConfigurationValue {
        id: homeLayout
        key: "/org/asteroidos/ux/home-layout"
        defaultValue: "wear"
    }

    ConfigurationValue {
        id: appLauncherSource
        key: "/desktop/asteroid/applauncher"
        defaultValue: "file:///usr/share/asteroid-launcher/applauncher/000-default-horizontal.qml"
    }

    // a language change reloads the app launcher
    Connections {
        target: localeManager
        function onChangesObserverChanged() {
            var appLauncherSourceBackup = appLauncherSource.value
            appLauncherSource.value = ""
            appLauncherSource.value = appLauncherSourceBackup
        }
    }

    Component { id: topPanel;    QuickPanel      { } }
    Component { id: streamPanel; NotificationStream { panelsGrid: grid } }
    Component { id: leftPanel;   NotificationsPanel { panelsGrid: grid } }
    Component { id: rightPanel;  Today              { } }
    Component {
        id: bottomPanel
        Loader {
            id: appLauncher
            property bool fakePressed:     false
            property bool toTopAllowed:    true
            property bool toBottomAllowed: true
            property bool toLeftAllowed:   true
            property bool toRightAllowed:  true
            property bool forbidTop: false
            property bool forbidBottom: false
            property bool forbidLeft: false
            property bool forbidRight: false
            source: appLauncherSource.value
            onStatusChanged: {
                if (appLauncher.status == Loader.Ready) {
                    Desktop.appLauncher = appLauncher.item
                }
            }
        }
    }

    // the grid's panels, once it is complete
    function build() {
        desktop._wearLayout = homeLayout.value !== "asteroid"
        if (desktop.wearLayout) {
            desktop.centreItem = grid.addPanel(0, 0, faceLayer.panel)
            grid.addPanel(0, -1, topPanel)
            var ns = grid.addPanel(0, 1, streamPanel)
            desktop.streamItem = ns
            desktop.buildTiles()
            appDrawer.source = Qt.binding(function() { return appLauncherSource.value })
            rightIndicator.visible  = Qt.binding(function() { return grid.toLeftAllowed && !displayAmbient })
            leftIndicator.visible   = Qt.binding(function() { return grid.toRightAllowed && !displayAmbient && !appDrawer.isOpen })
            topIndicator.visible    = Qt.binding(function() { return grid.toBottomAllowed && !displayAmbient })
            // Wear OS: the unread notification dot (NotificationIndicator) says what waits below
            bottomIndicator.visible = Qt.binding(function() { return grid.toTopAllowed && !displayAmbient && statusSlot.notificationIndicator.unreadCount === 0 })
            return
        }
        desktop.centreItem = grid.addPanel(0, 0, faceLayer.panel)
        var al = grid.addPanel(0, 1, bottomPanel)
        grid.addPanel(1, 0, rightPanel)
        var np = grid.addPanel(-1, 0, leftPanel)
        grid.addPanel(0, -1, topPanel)

        rightIndicator.visible  = Qt.binding(function() { return ((grid.toLeftAllowed   || (grid.currentVerticalPos == 1 && al.toLeftAllowed ))   && !displayAmbient)})
        leftIndicator.visible   = Qt.binding(function() { return ((grid.toRightAllowed  || (grid.currentVerticalPos == 1 && al.toRightAllowed))   && (!displayAmbient || !np.modelEmpty))})
        topIndicator.visible    = Qt.binding(function() { return ((grid.toBottomAllowed || (grid.currentVerticalPos == 1 && al.toBottomAllowed )) && !displayAmbient)})
        bottomIndicator.visible = Qt.binding(function() { return ((grid.toTopAllowed    || (grid.currentVerticalPos == 1 && al.toTopAllowed ))    && !displayAmbient)})

        leftIndicator.keepExpanded = Qt.binding(function() { return !np.modelEmpty && grid.currentHorizontalPos == 0 && grid.currentVerticalPos == 0 })
    }
}
