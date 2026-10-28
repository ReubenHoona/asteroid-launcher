/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "assistantkey.h"

#include <QDBusConnection>
#include <QDebug>
#include <QDir>
#include <QFile>

#include <fcntl.h>
#include <linux/input.h>
#include <sys/ioctl.h>
#include <unistd.h>

static bool hasKey(int fd, int code)
{
    unsigned long bits[KEY_MAX / (8 * sizeof(unsigned long)) + 1] = {0};
    if (ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(bits)), bits) < 0)
        return false;
    return bits[code / (8 * sizeof(unsigned long))] & (1UL << (code % (8 * sizeof(unsigned long))));
}

AssistantKey::AssistantKey(QObject *parent) : QObject(parent)
{
    mHold.setSingleShot(true);
    connect(&mHold, &QTimer::timeout, this, [this] {
        if (mDown && !mFired) {
            mFired = true;
            emit longPressed();
        }
    });
    if (!openDevice())
        qInfo() << "AssistantKey: no side button (gpio-keys KEY_VOLUMEDOWN) found";
    // the launcher's own session bus name is lipstick's
    QDBusConnection::sessionBus().registerObject(QStringLiteral("/org/asteroidos/launcher/assistant"), this,
                                                 QDBusConnection::ExportScriptableSlots);
}

AssistantKey::~AssistantKey()
{
    if (mFd >= 0)
        ::close(mFd);
}

void AssistantKey::setHoldMs(int ms)
{
    if (ms == mHoldMs || ms < 100)
        return;
    mHoldMs = ms;
    emit holdMsChanged();
}

bool AssistantKey::openDevice()
{
    // the gpio-keys device with KEY_VOLUMEDOWN (event1/2 on eos; not the
    // pmic's pwrkey/resin, which mce and lipstick read)
    const QString env = qEnvironmentVariable("ASSISTANT_KEY_DEVICE");
    QStringList candidates;
    if (!env.isEmpty())
        candidates << env;
    const QStringList names = QDir(QStringLiteral("/sys/class/input")).entryList({QStringLiteral("event*")});
    for (const QString &n : names) {
        QFile name(QStringLiteral("/sys/class/input/%1/device/name").arg(n));
        if (!name.open(QIODevice::ReadOnly))
            continue;
        if (name.readAll().trimmed() == "gpio-keys")
            candidates.prepend(QStringLiteral("/dev/input/") + n);
    }
    for (const QString &path : std::as_const(candidates)) {
        const int fd = ::open(path.toLocal8Bit().constData(), O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (fd < 0)
            continue;
        if (!hasKey(fd, KEY_VOLUMEDOWN)) {
            ::close(fd);
            continue;
        }
        mFd = fd;
        mPath = path;
        mNotifier = new QSocketNotifier(fd, QSocketNotifier::Read, this);
        connect(mNotifier, &QSocketNotifier::activated, this, &AssistantKey::onReadable);
        qInfo() << "AssistantKey: the side button is" << path;
        return true;
    }
    return false;
}

void AssistantKey::onReadable()
{
    struct input_event ev[16];
    for (;;) {
        const ssize_t n = ::read(mFd, ev, sizeof(ev));
        if (n <= 0)
            break;
        for (size_t i = 0; i < size_t(n) / sizeof(ev[0]); i++) {
            if (ev[i].type != EV_KEY || ev[i].code != KEY_VOLUMEDOWN)
                continue;
            if (ev[i].value == 1 && !mDown) {
                mDown = true;
                mFired = false;
                mHold.start(mHoldMs);
            } else if (ev[i].value == 0 && mDown) {
                mDown = false;
                mHold.stop();
                if (!mFired)
                    emit pressed();
            }
        }
    }
}

void AssistantKey::Open()
{
    emit openRequested(QString());
}

void AssistantKey::Ask(const QString &text)
{
    emit openRequested(text);
}
