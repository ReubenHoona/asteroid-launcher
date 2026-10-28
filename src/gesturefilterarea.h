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

#ifndef GESTUREFILTERAREA_H
#define GESTUREFILTERAREA_H

#include <QObject>
#include <QQuickItem>

class GestureFilterArea : public QQuickItem
{
    Q_OBJECT

    Q_PROPERTY(bool toRightAllowed WRITE setToRightAllowed READ toRightAllowed NOTIFY toRightAllowedChanged)
    Q_PROPERTY(bool toLeftAllowed WRITE setToLeftAllowed READ toLeftAllowed NOTIFY toLeftAllowedChanged)
    Q_PROPERTY(bool toBottomAllowed WRITE setToBottomAllowed READ toBottomAllowed NOTIFY toBottomAllowedChanged)
    Q_PROPERTY(bool toTopAllowed WRITE setToTopAllowed READ toTopAllowed NOTIFY toTopAllowedChanged)
    /* Take a swipe to the right even with no panel on the left: the Wear
     * layout pulls its app list in with it */
    Q_PROPERTY(bool captureRight WRITE setCaptureRight READ captureRight NOTIFY captureRightChanged)

public:
    GestureFilterArea(QQuickItem *parent = 0);
    bool toRightAllowed()  { return m_toRightAllowed;  }
    bool toLeftAllowed()   { return m_toLeftAllowed;   }
    bool toBottomAllowed() { return m_toBottomAllowed; }
    bool toTopAllowed()    { return m_toTopAllowed;    }
    bool captureRight()    { return m_captureRight;    }
    void setCaptureRight(const bool capture) {
        if (m_captureRight != capture) {
            m_captureRight = capture;
            emit captureRightChanged();
        }
    }

    void setToRightAllowed(const bool allowed) {
        if (m_toRightAllowed != allowed) {
            m_toRightAllowed = allowed;
            emit toRightAllowedChanged();
        }
    }
    void setToLeftAllowed(const bool allowed) {
        if (m_toLeftAllowed != allowed) {
            m_toLeftAllowed = allowed;
            emit toLeftAllowedChanged();
        }
    }
    void setToBottomAllowed(const bool allowed) {
        if (m_toBottomAllowed != allowed) {
            m_toBottomAllowed = allowed;
            emit toBottomAllowedChanged();
        }
    }
    void setToTopAllowed(const bool allowed) {
        if (m_toTopAllowed != allowed) {
            m_toTopAllowed = allowed;
            emit toTopAllowedChanged();
        }
    }

signals:
    /* The area takes a swipe: its direction is decided and allowed */
    void swipeStarted(bool horizontal);
    void swipeMoved(bool horizontal, qreal delta);
    /* The swipe ends: the finger lifted, or the touch went away (cancelled,
     * grab lost, the area hidden; velocity 0 then) */
    void swipeReleased(bool horizontal, qreal velocity, bool tracing);

    void toRightAllowedChanged();
    void toLeftAllowedChanged();
    void toTopAllowedChanged();
    void toBottomAllowedChanged();
    void captureRightChanged();

private:
    bool m_toRightAllowed, m_toLeftAllowed, m_toBottomAllowed, m_toTopAllowed;
    bool m_captureRight = false;

    bool m_horizontal, m_pressed, m_tracing, m_grabbed;
    unsigned int m_counter;
    QPointF m_prevPos;
    qreal m_velocityX, m_velocityY, m_threshold;
    /* the touch point followed, and the time of its press */
    int m_pointId = -1;
    quint64 m_pressTime = 0;

    /* Shared gesture state machine, positions in GFA-local coordinates */
    void beginTracking(const QPointF &pos);
    bool trackMove(const QPointF &pos);   // returns true when the exclusive grab is wanted
    void finishTracking();                // emits swipeReleased when appropriate

    QEventPoint *followedPoint(QTouchEvent *event);
    void startGesture(const QTouchEvent *event, const QEventPoint &point, const QPointF &localPos);
    /* The touch went away without a lift: a swipe going on ends there */
    void endGesture(const char *why);

protected:
    void itemChange(ItemChange change, const ItemChangeData &value) override;
    virtual bool childMouseEventFilter(QQuickItem *, QEvent *);
    virtual void mousePressEvent(QMouseEvent *event);
    virtual void mouseMoveEvent(QMouseEvent *event);
    virtual void mouseReleaseEvent(QMouseEvent *event);
    virtual void mouseUngrabEvent();
    virtual void touchEvent(QTouchEvent *event);
    virtual void touchUngrabEvent();
    virtual void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry);
    bool filterMouseEvent(QQuickItem *item, QMouseEvent *event);
    bool filterTouchEvent(QQuickItem *item, QTouchEvent *event);
};

#endif // GESTUREFILTERAREA_H
