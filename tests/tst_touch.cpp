/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

// The multi-tap recognizer (src/eostouch.h) and the observer built on it (src/touchobserver.*)
// against synthetic touch streams:  ./tst_touch

#include "touchobserver.h"

#include <QCoreApplication>
#include <QEventLoop>
#include <QTimer>
#include <cstdio>

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

using namespace EosTouch;

static void spin(int ms)
{
    QEventLoop loop;
    QTimer::singleShot(ms, &loop, &QEventLoop::quit);
    loop.exec();
}

// one tap of n fingers: down together at t, up `hold` ms later
static void tap(TapSequence &s, int n, qint64 t, qint64 hold, QPointF at = QPointF(100, 100), double spread = 10)
{
    for (int i = 0; i < n; ++i)
        s.down(i, at + QPointF(i * spread, 0), t + i * 5);
    for (int i = 0; i < n; ++i)
        s.up(i, t + (n - 1) * 5 + hold);
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);

    // ---- stock's numbers ----
    CHECK(TAP_TIMEOUT_MS == 100 && DOUBLE_TAP_TIMEOUT_MS == 300 && MAGNIFICATION_ADJUST_MS == 25);
    CHECK(TOUCH_SLOP_DP == 8 && DOUBLE_TAP_SLOP_DP == 100);

    // ---- a one-finger triple tap ----
    {
        TapSequence s(2.0, MAGNIFICATION_ADJUST_MS);
        CHECK(s.gapMs() == 325);
        tap(s, 1, 0, 60);
        CHECK(s.taps() == 1 && s.fingers() == 1);
        CHECK(s.deadline() == 60 + 325);
        tap(s, 1, 200, 60, QPointF(110, 105));
        CHECK(s.taps() == 2);
        tap(s, 1, 400, 60, QPointF(95, 95));
        CHECK(s.taps() == 3);
        Result r = s.current();
        CHECK(r.valid() && r.fingers == 1 && r.taps == 3);
    }
    // the gap: 325 ms from the up is in, 326 is a new sequence
    {
        TapSequence s(2.0, MAGNIFICATION_ADJUST_MS);
        tap(s, 1, 0, 50);
        tap(s, 1, 50 + 325, 50);
        CHECK(s.taps() == 2);
        TapSequence s2(2.0, MAGNIFICATION_ADJUST_MS);
        tap(s2, 1, 0, 50);
        tap(s2, 1, 50 + 326, 50);
        CHECK(s2.taps() == 1);   // a new sequence
    }
    // without the adjustment 300 ms
    {
        TapSequence s(2.0);
        tap(s, 1, 0, 50);
        tap(s, 1, 50 + 301, 50);
        CHECK(s.taps() == 1);
    }
    // a tap held longer than 100 ms is no tap; 100 ms is
    {
        TapSequence s(2.0);
        tap(s, 1, 0, 100);
        CHECK(s.taps() == 1);
        TapSequence s2(2.0);
        tap(s2, 1, 0, 101);
        CHECK(s2.taps() == 0 && !s2.open());
    }
    // a finger that moves more than 8 dp (16 px at 2 px/dp) makes no tap
    {
        TapSequence s(2.0);
        s.down(0, QPointF(100, 100), 0);
        s.move(0, QPointF(115, 100), 10);
        s.up(0, 40);
        CHECK(s.taps() == 1);
        TapSequence s2(2.0);
        s2.down(0, QPointF(100, 100), 0);
        s2.move(0, QPointF(117, 100), 10);
        s2.up(0, 40);
        CHECK(s2.taps() == 0);
    }
    // the second tap must be within 100 dp (200 px) of the first
    {
        TapSequence s(2.0);
        tap(s, 1, 0, 50, QPointF(50, 50));
        tap(s, 1, 150, 50, QPointF(240, 50));
        CHECK(s.taps() == 2);
        TapSequence s2(2.0);
        tap(s2, 1, 0, 50, QPointF(50, 50));
        tap(s2, 1, 150, 50, QPointF(260, 50));
        CHECK(s2.taps() == 1);   // too far: a new sequence
    }
    // two fingers: once, twice; fingers must stay the count of the first tap
    {
        TapSequence s(2.0);
        tap(s, 2, 0, 60);
        CHECK(s.fingers() == 2 && s.taps() == 1);
        tap(s, 2, 150, 60);
        CHECK(s.taps() == 2);
        CHECK(s.deadline() == 150 + 5 + 60 + 300);
        Result r = s.finish();
        CHECK(r.valid() && r.fingers == 2 && r.taps == 2);
        CHECK(!s.open());
    }
    {
        TapSequence s(2.0);
        tap(s, 2, 0, 60);
        tap(s, 3, 150, 60);      // a third finger: the sequence fails
        CHECK(s.taps() == 0);
    }
    {
        TapSequence s(2.0);
        tap(s, 2, 0, 60);
        tap(s, 1, 150, 60);      // fewer fingers: not the same gesture
        CHECK(s.taps() == 0);
    }
    // two fingers that are not down together: the first one waits more than 100 ms for the second
    {
        TapSequence s(2.0);
        s.down(0, QPointF(100, 100), 0);
        s.down(1, QPointF(120, 100), 90);
        s.up(0, 150);       // 60 ms after the last down: a tap
        s.up(1, 160);
        CHECK(s.taps() == 1 && s.fingers() == 2);
        TapSequence s2(2.0);
        s2.down(0, QPointF(100, 100), 0);
        s2.down(1, QPointF(120, 100), 90);
        s2.up(0, 200);      // 110 ms after the last down: too long
        s2.up(1, 210);
        CHECK(s2.taps() == 0);
    }
    // a failed sequence starts again with the next touch
    {
        TapSequence s(2.0);
        tap(s, 1, 0, 300);
        CHECK(s.taps() == 0);
        tap(s, 1, 500, 50);
        CHECK(s.taps() == 1);
    }

    // ---- the observer ----
    {
        TouchObserver o;
        o.setDensity(2.0);
        int n = 0, lastF = 0, lastT = 0;
        double lx = 0, ly = 0;
        QObject::connect(&o, &TouchObserver::multiTap, [&](int f, int t, double x, double y) { n++; lastF = f; lastT = t; lx = x; ly = y; });
        // nothing asked for: nothing seen
        auto oneTap = [&](qint64 t, QPointF p, int id = 0) {
            o.feed(TouchObserver::Down, id, p, t);
            o.feed(TouchObserver::Up, id, p, t + 40);
        };
        oneTap(0, QPointF(10, 20)); oneTap(100, QPointF(10, 20)); oneTap(200, QPointF(10, 20));
        spin(10);
        CHECK(n == 0);

        o.setTripleTap(true);
        // the real clock runs the timer, the events carry their own: a triple at once on the third up
        oneTap(1000, QPointF(100, 120)); oneTap(1100, QPointF(104, 118));
        CHECK(n == 0);
        oneTap(1200, QPointF(98, 122));
        CHECK(n == 1 && lastF == 1 && lastT == 3);
        CHECK(lx == 98 && ly == 122);
        // a double tap: nothing
        oneTap(2000, QPointF(5, 5)); oneTap(2100, QPointF(5, 5));
        spin(400);
        CHECK(n == 1);
        // two fingers are not wanted yet
        o.feed(TouchObserver::Down, 0, QPointF(100, 100), 3000);
        o.feed(TouchObserver::Down, 1, QPointF(130, 100), 3005);
        o.feed(TouchObserver::Up, 0, QPointF(100, 100), 3050);
        o.feed(TouchObserver::Up, 1, QPointF(130, 100), 3055);
        spin(400);
        CHECK(n == 1);

        o.setTripleTap(false);
        o.setTwoFingerTaps(true);
        // two fingers once: reported when the gap has passed (300 ms)
        o.feed(TouchObserver::Down, 0, QPointF(100, 100), 4000);
        o.feed(TouchObserver::Down, 1, QPointF(130, 100), 4005);
        o.feed(TouchObserver::Up, 0, QPointF(100, 100), 4050);
        o.feed(TouchObserver::Up, 1, QPointF(130, 100), 4055);
        CHECK(n == 1);
        spin(150);
        CHECK(n == 1);       // not yet: 300 ms has not passed
        spin(250);
        CHECK(n == 2 && lastF == 2 && lastT == 1);
        // twice: one report
        o.feed(TouchObserver::Down, 0, QPointF(100, 100), 5000);
        o.feed(TouchObserver::Down, 1, QPointF(130, 100), 5005);
        o.feed(TouchObserver::Up, 0, QPointF(100, 100), 5050);
        o.feed(TouchObserver::Up, 1, QPointF(130, 100), 5055);
        o.feed(TouchObserver::Down, 0, QPointF(100, 100), 5150);
        o.feed(TouchObserver::Down, 1, QPointF(130, 100), 5155);
        o.feed(TouchObserver::Up, 0, QPointF(100, 100), 5200);
        o.feed(TouchObserver::Up, 1, QPointF(130, 100), 5205);
        spin(450);
        CHECK(n == 3 && lastF == 2 && lastT == 2);
        // a one-finger tap is nothing to it
        oneTap(6000, QPointF(5, 5));
        spin(400);
        CHECK(n == 3);
        // turned off: the filter goes
        o.setTwoFingerTaps(false);
        CHECK(!o.tripleTap() && !o.twoFingerTaps());
    }

    printf("tst_touch: %d checks, %d failures\n", checks, failures);
    return failures ? 1 : 0;
}
