/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "touchobserver.h"

#include <QCoreApplication>
#include <QEvent>
#include <QPointerEvent>
#include <QTouchEvent>

TouchObserver::TouchObserver(QObject *parent) : QObject(parent)
{
    m_timer.setSingleShot(true);
    connect(&m_timer, &QTimer::timeout, this, &TouchObserver::timeout);
    m_clock.start();
}

void TouchObserver::update()
{
    const bool want = m_triple || m_two;
    if (want && !m_installed) {
        QCoreApplication::instance()->installEventFilter(this);
        m_installed = true;
    } else if (!want && m_installed) {
        QCoreApplication::instance()->removeEventFilter(this);
        m_installed = false;
        m_timer.stop();
        m_seq.reset();
    }
    m_seq.setDensity(m_density);
    // the magnification waits 25 ms longer between taps (a watch, not a phone)
    m_seq.setExtraGap(m_triple ? EosTouch::MAGNIFICATION_ADJUST_MS : 0);
    emit wantedChanged();
}

void TouchObserver::setTripleTap(bool on)
{
    if (m_triple == on)
        return;
    m_triple = on;
    update();
}

void TouchObserver::setTwoFingerTaps(bool on)
{
    if (m_two == on)
        return;
    m_two = on;
    update();
}

void TouchObserver::setDensity(double dp)
{
    if (m_density == dp || dp <= 0)
        return;
    m_density = dp;
    update();
}

bool TouchObserver::eventFilter(QObject *watched, QEvent *event)
{
    Q_UNUSED(watched);
    switch (event->type()) {
    case QEvent::TouchBegin:
    case QEvent::TouchUpdate:
    case QEvent::TouchEnd:
    case QEvent::TouchCancel: {
        auto *te = static_cast<QTouchEvent *>(event);
        // one event is seen once for each object it is sent to: only the window's copy counts
        if (!watched->isWindowType())
            break;
        const qint64 t = qint64(te->timestamp());
        if (event->type() == QEvent::TouchCancel) {
            m_seq.cancel();
            m_timer.stop();
            break;
        }
        for (const QEventPoint &pt : te->points()) {
            switch (pt.state()) {
            case QEventPoint::Pressed: feed(Down, pt.id(), pt.scenePosition(), t); break;
            case QEventPoint::Updated: feed(Move, pt.id(), pt.scenePosition(), t); break;
            case QEventPoint::Released: feed(Up, pt.id(), pt.scenePosition(), t); break;
            default: break;
            }
        }
        break;
    }
    default:
        break;
    }
    // never consumed
    return false;
}

void TouchObserver::feed(int type, int id, const QPointF &p, qint64 t)
{
    switch (type) {
    case Down:
        m_timer.stop();
        m_seq.down(id, p, t);
        break;
    case Move:
        m_seq.move(id, p, t);
        break;
    case Up:
        m_seq.up(id, t);
        sequenceStep(t);
        break;
    default:
        m_seq.cancel();
        m_timer.stop();
        break;
    }
}

/* A finger went up: if it ended a tap, a one-finger triple tap is reported at once, anything else waits for the gap. */
void TouchObserver::sequenceStep(qint64 now)
{
    const EosTouch::Result r = m_seq.current();
    if (!r.valid()) {
        m_timer.stop();
        return;
    }
    if (m_triple && r.fingers == 1 && r.taps == 3) {
        m_seq.reset();
        m_timer.stop();
        emit multiTap(1, 3, r.where.x(), r.where.y());
        return;
    }
    armTimer(now);
}

void TouchObserver::armTimer(qint64 now)
{
    const qint64 d = m_seq.deadline();
    if (d < 0)
        return;
    m_timer.start(int(qMax<qint64>(1, d - now)));
}

void TouchObserver::timeout()
{
    const EosTouch::Result r = m_seq.finish();
    if (m_two && r.fingers == 2 && (r.taps == 1 || r.taps == 2))
        emit multiTap(2, r.taps, r.where.x(), r.where.y());
}
