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

#include "notifications/notificationmanager.h"
#include "notifications/notificationfeedbackplayer.h"
#include "notifications/eosquietpolicy.h"
#include "notifications/eosalertpolicy.h"
#include <QScreen> // should be included by lipstickcompositor.h
#include "compositor/lipstickcompositor.h"
#include "compositor/lipstickcompositorwindow.h"
#include "notificationpreviewpresenter.h"

#include <qmcedisplay.h>
#include <qmcetklock.h>

#include <mce/dbus-names.h>

#include <MDConfItem>

#include <QDBusMessage>
#include <QDBusConnection>
#include <QDBusPendingCall>
#include <QTimer>

namespace {

const char *const ShowImmediatelyKey = "/org/asteroidos/notifications/show-immediately";
const char *const BatterySaverKey = "/org/asteroidos/modes/battery-saver";

}

NotificationPreviewPresenter::NotificationPreviewPresenter(QObject *parent) :
    QObject(parent),
    currentNotification(0),
    notificationFeedbackPlayer(new NotificationFeedbackPlayer(this)),
    locks(new QMceTkLock(this)),
    displayState(new QMceDisplay(this)),
    m_showImmediately(new MDConfItem(ShowImmediatelyKey, this)),
    m_batterySaver(new MDConfItem(BatterySaverKey, this))
{
    connect(NotificationManager::instance(), SIGNAL(notificationAdded(uint)), this, SLOT(updateNotification(uint)));
    connect(NotificationManager::instance(), SIGNAL(notificationRemoved(uint)), this, SLOT(removeNotification(uint)));
    connect(this, SIGNAL(notificationPresented(uint)), notificationFeedbackPlayer, SLOT(addNotification(uint)));
    connect(m_showImmediately, SIGNAL(valueChanged()), this, SIGNAL(showImmediatelyChanged()));

    // eos: the display on, off or ambient (mce's own signal; no polling)
    m_screenOn = displayState->state() != QMceDisplay::DisplayOff;
    connect(displayState, SIGNAL(stateChanged()), this, SLOT(displayStateChanged()));
    connect(displayState, SIGNAL(validChanged()), this, SLOT(displayStateChanged()));
}

NotificationPreviewPresenter::~NotificationPreviewPresenter()
{
}

bool NotificationPreviewPresenter::showImmediately() const
{
    return m_showImmediately->value(false).toBool();
}

bool NotificationPreviewPresenter::batterySaver() const
{
    return m_batterySaver->value(false).toBool();
}

void NotificationPreviewPresenter::updateWaiting()
{
    const bool waiting = !notificationQueue.isEmpty();
    if (m_waiting == waiting)
        return;
    m_waiting = waiting;
    emit waitingChanged();
}

void NotificationPreviewPresenter::setFaceCurrent(bool current)
{
    if (m_faceCurrent == current)
        return;
    m_faceCurrent = current;
    emit faceCurrentChanged();
}

void NotificationPreviewPresenter::setSurfaceBusy(bool busy)
{
    if (m_surfaceBusy == busy)
        return;
    m_surfaceBusy = busy;
    emit surfaceBusyChanged();
}

void NotificationPreviewPresenter::setDetailOpen(bool open)
{
    if (m_detailOpen == open)
        return;
    m_detailOpen = open;
    emit detailOpenChanged();
}

void NotificationPreviewPresenter::showNextNotification()
{
    if (!LipstickCompositor::instance() && !notificationQueue.isEmpty()) {
        QTimer::singleShot(0, this, SLOT(showNextNotification()));
        return;
    }

    if (notificationQueue.isEmpty()) {
        // No more notifications to show
        setCurrentNotification(0);
        return;
    }

    LipstickNotification *notification = notificationQueue.takeFirst();
    updateWaiting();
    const uint id = notification->replacesId();

    if (!m_screenOn) {
        // The display went off while it waited: it waits for the next raise
        m_pending.add(id, m_arrival.value(id, EosAlert::bootTimeMs()));
        showNextNotification();
    } else if (surfaceSuppressed()) {
        // The list opened (or a keyboard) while it waited: it is seen there
        NotificationManager::instance()->MarkNotificationDisplayed(id);
        showNextNotification();
    } else if (!present(notification, false)) {
        showNextNotification();
    }
}

