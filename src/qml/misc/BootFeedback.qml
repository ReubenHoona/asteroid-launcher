/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.DBus
import Nemo.Ngf

/* The boot-complete feedback (R5 B-09; power-boot-warnings-06 = haptics-sounds-10), as stock's
 * BootCompletedFeedbackProvider: when the boot screen has handed over to the first face (splashDone), the
 * screen is woken (mce req_display_state_on, "Keyguard: locked boot completed") and ngfd's boot_done plays:
 * the two-part haptic (quick fall, quick rise 80 ms later) and the after-reboot sound, a system sound that is
 * silent while ring and notifications are muted (meta-eos64 events.d/boot_done.ini). Not after an update's trial
 * boot, not during setup, once per boot: firstRun.bootFeedbackDue() decides (eosbootfeedback.h). A restart of
 * the launcher in the same boot plays nothing. Nothing runs after that one check. */
Item {
    id: feedback
    visible: false
    width: 0
    height: 0

    // the boot screen is gone (Splash.done)
    property bool splashDone: false
    // it was asked (once per launcher start); played: the boot's feedback ran
    property bool asked: false
    property bool played: false

    onSplashDoneChanged: check()
    Component.onCompleted: check()

    function check() {
        if (!splashDone || asked)
            return
        asked = true
        if (typeof firstRun === "undefined" || firstRun === null || typeof firstRun.bootFeedbackDue !== "function")
            return
        if (!firstRun.bootFeedbackDue())
            return
        played = true
        mce.call("req_display_state_on", undefined)
        bootDone.play()
    }

    DBusInterface {
        id: mce
        bus: DBus.SystemBus
        service: "com.nokia.mce"
        path: "/com/nokia/mce/request"
        iface: "com.nokia.mce.request"
    }
    NonGraphicalFeedback {
        id: bootDone
        objectName: "bootDoneFeedback"
        event: "boot_done"
    }
}
