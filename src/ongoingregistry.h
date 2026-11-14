/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef ONGOINGREGISTRY_H
#define ONGOINGREGISTRY_H

#include <QDBusConnection>
#include <QDBusContext>
#include <QHash>
#include <QList>
#include <QObject>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

class QDBusServiceWatcher;

/*
 * The ongoing activities of the watch (W2-launcher-status, audit
 * status-indicators-11): what an app is doing in the background that the face
 * shows as a chip (a running timer or stopwatch, a call, media, a workout,
 * navigation). Stock SysUI collects them from ongoing notifications
 * (OngoingActivitySubscriber, jpd.java), ranks them (jrj.java, jri.java) and
 * feeds the face chip (the Live Space), the notification tray and Recents.
 *
 * Three ways in, all into one table:
 *  - a notification with the hints of eosongoing.h (the apps that already post
 *    notifications): the launcher's OngoingFeed.qml hands the notification list
 *    to syncNotifications() at each change;
 *  - an application on the launcher's session bus connection
 *    (org.nemomobile.lipstick), /org/asteroidos/launcher/ongoing, interface
 *    org.asteroidos.launcher.Ongoing:
 *        Publish(s id, a{sv} props)   adds or replaces the caller's entry `id`;
 *        Remove(s id)                 withdraws it (an entry also ends when
 *                                     the caller leaves the bus);
 *        SetInUse(s kind, b active)   "mic" / "location": a privacy claim,
 *                                     the face's status icons (stock: an app op;
 *                                     other kinds are the launcher's own);
 *    and listens to the signal Activated(s id), sent to the owner only, when
 *    the user taps the chip;
 *  - the launcher's own QML (the call, the media session): publish() / remove().
 * props keys, all optional: category, icon, staticIcon, status, when,
 * countdown, paused, frozen, duration, app, title (eosongoing.h, with the hint
 * names minus "x-eos-ongoing-").
 *
 * The order (stock jri.java): a call first, media (transport) last, the rest
 * between; within a rank the newest of the time the entry first appeared and
 * the time the user last opened it. `top` is the first entry whose app the
 * user has not turned off (mutedApps). entriesChanged is emitted when
 * something the screen shows changes, not for an identical republish: the
 * sensor hub's layout is rebuilt once per change.
 *
 * Table is plain Qt Core, tested by tests/tst_ongoing.cpp together with the
 * bus object on a private bus.
 */
namespace EosOngoing {

struct Entry {
    QString key;       // "n:<id>" notification, "local:<id>", "bus:<service>/<id>"
    QString source;    // "notifications", "local", "bus:<service>"
    QString owner;     // the bus name of an entry from the bus
    QString app;       // the desktop file id (without .desktop) the touch opens
    QString title;     // what names it (the app's name)
    QString category;
    QString icon;
    QString staticIcon;
    QString status;
    qint64 when = 0;
    qint64 frozen = -1;
    bool countdown = false;
    bool paused = false;
    bool duration = false;
    qint64 posted = 0;   // first time seen
    qint64 lastOpen = 0; // last tap
};

class Table
{
public:
    // False when the stored entry shows the same as before
    bool upsert(const QString &source, const QString &key, const QVariantMap &props, qint64 now,
                const QString &owner = QString());
    // The entries of `source` become exactly `items` (maps with "key" and the props)
    bool replaceSource(const QString &source, const QVariantList &items, qint64 now);
    bool remove(const QString &key);
    bool removeSource(const QString &source);
    bool touch(const QString &key, qint64 now);

    QList<Entry> sorted() const;
    // As the QML sees them, in order: key, app, title, category, icon, staticIcon,
    // status, when, countdown, paused, frozen, duration, rank, muted
    QVariantList toList(const QStringList &mutedApps) const;
    // The first entry that is not muted, {} when none
    QVariantMap top(const QStringList &mutedApps) const;
    const Entry *find(const QString &key) const;
    int count() const { return mEntries.size(); }

    static QString normalApp(const QString &app);
    static bool isMuted(const QString &app, const QStringList &mutedApps);

private:
    static QVariantMap toMap(const Entry &e, const QStringList &mutedApps);
    QHash<QString, Entry> mEntries;
};

} // namespace EosOngoing

class OngoingRegistry : public QObject, protected QDBusContext
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.asteroidos.launcher.Ongoing")
    Q_PROPERTY(QVariantList entries READ entries NOTIFY entriesChanged)
    Q_PROPERTY(QVariantMap top READ top NOTIFY entriesChanged)
    Q_PROPERTY(int count READ count NOTIFY entriesChanged)
    // Settings > Notifications > an app > Live updates off: the desktop file ids
    Q_PROPERTY(QStringList mutedApps READ mutedApps WRITE setMutedApps NOTIFY entriesChanged)
    Q_PROPERTY(bool micInUse READ micInUse NOTIFY inUseChanged)
    Q_PROPERTY(bool locationInUse READ locationInUse NOTIFY inUseChanged)
    // the touch lock is on (the launcher's own claim: the face's "Touch lock on" slot)
    Q_PROPERTY(bool touchLocked READ touchLocked NOTIFY inUseChanged)

public:
    explicit OngoingRegistry(QObject *parent = nullptr,
                             const QDBusConnection &bus = QDBusConnection::sessionBus());

    static constexpr const char *Path = "/org/asteroidos/launcher/ongoing";

    QVariantList entries() const { return mTable.toList(mMuted); }
    QVariantMap top() const { return mTable.top(mMuted); }
    int count() const { return mTable.count(); }
    QStringList mutedApps() const { return mMuted; }
    void setMutedApps(const QStringList &apps);
    bool micInUse() const { return inUse(QStringLiteral("mic")); }
    bool locationInUse() const { return inUse(QStringLiteral("location")); }
    bool touchLocked() const { return inUse(QStringLiteral("touchlock")); }

    // The launcher's own QML: an entry of its own, withdrawn with remove()
    Q_INVOKABLE void publish(const QString &id, const QVariantMap &props);
    Q_INVOKABLE void remove(const QString &id);
    // The notification list, [{id, appName, hints}]: the ongoing ones become entries, the
    // ones that went are withdrawn, in one change
    Q_INVOKABLE void syncNotifications(const QVariantList &items);
    // The user taps an entry: the newest again, the owner told, `activated` for the QML
    Q_INVOKABLE void activate(const QString &key);
    Q_INVOKABLE void setInUse(const QString &kind, bool active);
    Q_INVOKABLE bool inUse(const QString &kind) const;

public slots:
    Q_SCRIPTABLE void Publish(const QString &id, const QVariantMap &props);
    Q_SCRIPTABLE void Remove(const QString &id);
    Q_SCRIPTABLE void SetInUse(const QString &kind, bool active);

signals:
    void entriesChanged();
    void inUseChanged();
    // The user tapped the entry `key`; `app` is the desktop file id it opens ("" none)
    void activated(const QString &key, const QString &app);

private slots:
    void serviceGone(const QString &service);

private:
    void changed(bool did);
    void claim(const QString &service, const QString &kind, bool active);

    QDBusConnection mBus;
    QDBusServiceWatcher *mWatcher;
    EosOngoing::Table mTable;
    QStringList mMuted;
    QHash<QString, QSet<QString>> mClaims; // bus name -> kinds ("local" for the QML)
};

#endif // ONGOINGREGISTRY_H
