/***************************************************************************
**
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

#ifndef NOTIFICATIONPREVIEWPRESENTER_H
#define NOTIFICATIONPREVIEWPRESENTER_H

#include "lipsticknotification.h"
#include "eosalertpolicy.h"
#include <QHash>
#include <QList>
#include <QObject>

class NotificationFeedbackPlayer;

class QMceTkLock;
class QMceDisplay;
class MDConfItem;

/*!
 * \class NotificationPreviewPresenter
 *
 * \brief Decides when and how a new notification alerts, and presents the
 * ones that show one at a time.
 *
 * Tracks which notification (if any) should currently be previewed; the
 * preview overlay in the compositor scene renders it (a glanceable over the
 * face, an icon bubble anywhere else). The rules are Wear OS's and live in
 * eosalertpolicy.h (W2-launcher-heads-up):
 *  - the vibration is on arrival, at most one per 2000 ms;
 *  - 'Show new notifications' (dconf /org/asteroidos/notifications/show-immediately,
 *    default false = On wrist raise): with the display off or ambient the
 *    watch vibrates and never wakes; the alert is kept 10000 ms and shows,
 *    without a second vibration, if the display turns on in that time.
 *    Immediately: a display-on request, the vibration after 500 ms, the card
 *    after 750 ms, and mce's normal screen timeout from there;
 *  - the card that the display going off hides shows again if the display is
 *    on again within 10000 ms;
 *  - vibration only over a keyboard, an immersive app, the open notification
 *    list, and no bubble in Battery Saver.
 * Nothing here is a timer but the two short delays of Immediately; the
 * windows are compared with CLOCK_BOOTTIME stamps when the display turns on.
 */
class NotificationPreviewPresenter : public QObject
{
    Q_OBJECT
    Q_PROPERTY(LipstickNotification *notification READ notification NOTIFY notificationChanged)
    //! What the overlay draws for notification: 1 glanceable (the face), 2 bubble (anywhere else), 0 none
    Q_PROPERTY(int kind READ kind NOTIFY notificationChanged)
    //! The notification is shown again after the display left ON (auto-resume)
    Q_PROPERTY(bool resumed READ resumed NOTIFY notificationChanged)
    //! The face is the current panel with nothing over it (set by the home screen)
    Q_PROPERTY(bool faceCurrent READ faceCurrent WRITE setFaceCurrent NOTIFY faceCurrentChanged)
    //! The notification list (or a keyboard of the home screen) is in front: vibrate only
    Q_PROPERTY(bool surfaceBusy READ surfaceBusy WRITE setSurfaceBusy NOTIFY surfaceBusyChanged)
    //! The full view is open: a new alert waits for it instead of replacing it
    Q_PROPERTY(bool detailOpen READ detailOpen WRITE setDetailOpen NOTIFY detailOpenChanged)
    //! Settings > Notifications > Show new notifications: Immediately
    Q_PROPERTY(bool showImmediately READ showImmediately NOTIFY showImmediatelyChanged)
    //! Another alert waits for the one that is shown (a bubble sinks faster then)
    Q_PROPERTY(bool waiting READ waiting NOTIFY waitingChanged)
    //! The display is on (dim or bright); off and ambient are not
    Q_PROPERTY(bool screenOn READ screenOn NOTIFY screenOnChanged)

public:
    /*!
     * Creates a notification preview presenter.
     *
     * \param parent the parent object
     */
    explicit NotificationPreviewPresenter(QObject *parent = 0);

    /*!
     * Destroys the notification preview presenter.
     */
    virtual ~NotificationPreviewPresenter();

    /*!
     * Returns the notification to be currently shown or 0 if no notification
     * should be shown.
     *
     * \return the notification to be currently shown or 0 if no notification should be shown
     */
    LipstickNotification *notification() const;

