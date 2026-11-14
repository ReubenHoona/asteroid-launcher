/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef LOCKBACKEND_H
#define LOCKBACKEND_H

#include "eoslock.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusReply>
#include <QVariant>

/*
 * Where the credential lives (W3-launcher-a11y-security,
 * accessibility-lock-security-03). Applications run as the launcher's own
 * user, so a hash kept in the launcher's account could be read and tried
 * offline by any of them (4 digits are 10000 tries). The real store is
 * therefore a root helper, eos-lockd (lockhelper.h), on the system bus; the
 * wait after too many tries is kept there too.
 *
 *   HelperBackend  asks eos-lockd (org.asteroidos.LockHelper): the launcher's
 *                  default; if the helper cannot be reached nothing is secured
 *                  and no credential can be set (never a silent fallback to a
 *                  file in the user's account)
 *   DirectBackend  the store in this process (EosLock::Store): the tests, and
 *                  development with EOS_LOCK_FILE set
 */
class LockBackend
{
public:
    virtual ~LockBackend() = default;
    // EosLock::Kind
    virtual int kind() = 0;
    // EosLock::Result
    virtual int check(const QString &secret) = 0;
    virtual qint64 remainingMs() = 0;
    virtual int set(int kind, const QString &old, const QString &secret) = 0;
    virtual int clear(const QString &old) = 0;
    virtual int failures() = 0;
};

class DirectBackend : public LockBackend
{
public:
    explicit DirectBackend(const QString &path, std::function<qint64()> clock = nullptr) : mStore(path, clock) {}
    int kind() override { return mStore.kind(); }
    int check(const QString &secret) override { return int(mStore.check(secret)); }
    qint64 remainingMs() override { return mStore.remainingMs(); }
    int set(int kind, const QString &old, const QString &secret) override { return int(mStore.set(kind, old, secret)); }
    int clear(const QString &old) override { return int(mStore.clear(old)); }
    int failures() override { return mStore.failures(); }

private:
    EosLock::Store mStore;
};

class HelperBackend : public LockBackend
{
public:
    static constexpr const char *Service = "org.asteroidos.LockHelper";
    static constexpr const char *Path = "/org/asteroidos/lockhelper";
    static constexpr const char *Interface = "org.asteroidos.LockHelper";

    explicit HelperBackend(const QDBusConnection &bus = QDBusConnection::systemBus(),
                           const QString &service = QLatin1String(Service)) : mBus(bus), mService(service)
    {
        refresh();
    }

    // false when the helper did not answer the last call
    bool reachable() const { return mReachable; }

    int kind() override { return mKind; }
    int check(const QString &secret) override
    {
        const int r = asInt(call("Check", { secret }), EosLock::Invalid);
        mFailures = asInt(call("Failures", {}), mFailures);
        return r;
    }
    qint64 remainingMs() override { return asInt64(call("Remaining", {}), 0); }
    int set(int kind, const QString &old, const QString &secret) override
    {
        const int r = asInt(call("Set", { kind, old, secret }), EosLock::Invalid);
        refresh();
        return r;
    }
    int clear(const QString &old) override
    {
        const int r = asInt(call("Clear", { old }), EosLock::Invalid);
        refresh();
        return r;
    }
    int failures() override { return mFailures; }

private:
    QDBusMessage call(const char *method, const QVariantList &args)
    {
        QDBusMessage m = QDBusMessage::createMethodCall(mService, QLatin1String(Path), QLatin1String(Interface),
                                                        QLatin1String(method));
        m.setArguments(args);
        // PBKDF2 of 10000 rounds: well under a second even loaded
        const QDBusMessage reply = mBus.call(m, QDBus::Block, 15000);
        mReachable = reply.type() == QDBusMessage::ReplyMessage;
        return reply;
    }
    static int asInt(const QDBusMessage &r, int fallback)
    {
        return r.type() == QDBusMessage::ReplyMessage && !r.arguments().isEmpty() ? r.arguments().first().toInt() : fallback;
    }
    static qint64 asInt64(const QDBusMessage &r, qint64 fallback)
    {
        return r.type() == QDBusMessage::ReplyMessage && !r.arguments().isEmpty() ? r.arguments().first().toLongLong() : fallback;
    }
    void refresh()
    {
        const QDBusMessage r = call("State", {});
        mKind = r.type() == QDBusMessage::ReplyMessage && !r.arguments().isEmpty()
                ? EosLock::kindFromName(r.arguments().first().toString()) : int(EosLock::None);
        mFailures = asInt(call("Failures", {}), 0);
    }

    QDBusConnection mBus;
    QString mService;
    int mKind = EosLock::None;
    int mFailures = 0;
    bool mReachable = false;
};

#endif // LOCKBACKEND_H
