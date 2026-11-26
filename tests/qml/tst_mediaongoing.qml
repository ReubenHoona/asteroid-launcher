/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

// The media session's ongoing entry (src/qml/home/MediaOngoing.qml, status-indicators-14): the chip is
// there only while the session plays (stock); paused, stopped or without a track it goes. The session's
// values are set on the item (service, trackTitle, playbackStatus with Amber.Mpris' values); the registry
// is a recorder with the context name ongoingRegistry. MODE=st (the staged tree).
import QtQuick
import QtTest
import Amber.Mpris

Item {
    id: top
    width: 384
    height: 384

    QtObject {
        id: ongoingRegistry
        property var entries: ({})
        property int publishes: 0
        function publish(id, props) { var e = Object.assign({}, entries); e[id] = props; entries = e; publishes++ }
        function remove(id) { var e = Object.assign({}, entries); delete e[id]; entries = e }
    }

    Loader { id: ml; active: false; source: Qt.resolvedUrl("st/qml/home/MediaOngoing.qml") }

    TestCase {
        name: "MediaOngoing"
        when: windowShown

        property var media: null

        function initTestCase() {
            ml.active = true
            tryCompare(ml, "status", Loader.Ready, 30000)
            media = ml.item
            media.service = "org.mpris.MediaPlayer2.phone"
            media.trackTitle = "Night Drive"
        }

        function test_00_playing_has_the_chip() {
            media.playbackStatus = Mpris.Playing
            verify(media.live)
            var e = ongoingRegistry.entries["media"]
            verify(e !== undefined)
            compare(e.category, "transport")
            compare(e.status, "Night Drive")
            compare(e.app, "asteroid-music")
        }

        function test_01_paused_has_none() {
            media.playbackStatus = Mpris.Playing
            verify(ongoingRegistry.entries["media"] !== undefined)
            media.playbackStatus = Mpris.Paused
            verify(!media.live)
            compare(ongoingRegistry.entries["media"], undefined)
            // playing again: back
            media.playbackStatus = Mpris.Playing
            verify(ongoingRegistry.entries["media"] !== undefined)
        }

        function test_02_stopped_or_no_track_has_none() {
            media.playbackStatus = Mpris.Playing
            media.playbackStatus = Mpris.Stopped
            compare(ongoingRegistry.entries["media"], undefined)
            media.playbackStatus = Mpris.Playing
            media.trackTitle = ""
            compare(ongoingRegistry.entries["media"], undefined)
            media.trackTitle = "Night Drive"
            media.service = ""
            compare(ongoingRegistry.entries["media"], undefined)
            media.service = "org.mpris.MediaPlayer2.phone"
            verify(ongoingRegistry.entries["media"] !== undefined)
        }

        function test_03_a_new_track_updates_it() {
            media.playbackStatus = Mpris.Playing
            media.trackTitle = "Morning"
            compare(ongoingRegistry.entries["media"].status, "Morning")
        }
    }
}
