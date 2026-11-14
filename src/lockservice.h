/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef LOCKSERVICE_H
#define LOCKSERVICE_H

#include "lockbackend.h"

#include <QDBusConnection>
#include <QObject>
#include <QString>

#include <memory>

/*
 * The screen lock of the launcher (W3-launcher-a11y-security,
 * accessibility-lock-security-03, -05, -06, -08, -10): the credential store
 * (eoslock.h) and whether the watch is locked now. Context property
 * `lockService` of the launcher's QML (qml/lock/Keyguard.qml draws it) and,
 * for Settings, the session bus object /org/asteroidos/launcher/lock,
 * interface org.asteroidos.launcher.Lock:
 *
 *   State() -> s            "none", "pin" or "pattern"
 *   Locked() -> b
 *   Verify(s secret) -> i   confirm the credential in force (Settings asks it
 *                           before changing or removing it); counts a failure
 *   SetPin(s old, s pin) -> i       exactly 4 digits; `old` confirms a credential in force
 *   SetPattern(s old, s dots) -> i  "0".."8" in drawing order, 4 to 9, none twice
 *   Clear(s old) -> i               "None"
 *   Lock()                          lock now (Lock screen now; the off-wrist lock)
 *   Remaining() -> x        ms of the wait after too many failures, 0 = none
 *   signal LockedChanged(b), StateChanged(s)
 * The integer answers are EosLock::Result: 0 ok, 1 wrong, 2 throttled (the
 * wait is on), 3 no credential set, 4 invalid or not saved.
 *
 * The credential is kept by the root helper eos-lockd (lockbackend.h): this
 * object holds no hash. If the helper cannot be reached nothing is secured
 * and no credential can be set.
 * Locked at start while a credential is set (a restart of the launcher or
 * the watch asks for it: the boot lock screen), unlocked by tryUnlock() only.
 * No timer, no polling: the wait's countdown is the view's, while it is up.
 */
class LockService : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.asteroidos.launcher.Lock")
    Q_PROPERTY(QString kind READ kindName NOTIFY stateChanged)
    Q_PROPERTY(bool secured READ secured NOTIFY stateChanged)
    Q_PROPERTY(bool locked READ locked NOTIFY lockedChanged)
    // locked since start and not unlocked since: the boot lock screen
    Q_PROPERTY(bool bootLocked READ bootLocked NOTIFY lockedChanged)
    Q_PROPERTY(int failures READ failures NOTIFY attempted)

public:
    /* bus: where this object is exported (the session bus). The credential store: `backend` if given;
     * else a file store when `path` or EOS_LOCK_FILE names a file (development, tests); else the root
     * helper eos-lockd on the system bus (the launcher's default). */
    explicit LockService(QObject *parent = nullptr,
                         const QDBusConnection &bus = QDBusConnection::sessionBus(),
                         const QString &path = QString(),
                         std::function<qint64()> clock = nullptr,
                         LockBackend *backend = nullptr);

    QString kindName() const { return EosLock::kindName(mBackend->kind()); }
    bool secured() const { return mBackend->kind() != EosLock::None; }
    bool locked() const { return mLocked; }
    bool bootLocked() const { return mBootLocked; }
    int failures() const { return mBackend->failures(); }

    // the answers of a try: EosLock::Result
    Q_INVOKABLE int tryUnlock(const QString &secret);
    Q_INVOKABLE int verify(const QString &secret) { return mBackend->check(secret); }
    Q_INVOKABLE int setPin(const QString &old, const QString &pin) { return set(EosLock::Pin, old, pin); }
    Q_INVOKABLE int setPattern(const QString &old, const QString &dots) { return set(EosLock::Pattern, old, dots); }
    Q_INVOKABLE int clear(const QString &old);
    Q_INVOKABLE void lock();
    Q_INVOKABLE double remainingMs() const { return double(mBackend->remainingMs()); }

public slots:
    Q_SCRIPTABLE QString State() const { return kindName(); }
    Q_SCRIPTABLE bool Locked() const { return mLocked; }
    Q_SCRIPTABLE int Verify(const QString &secret) { return verify(secret); }
    Q_SCRIPTABLE int SetPin(const QString &old, const QString &pin) { return setPin(old, pin); }
    Q_SCRIPTABLE int SetPattern(const QString &old, const QString &dots) { return setPattern(old, dots); }
    Q_SCRIPTABLE int Clear(const QString &old) { return clear(old); }
    Q_SCRIPTABLE void Lock() { lock(); }
    Q_SCRIPTABLE qlonglong Remaining() const { return qlonglong(mBackend->remainingMs()); }

signals:
    void stateChanged();
    void lockedChanged();
    // a try was made (right or wrong): the failures and the wait have changed
    void attempted(int result);
    // the credential was right
    void unlocked();
    Q_SCRIPTABLE void LockedChanged(bool locked);
    Q_SCRIPTABLE void StateChanged(const QString &state);

private:
    int set(int kind, const QString &old, const QString &secret);
    void setLocked(bool l);

    QDBusConnection mBus;
    std::unique_ptr<LockBackend> mBackend;
    bool mLocked = false;
    bool mBootLocked = false;
};

#endif // LOCKSERVICE_H
