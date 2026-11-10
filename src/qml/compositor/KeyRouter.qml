/*
 * Copyright (C) 2015 Florent Revest <revestflo@gmail.com>
 *               2014 Aleksi Suomalainen <suomalainen.aleksi@gmail.com>
 *               2013 John Brooks <john.brooks@dereferenced.net>
 *               2013 Jolla Ltd.
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
import org.asteroid.controls
import org.asteroid.utils

/* The hardware keys in the compositor (split out of compositor.qml): the
 * side button's hold (assistantKey: the assistant) and the crown button
 * (crownButton, mce's power_button_trigger, see CrownButton), as Wear OS
 * uses it: it dismisses the assistant, in an application it goes back to
 * the watchface (the window leaves as a Wear OS window does: down to 0.75
 * and fading, 250 ms), on the home screen the home screen decides (app
 * list, back to the watchface). Reads compositor.qml's ids (root, comp,
 * launchSplash, homeLoader) through the context. Owned by
 * W2-launcher-keys-lifecycle. */
QtObject {
    id: keyRouter

    /* The assistant over the home screen and applications (Wear OS: an
     * activity on top), under heads-up notifications, calls and alarms.
     * It opens on a hold of the side button (assistantKey, as the stock
     * Pixel Watch 2), from the app list and from the Assistant tile. */
    property Connections assistantKeyConnection: Connections {
        target: typeof assistantKey !== "undefined" ? assistantKey : null
        function onLongPressed() {
            // mce: held 500 ms, from any display state (it turns the
            // display on first)
            Haptics.longPress()
            root.openAssistant("")
        }
        function onOpenRequested(text) { root.openAssistant(text) }
    }

    property Connections crownButtonConnection: Connections {
        target: typeof crownButton !== "undefined" ? crownButton : null
        function onPressed() {
            // the crown dismisses the assistant, wherever it was opened
            if (root.assistantShown) {
                root.closeAssistant()
                return
            }
            if (launchSplash.active)
                return
            if (comp.appActive)
                root.closeTopmost()
            else if (homeLoader.item)
                homeLoader.item.crownPressed()
        }
    }
}
