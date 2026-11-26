/***************************************************************************
**
** Copyright (C) 2013 Jolla Ltd.
** Contact: Aaron Kennedy <aaron.kennedy@jollamobile.com>
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

#ifndef LIPSTICKCOMPOSITORWINDOW_H
#define LIPSTICKCOMPOSITORWINDOW_H

#include <QWaylandQuickItem>
#include <QWaylandBufferRef>
#include "eoskeyboardopen.h"

class AsteroidGestureSurface;

class LipstickCompositorWindow : public QWaylandQuickItem
{
    Q_OBJECT

    Q_PROPERTY(int windowId READ windowId CONSTANT)
    Q_PROPERTY(bool isInProcess READ isInProcess CONSTANT)

    Q_PROPERTY(bool delayRemove READ delayRemove WRITE setDelayRemove NOTIFY delayRemoveChanged)
    Q_PROPERTY(QVariant userData READ userData WRITE setUserData NOTIFY userDataChanged)

    Q_PROPERTY(QString category READ category CONSTANT)
    Q_PROPERTY(QString title READ title NOTIFY titleChanged)
    Q_PROPERTY(qint64 processId READ processId CONSTANT)
    // eos: the program name of the process (eosappkey.h), to find a hidden window again
    Q_PROPERTY(QString appKey READ appKey CONSTANT)
    Q_PROPERTY(qint16 windowFlags READ windowFlags NOTIFY windowFlagsChanged)
    Q_PROPERTY(bool overridesSystemGestures READ overridesSystemGestures NOTIFY overridesSystemGesturesChanged)
    /* The client allows a swipe right from anywhere to go back (it is at
     * its root page and the touch is not on content moving sideways) */
    Q_PROPERTY(bool backFromAnywhere READ backFromAnywhere NOTIFY backFromAnywhereChanged)
    /* The client's full screen keyboard is open (gestures protocol version
     * 3, set_keyboard_open; eoskeyboardopen.h): the crown closes it first,
     * and the window property EOS_KEYBOARD_OPEN keeps heads-ups away */
    Q_PROPERTY(bool keyboardOpen READ keyboardOpen NOTIFY keyboardOpenChanged)

    Q_PROPERTY(bool focusOnTouch READ focusOnTouch WRITE setFocusOnTouch NOTIFY focusOnTouchChanged)

public:
    LipstickCompositorWindow(int windowId, const QString &, QWaylandSurface *surface, QQuickItem *parent = 0);
    ~LipstickCompositorWindow();

    QVariant userData() const;
    void setUserData(QVariant);

    int windowId() const;
    qint64 processId() const;

    bool delayRemove() const;
    void setDelayRemove(bool);

    QString category() const;
    virtual QString title() const;
    virtual bool isInProcess() const;
    qint16 windowFlags();

    bool eventFilter(QObject *object, QEvent *event);

    Q_INVOKABLE void terminateProcess(int killTimeout);

    QString appKey() const { return m_appKey; }

    bool focusOnTouch() const;
    void setFocusOnTouch(bool focusOnTouch);

    bool overridesSystemGestures() const;
    void setOverridesSystemGestures(bool enabled);
    bool backFromAnywhere() const { return m_backFromAnywhere; }
    void setBackFromAnywhere(bool enabled);
    bool keyboardOpen() const { return m_keyboard.open(); }
    // set_keyboard_open from the client's gesture surface `from`
    void setKeyboardOpen(bool open, AsteroidGestureSurface *from);
    // that gesture surface went away: the keyboard counts as closed
    void keyboardSurfaceGone(AsteroidGestureSurface *from);
    /* A crown press with this window in front (KeyRouter.qml): true when it
     * sent close_keyboard (the press does nothing else), false when the
     * press goes on Home (no keyboard, or the last close went unanswered) */
    Q_INVOKABLE bool closeKeyboard();

    QVariantMap windowProperties();

protected:
    void itemChange(ItemChange change, const ItemChangeData &data);

    virtual bool event(QEvent *);
    virtual void mousePressEvent(QMouseEvent *event);
    virtual void mouseMoveEvent(QMouseEvent *event);
    virtual void mouseReleaseEvent(QMouseEvent *event);
    virtual void wheelEvent(QWheelEvent *event);
    virtual void touchEvent(QTouchEvent *event);

signals:
    void userDataChanged();
    void titleChanged();
    void delayRemoveChanged();
    void committed();
    void focusOnTouchChanged();
    void windowFlagsChanged();
    void overridesSystemGesturesChanged();
    void backFromAnywhereChanged();
    void keyboardOpenChanged();
    /* A swipe right from anywhere was taken from the client (it got a
     * touch cancel): value is how far the finger went right, in px;
     * velocity at the end in px/s */
    void backSwipeStarted();
    void backSwipeMoved(qreal value);
    void backSwipeFinished(qreal value, qreal velocity);

private slots:
    void handleTouchCancel();
    void killProcess();

private:
    friend class LipstickCompositor;
    void imageAddref(QQuickItem *item);
    void imageRelease(QQuickItem *item);

    bool canRemove() const;
    void tryRemove();
    void handleTouchEvent(QTouchEvent *e);
    /* true: the event belongs to a back swipe and is not for the client */
    bool trackBackSwipe(QTouchEvent *e);

    void setTitle(QString title);
    QString m_title;

    qint64 m_processId;
    QString m_appKey;
    int m_windowId;
    QString m_category;
    bool m_delayRemove:1;
    bool m_windowClosed:1;
    bool m_removePosted:1;
    bool m_interceptingTouch:1;
    bool m_mapped : 1;
    bool m_noHardwareComposition: 1;
    bool m_focusOnTouch : 1;
    bool m_overridesSystemGestures : 1;
    bool m_backFromAnywhere = false;
    EosKeyboard::State m_keyboard;
    // the gesture surface that said the keyboard is open (close_keyboard goes there)
    AsteroidGestureSurface *m_keyboardSurface = nullptr;
    bool m_backTracking = false;
    // the crown's wheel delta not sent yet: QWaylandPointer sends delta / 12 as an
    // integer, so the hi-res steps of a slow turn (5 per sensor count) became 0
    int m_wheelRemainder = 0;
    bool m_backSwiping = false;
    QPointF m_backStart;        // in the user's x (m_backSign), the screen's y
    int m_backSign = 1;         // -1 while the picture is flipped (EosWrist::axisSign)
    qreal m_backLastX = 0;
    qreal m_backSpeed = 0;
    qint64 m_backLastTime = 0;
    int m_backPointId = -1;
    QVariant m_data;
    QVector<QQuickItem *> m_refs;
};

#endif // LIPSTICKCOMPOSITORWINDOW_H
