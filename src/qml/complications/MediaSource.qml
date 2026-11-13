/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Amber.Mpris

// What plays, for the Media controls complication (stock: the title and
// the artist, or 'Media controls' and 'Nothing playing'): the phone's
// player (asteroid-btsyncd's MPRIS) or the watch's, as the media tile
// reads it. Loaded only while a slot shows it; D-Bus signals only.
QtObject {
    id: source

    property bool active: false
    readonly property bool present: active && mpris.currentService !== "" && mpris.currentService !== undefined
                                    && mpris.metaData.title !== undefined && mpris.metaData.title !== ""
    readonly property string title: present ? mpris.metaData.title : ""
    readonly property string artist: present ? (mpris.metaData.contributingArtist || []).join(", ") : ""
    readonly property bool playing: present && mpris.playbackStatus === Mpris.Playing

    property MprisController mpris: MprisController { }
}
