/*
 * Test fake of lipstick's NotificationManager, built against the real notificationmanager.h (so the
 * units see the real class and its signals): an in-memory store instead of the sqlite database and
 * the org.freedesktop.Notifications service. Notify adds or updates a notification and emits
 * notificationAdded / notificationModified; CloseNotification emits notificationRemoved before the
 * notification goes, as the real one does.
 */

#include "notificationmanager.h"
#include "fakenotificationmanager.h"

#include <QCoreApplication>

const char *NotificationManager::HINT_URGENCY = "urgency";
const char *NotificationManager::HINT_CATEGORY = "category";
const char *NotificationManager::HINT_TRANSIENT = "transient";
const char *NotificationManager::HINT_RESIDENT = "resident";
const char *NotificationManager::HINT_IMAGE_PATH = "image-path";
const char *NotificationManager::HINT_ICON = "x-nemo-icon";
const char *NotificationManager::HINT_ITEM_COUNT = "x-nemo-item-count";
const char *NotificationManager::HINT_PRIORITY = "x-nemo-priority";
const char *NotificationManager::HINT_TIMESTAMP = "x-nemo-timestamp";
const char *NotificationManager::HINT_PREVIEW_ICON = "x-nemo-preview-icon";
const char *NotificationManager::HINT_PREVIEW_BODY = "x-nemo-preview-body";
const char *NotificationManager::HINT_PREVIEW_SUMMARY = "x-nemo-preview-summary";
const char *NotificationManager::HINT_REMOTE_ACTION_PREFIX = "x-nemo-remote-action-";
const char *NotificationManager::HINT_REMOTE_ACTION_ICON_PREFIX = "x-nemo-remote-action-icon-";
const char *NotificationManager::HINT_USER_REMOVABLE = "x-nemo-user-removable";
const char *NotificationManager::HINT_USER_CLOSEABLE = "x-nemo-user-closeable";
const char *NotificationManager::HINT_FEEDBACK = "x-nemo-feedback";
const char *NotificationManager::HINT_FEEDBACK_SUPPRESSED = "x-nemo-feedback-suppressed";
const char *NotificationManager::HINT_HIDDEN = "x-nemo-hidden";
const char *NotificationManager::HINT_DISPLAY_ON = "x-nemo-display-on";
const char *NotificationManager::HINT_LED_DISABLED_WITHOUT_BODY_AND_SUMMARY = "x-nemo-led-disabled-without-body-and-summary";
const char *NotificationManager::HINT_ORIGIN = "x-nemo-origin";
const char *NotificationManager::HINT_ORIGIN_PACKAGE = "x-nemo-origin-package";
const char *NotificationManager::HINT_OWNER = "x-nemo-owner";
const char *NotificationManager::HINT_MAX_CONTENT_LINES = "x-nemo-max-content-lines";
const char *NotificationManager::HINT_RESTORED = "x-nemo-restored";

NotificationManager *NotificationManager::instance_ = nullptr;

NotificationManager *NotificationManager::instance(bool owner)
{
    if (!instance_)
        instance_ = new NotificationManager(qApp, owner);
    return instance_;
}

NotificationManager::NotificationManager(QObject *parent, bool)
    : QObject(parent), previousNotificationID(0), categoryDefinitionStore(nullptr), database(nullptr),
      committed(true), nextExpirationTime(0)
{
}

NotificationManager::~NotificationManager()
{
    qDeleteAll(notifications);
    instance_ = nullptr;
}

LipstickNotification *NotificationManager::notification(uint id) const
{
    return notifications.value(id);
}

QList<uint> NotificationManager::notificationIds() const
{
    return notifications.keys();
}

QStringList NotificationManager::GetCapabilities()
{
    return QStringList();
}

uint NotificationManager::Notify(const QString &appName, uint replacesId, const QString &appIcon, const QString &summary,
                                 const QString &body, const QStringList &actions, const QVariantHash &hints,
                                 int expireTimeout)
{
    if (replacesId != 0 && notifications.contains(replacesId)) {
        LipstickNotification *n = notifications.value(replacesId);
        n->setSummary(summary);
        n->setBody(body);
        n->setActions(actions);
        n->setHints(hints);
        emit notificationModified(replacesId);
        return replacesId;
    }
    const uint id = replacesId != 0 ? replacesId : ++previousNotificationID;
    notifications.insert(id, new LipstickNotification(appName, id, appIcon, summary, body, actions, hints, expireTimeout));
    emit notificationAdded(id);
    return id;
}

void NotificationManager::CloseNotification(uint id, NotificationClosedReason closeReason)
{
    if (!notifications.contains(id))
        return;
    emit notificationRemoved(id);
    delete notifications.take(id);
    emit NotificationClosed(id, closeReason);
}

void NotificationManager::CloseNotifications(const QList<uint> &ids, NotificationClosedReason closeReason)
{
    for (uint id : ids)
        CloseNotification(id, closeReason);
}

void NotificationManager::MarkNotificationDisplayed(uint id)
{
    FakeNotificationManagerLog::markedDisplayed << id;
}

QString NotificationManager::GetServerInformation(QString &, QString &, QString &)
{
    return QString();
}

NotificationList NotificationManager::GetNotifications(const QString &)
{
    return NotificationList();
}

void NotificationManager::removeUserRemovableNotifications() {}
void NotificationManager::removeNotificationsWithCategory(const QString &) {}
void NotificationManager::updateNotificationsWithCategory(const QString &) {}
void NotificationManager::commit() {}
void NotificationManager::invokeAction(const QString &) {}
void NotificationManager::removeNotificationIfUserRemovable(uint) {}
void NotificationManager::expire() {}
void NotificationManager::reportModifications() {}
