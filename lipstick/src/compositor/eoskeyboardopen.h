/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef EOSKEYBOARDOPEN_H
#define EOSKEYBOARDOPEN_H

/*
 * An application's full screen keyboard and the crown (gestures protocol
 * version 3, CR-45; text-input-04, heads-up-alerts-10). Stock Wear OS
 * (config_shortPressOnPowerBehavior 5, SHORT_PRESS_POWER_CLOSE_IME_OR_GO_HOME,
 * PowerKeyRule.java:130-160): a short press of the crown while the input
 * method shows hides it, and the next press goes Home. The client says when
 * its keyboard opens and closes (set_keyboard_open); while it is open the
 * window has the property EOS_KEYBOARD_OPEN (no heads-up over the keyboard,
 * notificationpreviewpresenter.cpp) and a crown press sends close_keyboard
 * instead of going Home.
 *
 * One State per window (LipstickCompositorWindow). A client that leaves its
 * keyboard open after close_keyboard (it hangs, or it lost the event) must
 * not keep the crown from going Home: the press after an unanswered close
 * goes Home. Plain C++, no I/O: tests/tst_keyboardopen.cpp.
 */
namespace EosKeyboard {

enum Crown { GoHome, CloseKeyboard };

class State
{
public:
    bool open() const { return m_open; }

    // set_keyboard_open from the client (0 or 1); true when open() changed
    bool set(bool open)
    {
        m_asked = false;
        if (m_open == open)
            return false;
        m_open = open;
        return true;
    }

    // the gesture surface (or its window) went away: closed; true when open() changed
    bool surfaceGone() { return set(false); }

    // A crown press with this window in front. canSend: the client can still
    // hear close_keyboard (its gesture surface is there, version 3).
    // CloseKeyboard: send close_keyboard, the press does nothing else; GoHome:
    // the press goes on as without a keyboard.
    Crown crown(bool canSend)
    {
        if (!m_open || !canSend || m_asked)
            return GoHome;
        m_asked = true;
        return CloseKeyboard;
    }

private:
    bool m_open = false;
    // close_keyboard was sent and the client has not answered since
    bool m_asked = false;
};

} // namespace EosKeyboard

#endif // EOSKEYBOARDOPEN_H
