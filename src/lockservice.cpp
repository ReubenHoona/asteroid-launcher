/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "lockservice.h"

#include <QDebug>

namespace {
const char LOCK_PATH[] = "/org/asteroidos/launcher/lock";
}

LockService::LockService(QObject *parent, const QDBusConnection &bus, const QString &path,
                         std::function<qint64()> clock, LockBackend *backend) :
    QObject(parent), mBus(bus)
{
    if (backend) {
        mBackend.reset(backend);
    } else {
        const QByteArray env = qgetenv("EOS_LOCK_FILE");
        const QString file = !path.isEmpty() ? path : QString::fromLocal8Bit(env);
        if (!file.isEmpty()) {
            mBackend.reset(new DirectBackend(file, clock));
        } else {
            auto *helper = new HelperBackend(QDBusConnection::systemBus());
            if (!helper->reachable())
                qWarning() << "LockService: the lock helper eos-lockd does not answer: no screen lock";
            mBackend.reset(helper);
        }
    }
    mLocked = secured();
    mBootLocked = mLocked;
    if (!mBus.registerObject(QLatin1String(LOCK_PATH), this,
                             QDBusConnection::ExportScriptableSlots | QDBusConnection::ExportScriptableSignals))
        qWarning() << "LockService: cannot register" << LOCK_PATH;
}

void LockService::setLocked(bool l)
{
    if (mLocked == l)
        return;
    mLocked = l;
    if (!l)
        mBootLocked = false;
    emit lockedChanged();
    emit LockedChanged(l);
}

int LockService::tryUnlock(const QString &secret)
{
    const int r = mBackend->check(secret);
    emit attempted(r);
    if (r == EosLock::Ok) {
        setLocked(false);
        emit unlocked();
    }
    return r;
}

int LockService::set(int kind, const QString &old, const QString &secret)
{
    const int r = mBackend->set(kind, old, secret);
    if (r == EosLock::Ok) {
        // the credential just set confirms nothing further: the watch stays unlocked
        emit stateChanged();
        emit StateChanged(kindName());
    } else {
        emit attempted(r);
    }
    return r;
}

int LockService::clear(const QString &old)
{
    const int r = mBackend->clear(old);
    if (r == EosLock::Ok) {
        setLocked(false);
        emit stateChanged();
        emit StateChanged(kindName());
    } else {
        emit attempted(r);
    }
    return r;
}

void LockService::lock()
{
    if (secured())
        setLocked(true);
}
