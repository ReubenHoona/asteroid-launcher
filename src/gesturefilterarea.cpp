/*
 * Copyright (C) 2017 Florent Revest <revestflo@gmail.com>
 * All rights reserved.
 *
 * You may use this file under the terms of BSD license as follows:
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of the author nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/*
 * Touch is handled natively, following the pattern of
 * QQuickFlickable::childMouseEventFilter(): touch events are processed
 * directly in the filter, the exclusive grab is taken by accepting the
 * filtered touch event, and further updates then arrive in touchEvent().
 * The mouse path is kept for pointer devices.
 *
 * A gesture follows one touch point: the one pressed last. Other points in
 * an event are left alone. Qt's evdevtouch does not resync after the
 * kernel drops events (SYN_DROPPED): a contact whose lift it missed stays
 * in every later event as a stationary point, and refusing every event
 * with more than one point left the home screen without a swipe until the
 * launcher restarted, while taps (touch to mouse, from any pressed point)
 * still worked. A new press always starts over: a swipe whose lift never
 * came ends there, and so does one whose touch is cancelled, taken away
 * or hidden, so the panels settle and nothing stays pressed.
 */

#include "gesturefilterarea.h"

#include <QLoggingCategory>
#include <QQuickWindow>
#include <QScreen>

Q_LOGGING_CATEGORY(lcGesture, "asteroid.launcher.gesture", QtInfoMsg)

GestureFilterArea::GestureFilterArea(QQuickItem *parent) : QQuickItem(parent)
{
    setFiltersChildMouseEvents(true);
    setAcceptedMouseButtons(Qt::LeftButton);
    setAcceptTouchEvents(true);
    m_toLeftAllowed = true;
    m_toRightAllowed = true;
    m_toBottomAllowed = true;
    m_toTopAllowed = true;
    m_pressed = false;
    m_grabbed = false;

    m_threshold = width()*0.01;
}

void GestureFilterArea::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    m_threshold = newGeometry.width()*0.01;
    QQuickItem::geometryChange(newGeometry, oldGeometry);
}

/* Shared gesture state machine */

void GestureFilterArea::beginTracking(const QPointF &pos)
{
    m_pressed = true;
    m_grabbed = false;
    m_velocityX = 0;
    m_velocityY = 0;
    m_tracing = true;
    m_horizontal = false;
    m_prevPos = pos;
    m_counter = 0;
}

/* The point followed, for the trays (W2-launcher-trays): where it went down,
 * where it is, how fast it goes. Passive: nothing here decides a gesture. */

void GestureFilterArea::notePress(const QPointF &pos, quint64 timestamp)
{
    m_pressPos = pos;
    m_touchPos = pos;
    m_vel.reset();
    m_vel.add(static_cast<long long>(timestamp), pos.x(), pos.y());
}

void GestureFilterArea::noteMove(const QPointF &pos, quint64 timestamp)
{
    m_touchPos = pos;
    m_vel.add(static_cast<long long>(timestamp), pos.x(), pos.y());
    emit touchMoved();
}

bool GestureFilterArea::trackMove(const QPointF &pos)
{
    bool wantsGrab = false;
    m_counter++;

    m_velocityX = (m_velocityX*(m_counter-1) + (pos.x()-m_prevPos.x()))/m_counter;
    m_velocityY = (m_velocityY*(m_counter-1) + (pos.y()-m_prevPos.y()))/m_counter;
    if(m_tracing) {
        if (qAbs(m_velocityX) > qAbs(m_velocityY)) {
            if(m_velocityX > m_threshold) {
                m_tracing = false;
                if(m_toRightAllowed || m_captureRight) {
                    m_horizontal = true;
                    wantsGrab = true;
                }
                else
                    m_pressed = false;
            } else if(m_velocityX < -m_threshold) {
                m_tracing = false;
                if(m_toLeftAllowed) {
                    m_horizontal = true;
                    wantsGrab = true;
                }
                else
                    m_pressed = false;
            }
        } else {
            if(m_velocityY > m_threshold) {
                m_tracing = false;
                if(m_toBottomAllowed) {
                    m_horizontal = false;
                    wantsGrab = true;
                }
                else
                    m_pressed = false;
            } else if(m_velocityY < -m_threshold) {
                m_tracing = false;
                if(m_toTopAllowed) {
                    m_horizontal = false;
                    wantsGrab = true;
                }
                else
                    m_pressed = false;
            }
        }
    } else if(m_pressed && m_grabbed) {
        qreal delta;
        if(m_horizontal)
            delta = pos.x() - m_prevPos.x();
        else
            delta = pos.y() - m_prevPos.y();

        emit swipeMoved(m_horizontal, delta);
    }
    m_prevPos = pos;
    if (wantsGrab)
        emit swipeStarted(m_horizontal);
    return wantsGrab;
}

