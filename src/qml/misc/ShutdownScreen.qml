/*
 * Copyright (C) 2015 Florent Revest <revestflo@gmail.com>
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
import QtQuick.Window
import org.asteroid.controls
import org.nemomobile.lipstick

/* The shutdown and restart screen (power-boot-warnings-03), as stock's
 * WearComposeShutdownDialogProvider / ShuttingDialogProvider: black, not
 * cancelable, the same for a user's, a battery-empty and a thermal shutdown.
 *  - the curved time at the top (TimeText, arcMedium, the 12/24 h setting);
 *  - the message centred both ways, at most 89.6 % of the screen wide:
 *    power off "Bye", on one line, the first of displayMedium (60 px) /
 *    displaySmall (48 px) / titleMedium (32 px) that fits; restart
 *    "Restarting...", titleLarge (36 px) then titleMedium (32 px), up to 2
 *    lines; it fades in linearly over 300 ms after 100 ms;
 *  - the indeterminate arc (ArcProgressIndicator): a 312 px box (81.24 % of
 *    the height) centred on the screen, stroke 12 px, 65 to 115 degrees,
 *    head 0-600 ms, tail 300-900 ms of 2000 ms, cubic (0.3, 0, 0.7, 1),
 *    primaryDim.
 * The restart is told by logind (shutdownScreen.restart, from
 * PrepareForShutdownWithMetadata). The frame stays until the power goes:
 * nothing here hides it again except the 150 ms fade-out of a cancelled
 * shutdown (logind does not offer one). Nothing animates while it is not
 * shown. */
Rectangle {
    id: shutdownWindow
    objectName: "shutdownScreen"
    width: initialSize.width
    height: initialSize.height
    color: "black"
    opacity: shutdownScreen.windowVisible ? 1.0 : 0.0
    visible: opacity > 0

    readonly property bool restart: shutdownScreen.restart === true
    readonly property real maxTextWidth: Math.round(0.896 * width)
    readonly property alias message: message

    // the first role the text fits in: one line for "Bye", two lines for "Restarting...". Each
    // role has a hidden label of its own to measure: the size is wanted at once, with no frame
    // between switching the role and reading the width.
    function fit() {
        var probes = restart ? [probeTitleLarge, probeTitleMedium] : [probeDisplayMedium, probeDisplaySmall, probeTitleMedium]
        var limit = restart ? 2 * maxTextWidth : maxTextWidth
        for (var i = 0; i < probes.length; i++) {
            probes[i].forceLayout()
            if (probes[i].implicitWidth <= limit || i === probes.length - 1) {
                message.role = probes[i].role
                return
            }
        }
    }
    // the text and the width are what it is measured against: fit once their bindings have settled
    readonly property string shownText: restart
        //% "Restarting..."
        ? qsTrId("id-restarting") + localeManager.changesObserver
        //% "Bye"
        : qsTrId("id-bye") + localeManager.changesObserver
    onShownTextChanged: Qt.callLater(fit)
    onMaxTextWidthChanged: Qt.callLater(fit)
    Component.onCompleted: fit()

    Behavior on opacity {
        NumberAnimation {
            duration: 150
        }
    }

    // the message fades in: 100 ms of nothing, then 300 ms linear
    readonly property bool _show: shutdownScreen.windowVisible
    on_ShowChanged: {
        if (_show) {
            message.opacity = 0
            fade.restart()
        } else {
            fade.stop()
        }
    }
    SequentialAnimation {
        id: fade
        PauseAnimation { duration: 100 }
        NumberAnimation { target: message; property: "opacity"; from: 0; to: 1; duration: 300; easing.type: Easing.Linear }
    }

    ArcProgressIndicator {
        objectName: "shutdownArc"
        displayOn: shutdownWindow.visible
        visible: shutdownWindow.visible
    }

    Label { id: probeDisplayMedium; visible: false; role: "displayMedium"; text: shutdownWindow.shownText; elide: Text.ElideNone }
    Label { id: probeDisplaySmall; visible: false; role: "displaySmall"; text: shutdownWindow.shownText; elide: Text.ElideNone }
    Label { id: probeTitleLarge; visible: false; role: "titleLarge"; text: shutdownWindow.shownText; elide: Text.ElideNone }
    Label { id: probeTitleMedium; visible: false; role: "titleMedium"; text: shutdownWindow.shownText; elide: Text.ElideNone }

    Label {
        id: message
        objectName: "shutdownMessage"
        width: shutdownWindow.maxTextWidth
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        wrapMode: shutdownWindow.restart ? Text.WordWrap : Text.NoWrap
        maximumLineCount: shutdownWindow.restart ? 2 : 1
        elide: Text.ElideNone
        color: Theme.color.onBackground
        role: "displayMedium"
        text: shutdownWindow.shownText
    }

    TimeText { }
}