LipstickNotification *NotificationPreviewPresenter::notification() const
{
    return currentNotification;
}

// The feedback is due when a notification arrives, not when its card is up
// (audit heads-up-alerts-09); the notification vibrations (notif_*) are held
// to one per 2000 ms, anything else (alarms, calls, battery) never
void NotificationPreviewPresenter::playFeedback(uint id)
{
    LipstickNotification *notification = NotificationManager::instance()->notification(id);
    if (notification != 0) {
        const std::string hint = notification->hints().value(NotificationManager::HINT_FEEDBACK).toString().toStdString();
        if (EosAlert::isNotificationVibration(hint) && !m_limiter.allow(EosAlert::bootTimeMs()))
            return;
    }
    emit notificationPresented(id);
}

void NotificationPreviewPresenter::updateNotification(uint id)
{
    LipstickNotification *notification = NotificationManager::instance()->notification(id);

    if (notification == 0)
        return;

    if (!notificationShouldBeShown(notification)) {
        // Remove updated notification only from the queue so that a currently visible notification won't suddenly disappear
        playFeedback(id);

        removeNotification(id, true);

        if (currentNotification != notification) {
            NotificationManager::instance()->MarkNotificationDisplayed(id);
        }
        return;
    }

    // Already waiting or on screen: an update, not a new alert
    if (currentNotification == notification || notificationQueue.contains(notification) || m_pending.contains(id) || m_waking.contains(id))
        return;

    const qint64 now = EosAlert::bootTimeMs();
    // A notification that asks for the display itself (x-nemo-display-on: the critical battery
    // warnings) wakes it as Immediately does, whatever the setting says
    const bool wakes = showImmediately() || notification->hints().value(NotificationManager::HINT_DISPLAY_ON).toBool();
    const EosAlert::Arrival arrival = EosAlert::onArrival(m_screenOn, wakes, surfaceSuppressed());

    // Immediately vibrates 500 ms after the wake request; every other alert on arrival
    if (arrival != EosAlert::WakeThenShow)
        playFeedback(id);

    switch (arrival) {
    case EosAlert::VibrateOnly:
        // seen in the list, over a keyboard or in an immersive app: the vibration is all
        NotificationManager::instance()->MarkNotificationDisplayed(id);
        break;
    case EosAlert::KeepPending:
        // On wrist raise (the default): no mce request, so the display never wakes for it
        m_arrival.insert(id, now);
        m_pending.add(id, now);
        break;
    case EosAlert::WakeThenShow:
        m_arrival.insert(id, now);
        wakeFor(notification);
        break;
    case EosAlert::ShowNow:
        enqueue(notification, now);
        break;
    }
}

QString NotificationPreviewPresenter::threadOf(LipstickNotification *notification) const
{
    const bool conversation = !notification->hints().value(QStringLiteral("x-asteroid-messages")).toString().isEmpty();
    return QString::fromStdString(EosAlert::threadKey(notification->appName().toStdString(),
                                                      notification->summary().toStdString(), conversation));
}

void NotificationPreviewPresenter::enqueue(LipstickNotification *notification, qint64 now)
{
    const uint id = notification->replacesId();
    m_arrival.insert(id, now);

    const int kind = EosAlert::kindFor(m_faceCurrent, batterySaver());
    if (currentNotification != 0) {
        if (EosAlert::replacesCurrent(static_cast<EosAlert::Kind>(m_kind), static_cast<EosAlert::Kind>(kind), m_detailOpen)) {
            // On the face the newest alert replaces the glanceable at once; the ones
            // that waited behind it stay in the list
            foreach (LipstickNotification *waiting, notificationQueue)
                NotificationManager::instance()->MarkNotificationDisplayed(waiting->replacesId());
            notificationQueue.clear();
            updateWaiting();
            present(notification, false);
            return;
        }
        // One bubble per conversation: the one that is up already says it
        const QString thread = threadOf(notification);
        if (m_kind == EosAlert::Bubble && !thread.isEmpty() && thread == threadOf(currentNotification)) {
            NotificationManager::instance()->MarkNotificationDisplayed(id);
            return;
        }
    }

    notificationQueue.append(notification);
    // at most 5 wait; the oldest are given up (they stay in the list)
    for (int n = EosAlert::overflow(notificationQueue.size()); n > 0; --n)
        NotificationManager::instance()->MarkNotificationDisplayed(notificationQueue.takeFirst()->replacesId());

    updateWaiting();

    // Show the notification if no notification currently being shown
    if (currentNotification == 0)
        showNextNotification();
}