void GestureFilterArea::finishTracking()
{
    m_pointId = -1;
    if (!m_pressed)
        return;
    // cleared first: a handler of swipeReleased may start something new
    const bool grabbed = m_grabbed;
    m_pressed = false;
    m_grabbed = false;
    setKeepTouchGrab(false);
    setKeepMouseGrab(false);
    if (grabbed) {
        qreal currVel = m_horizontal ? m_velocityX : m_velocityY;
        emit swipeReleased(m_horizontal, currVel, m_tracing);
    }
}

void GestureFilterArea::endGesture(const char *why)
{
    const bool following = m_pointId >= 0;
    const bool swiping = m_pressed && m_grabbed;
    m_pressed = false;
    m_grabbed = false;
    m_pointId = -1;
    setKeepTouchGrab(false);
    setKeepMouseGrab(false);
    if (swiping) {
        qCInfo(lcGesture, "swipe ended without a lift: %s", why);
        emit swipeReleased(m_horizontal, 0, m_tracing);
    }
    if (following)
        emit touchEnded();
}

/* The point a gesture follows: one just pressed (it starts a gesture), else
 * the one followed so far; nullptr when the event has neither */
QEventPoint *GestureFilterArea::followedPoint(QTouchEvent *event)
{
    for (qsizetype i = 0; i < event->pointCount(); ++i) {
        QEventPoint &p = event->point(i);
        if (p.state() == QEventPoint::State::Pressed)
            return &p;
    }
    return m_pointId >= 0 ? event->pointById(m_pointId) : nullptr;
}

void GestureFilterArea::startGesture(const QTouchEvent *event, const QEventPoint &point, const QPointF &localPos)
{
    // the same press can be seen more than once (filtered for each child
    // it is offered to, then delivered here): only a new one starts over
    const bool newPress = event->timestamp() != m_pressTime || point.id() != m_pointId;
    if (newPress) {
        endGesture("a new touch came first");
        if (event->pointCount() > 1) {
            for (const QEventPoint &p : event->points()) {
                if (p.id() != point.id())
                    qCInfo(lcGesture) << "press with another touch point held, left alone: id" << p.id()
                                      << p.state() << p.scenePosition() << "held" << p.timeHeld() << "s";
            }
        }
    }
    beginTracking(localPos);
    notePress(localPos, event->timestamp());
    m_pointId = point.id();
    m_pressTime = event->timestamp();
}

void GestureFilterArea::itemChange(ItemChange change, const ItemChangeData &value)
{
    if ((change == ItemVisibleHasChanged || change == ItemEnabledHasChanged) && !value.boolValue)
        endGesture("the area was hidden or disabled");
    QQuickItem::itemChange(change, value);
}

/* Child event filtering */

bool GestureFilterArea::childMouseEventFilter(QQuickItem *i, QEvent *e)
{
    if (!isVisible() || !isEnabled())
        return QQuickItem::childMouseEventFilter(i, e);

    switch (e->type()) {
    case QEvent::MouseButtonPress:
    case QEvent::MouseMove:
    case QEvent::MouseButtonRelease:
        return filterMouseEvent(i, static_cast<QMouseEvent *>(e));
    case QEvent::TouchBegin:
    case QEvent::TouchUpdate:
    case QEvent::TouchEnd:
        return filterTouchEvent(i, static_cast<QTouchEvent *>(e));
    case QEvent::TouchCancel:
        endGesture("touch cancelled");
        break;
    case QEvent::UngrabMouse:
        if (window() && window()->mouseGrabberItem() && window()->mouseGrabberItem() != this) {
            // The grab has been taken away from a child and given to some other item.
            endGesture("a child's grab went to another item");
        }
        break;
    default:
        break;
    }

    return QQuickItem::childMouseEventFilter(i, e);
}

