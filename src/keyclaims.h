/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef KEYCLAIMS_H
#define KEYCLAIMS_H

#include <QDBusConnection>
#include <QDBusContext>
#include <QList>
#include <QObject>
#include <QString>

class QDBusServiceWatcher;

/*
 * Which hardware key the window in front takes for itself, as stock Wear OS
 * lets the focused window override a key (PhoneWindowManager
 * OVERRIDE_SYSTEM_KEY_BEHAVIOR_IN_FOCUSED_WINDOW; StemPrimaryKeyRule.java:
 * 249-255 defers the system action until the app declines): the alarm
 * presenter takes the side button (dismiss) and the crown (snooze), an
 * exercise app its side button (pause / resume while its own "Button action"
 * is on). The key router (KeyRouter.qml) asks claimed("side") before the
 * global key map and hands the press over with offer().
 *
 * An application claims on the launcher's session bus connection
 * (org.nemomobile.lipstick), /org/asteroidos/launcher/keys, interface
 * org.asteroidos.launcher.Keys:
 *   Claim(s keys)   "side", "crown" or "side,crown"; replaces the caller's
 *                   earlier claim;
 *   Release()       gives the keys back (a claim also ends when the caller
 *                   leaves the bus);
 * and listens to the signal Key(s key, i count), which only the claimant
 * gets (a targeted signal): count is the press number of a side button
 * sequence (1, 2, 3), always 1 for the crown.
 * A claim holds only while the claimant's window is the one in front: the
 * claimant is the process of the bus caller, the window's process is
 * frontPid (set by the key router from the front window).
 *
 * ClaimTable is plain Qt Core, tested by tests/tst_keyclaims.cpp together
 * with the bus object on a private bus.
 */
namespace EosKeys {

enum Key { NoKey = 0, SideKey = 1, CrownKey = 2 };

inline int keyFromName(const QString &name)
{
    const QString n = name.trimmed().toLower();
    return n == QLatin1String("side") ? SideKey : n == QLatin1String("crown") ? CrownKey : NoKey;
}

// "side,crown" -> bits; unknown names are ignored
inline int keysFromList(const QString &list)
{
    int keys = NoKey;
    const QStringList parts = list.split(QLatin1Char(','), Qt::SkipEmptyParts);
    for (const QString &p : parts)
        keys |= keyFromName(p);
    return keys;
}

class ClaimTable
{
public:
    // One claim per service: a new one replaces the old
    void claim(const QString &service, qint64 pid, int keys);
    void release(const QString &service);
    // The service that holds `key` for the process `pid`, or an empty string
    QString owner(qint64 pid, int key) const;
    int count() const { return mClaims.size(); }

private:
    struct Entry { QString service; qint64 pid; int keys; };
    QList<Entry> mClaims;
};

} // namespace EosKeys

class KeyClaims : public QObject, protected QDBusContext
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.asteroidos.launcher.Keys")
    Q_PROPERTY(qint64 frontPid READ frontPid WRITE setFrontPid NOTIFY frontPidChanged)

public:
    explicit KeyClaims(QObject *parent = nullptr,
                       const QDBusConnection &bus = QDBusConnection::sessionBus());

    qint64 frontPid() const { return mFrontPid; }
    void setFrontPid(qint64 pid);

    // Does the window in front hold this key ("side" or "crown")?
    Q_INVOKABLE bool claimed(const QString &key) const;
    // Send the press to the claimant; false when nobody holds the key
    Q_INVOKABLE bool offer(const QString &key, int count);

public slots:
    Q_SCRIPTABLE void Claim(const QString &keys);
    Q_SCRIPTABLE void Release();

signals:
    void frontPidChanged();

private slots:
    void serviceGone(const QString &service);

private:
    QDBusConnection mBus;
    QDBusServiceWatcher *mWatcher;
    EosKeys::ClaimTable mTable;
    qint64 mFrontPid = 0;
};

#endif // KEYCLAIMS_H
