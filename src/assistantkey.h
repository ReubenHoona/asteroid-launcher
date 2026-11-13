/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef ASSISTANTKEY_H
#define ASSISTANTKEY_H

#include <QObject>
#include <QString>

/*
 * What starts the assistant, as on the stock Pixel Watch 2: a press and
 * hold of the side button (Google: "press and hold the side button next to
 * the crown"; holding the crown stays the power menu, which mce owns).
 *
 * The side button is the gpio-keys KEY_VOLUMEDOWN (PM5100 GPIO 9). mce owns
 * it as it owns the crown: it grabs the device with the display off or in
 * low power mode, so a reader of its own would miss presses then. mce's
 * side key (side_key_code in /etc/mce/61eos-side-key.conf) wakes the
 * display on a press and sends com.nokia.mce.signal.power_button_trigger on
 * the system bus:
 * - "side-key-long": held for the long press delay (300 ms, stock's: mce
 *   side_key_long_press_delay in 61eos-side-key.conf), sent once the display
 *   is on, from every display state -> longPressed();
 * - "side-key": a shorter press with the display on, sent at the release
 *   -> pressed(). The key router (KeyRouter.qml) counts the presses (300 ms
 *   window) and runs the key map (keymap.js): Recents, previous app, screen
 *   reader. A press with the display off only wakes it.
 *
 * Also on the session bus, on the launcher's connection
 * (org.nemomobile.lipstick): /org/asteroidos/launcher/assistant,
 * org.asteroidos.launcher.Assistant: Open() and Ask(s text) open the
 * overlay (tests, the app list's .desktop Exec).
 */
class AssistantKey : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.asteroidos.launcher.Assistant")
    Q_PROPERTY(bool available READ available CONSTANT)

public:
    explicit AssistantKey(QObject *parent = nullptr);

    /* listening to mce for the side button */
    bool available() const { return mAvailable; }

public slots:
    /* D-Bus: open the assistant (listening) or ask it a text question */
    Q_SCRIPTABLE void Open();
    Q_SCRIPTABLE void Ask(const QString &text);

signals:
    void longPressed();
    void pressed();
    void openRequested(const QString &text);

private slots:
    void onTrigger(const QString &action);

private:
    bool mAvailable = false;
};

#endif // ASSISTANTKEY_H
