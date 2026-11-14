/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef EOSTOUCH_H
#define EOSTOUCH_H

#include <QHash>
#include <QPointF>
#include <QtGlobal>
#include <cmath>

/*
 * Multi-finger multi-tap recognition (W3-launcher-a11y-security: the
 * magnification's triple tap, accessibility-lock-security-15, and the
 * vibration watch's two-finger taps, -21), plain Qt Core so that
 * tests/tst_touch.cpp feeds it synthetic touch streams.
 *
 * Stock CP3A's accessibility gesture detectors are android's
 * MultiFingerMultiTap (the vibration watch service, decompiled in
 * VibrationWatchService.onMotionEvent) and MagnificationGestureHandler:
 *  - a tap is every finger of it down and the first one up within the tap
 *    timeout (100 ms, ViewConfiguration.getTapTimeout) of the last finger
 *    going down, none of them moving more than the touch slop (8 dp);
 *  - the next tap must begin within the double tap timeout (300 ms, getDoubleTapTimeout;
 *    +25 ms for the magnification on a watch,
 *    config_screen_magnification_multi_tap_adjustment) of the last finger of
 *    the one before leaving, and within the double tap slop (100 dp) of it;
 *  - every tap of a sequence has the finger count of the first one;
 *  - the sequence ends when the timeout passes without a next tap.
 * The sequence reports (fingers, taps, where). It reads no clock: the caller
 * gives the time of each event and arms one single-shot timer for deadline()
 * while a sequence is open (no polling).
 */
namespace EosTouch {

constexpr qint64 TAP_TIMEOUT_MS = 100;
constexpr qint64 DOUBLE_TAP_TIMEOUT_MS = 300;
constexpr qint64 MAGNIFICATION_ADJUST_MS = 25;
constexpr double TOUCH_SLOP_DP = 8;
constexpr double DOUBLE_TAP_SLOP_DP = 100;

struct Result {
    int fingers = 0;
    int taps = 0;
    QPointF where;
    bool valid() const { return taps > 0 && fingers > 0; }
};

class TapSequence
{
public:
    // dp: pixels per dp; extraGapMs: added to the double tap timeout
    explicit TapSequence(double dp = 1.0, qint64 extraGapMs = 0) : mDp(dp), mExtra(extraGapMs) {}

    void setDensity(double dp) { mDp = dp; }
    void setExtraGap(qint64 ms) { mExtra = ms; }
    qint64 gapMs() const { return DOUBLE_TAP_TIMEOUT_MS + mExtra; }

    void down(int id, const QPointF &p, qint64 t)
    {
        if (mFingers.isEmpty()) {
            // a new tap: the one before must be near enough in time and place, else a new sequence
            if (mTaps > 0 && (mFailed || t - mLastUp > gapMs() || far(p, mWhere, DOUBLE_TAP_SLOP_DP)))
                reset();
            if (mTaps == 0)
                mFailed = false;
            mTapFailed = mFailed;
            mTapMax = 0;
        }
        mFingers.insert(id, { p, p, t });
        mLastDown = t;
        mFirstUpSeen = false;
        mTapMax = qMax(mTapMax, int(mFingers.size()));
        if (mTaps > 0 && mTapMax > mSeqFingers)
            mFailed = mTapFailed = true;
    }

    void move(int id, const QPointF &p, qint64 t)
    {
        Q_UNUSED(t);
        auto it = mFingers.find(id);
        if (it == mFingers.end())
            return;
        it->now = p;
        if (far(p, it->start, TOUCH_SLOP_DP))
            mFailed = mTapFailed = true;
    }

    void up(int id, qint64 t)
    {
        auto it = mFingers.find(id);
        if (it == mFingers.end())
            return;
        if (!mFirstUpSeen) {
            mFirstUpSeen = true;
            if (t - mLastDown > TAP_TIMEOUT_MS)
                mFailed = mTapFailed = true;
        }
        mTapPoints.append(it->start);
        mFingers.erase(it);
        if (!mFingers.isEmpty())
            return;
        // the last finger is up: the tap is over
        if (!mTapFailed) {
            if (mTaps == 0)
                mSeqFingers = mTapMax;
            if (mTapMax == mSeqFingers) {
                QPointF c;
                for (const QPointF &q : std::as_const(mTapPoints))
                    c += q;
                mWhere = c / qMax<qsizetype>(1, mTapPoints.size());
                mTaps++;
                mLastUp = t;
            } else {
                mFailed = true;
            }
        }
        mTapPoints.clear();
    }

    // a touch ended without its up (cancelled): the sequence is over
    void cancel() { reset(); }

    bool open() const { return mTaps > 0 && !mFailed; }
    bool fingersDown() const { return !mFingers.isEmpty(); }
    int taps() const { return mFailed ? 0 : mTaps; }
    int fingers() const { return mSeqFingers; }

    // when the sequence ends if nothing else happens (ms of the events' clock), -1 = not open or a finger is down
    qint64 deadline() const { return open() && mFingers.isEmpty() ? mLastUp + gapMs() : -1; }

    // what the sequence so far is; invalid when it failed
    Result current() const
    {
        Result r;
        if (open() && mFingers.isEmpty()) {
            r.fingers = mSeqFingers;
            r.taps = mTaps;
            r.where = mWhere;
        }
        return r;
    }

    // the timeout passed: the result, and a new start
    Result finish()
    {
        const Result r = current();
        reset();
        return r;
    }

    void reset()
    {
        mFingers.clear();
        mTapPoints.clear();
        mTaps = 0;
        mSeqFingers = 0;
        mTapMax = 0;
        mFailed = mTapFailed = false;
        mFirstUpSeen = false;
    }

private:
    struct Finger { QPointF start; QPointF now; qint64 downAt; };

    bool far(const QPointF &a, const QPointF &b, double dp) const
    {
        const double d = dp * mDp;
        return std::hypot(a.x() - b.x(), a.y() - b.y()) > d;
    }

    double mDp;
    qint64 mExtra;
    QHash<int, Finger> mFingers;
    QList<QPointF> mTapPoints;
    int mTaps = 0;
    int mSeqFingers = 0;
    int mTapMax = 0;
    bool mFailed = false;
    bool mTapFailed = false;
    bool mFirstUpSeen = false;
    qint64 mLastDown = 0;
    qint64 mLastUp = 0;
    QPointF mWhere;
};

} // namespace EosTouch

#endif // EOSTOUCH_H
