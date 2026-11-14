/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "crownbutton.h"

#include <QDBusConnection>
#include <QDebug>

static const char MCE_SIGNAL_PATH[] = "/com/nokia/mce/signal";
static const char MCE_SIGNAL_IF[] = "com.nokia.mce.signal";
static const char MCE_POWER_BUTTON_TRIGGER[] = "power_button_trigger";
static const char CROWN_ACTION[] = "asteroid-crown";
// mce actions_single_off=unblank,dbus3 with dbus_action3=asteroid-crown-wake: a press
// that woke the display (meta-eos64 60eos-crown.conf; buttons-navigation-18)
static const char CROWN_WAKE_ACTION[] = "asteroid-crown-wake";
// the crown held 3000 ms (60eos-crown.conf: long_press_delay 3000, actions_long_on=dbus2)
static const char CROWN_LONG_ACTION[] = "asteroid-crown-long";
// the crown's edges (the mce crown trigger patch)
static const char CROWN_DOWN_ACTION[] = "asteroid-crown-down";
static const char CROWN_UP_ACTION[] = "asteroid-crown-up";
// mce 0005: the chord of the crown and the side button
static const char CHORD_SCREENSHOT_ACTION[] = "screenshot";

CrownButton::CrownButton(QObject *parent) : QObject(parent)
{
    /* any sender: mce broadcasts it */
    if (!QDBusConnection::systemBus().connect(QString(), QLatin1String(MCE_SIGNAL_PATH),
                                              QLatin1String(MCE_SIGNAL_IF),
                                              QLatin1String(MCE_POWER_BUTTON_TRIGGER),
                                              this, SLOT(onTrigger(QString))))
        qWarning() << "CrownButton: cannot listen to mce's power_button_trigger";
}

void CrownButton::onTrigger(const QString &action)
{
    if (action == QLatin1String(CROWN_ACTION))
        emit pressed();
    else if (action == QLatin1String(CROWN_WAKE_ACTION))
        emit wakePressed();
    else if (action == QLatin1String(CROWN_LONG_ACTION))
        emit longPressed();
    else if (action == QLatin1String(CROWN_DOWN_ACTION))
        emit pressStarted();
    else if (action == QLatin1String(CROWN_UP_ACTION))
        emit released();
    else if (action == QLatin1String(CHORD_SCREENSHOT_ACTION))
        emit screenshotRequested();
    else
        emit triggered(action);
}
