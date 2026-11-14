/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "offbody.h"

#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>
#include <QDebug>

OffBody::OffBody(QObject *parent, const QDBusConnection &bus)
    : QObject(parent), m_bus(bus),
      m_watcher(new QDBusServiceWatcher(QString::fromLatin1(Service), m_bus,
                                        QDBusServiceWatcher::WatchForOwnerChange, this))
{
    m_bus.connect(QString::fromLatin1(Service), QString::fromLatin1(Path), QString::fromLatin1(Interface),
                  QStringLiteral("OffBodyChanged"), this, SLOT(onSignal(int)));
    // the service (re)started: read the state again; gone: unknown
    connect(m_watcher, &QDBusServiceWatcher::serviceRegistered, this, &OffBody::refresh);
    connect(m_watcher, &QDBusServiceWatcher::serviceUnregistered, this, &OffBody::serviceGone);
    refresh();
}

void OffBody::set(int state)
{
    if (state < -1 || state > 1)
        state = -1;
    if (state == m_state)
        return;
    m_state = state;
    emit changed();
}

void OffBody::onSignal(int state)
{
    set(state);
}

void OffBody::serviceGone()
{
    set(-1);
}

void OffBody::refresh()
{
    QDBusMessage call = QDBusMessage::createMethodCall(QString::fromLatin1(Service), QString::fromLatin1(Path),
                                                       QString::fromLatin1(Interface), QStringLiteral("GetOffBody"));
    auto *w = new QDBusPendingCallWatcher(m_bus.asyncCall(call, 5000), this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *watcher) {
        QDBusPendingReply<int> reply = *watcher;
        // no such sensor: unknown, which the rule treats as on the wrist
        set(reply.isError() ? -1 : reply.value());
        watcher->deleteLater();
    });
}