bool NotificationPreviewPresenter::present(LipstickNotification *notification, bool resumed)
{
    const int kind = EosAlert::kindFor(m_faceCurrent, batterySaver());
    if (kind == EosAlert::NoKind) {
        // Battery Saver away from the face: no bubble (the vibration was played)
        NotificationManager::instance()->MarkNotificationDisplayed(notification->replacesId());
        return false;
    }

    m_arrival.remove(notification->replacesId());
    setCurrentNotification(notification, kind, resumed);

    // A new alert on the face while the display is on is user activity: mce's
    // normal dim and blank timers start again (no fixed hold of its own)
    if (kind == EosAlert::Glanceable && !resumed && m_screenOn)
        requestDisplayOn();
    return true;
}

void NotificationPreviewPresenter::removeNotification(uint id, bool onlyFromQueue)
{
    m_pending.remove(id);
    m_resume.forget(id);
    m_arrival.remove(id);
    m_waking.removeAll(id);

    // Remove the notification from the queue
    LipstickNotification *notification = NotificationManager::instance()->notification(id);

    if (notification != 0) {
        notificationQueue.removeAll(notification);
        updateWaiting();

        // If the notification is currently being shown hide it - the next notification will be shown after the current one has been hidden
        if (!onlyFromQueue && currentNotification == notification) {
            currentNotification = 0;
            m_kind = EosAlert::NoKind;
            m_resumed = false;
            emit notificationChanged();
        }
    }
}

bool NotificationPreviewPresenter::windowSuppresses() const
{
    LipstickCompositor *compositor = LipstickCompositor::instance();
    // with the home screen in front no window keeps cards away (a game sent to the
    // background must not mute the face)
    if (compositor == 0 || compositor->homeActive())
        return false;
    LipstickCompositorWindow *win = compositor->m_windows.value(compositor->topmostWindowId(), 0);
    if (win == 0)
        return false;
    const QVariantMap properties = win->windowProperties();
    // an immersive app (a game, a video) sets NOTIFICATION_PREVIEWS_DISABLED to anything
    // but 0 and gets the vibration only; the keyboard of an app says so with
    // EOS_KEYBOARD_OPEN (heads-up-alerts-10)
    return properties.value(QStringLiteral("NOTIFICATION_PREVIEWS_DISABLED"), 0u).toUInt() != 0
        || properties.value(QStringLiteral("EOS_KEYBOARD_OPEN"), false).toBool();
}

bool NotificationPreviewPresenter::notificationShouldBeShown(LipstickNotification *notification)
{
    if (notification->hidden() || notification->restored() || (notification->previewBody().isEmpty() && notification->previewSummary().isEmpty()))
        return false;

    // eos: Bedtime or Theater: no banner (it would turn the screen on) but
    // an alarm's; the notification goes to the stream (eosquietpolicy.h)
    const std::string feedbackHint = notification->hints().value(NotificationManager::HINT_FEEDBACK).toString().toStdString();
    if (!EosQuiet::previewAllowed(NotificationManager::instance()->quiet(), feedbackHint))
        return false;
    // ...and Do Not Disturb, but for an alarm, a call and the critical battery warning
    if (!EosQuiet::previewAllowedDnd(NotificationManager::instance()->dnd(), feedbackHint))
        return false;

    const bool screenLocked = locks->locked();
    const bool notificationIsCritical = notification->urgency() >= 2 || notification->hints().value(NotificationManager::HINT_DISPLAY_ON).toBool();

    return !screenLocked || notificationIsCritical;
}

