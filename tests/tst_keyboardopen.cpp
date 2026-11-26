/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * An application's keyboard and the crown (lipstick/src/compositor/
 * eoskeyboardopen.h, gestures protocol version 3, CR-45): set and clear,
 * the gesture surface going away, the crown while open (close_keyboard)
 * and closed (Home), and the press after an unanswered close (Home).
 * Plain C++: cmake -DLAUNCHER_TESTS=ON, or
 * g++ -std=c++17 -I../lipstick/src/compositor tst_keyboardopen.cpp
 */

#include "eoskeyboardopen.h"

#include <cstdio>

using namespace EosKeyboard;

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

static void testSetClear()
{
    State k;
    CHECK(!k.open());                       // a new gesture surface: closed
    CHECK(k.set(true));                     // set_keyboard_open(1): changed
    CHECK(k.open());
    CHECK(!k.set(true));                    // the same again: no change (no property signal)
    CHECK(k.open());
    CHECK(k.set(false));                    // set_keyboard_open(0)
    CHECK(!k.open());
    CHECK(!k.set(false));
}

static void testSurfaceGone()
{
    State k;
    k.set(true);
    CHECK(k.surfaceGone());                 // destroyed with the keyboard up: closed
    CHECK(!k.open());
    CHECK(!k.surfaceGone());                // nothing to clear
    CHECK(k.crown(true) == GoHome);
}

static void testCrown()
{
    State k;
    // closed: the crown goes Home
    CHECK(k.crown(true) == GoHome);
    CHECK(k.crown(true) == GoHome);
    // open: the press closes the keyboard and does nothing else
    k.set(true);
    CHECK(k.crown(true) == CloseKeyboard);
    CHECK(k.open());                        // open until the client says it closed
    // the client closed it (set_keyboard_open 0): the next press goes Home
    CHECK(k.set(false));
    CHECK(k.crown(true) == GoHome);
    // opened again: the first press closes it again
    k.set(true);
    CHECK(k.crown(true) == CloseKeyboard);
}

static void testUnanswered()
{
    State k;
    k.set(true);
    CHECK(k.crown(true) == CloseKeyboard);
    // the client did not answer: the next press goes Home (the crown is never stuck)
    CHECK(k.crown(true) == GoHome);
    CHECK(k.crown(true) == GoHome);
    // the client reports its keyboard again (open): a press closes it once more
    k.set(true);
    CHECK(k.crown(true) == CloseKeyboard);
}

static void testCannotSend()
{
    State k;
    k.set(true);
    // no gesture surface to send close_keyboard on: the press goes Home
    CHECK(k.crown(false) == GoHome);
    CHECK(k.crown(true) == CloseKeyboard);
}

int main()
{
    testSetClear();
    testSurfaceGone();
    testCrown();
    testUnanswered();
    testCannotSend();
    printf("tst_keyboardopen: %d checks, %d failed\n", checks, failures);
    return failures ? 1 : 0;
}
