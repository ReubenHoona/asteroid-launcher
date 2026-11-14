/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Amber.Mpris

/* The phone's media session as an ongoing activity (W2-launcher-status, audit
 * media-controls-17): while a session plays or is paused (stock gir.java:96-120,
 * fyy.java:412-428: the transport category, ranked last) the registry has an entry
 * for it: the note glyph, the track title as its status, a tap opens the music app
 * (Media Controls). Stopped, or no session: the entry goes. The MPRIS session is
 * followed by D-Bus signals only (Amber.Mpris), nothing is polled; the entry is
 * published when the session's state or title changes. */
Item {
    id: media
    visible: false

    readonly property QtObject registry: typeof ongoingRegistry !== "undefined" ? ongoingRegistry : null
    property MprisController mpris: MprisController { }

    readonly property bool present: mpris.currentService !== "" && mpris.currentService !== undefined
                                    && mpris.metaData.title !== undefined && mpris.metaData.title !== ""
    readonly property bool live: present && (mpris.playbackStatus === Mpris.Playing
                                             || mpris.playbackStatus === Mpris.Paused)
    readonly property string title: present ? mpris.metaData.title : ""

    // the entry for this state, "" when none (the tests compare it)
    readonly property string stateKey: live ? title : ""
    onStateKeyChanged: publish()
    Component.onCompleted: publish()
    onRegistryChanged: publish()

    function publish() {
        if (registry === null)
            return
        if (!live) {
            registry.remove("media")
            return
        }
        registry.publish("media", { category: "transport", staticIcon: "ms-music_note", title: title,
                                    status: title, app: "asteroid-music" })
    }
}
