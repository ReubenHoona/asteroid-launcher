/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef LOCKHELPER_H
#define LOCKHELPER_H

#include "eoslock.h"

#include <QDBusConnection>
#include <QObject>
#include <QTimer>

/*
 * eos-lockd (W3-launcher-a11y-security, accessibility-lock-security-03,
 * -05): the root helper that keeps the screen lock credential and the count
 * of wrong tries, on the system bus as org.asteroidos.LockHelper at
 * /org/asteroidos/lockhelper (D-Bus activated, exits after 120 s without a
 * call). The launcher's LockService asks it through HelperBackend
 * (lockbackend.h); the launcher's own account never holds the hash. The file
 * is /var/lib/eos-lock/lock.json, owned by root, mode 0600 in a 0700
 * directory (eoslock.h Store, salted PBKDF2, the wait after failures 5, 10 ...).
 *
 *   State() -> s                    "none", "pin" or "pattern"
 *   Check(s secret) -> i            EosLock::Result; a wrong try is counted and saved before this answers
 *   Set(i kind, s old, s secret) -> i   kind 1 = PIN (4 digits), 2 = pattern; `old` confirms one in force
 *   Clear(s old) -> i               "None"
 *   Remaining() -> x                ms of the wait, 0 = none
 *   Failures() -> i
 * Every caller may ask: a wrong try costs the same whoever makes it, and
 * changing or removing needs the old credential.
 */
class LockHelper : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.asteroidos.LockHelper")

public:
    explicit LockHelper(const QString &path, const QDBusConnection &bus, const QString &service,
                        int idleMs = 120000, std::function<qint64()> clock = nullptr);

    bool registered() const { return mRegistered; }

public slots:
    Q_SCRIPTABLE QString State();
    Q_SCRIPTABLE int Check(const QString &secret);
    Q_SCRIPTABLE int Set(int kind, const QString &old, const QString &secret);
    Q_SCRIPTABLE int Clear(const QString &old);
    Q_SCRIPTABLE qlonglong Remaining();
    Q_SCRIPTABLE int Failures();

signals:
    // nothing was asked for the idle time: the daemon quits
    void idle();

private:
    void touch();

    EosLock::Store mStore;
    QTimer mIdle;
    bool mRegistered = false;
};

#endif // LOCKHELPER_H
