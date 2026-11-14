/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "ongoingregistry.h"
#include "eosongoing.h"

#include <QDBusMessage>
#include <QDBusServiceWatcher>
#include <QDateTime>
#include <QDebug>
#include <algorithm>

namespace {
const char ONGOING_IF[] = "org.asteroidos.launcher.Ongoing";
const char ACTIVATED_SIGNAL[] = "Activated";
const char LOCAL[] = "local";

std::string std8(const QVariant &v) { return v.toString().toStdString(); }

QString hint(const QVariantMap &h, const char *name) { return h.value(QLatin1String(name)).toString(); }

// the props of an entry from a notification's hints
QVariantMap propsOfHints(const QString &appName, const QVariantMap &h)
{
    QVariantMap p;
    p.insert(QStringLiteral("title"), appName);
    p.insert(QStringLiteral("category"), hint(h, "x-eos-ongoing-category"));
    p.insert(QStringLiteral("icon"), hint(h, "x-eos-ongoing-icon"));
    p.insert(QStringLiteral("staticIcon"), hint(h, "x-eos-ongoing-static-icon"));
    p.insert(QStringLiteral("status"), hint(h, "x-eos-ongoing-status"));
    p.insert(QStringLiteral("when"), h.value(QStringLiteral("x-eos-ongoing-when")));
    p.insert(QStringLiteral("countdown"), EosOngoing::isTrue(std8(h.value(QStringLiteral("x-eos-ongoing-countdown")))));
    p.insert(QStringLiteral("paused"), EosOngoing::isTrue(std8(h.value(QStringLiteral("x-eos-ongoing-paused")))));
    p.insert(QStringLiteral("frozen"), h.contains(QStringLiteral("x-eos-ongoing-frozen"))
                                           ? h.value(QStringLiteral("x-eos-ongoing-frozen")) : QVariant(qlonglong(-1)));
    p.insert(QStringLiteral("duration"), EosOngoing::isTrue(std8(h.value(QStringLiteral("x-eos-ongoing-duration")))));
    QString app = hint(h, "x-eos-ongoing-app");
    if (app.isEmpty())
        app = hint(h, "x-eos-app");
    if (app.isEmpty())
        app = appName;
    p.insert(QStringLiteral("app"), app);
    return p;
}
}

