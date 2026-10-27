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
    /* Any other power_button_trigger argument (another dbusN action) */
    void triggered(const QString &action);

private slots:
    void onTrigger(const QString &action);
};

#endif // CROWNBUTTON_H
