/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef CROWNBUTTON_H
#define CROWNBUTTON_H

#include <QObject>
#include <QString>

/*
 * Presses of the crown button (the power key of the Pixel Watch 2, pmic
 * pwrkey) while the display is on, as Wear OS uses them: open the app list
 * from the watchface, back to the watchface from anywhere else.
 *
 * mce owns the key. install-ux2.sh sets its display-on single and double
 * press actions to "dbus1", and dbus action 1 to a signal with the argument
 * "asteroid-crown" (mcetool --set-powerkey-dbus-action=1,asteroid-crown);
 * mce then sends com.nokia.mce.signal.power_button_trigger("asteroid-crown")
 * on the system bus instead of blanking the display. Presses with the
 * display off still wake it (mce's display-off actions are left alone), and
 * the long press keeps its power menu.
 */
class CrownButton : public QObject
{
    Q_OBJECT
public:
    explicit CrownButton(QObject *parent = nullptr);

signals:
    /* A short press with the display on */
    void pressed();
    /* A short press that woke the display (mce unblanked first, then sent
     * "asteroid-crown-wake"): stock runs Home too when the display came out of
     * the always-on display and tilt- and touch-to-wake are both on; KeyRouter
     * decides */
    void wakePressed();
    /* The crown held 3000 ms (mce long_press_delay, actions_long_on=dbus2 with
     * dbus_action2=asteroid-crown-long, also from the always-on screen with
     * actions_long_off): the power menu, while the button is still down
     * (power-boot-warnings-01) */
    void longPressed();
    /* The crown went down and came up (mce with the crown edge triggers,
     * "asteroid-crown-down" and "asteroid-crown-up", in every display state):
     * touch lock's 2 s exit ring follows the button (wake-sleep-display-03) */
    void pressStarted();
    void released();
    /* mce's chord of the crown and the side button within 150 ms
     * (61eos-side-key.conf): "screenshot" */
    void screenshotRequested();
    /* Any other power_button_trigger argument (another dbusN action) */
    void triggered(const QString &action);

private slots:
    void onTrigger(const QString &action);
};

#endif // CROWNBUTTON_H
