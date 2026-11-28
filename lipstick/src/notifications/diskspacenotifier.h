/***************************************************************************
**
** Copyright (C) 2010 Nokia Corporation and/or its subsidiary(-ies).
** Copyright (C) 2012 Jolla Ltd.
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

#ifndef DISKSPACENOTIFIER_H_
#define DISKSPACENOTIFIER_H_

#include <QObject>

#include "eosstorage.h"

class MDConfItem;

/*!
 * Disk space notifier sends the low storage notification ("Storage space running out" / "Some system
 * functions may not work", resident, Open app opens Settings > Apps > Storage) while the data partition
 * is low (eosstorage.h: stock's min(5 %, 250 MiB)), looking at the start, when the screen comes on (at
 * most once an hour), when eos-update's state changes and on dsme's signal; no timer of its own.
 */
class DiskSpaceNotifier : public QObject
{
    Q_OBJECT

public:
    /*!
     * Creates a disk space notifier.
     */
    DiskSpaceNotifier(QObject *parent = NULL);

    /*!
     * Destroys the disk space notifier.
     */
    virtual ~DiskSpaceNotifier();

private slots:
    /*!
     * dsme's diskmonitor signalled a change of its state (disk_space_state_ind): a look.
     *
     * \param path the mount point dsme checked
     * \param state its state (dsme's diskspace_state_t)
     */
    void handleDiskSpaceState(const QString &path, int state);

    //! mce's display state: "on" is a look when the last one is an hour old
    void handleDisplayStatus(const QString &status);

    //! Removes the low storage notification (the start, and when there is room again)
    void removeDiskSpaceNotifications();

private:
    //! A look at the data partition for an EosStorage::Reason
    void look(int reason);
    void showNotification();

    //! The disk space notification
    uint notificationId;

    //! When it looked last and whether the notification is up
    EosStorage::Monitor m_monitor;

    //! eos-update's state (/org/asteroidos/eos-update/state)
    MDConfItem *m_updateState = nullptr;

#ifdef UNIT_TEST
    friend class Ut_DiskSpaceNotifier;
#endif
};

#endif /* DISKSPACENOTIFIER_H_ */