void NotificationPreviewPresenter::setCurrentNotification(LipstickNotification *notification, int kind, bool resumed)
{
    if (currentNotification != notification) {
        if (currentNotification) {
            NotificationManager::instance()->MarkNotificationDisplayed(currentNotification->replacesId());
        }

        currentNotification = notification;
        m_kind = notification ? kind : static_cast<int>(EosAlert::NoKind);
        m_resumed = notification ? resumed : false;
        emit notificationChanged();
    }
}

/* Immediately (the user's choice): the display on now, the vibration 500 ms
 * after the request, the card 750 ms after it (kfl.java:117-141, kft.java:
 * 32-70). The two delays are single shots while the wake keeps the CPU up;
 * the screen timeout that follows is the user's (mce's), no hold of ours. */
void NotificationPreviewPresenter::wakeFor(LipstickNotification *notification)
{
    const uint id = notification->replacesId();
    m_waking.append(id);
    requestDisplayOn();
    QTimer::singleShot(EosAlert::ImmediateVibrateMs, this, [this, id] {
        if (m_waking.contains(id))
            playFeedback(id);
    });
    QTimer::singleShot(EosAlert::ImmediateShowMs, this, [this, id] { showAfterWake(id); });
}

void NotificationPreviewPresenter::showAfterWake(uint id)
{
    if (!m_waking.removeOne(id))
        return;
    LipstickNotification *notification = NotificationManager::instance()->notification(id);
    if (notification == 0)
        return;
    const qint64 now = EosAlert::bootTimeMs();
    if (!m_screenOn) {
        // the display did not come on (no request granted): it waits like On wrist raise
        m_pending.add(id, m_arrival.value(id, now));
    } else if (surfaceSuppressed()) {
        NotificationManager::instance()->MarkNotificationDisplayed(id);
    } else {
        enqueue(notification, m_arrival.value(id, now));
    }
}

void NotificationPreviewPresenter::requestDisplayOn()
{
    QDBusMessage msg = QDBusMessage::createMethodCall(MCE_SERVICE, MCE_REQUEST_PATH, MCE_REQUEST_IF, MCE_DISPLAY_ON_REQ);
    QDBusConnection::systemBus().asyncCall(msg);
}

void NotificationPreviewPresenter::displayStateChanged()
{
    const bool on = displayState->state() != QMceDisplay::DisplayOff;
    if (on == m_screenOn)
        return;
    m_screenOn = on;
    emit screenOnChanged();

    const qint64 now = EosAlert::bootTimeMs();

    if (!on) {
        // The glanceable or the full view that was up: it comes back if the display is
        // on again within 10 s (a bubble is only 3 s: nothing to resume)
        if (currentNotification != 0) {
            if (m_kind == EosAlert::Glanceable)
                m_resume.left(currentNotification->replacesId(), now);
            setCurrentNotification(0);
        }
        // what waited for its turn waits for the raise instead
        foreach (LipstickNotification *waiting, notificationQueue)
            m_pending.add(waiting->replacesId(), m_arrival.value(waiting->replacesId(), now));
        notificationQueue.clear();
        updateWaiting();
        return;
    }

    // The display is on. Immediately's own card is shown by its 750 ms delay.
    if (!m_waking.isEmpty()) {
        m_resume.clear();
        return;
    }

    // On wrist raise: the newest alert of the last 10 s shows, with no second
    // vibration; the others stay in the list. Else the card that was up resumes.
    QList<uint> dropped;
    foreach (const EosAlert::Pending::Item &item, m_pending.items())
        dropped.append(item.id);
    uint id = m_pending.takeNewest(now);
    bool resumed = false;
    const uint resumeId = m_resume.take(now);
    if (id == 0 && resumeId != 0) {
        id = resumeId;
        resumed = true;
    }
    foreach (uint other, dropped) {
        m_arrival.remove(other);
        if (other != id)
            NotificationManager::instance()->MarkNotificationDisplayed(other);
    }

    if (id == 0)
        return;
    LipstickNotification *notification = NotificationManager::instance()->notification(id);
    if (notification == 0 || notification->hidden())
        return;
    if (surfaceSuppressed()) {
        // the list is open: it is seen there
        NotificationManager::instance()->MarkNotificationDisplayed(id);
        return;
    }
    if (currentNotification == 0)
        present(notification, resumed);
}
