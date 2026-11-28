/***************************************************************************
**
** Copyright (C) 2010 Nokia Corporation and/or its subsidiary(-ies).
** Copyright (C) 2012-2013 Jolla Ltd.
** Contact: Robin Burchell <robin.burchell@jollamobile.com>
**
** This file is part of lipstick.
**
** This library is free software; you can redistribute it and/or
** modify it under the terms of the GNU Lesser General Public
** License version 2.1 as published by the Free Software Foundation
** and appearing in the file LICENSE.LGPL included in the packaging
** of this file.
**
****************************************************************************/

#include <QDBusConnection>
#include <QDebug>
#include <QTimer>
#include <MDConfItem>
#include <sys/statvfs.h>
#include <time.h>
#include "homeapplication.h"
#include "lipsticknotification.h"
#include "notificationmanager.h"
#include "diskspacenotifier.h"
#include "eosstorage.h"

// The data partition: on this watch the root is the userdata partition, /home is on it
static const char DATA_PATH[] = "/";

// seconds since the boot, the time asleep included: "an hour since the last look" is an hour of the clock
static int64_t bootSeconds()
{
    struct timespec ts;
    if (clock_gettime(CLOCK_BOOTTIME, &ts) != 0)
        return 0;
    return int64_t(ts.tv_sec);
}

// what an app may still write (stock File.getUsableSpace: f_bavail) and the size of the partition
static bool dataPartition(int64_t &freeBytes, int64_t &totalBytes)
{
    struct statvfs st;
    if (statvfs(DATA_PATH, &st) != 0)
        return false;
    freeBytes = int64_t(st.f_bavail) * int64_t(st.f_frsize);
    totalBytes = int64_t(st.f_blocks) * int64_t(st.f_frsize);
    return true;
}

/* The low storage notification (C-17, connectivity-system-ux-20): the rule and when to look are
 * EosStorage's (eosstorage.h). The looks come with events the watch has anyway, never from a timer of
 * this one: the start, the screen coming on (at most once an hour), eos-update's state changing (a
 * download staged, an install) and dsme's diskmonitor signal. */
DiskSpaceNotifier::DiskSpaceNotifier(QObject *parent) : QObject(parent),
    notificationId(0)
{
    QDBusConnection system = QDBusConnection::systemBus();
    // dsme's diskmonitor: it checks on its own schedule and signals a change of its state (its limits
    // are not stock's: the signal only asks for a look)
    system.connect(QString(), "/com/nokia/diskmonitor/signal", "com.nokia.diskmonitor.signal", "disk_space_state_ind",
                   this, SLOT(handleDiskSpaceState(QString, int)));
    // the screen comes on
    system.connect("com.nokia.mce", "/com/nokia/mce/signal", "com.nokia.mce.signal", "display_status_ind",
                   this, SLOT(handleDisplayStatus(QString)));
    // eos-update's state (current, staged, installing, trial, failed, broken): a download or an install
    m_updateState = new MDConfItem(QStringLiteral("/org/asteroidos/eos-update/state"), this);
    connect(m_updateState, &MDConfItem::valueChanged, this, [this] { look(EosStorage::Update); });

    // the notification database keeps a notification over a restart: the old one goes, then the first look
    QTimer::singleShot(0, this, [this] {
        removeDiskSpaceNotifications();
        look(EosStorage::Start);
    });
}

DiskSpaceNotifier::~DiskSpaceNotifier()
{
}

void DiskSpaceNotifier::handleDiskSpaceState(const QString &path, int state)
{
    Q_UNUSED(path)
    Q_UNUSED(state)
    // whatever mount point dsme names (it also watches /tmp and /run): the data partition is looked at
    look(EosStorage::Dsme);
}

void DiskSpaceNotifier::handleDisplayStatus(const QString &status)
{
    if (status == QLatin1String("on"))
        look(EosStorage::DisplayOn);
}

void DiskSpaceNotifier::look(int reason)
{
    const int64_t now = bootSeconds();
    if (!m_monitor.due(EosStorage::Reason(reason), now))
        return;
    int64_t freeBytes = -1, totalBytes = -1;
    const EosStorage::Action action = m_monitor.look(EosStorage::Reason(reason), now, [&](int64_t &f, int64_t &t) {
        const bool ok = dataPartition(f, t);
        freeBytes = f;
        totalBytes = t;
        return ok;
    });
    // one line a look (the start, a screen on at most once an hour, an update state, dsme): the free space
    // and the limit, no path or name
    static const char *const reasons[] = { "start", "display on", "update", "dsme" };
    const qint64 mib = 1024 * 1024;
    qInfo().noquote() << QStringLiteral("DiskSpaceNotifier: look (") + QLatin1String(reasons[qBound(0, reason, 3)])
                             + QStringLiteral("):")
                      << (totalBytes > 0 ? qint64(freeBytes) / mib : -1) << "MiB free, the limit"
                      << (totalBytes > 0 ? qint64(EosStorage::lowBytes(uint64_t(totalBytes))) / mib : -1) << "MiB"
                      << (action == EosStorage::Show ? "- low: notice posted"
                          : action == EosStorage::Clear ? "- room again: notice removed" : "");
    if (action == EosStorage::None)
        return;
    if (action == EosStorage::Clear) {
        removeDiskSpaceNotifications();
        notificationId = 0;
        return;
    }
    showNotification();
}

void DiskSpaceNotifier::showNotification()
{
    //% "Storage space running out"
    const QString title = qtTrId("id-storage-low-title");
    //% "Some system functions may not work"
    const QString text = qtTrId("id-storage-low-text");

    // An ongoing notification: it stays (resident, not clearable) until there is room again,
    // and a tap opens Settings on its storage page (x-eos-ui-open, NotificationManager)
    QVariantHash hints;
    hints.insert(NotificationManager::HINT_CATEGORY, "x-nemo.system.diskspace");
    hints.insert(NotificationManager::HINT_PREVIEW_SUMMARY, title);
    hints.insert(NotificationManager::HINT_PREVIEW_BODY, text);
    hints.insert(NotificationManager::HINT_RESIDENT, true);
    hints.insert(NotificationManager::HINT_USER_REMOVABLE, false);
    // the card's Open app opens Settings > Apps > Storage (stock: ACTION_MANAGE_STORAGE)
    hints.insert(QStringLiteral("x-eos-ui-open"), QStringLiteral("app_storage"));
    // a system notice of its own (stock: the Android System's ALERTS channel); no per-app switch names it
    hints.insert(QStringLiteral("x-eos-app"), QStringLiteral("storage"));

    NotificationManager *manager = NotificationManager::instance();
    notificationId = manager->Notify(qApp->applicationName(), notificationId, QString(), title, text,
                                     QStringList(), hints, -1);
}

void DiskSpaceNotifier::removeDiskSpaceNotifications()
{
    NotificationManager *manager = NotificationManager::instance();
    foreach (uint id, manager->notificationIds()) {
        LipstickNotification *notification = NotificationManager::instance()->notification(id);
        if (notification->category() == "x-nemo.system.diskspace") {
            manager->CloseNotification(id);
        }
    }
}
