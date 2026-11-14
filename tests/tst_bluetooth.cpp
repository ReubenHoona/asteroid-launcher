/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The pairing rules (lipstick/src/eosbluetooth.h). Plain C++:
 * g++ -std=c++17 -I../lipstick/src tst_bluetooth.cpp
 */

#include "eosbluetooth.h"

#include <cstdio>

using namespace EosBluetooth;

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

int main()
{
    // connectivity-system-ux-02: the phone class picks the wording (major class 0x200 in stock)
    CHECK(isPhoneClass(0x5a020c));     // a typical smart phone
    CHECK(isPhoneClass(0x200));
    CHECK(!isPhoneClass(0x240404));    // audio/video
    CHECK(!isPhoneClass(0x000100));    // computer
    CHECK(!isPhoneClass(0));           // LE only: no class

    // connectivity-system-ux-01: no address in the title
    CHECK(looksLikeAddress("AA-BB-CC-DD-EE-FF"));
    CHECK(looksLikeAddress("aa:bb:cc:dd:ee:0f"));
    CHECK(!looksLikeAddress("Pixel 8"));
    CHECK(!looksLikeAddress("AA-BB-CC-DD-EE-FG"));
    CHECK(!looksLikeAddress("AA-BB-CC-DD-EE-F"));
    CHECK(displayName("Pixel 8", "x") == "Pixel 8");
    CHECK(displayName("AA-BB-CC-DD-EE-FF", "Pixel 8") == "Pixel 8");
    CHECK(displayName("AA-BB-CC-DD-EE-FF", "") == "");
    CHECK(displayName("", "") == "");
    CHECK(displayName("", "My phone") == "My phone");

    // the short title: the formatted text is over 18 characters (stock checks the whole title)
    CHECK(!useShortTitle(std::string("Secure pair with X").size()));
    CHECK(useShortTitle(std::string("Secure pair with Xy").size()));
    CHECK(!useShortTitle(std::string("Legacy pair with X").size()));
    CHECK(isLegacy(Request::PinCode));
    CHECK(isLegacy(Request::DisplayPinCode));
    CHECK(!isLegacy(Request::Passkey));
    CHECK(!isLegacy(Request::Confirmation));
    CHECK(!isLegacy(Request::DisplayPasskey));
    CHECK(!isLegacy(Request::Authorization));

    // connectivity-system-ux-03: a bonded device's service is authorised silently, an unbonded one's refused
    CHECK(authorizeService(true) == ServiceReply::Accept);
    CHECK(authorizeService(false) == ServiceReply::Reject);
    CHECK(!opensWindow(Request::Service));
    CHECK(opensWindow(Request::PinCode));
    CHECK(opensWindow(Request::Confirmation));
    CHECK(opensWindow(Request::Authorization));

    printf("%d checks, %d failed\n", checks, failures);
    return failures ? 1 : 0;
}
