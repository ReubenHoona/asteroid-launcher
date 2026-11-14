/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef EOSANR_H
#define EOSANR_H

/*
 * When the app in front is "not responding" (system-dialogs-misc-03), as
 * stock's input dispatcher: an app that does not take input for 5000 ms
 * (AOSP's default dispatching timeout) gets the non-cancelable "isn't
 * responding" dialog with Close app and Wait; Wait waits another 5 s;
 * background apps are silent (AppErrors.java:872-874).
 *
 * The compositor sends an xdg_wm_base ping to the client after it delivered
 * a touch and arms one single-shot 5 s timer; the pong stops it, so a
 * responsive app costs no timer expiry and a watch that is not touched sends
 * no ping at all. Never with the display off (the timer is checked against
 * it when it fires). This is the state of that exchange, plain C++
 * (tests/tst_anr.cpp); the Wayland calls are LipstickCompositor's.
 */
namespace EosAnr {

const long long TimeoutMs = 5000;

class Policy
{
public:
    /* A touch was delivered to window `id`: true when a ping has to go out
     * now (none is out for it, and its dialog is not up). */
    bool touched(int id, long long nowMs)
    {
        if (mShown || (mPending && mWindow == id))
            return false;
        mPending = true;
        mWindow = id;
        mSentAt = nowMs;
        return true;
    }

    /* The pong came: the app answered. */
    void ponged() { mPending = false; }

    /* The single-shot timer fired. True when the dialog has to show: a ping
     * is still out, the display is on and the same window is still in front. */
    bool expired(bool displayOn, int frontWindow)
    {
        if (!mPending)
            return false;
        mPending = false;
        if (!displayOn || frontWindow != mWindow)
            return false;
        mShown = true;
        return true;
    }

    /* "Wait": another ping and another 5 s. */
    void waited(long long nowMs)
    {
        mShown = false;
        mPending = true;
        mSentAt = nowMs;
    }

    /* The app was closed, or went away. */
    void closed()
    {
        mShown = false;
        mPending = false;
    }

    bool pending() const { return mPending; }
    bool shown() const { return mShown; }
    int window() const { return mWindow; }
    long long sentAt() const { return mSentAt; }

private:
    bool mPending = false;
    bool mShown = false;
    int mWindow = -1;
    long long mSentAt = 0;
};

} // namespace EosAnr

#endif // EOSANR_H
