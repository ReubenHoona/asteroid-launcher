/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "keyclaims.h"

#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDBusServiceWatcher>
#include <QDebug>

namespace {
const char KEYS_PATH[] = "/org/asteroidos/launcher/keys";
const char KEYS_IF[] = "org.asteroidos.launcher.Keys";
const char KEY_SIGNAL[] = "Key";
}

namespace EosKeys {

void ClaimTable::claim(const QString &service, qint64 pid, int keys)
{
    release(service);
    if (keys != NoKey && pid > 0)
        mClaims.append({ service, pid, keys });
}

void ClaimTable::release(const QString &service)
{
    for (int i = mClaims.size() - 1; i >= 0; --i)
        if (mClaims.at(i).service == service)
            mClaims.removeAt(i);
}

QString ClaimTable::owner(qint64 pid, int key) const
{
    if (pid <= 0)
        return QString();
    // the newest claim of the process wins
    for (int i = mClaims.size() - 1; i >= 0; --i) {
        const Entry &e = mClaims.at(i);
        if (e.pid == pid && (e.keys & key))
            return e.service;
    }
    return QString();
}

} // namespace EosKeys

KeyClaims::KeyClaims(QObject *parent, const QDBusConnection &bus) :
    QObject(parent), mBus(bus),
    mWatcher(new QDBusServiceWatcher(this))
{
    mWatcher->setConnection(mBus);
    mWatcher->setWatchMode(QDBusServiceWatcher::WatchForUnregistration);
    connect(mWatcher, &QDBusServiceWatcher::serviceUnregistered, this, &KeyClaims::serviceGone);
    if (!mBus.registerObject(QLatin1String(KEYS_PATH), this, QDBusConnection::ExportScriptableSlots))
        qWarning() << "KeyClaims: cannot register" << KEYS_PATH;
}

void KeyClaims::setFrontPid(qint64 pid)
{
    if (mFrontPid == pid)
        return;
    mFrontPid = pid;
    emit frontPidChanged();
}

bool KeyClaims::claimed(const QString &key) const
{
    return !mTable.owner(mFrontPid, EosKeys::keyFromName(key)).isEmpty();
}

bool KeyClaims::offer(const QString &key, int count)
{
    const QString service = mTable.owner(mFrontPid, EosKeys::keyFromName(key));
    if (service.isEmpty())
        return false;
    QDBusMessage m = QDBusMessage::createTargetedSignal(service, QLatin1String(KEYS_PATH),
                                                        QLatin1String(KEYS_IF), QLatin1String(KEY_SIGNAL));
    m << key.trimmed().toLower() << count;
    return mBus.send(m);
}

void KeyClaims::Claim(const QString &keys)
{
    if (!calledFromDBus())
        return;
    const QString service = message().service();
    const QDBusReply<uint> pid = connection().interface()->servicePid(service);
    if (!pid.isValid() || pid.value() == 0) {
        qWarning() << "KeyClaims: no process for" << service;
        return;
    }
    mTable.claim(service, pid.value(), EosKeys::keysFromList(keys));
    mWatcher->addWatchedService(service);
}

void KeyClaims::Release()
{
    if (!calledFromDBus())
        return;
    mTable.release(message().service());
}

void KeyClaims::serviceGone(const QString &service)
{
    mTable.release(service);
    mWatcher->removeWatchedService(service);
}
