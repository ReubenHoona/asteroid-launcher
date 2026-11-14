/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "offbody.h"

#include <MDConfItem>

#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>
#include <QDebug>

// a bool key, written when it is not that value already
static void writeIfChanged(MDConfItem *item, bool value)
{
    const QVariant current = item->value();
    if (!current.isValid() || current.toBool() != value)
        item->set(value);
}

OffBody::OffBody(QObject *parent, const QDBusConnection &bus)
    : QObject(parent), m_bus(bus),
      m_offBodyKey(new MDConfItem(QString::fromLatin1(OffBodyKey), this)),
      m_availableKey(new MDConfItem(QString::fromLatin1(AvailableKey), this)),
      m_watcher(new QDBusServiceWatcher(QString::fromLatin1(Service), m_bus,
                                        QDBusServiceWatcher::WatchForOwnerChange, this))
{
    m_bus.connect(QString::fromLatin1(Service), QString::fromLatin1(Path), QString::fromLatin1(Interface),
                  QStringLiteral("OffBodyChanged"), this, SLOT(onSignal(int)));
    // the service (re)started: read the state again; gone: unknown
    connect(m_watcher, &QDBusServiceWatcher::serviceRegistered, this, &OffBody::refresh);
    connect(m_watcher, &QDBusServiceWatcher::serviceUnregistered, this, &OffBody::serviceGone);
    // unknown until the hub answers: dconf says so too
    mirror();
    refresh();
}

void OffBody::mirror()
{
    writeIfChanged(m_offBodyKey, offBody());
    writeIfChanged(m_availableKey, known());
}

void OffBody::set(int state)
{
    if (state < -1 || state > 1)
        state = -1;
    if (state == m_state)
        return;
    m_state = state;
    mirror();
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
