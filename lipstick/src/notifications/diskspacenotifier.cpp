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
#include <QStorageInfo>
#include <QTimer>
#include "homeapplication.h"
#include "lipsticknotification.h"
#include "notificationmanager.h"
#include "diskspacenotifier.h"
#include "eosstorage.h"

DiskSpaceNotifier::DiskSpaceNotifier(QObject *parent) : QObject(parent),
    notificationId(0)
{
    QDBusConnection::systemBus().connect(QString(), "/com/nokia/diskmonitor/signal", "com.nokia.diskmonitor.signal", "disk_space_change_ind", this, SLOT(handleDiskSpaceChange(QString, int)));

    QTimer::singleShot(0, this, SLOT(removeDiskSpaceNotifications()));
}

DiskSpaceNotifier::~DiskSpaceNotifier()
{
}

void DiskSpaceNotifier::handleDiskSpaceChange(const QString &path, int percentage)
{
    Q_UNUSED(percentage)

    // dsme's signal only says that something changed (it fires on its own thresholds, so no
    // polling is needed); what is low is stock's rule: free space under the smaller of 5 % of
    // the partition and 250 MiB (DeviceStorageMonitorService.java:279-360)
    const QStorageInfo info(path.isEmpty() ? QStringLiteral("/") : path);
    const bool low = info.isValid() && EosStorage::isLow(info.bytesAvailable(), info.bytesTotal());

    if (!low) {
        if (m_lowShown) {
            m_lowShown = false;
            removeDiskSpaceNotifications();
        }
        return;
    }
    if (m_lowShown)
        return;
    m_lowShown = true;

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
    hints.insert(QStringLiteral("x-eos-ui-open"), QStringLiteral("app_storage"));

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