    int kind() const { return m_kind; }
    bool resumed() const { return m_resumed; }
    bool faceCurrent() const { return m_faceCurrent; }
    void setFaceCurrent(bool current);
    bool surfaceBusy() const { return m_surfaceBusy; }
    void setSurfaceBusy(bool busy);
    bool detailOpen() const { return m_detailOpen; }
    void setDetailOpen(bool open);
    bool showImmediately() const;
    bool screenOn() const { return m_screenOn; }
    bool waiting() const { return m_waiting; }

signals:
    //! Sent when the notification to be shown has changed.
    void notificationChanged();

    //! Sent when a notification's feedback is due (it arrived, or its delay of Immediately ended)
    void notificationPresented(uint id);

    void faceCurrentChanged();
    void surfaceBusyChanged();
    void detailOpenChanged();
    void showImmediatelyChanged();
    void screenOnChanged();
    void waitingChanged();

public slots:
    /*!
     * Advances to the next notification to be previewed, if any, or clears
     * the current notification when the queue is empty.
     */
    void showNextNotification();

private slots:
    /*!
     * Updates the notification with the given ID.
     *
     * \param id the ID of the notification to be updated
     */
    void updateNotification(uint id);

    /*!
     * Removes the notification with the given ID.
     *
     * \param id the ID of the notification to be removed
     */
    void removeNotification(uint id, bool onlyFromQueue = false);

    //! The display went on, dim, off or ambient (mce)
    void displayStateChanged();

private:
    //! Checks whether the given notification has a preview body and a preview summary.
    bool notificationShouldBeShown(LipstickNotification *notification);

    //! Sets the given notification as the current notification
    void setCurrentNotification(LipstickNotification *notification, int kind = EosAlert::NoKind, bool resumed = false);

    //! Presents the notification: the overlay of the panel in front; false when nothing is shown for it
    bool present(LipstickNotification *notification, bool resumed);

    void updateWaiting();

    //! The notification goes to the queue of the cards (at most 5)
    void enqueue(LipstickNotification *notification, qint64 now);

    //! The feedback of the notification, with the 2000 ms rule of the notification vibrations
    void playFeedback(uint id);

    //! Immediately with the display off: wake, vibrate after 500 ms, show after 750 ms
    void wakeFor(LipstickNotification *notification);
    void showAfterWake(uint id);

    //! mce: the display on (with its normal blanking timers)
    void requestDisplayOn();

    //! The topmost application keeps cards away (immersive, keyboard): vibration only
    bool windowSuppresses() const;
    bool surfaceSuppressed() const { return m_surfaceBusy || windowSuppresses(); }
    bool batterySaver() const;

    //! The conversation of a notification, "" for a plain one
    QString threadOf(LipstickNotification *notification) const;

    //! Notifications to be shown
    QList<LipstickNotification *> notificationQueue;

    //! Notification currently being shown
    LipstickNotification *currentNotification;

    //! Player for notification feedbacks
    NotificationFeedbackPlayer *notificationFeedbackPlayer;

    //! For getting information about the touch screen lock state
    QMceTkLock *locks;

    //! For getting information about the display state
    QMceDisplay *displayState;

    //! dconf /org/asteroidos/notifications/show-immediately and /org/asteroidos/modes/battery-saver
    MDConfItem *m_showImmediately;
    MDConfItem *m_batterySaver;

    //! The alerts that came with the display off (On wrist raise), and the card the display took away
    EosAlert::Pending m_pending;
    EosAlert::Resume m_resume;
    EosAlert::VibrationLimiter m_limiter;
    //! When each alert still waiting arrived (CLOCK_BOOTTIME, ms)
    QHash<uint, qint64> m_arrival;
    //! The alerts of Immediately between the wake request and their card
    QList<uint> m_waking;

    int m_kind = EosAlert::NoKind;
    bool m_resumed = false;
    bool m_faceCurrent = false;
    bool m_surfaceBusy = false;
    bool m_detailOpen = false;
    bool m_screenOn = true;
    bool m_waiting = false;

#ifdef UNIT_TEST
    friend class Ut_NotificationPreviewPresenter;
#endif
};

#endif // NOTIFICATIONPREVIEWPRESENTER_H