namespace EosOngoing {

QString Table::normalApp(const QString &app)
{
    QString a = app.trimmed();
    if (a.endsWith(QLatin1String(".desktop")))
        a.chop(8);
    return a;
}

bool Table::isMuted(const QString &app, const QStringList &mutedApps)
{
    const QString a = normalApp(app);
    if (a.isEmpty())
        return false;
    for (const QString &m : mutedApps)
        if (normalApp(m) == a)
            return true;
    return false;
}

static Entry fromProps(const QString &source, const QString &key, const QVariantMap &p, const QString &owner)
{
    Entry e;
    e.key = key;
    e.source = source;
    e.owner = owner;
    e.app = Table::normalApp(p.value(QStringLiteral("app")).toString());
    e.title = p.value(QStringLiteral("title")).toString();
    QString c = p.value(QStringLiteral("category")).toString().trimmed().toLower();
    e.category = knownCategory(c.toStdString()) ? c : QStringLiteral("other");
    e.icon = p.value(QStringLiteral("icon")).toString();
    e.staticIcon = p.value(QStringLiteral("staticIcon")).toString();
    e.status = p.value(QStringLiteral("status")).toString();
    e.when = p.value(QStringLiteral("when")).toLongLong();
    e.countdown = p.value(QStringLiteral("countdown")).toBool();
    e.paused = p.value(QStringLiteral("paused")).toBool();
    e.duration = p.value(QStringLiteral("duration")).toBool();
    e.frozen = p.contains(QStringLiteral("frozen")) ? p.value(QStringLiteral("frozen")).toLongLong() : -1;
    return e;
}

// what the screen shows: everything but the times of the ordering
static bool sameShown(const Entry &a, const Entry &b)
{
    return a.source == b.source && a.owner == b.owner && a.app == b.app && a.title == b.title
           && a.category == b.category && a.icon == b.icon && a.staticIcon == b.staticIcon
           && a.status == b.status && a.when == b.when && a.frozen == b.frozen
           && a.countdown == b.countdown && a.paused == b.paused && a.duration == b.duration;
}

bool Table::upsert(const QString &source, const QString &key, const QVariantMap &props, qint64 now,
                   const QString &owner)
{
    Entry e = fromProps(source, key, props, owner);
    auto it = mEntries.find(key);
    if (it == mEntries.end()) {
        e.posted = now;
        mEntries.insert(key, e);
        return true;
    }
    if (sameShown(it.value(), e))
        return false;
    e.posted = it.value().posted;
    e.lastOpen = it.value().lastOpen;
    it.value() = e;
    return true;
}

bool Table::replaceSource(const QString &source, const QVariantList &items, qint64 now)
{
    bool did = false;
    QSet<QString> keep;
    for (const QVariant &v : items) {
        const QVariantMap m = v.toMap();
        const QString key = m.value(QStringLiteral("key")).toString();
        if (key.isEmpty())
            continue;
        keep.insert(key);
        did |= upsert(source, key, m, now);
    }
    const QList<QString> keys = mEntries.keys();
    for (const QString &k : keys)
        if (mEntries.value(k).source == source && !keep.contains(k)) {
            mEntries.remove(k);
            did = true;
        }
    return did;
}

bool Table::remove(const QString &key)
{
    return mEntries.remove(key) > 0;
}

bool Table::removeSource(const QString &source)
{
    bool did = false;
    const QList<QString> keys = mEntries.keys();
    for (const QString &k : keys)
        if (mEntries.value(k).source == source) {
            mEntries.remove(k);
            did = true;
        }
    return did;
}

bool Table::touch(const QString &key, qint64 now)
{
    auto it = mEntries.find(key);
    if (it == mEntries.end())
        return false;
    it.value().lastOpen = now;
    return true;
}

const Entry *Table::find(const QString &key) const
{
    auto it = mEntries.constFind(key);
    return it == mEntries.constEnd() ? nullptr : &it.value();
}

QList<Entry> Table::sorted() const
{
    QList<Entry> l = mEntries.values();
    std::sort(l.begin(), l.end(), [](const Entry &a, const Entry &b) {
        const int ra = rankOf(a.category.toStdString()), rb = rankOf(b.category.toStdString());
        if (ra != rb)
            return ra < rb;
        const qint64 ta = std::max(a.posted, a.lastOpen), tb = std::max(b.posted, b.lastOpen);
        if (ta != tb)
            return ta > tb;
        return a.key < b.key;
    });
    return l;
}

QVariantMap Table::toMap(const Entry &e, const QStringList &mutedApps)
{
    QVariantMap m;
    m.insert(QStringLiteral("key"), e.key);
    m.insert(QStringLiteral("app"), e.app);
    m.insert(QStringLiteral("title"), e.title);
    m.insert(QStringLiteral("category"), e.category);
    m.insert(QStringLiteral("icon"), e.icon);
    m.insert(QStringLiteral("staticIcon"), e.staticIcon);
    m.insert(QStringLiteral("status"), e.status);
    m.insert(QStringLiteral("when"), e.when);
    m.insert(QStringLiteral("countdown"), e.countdown);
    m.insert(QStringLiteral("paused"), e.paused);
    m.insert(QStringLiteral("frozen"), e.frozen);
    m.insert(QStringLiteral("duration"), e.duration);
    m.insert(QStringLiteral("rank"), rankOf(e.category.toStdString()));
    m.insert(QStringLiteral("muted"), isMuted(e.app, mutedApps));
    return m;
}

QVariantList Table::toList(const QStringList &mutedApps) const
{
    QVariantList out;
    const QList<Entry> l = sorted();
    for (const Entry &e : l)
        out.append(toMap(e, mutedApps));
    return out;
}

QVariantMap Table::top(const QStringList &mutedApps) const
{
    const QList<Entry> l = sorted();
    for (const Entry &e : l)
        if (!isMuted(e.app, mutedApps))
            return toMap(e, mutedApps);
    return QVariantMap();
}

} // namespace EosOngoing

OngoingRegistry::OngoingRegistry(QObject *parent, const QDBusConnection &bus) :
    QObject(parent), mBus(bus), mWatcher(new QDBusServiceWatcher(this))
{
    mWatcher->setConnection(mBus);
    mWatcher->setWatchMode(QDBusServiceWatcher::WatchForUnregistration);
    connect(mWatcher, &QDBusServiceWatcher::serviceUnregistered, this, &OngoingRegistry::serviceGone);
    if (!mBus.registerObject(QLatin1String(Path), this, QDBusConnection::ExportScriptableSlots))
        qWarning() << "OngoingRegistry: cannot register" << Path;
}

void OngoingRegistry::changed(bool did)
{
    if (did)
        emit entriesChanged();
}

