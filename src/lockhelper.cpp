/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "lockhelper.h"

#include <QDBusError>
#include <QDebug>

LockHelper::LockHelper(const QString &path, const QDBusConnection &bus, const QString &service, int idleMs,
                       std::function<qint64()> clock) :
    QObject(nullptr), mStore(path, clock)
{
    mIdle.setSingleShot(true);
    mIdle.setInterval(idleMs);
    connect(&mIdle, &QTimer::timeout, this, &LockHelper::idle);
    QDBusConnection b = bus;
    mRegistered = b.registerObject(QStringLiteral("/org/asteroidos/lockhelper"), this, QDBusConnection::ExportScriptableSlots)
                  && b.registerService(service);
    if (!mRegistered)
        qWarning() << "LockHelper: cannot register" << service << b.lastError().message();
    mIdle.start();
}

void LockHelper::touch()
{
    mIdle.start();
}

QString LockHelper::State()
{
    touch();
    return EosLock::kindName(mStore.kind());
}

int LockHelper::Check(const QString &secret)
{
    touch();
    return int(mStore.check(secret));
}

int LockHelper::Set(int kind, const QString &old, const QString &secret)
{
    touch();
    return int(mStore.set(kind, old, secret));
}

int LockHelper::Clear(const QString &old)
{
    touch();
    return int(mStore.clear(old));
}

qlonglong LockHelper::Remaining()
{
    touch();
    return qlonglong(mStore.remainingMs());
}

int LockHelper::Failures()
{
    touch();
    return mStore.failures();
}
