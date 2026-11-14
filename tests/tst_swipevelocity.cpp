/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The finger speed of a swipe (src/swipevelocity.h): a steady swipe in
 * px/s, the 100 ms horizon, the 40 ms stop rule, repeated samples, the
 * sample ring. Plain C++: g++ -std=c++17 -I../src tst_swipevelocity.cpp
 */
#include "swipevelocity.h"

#include <cmath>
#include <cstdio>

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)
#define NEAR(a, b, tol) do { checks++; const double _a = (a), _b = (b); if (std::fabs(_a - _b) > (tol)) { fprintf(stderr, "FAIL %s:%d: %s = %f, want %f +- %f\n", __FILE__, __LINE__, #a, _a, _b, (double)(tol)); failures++; } } while (0)

int main()
{
    SwipeVelocity v;
    CHECK(v.count() == 0);
    NEAR(v.vy(), 0, 1e-9);

    // one sample: no speed
    v.add(1000, 10, 100);
    NEAR(v.vy(), 0, 1e-9);

    // a steady swipe down at 1200 px/s sampled every 8 ms (9.6 px a step)
    v.reset();
    for (int i = 0; i < 30; ++i)
        v.add(1000 + 8 * i, 200 + 0.5 * i, 100 + 9.6 * i);
    NEAR(v.vy(), 1200, 1);
    NEAR(v.vx(), 0.5 / 0.008, 1);
    CHECK(v.lastTime() == 1000 + 8 * 29);

    // upwards: negative
    v.reset();
    for (int i = 0; i < 30; ++i)
        v.add(5000 + 10 * i, 200, 400 - 12.0 * i);
    NEAR(v.vy(), -1200, 1);

    // the 1000 px/s fling rule sits between 900 and 1100 px/s
    v.reset();
    for (int i = 0; i < 12; ++i)
        v.add(100 * 0 + 16 * i, 0, 14.4 * i);          // 900 px/s
    NEAR(v.vy(), 900, 1);
    v.reset();
    for (int i = 0; i < 12; ++i)
        v.add(16 * i, 0, 17.6 * i);                    // 1100 px/s
    NEAR(v.vy(), 1100, 1);

    // only the last 100 ms count: slow for a second, then 2000 px/s
    v.reset();
    for (int i = 0; i < 10; ++i)
        v.add(i * 30, 0, i * 3.0);                     // 100 px/s up to 270 ms
    for (int i = 1; i <= 8; ++i)
        v.add(270 + i * 12, 0, 27 + i * 24.0);         // 2000 px/s for 96 ms
    NEAR(v.vy(), 2000, 60);

    // a finger that rested more than 40 ms before it lifted has no speed
    v.reset();
    for (int i = 0; i < 10; ++i)
        v.add(i * 10, 0, i * 20.0);                    // 2000 px/s
    v.add(90 + 41, 0, 180);                            // lifts after 41 ms at the same place
    NEAR(v.vy(), 0, 1e-9);
    // exactly 40 ms is not yet a stop: the window goes on back through it,
    // and the swipe still counts (slower, the rest at the end)
    v.reset();
    for (int i = 0; i < 10; ++i)
        v.add(i * 10, 0, i * 20.0);
    v.add(90 + 40, 0, 180);
    CHECK(v.vy() > 500 && v.vy() < 2000);
    // a slow-down: the last 3 samples still at 40 ms apart count together
    v.reset();
    v.add(0, 0, 0);
    v.add(40, 0, 40);
    v.add(80, 0, 80);
    NEAR(v.vy(), 1000, 1);

    // the same time twice (one event seen by two filters): one sample, the last position
    v.reset();
    v.add(0, 0, 0);
    v.add(10, 0, 10);
    v.add(10, 0, 12);
    CHECK(v.count() == 2);
    NEAR(v.vy(), 1200, 1);

    // more samples than the ring holds: the newest 24 are used
    v.reset();
    for (int i = 0; i < 100; ++i)
        v.add(i * 4, 0, i * 4.0);                      // 1000 px/s
    CHECK(v.count() == SwipeVelocity::MAX_SAMPLES);
    NEAR(v.vy(), 1000, 1);

    // all samples at one time cannot be divided by zero time
    v.reset();
    v.add(5, 0, 0);
    v.add(5, 0, 50);
    NEAR(v.vy(), 0, 1e-9);

    if (failures) {
        fprintf(stderr, "%d of %d checks failed\n", failures, checks);
        return 1;
    }
    printf("tst_swipevelocity: %d checks passed\n", checks);
    return 0;
}