bool GestureFilterArea::filterTouchEvent(QQuickItem *item, QTouchEvent *event)
{
    Q_UNUSED(item)
    QEventPoint *followed = followedPoint(event);
    if (!followed)
        return false;
    const QEventPoint &point = *followed;
    QPointF localPos = mapFromScene(point.scenePosition());

    switch (point.state()) {
    case QEventPoint::State::Pressed:
        if (!contains(localPos))
            return false;
        startGesture(event, point, localPos);
        break;
    case QEventPoint::State::Updated: {
        noteMove(localPos, event->timestamp());
        // a child that keeps its grab (a list being dragged, a slider)
        // has this touch
        QQuickItem *grabber = qobject_cast<QQuickItem *>(event->exclusiveGrabber(point));
        if (grabber && grabber != this && (grabber->keepTouchGrab() || grabber->keepMouseGrab()))
            return false;
        if (m_pressed && trackMove(localPos)) {
            // Threshold crossed in an allowed direction: take the swipe.
            // Accepting the filtered event and returning true makes the
            // delivery agent transfer the exclusive grab to us (respecting a
            // child's keepTouchGrab, checked above); subsequent updates then
            // arrive natively in touchEvent().
            m_grabbed = true;
            setKeepTouchGrab(true);
            setKeepMouseGrab(true);
            event->accept();
            return true;
        }
        break;
    }
    case QEventPoint::State::Released:
        // Released before any grab: the child owns this gesture (tap/scroll).
        noteMove(localPos, event->timestamp());
        finishTracking();
        emit touchEnded();
        break;
    default:
        break;
    }
    return false;
}

bool GestureFilterArea::filterMouseEvent(QQuickItem *item, QMouseEvent *event)
{
    Q_UNUSED(item)
    QPointF localPos = mapFromScene(event->scenePosition());
    if (!contains(localPos))
        return false;

    QQuickWindow *c = window();
    QQuickItem *grabber = c ? c->mouseGrabberItem() : nullptr;
    if (grabber && grabber != this && grabber->keepMouseGrab())
        return false;

    switch (event->type()) {
    case QEvent::MouseButtonPress:
        beginTracking(localPos);
        notePress(localPos, event->timestamp());
        break;
    case QEvent::MouseMove:
        if (m_pressed)
            noteMove(localPos, event->timestamp());
        if (m_pressed && trackMove(localPos)) {
            m_grabbed = true;
            setKeepMouseGrab(true);
            grabMouse();
        }
        break;
    case QEvent::MouseButtonRelease:
        m_pressed = false;
        break;
    default:
        break;
    }
    return false;
}

/* Direct delivery: GestureFilterArea itself is the target (nothing pressable
 * under the finger) or has become the exclusive grabber. */

void GestureFilterArea::touchEvent(QTouchEvent *event)
{
    if (event->type() == QEvent::TouchCancel) {
        endGesture("touch cancelled");
        event->accept();
        return;
    }
    QEventPoint *followed = isEnabled() ? followedPoint(event) : nullptr;
    if (!followed) {
        QQuickItem::touchEvent(event);
        return;
    }
    const QEventPoint &point = *followed;
    QPointF localPos = mapFromScene(point.scenePosition());

    switch (point.state()) {
    case QEventPoint::State::Pressed:
        startGesture(event, point, localPos);
        // Accepting the press makes us the exclusive grabber of the point, so
        // updates keep coming even though nothing else is under the finger.
        // The gesture counts as grabbed from the start here — there is no
        // child to hand a tap over to.
        m_grabbed = true;
        event->accept();
        break;
    case QEventPoint::State::Updated:
        noteMove(localPos, event->timestamp());
        if (m_pressed)
            trackMove(localPos);
        event->accept();
        break;
    case QEventPoint::State::Released:
        noteMove(localPos, event->timestamp());
        finishTracking();
        emit touchEnded();
        event->accept();
        break;
    default:
        QQuickItem::touchEvent(event);
        break;
    }
}

void GestureFilterArea::mousePressEvent(QMouseEvent *event) {
    if (!isEnabled() || !(event->button() & acceptedMouseButtons())) {
        QQuickItem::mousePressEvent(event);
    } else {
        beginTracking(event->position());
        notePress(event->position(), event->timestamp());
        m_grabbed = true;
        event->accept();
    }
}

void GestureFilterArea::mouseMoveEvent(QMouseEvent *event) {
    if (!isEnabled() || !m_pressed) {
        QQuickItem::mouseMoveEvent(event);
        return;
    }
    noteMove(event->position(), event->timestamp());
    trackMove(event->position());
}

void GestureFilterArea::mouseReleaseEvent(QMouseEvent *event) {
    if (!isEnabled() || !m_pressed)
        QQuickItem::mouseReleaseEvent(event);
    else {
        noteMove(event->position(), event->timestamp());
        finishTracking();
        emit touchEnded();
    }
}

void GestureFilterArea::mouseUngrabEvent() {
    endGesture("mouse grab lost");
}

void GestureFilterArea::touchUngrabEvent() {
    endGesture("touch grab lost");
}
