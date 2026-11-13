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
    bool m_backTracking = false;
    bool m_backSwiping = false;
    QPointF m_backStart;
    qreal m_backLastX = 0;
    qreal m_backSpeed = 0;
    qint64 m_backLastTime = 0;
    int m_backPointId = -1;
    QVariant m_data;
    QVector<QQuickItem *> m_refs;
};

#endif // LIPSTICKCOMPOSITORWINDOW_H
