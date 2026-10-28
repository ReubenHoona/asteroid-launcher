/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef ASSISTANTKEY_H
#define ASSISTANTKEY_H

#include <QElapsedTimer>
#include <QObject>
#include <QSocketNotifier>
#include <QString>
#include <QTimer>

/*
 * What starts the assistant, as on the stock Pixel Watch 2: a press and
 * hold of the side button (Google: "press and hold the side button next to
 * the crown"; holding the crown stays the power menu, which mce owns).
 *
 * The side button is the gpio-keys KEY_VOLUMEDOWN (PM5100 GPIO 9). Nothing
 * else uses it with the display on: the launcher reads the evdev device
 * itself, without a grab (mce grabs it while the display is off, so then
 * the press only goes to mce). A hold of holdMs (Wear OS: the long-press
 * timeout, 400 ms; 500 here, the launcher's own long press) emits
 * longPressed() once, while the button is still down; a shorter press
 * emits pressed() (Wear OS: recent apps, not done yet).
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
    Q_PROPERTY(int holdMs READ holdMs WRITE setHoldMs NOTIFY holdMsChanged)
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)

public:
    explicit AssistantKey(QObject *parent = nullptr);
    ~AssistantKey() override;

    int holdMs() const { return mHoldMs; }
    void setHoldMs(int ms);
    bool available() const { return mFd >= 0; }

public slots:
    /* D-Bus: open the assistant (listening) or ask it a text question */
    Q_SCRIPTABLE void Open();
    Q_SCRIPTABLE void Ask(const QString &text);

signals:
    void longPressed();
    void pressed();
    void openRequested(const QString &text);
    void holdMsChanged();
    void availableChanged();

private slots:
    void onReadable();

private:
    bool openDevice();
    int mFd = -1;
    QString mPath;
    QSocketNotifier *mNotifier = nullptr;
    QTimer mHold;
    bool mDown = false;
    bool mFired = false;
    int mHoldMs = 500;
};

#endif // ASSISTANTKEY_H