void OngoingRegistry::setMutedApps(const QStringList &apps)
{
    if (apps == mMuted)
        return;
    mMuted = apps;
    emit entriesChanged();
}

void OngoingRegistry::publish(const QString &id, const QVariantMap &props)
{
    if (id.isEmpty())
        return;
    changed(mTable.upsert(QLatin1String(LOCAL), QStringLiteral("local:") + id, props,
                          QDateTime::currentMSecsSinceEpoch()));
}

void OngoingRegistry::remove(const QString &id)
{
    changed(mTable.remove(QStringLiteral("local:") + id));
}

void OngoingRegistry::syncNotifications(const QVariantList &items)
{
    QVariantList mine;
    for (const QVariant &v : items) {
        const QVariantMap n = v.toMap();
        const QVariantMap h = n.value(QStringLiteral("hints")).toMap();
        if (!EosOngoing::isOngoing(std8(h.value(QStringLiteral("x-eos-ongoing"))),
                                   std8(h.value(QStringLiteral("x-nemo-ongoing"))),
                                   n.value(QStringLiteral("category")).toString().toStdString(),
                                   std8(h.value(QStringLiteral("x-asteroid-category")))))
            continue;
        QVariantMap p = propsOfHints(n.value(QStringLiteral("appName")).toString(), h);
        p.insert(QStringLiteral("key"), QStringLiteral("n:") + n.value(QStringLiteral("id")).toString());
        mine.append(p);
    }
    changed(mTable.replaceSource(QStringLiteral("notifications"), mine, QDateTime::currentMSecsSinceEpoch()));
}

void OngoingRegistry::activate(const QString &key)
{
    const EosOngoing::Entry *e = mTable.find(key);
    if (!e)
        return;
    const QString app = e->app, owner = e->owner;
    const QString id = key.mid(key.indexOf(QLatin1Char('/')) + 1);
    mTable.touch(key, QDateTime::currentMSecsSinceEpoch());
    emit entriesChanged();
    if (!owner.isEmpty()) {
        QDBusMessage m = QDBusMessage::createTargetedSignal(owner, QLatin1String(Path), QLatin1String(ONGOING_IF),
                                                            QLatin1String(ACTIVATED_SIGNAL));
        m << id;
        mBus.send(m);
    }
    emit activated(key, app);
}

void OngoingRegistry::claim(const QString &service, const QString &kind, bool active)
{
    const bool was = inUse(kind);
    if (active)
        mClaims[service].insert(kind);
    else {
        mClaims[service].remove(kind);
        if (mClaims.value(service).isEmpty())
            mClaims.remove(service);
    }
    if (was != inUse(kind))
        emit inUseChanged();
}

void OngoingRegistry::setInUse(const QString &kind, bool active)
{
    claim(QLatin1String(LOCAL), kind, active);
}

bool OngoingRegistry::inUse(const QString &kind) const
{
    for (auto it = mClaims.constBegin(); it != mClaims.constEnd(); ++it)
        if (it.value().contains(kind))
            return true;
    return false;
}

void OngoingRegistry::Publish(const QString &id, const QVariantMap &props)
{
    if (!calledFromDBus() || id.isEmpty())
        return;
    const QString service = message().service();
    const QString source = QStringLiteral("bus:") + service;
    const QString key = QStringLiteral("bus:") + service + QLatin1Char('/') + id;
    mWatcher->addWatchedService(service);
    changed(mTable.upsert(source, key, props, QDateTime::currentMSecsSinceEpoch(), service));
}

void OngoingRegistry::Remove(const QString &id)
{
    if (!calledFromDBus())
        return;
    const QString service = message().service();
    changed(mTable.remove(QStringLiteral("bus:") + service + QLatin1Char('/') + id));
}

void OngoingRegistry::SetInUse(const QString &kind, bool active)
{
    if (!calledFromDBus())
        return;
    // an app claims the privacy kinds only; the touch lock is the launcher's own
    if (kind != QLatin1String("mic") && kind != QLatin1String("location"))
        return;
    const QString service = message().service();
    if (active)
        mWatcher->addWatchedService(service);
    claim(service, kind, active);
}

void OngoingRegistry::serviceGone(const QString &service)
{
    changed(mTable.removeSource(QStringLiteral("bus:") + service));
    if (mClaims.contains(service)) {
        const bool mic = micInUse(), loc = locationInUse();
        mClaims.remove(service);
        if (mic != micInUse() || loc != locationInUse())
            emit inUseChanged();
    }
    mWatcher->removeWatchedService(service);
}
