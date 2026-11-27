// Copyright (C) 2026 eos
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick
import "../eoskit"
import "../eoskit/facekit.js" as Kit

/*
 * Big Time: the layout of Wear OS's Big Time face (watch_face_bigtime.xml,
 * BigTimeWatchFaceService), our own drawing (A-07). The last face of the Wear OS 6
 * fresh carousel (S15). Very large hours over the minutes, two tones of the colour:
 *  - the hours in the colourway's text colour (gkz case 2: the interactive block
 *    gkw 19 sets g(), role "c"), the minutes in its light ramp (gkz case 3: the style
 *    block glb.a sets e(), role "e"); preview_bigtime.png: Pomelo #F8908B over #FFCBC9;
 *  - Color: the long list of 51 (all_colorway.xml), default Pomelo (index 5); no
 *    slot, no other option;
 *  - always-on: stock sets nothing in its ambient blocks, so the face looks the same
 *    (the same weight and colours); the sensor hub draws the digits (eosHubHour and
 *    eosHubMinute of EosTimeStack), so the AP sleeps through the minutes.
 * The numbers (boxes, size, weight) are Kit.BIG_TIME. Stock's Clepsydra is wider than
 * Roboto; ours matches the digits' height and stroke.
 */
EosFace {
    id: face

    eosOptions: [ Kit.colorOption("pomelo", Kit.ALL_COLORS) ]

    EosTimeStack {
        objectName: "eosTime"
        owner: face
        hourBox: Kit.BIG_TIME.hour
        minuteBox: Kit.BIG_TIME.minute
        size: Kit.BIG_TIME.size
        color: face.accent2
        minuteColor: face.accentLight
        ambientColor: face.accent2
        minuteAmbientColor: face.accentLight
        liveWeight: Font.Light
        ambientWeight: Font.Light
    }
}
