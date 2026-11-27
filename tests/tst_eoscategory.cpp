/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * M4 WO-12: what a notification's x-asteroid-category asks of the notification server
 * (lipstick/src/notifications/eoscategory.h): asteroid-sensorlogd's heart rate alert ("health-alert") as stock's
 * HrAlertService notification (Fitbit 4.01.1, HrAlertService.java:60-110): category "alarm" (its feedback plays
 * in Bedtime, Theater and Do Not Disturb), one card (a new alert replaces the app's card of it and alerts as a new
 * post), full screen instead of a banner. Every other category as before. And a lint: the server applies it
 * where it posts, plays and presents (NOTIFIER_SRC). Plain C++: cmake -DLAUNCHER_TESTS=ON, or
 * g++ -std=c++17 -I../lipstick/src/notifications -DNOTIFIER_SRC=\"../lipstick/src/notifications\".
 */

#include "eoscategory.h"

#include <cstdio>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

using namespace EosCategory;

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

static std::string readFile(const std::string &path)
{
    std::ifstream f(path);
    std::stringstream s;
    s << f.rdbuf();
    return s.str();
}

int main()
{
    // the heart rate alert is all three; nothing else is any of them, but a celebration is full screen (R5 E-06)
    CHECK(alarm("health-alert"));
    CHECK(oneId("health-alert"));
    CHECK(fullScreen("health-alert"));
    CHECK(fullScreen("celebration"));
    CHECK(!alarm("celebration"));
    CHECK(!oneId("celebration"));
    for (const char *c : { "", "alarm", "exercise-detect", "ongoing", "health", "Health-Alert", "Celebration" }) {
        CHECK(!alarm(c));
        CHECK(!oneId(c));
        CHECK(!fullScreen(c));
    }

    // its feedback (sensorlogd: notif_strong) plays in every mode, as an alarm's
    for (bool quiet : { false, true })
        for (bool dnd : { false, true })
            CHECK(modeFeedback("health-alert", quiet, dnd, "notif_strong") == "notif_strong");
    // ...any other post as eosquietpolicy.h says: a notification's not in the modes, an alarm's in all
    CHECK(modeFeedback("", false, false, "notif_strong") == "notif_strong");
    CHECK(modeFeedback("", true, false, "notif_strong").empty());
    CHECK(modeFeedback("", false, true, "notif_strong").empty());
    CHECK(modeFeedback("celebration", true, true, "notif_strong").empty());
    CHECK(modeFeedback("", true, true, "alarm") == "alarm");
    CHECK(modeFeedback("alarm", true, false, "eos_phone_alarm") == "eos_phone_alarm");
    CHECK(modeFeedback("", false, true, "ringtone") == "ringtone");
    CHECK(modeFeedback("", true, false, "ringtone").empty());
    // a call still holds it after (feedbackInCall): in progress, only alarms ring
    CHECK(EosQuiet::feedbackInCall(2, modeFeedback("health-alert", false, false, "notif_strong")).empty());
    CHECK(EosQuiet::feedbackInCall(1, modeFeedback("health-alert", true, true, "notif_strong")) == "notif_strong");

    // one card: a post of the category takes the place of the app's cards of it, whatever id it names
    const std::vector<Card> cards = { { 3, "Health", "health-alert" }, { 4, "Health", "celebration" },
                                      { 5, "Messages", "" }, { 7, "Other", "health-alert" } };
    CHECK((replacedCards("Health", "health-alert", cards) == std::vector<unsigned>{ 3 }));
    // the poster restarted (no id) or the card it named was cleared (none left): a new card
    CHECK(replacedCards("Health", "health-alert", {}).empty());
    CHECK(replacedCards("Health", "health-alert", { { 4, "Health", "celebration" } }).empty());
    // two left over from before (an older launcher): both go
    CHECK((replacedCards("Health", "health-alert", { { 3, "Health", "health-alert" }, { 9, "Health", "health-alert" } })
           == std::vector<unsigned>{ 3, 9 }));
    // another app's alert stays; any other category replaces nothing
    CHECK((replacedCards("Other", "health-alert", cards) == std::vector<unsigned>{ 7 }));
    CHECK(replacedCards("Health", "celebration", cards).empty());
    CHECK(replacedCards("Messages", "", cards).empty());

    // the lint: the notification server applies the rules where it posts, plays and presents
    const std::string dir = NOTIFIER_SRC;
    const std::string manager = readFile(dir + "/notificationmanager.cpp");
    const std::string player = readFile(dir + "/notificationfeedbackplayer.cpp");
    const std::string presenter = readFile(dir + "/notificationpreviewpresenter.cpp");
    const std::string presenterH = readFile(dir + "/notificationpreviewpresenter.h");
    CHECK(manager.find("EosCategory::replacedCards(") != std::string::npos);
    CHECK(manager.find("EosCategory::oneId(") != std::string::npos);
    // in Notify, before the id is chosen
    CHECK(manager.find("EosCategory::replacedCards(") < manager.find("uint id = replacesId != 0 ? replacesId : nextAvailableNotificationID();"));
    // the player: on arrival and when a mode comes on (two places)
    size_t first = player.find("EosCategory::modeFeedback(");
    CHECK(first != std::string::npos);
    CHECK(first != std::string::npos && player.find("EosCategory::modeFeedback(", first + 1) != std::string::npos);
    // the presenter: no banner, the full screen signal
    CHECK(presenter.find("EosCategory::fullScreen(") != std::string::npos);
    CHECK(presenter.find("emit fullScreenRequested(notification)") != std::string::npos);
    CHECK(presenterH.find("void fullScreenRequested(QObject *notification);") != std::string::npos);

    printf("tst_eoscategory: %d checks, %d failed\n", checks, failures);
    return failures ? 1 : 0;
}
