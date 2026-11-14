/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "wristorientation.h"

#include <QCoreApplication>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>
#include <QDebug>
#include <QEvent>
#include <QWheelEvent>

#include <eoswrist.h>

bool WristCrownFilter::eventFilter(QObject *watched, QEvent *event)
{
    if (!m_flip || m_busy || event->type() != QEvent::Wheel || !m_window || watched != m_window.data())
        return false;
    QWheelEvent *w = static_cast<QWheelEvent *>(event);
    // the same event with the turn negated (Qt has no setter): both deltas, so a pixel-scrolling
    // device and an angle-scrolling one (the crown is a mouse wheel: angle) agree
    QWheelEvent turned(w->position(), w->globalPosition(), -w->pixelDelta(), -w->angleDelta(),
                       w->buttons(), w->modifiers(), w->phase(), w->inverted(), w->source(),
                       w->pointingDevice());
    turned.setTimestamp(w->timestamp());
    m_busy = true;
    QCoreApplication::sendEvent(watched, &turned);
    m_busy = false;
    w->setAccepted(turned.isAccepted());
    return true;
}

WristOrientation::WristOrientation(QObject *parent, const QDBusConnection &bus, const QString &hubService)
    : QObject(parent), m_bus(bus), m_hubService(hubService), m_filter(this)
{
    // sensorfwd may start after the launcher (or restart): it keeps the last value itself, but the
    // launcher tells it again when it appears, on the bus's own signal, not by asking now and then
    m_watcher = new QDBusServiceWatcher(m_hubService, m_bus, QDBusServiceWatcher::WatchForRegistration, this);
    connect(m_watcher, &QDBusServiceWatcher::serviceRegistered, this, [this] { tellHub(); });
}

int WristOrientation::rotation() const { return EosWrist::rotation(m_mode); }
bool WristOrientation::flip() const { return EosWrist::flipped(m_mode); }
bool WristOrientation::crownLeft() const { return EosWrist::crownLeft(m_mode); }
bool WristOrientation::rightWrist() const { return EosWrist::rightWrist(m_mode); }
int WristOrientation::gestureXSign() const { return EosWrist::gestureXSign(m_mode); }

void WristOrientation::setMode(const QVariant &stored, bool start)
{
    const int mode = EosWrist::normalize(stored);
    const bool wasFlipped = flip();
    const bool differs = mode != m_mode;
    m_mode = mode;
    m_filter.setFlip(flip());
    if (differs) {
        emit changed();
        if (wasFlipped != flip())
            emit flipChanged();
    }
    if (differs || start)
        tellHub();
}

void WristOrientation::attachWindow(QObject *window)
{
    // out and in again: installEventFilter puts the filter first, ahead of RotaryInput (see the header)
    if (QCoreApplication *app = QCoreApplication::instance())
        app->removeEventFilter(&m_filter);
    m_window = window;
    m_filter.setWindow(window);
    if (window && QCoreApplication::instance())
        QCoreApplication::instance()->installEventFilter(&m_filter);
}

void WristOrientation::tellHub()
{
    QDBusMessage call = QDBusMessage::createMethodCall(m_hubService, QStringLiteral("/org/eos/usfhub"),
                                                       QStringLiteral("org.eos.UsfHub"),
                                                       QStringLiteral("SetWristOrientation"));
    call << m_mode;
    auto *watch = new QDBusPendingCallWatcher(m_bus.asyncCall(call), this);
    const int sent = m_mode;
    connect(watch, &QDBusPendingCallWatcher::finished, this, [sent](QDBusPendingCallWatcher *w) {
        const QDBusPendingReply<int> reply = *w;
        if (reply.isError())
            qInfo().noquote() << "wrist orientation: the sensor hub service did not take" << sent
                              << "(it is told again when it appears):" << reply.error().name();
        else
            qInfo().noquote() << "wrist orientation: the sensor hub took" << sent << "->" << reply.value()
                              << "(0 set, 1 kept for the hub's connect)";
        w->deleteLater();
    });
}
