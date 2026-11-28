/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "mediamute.h"
#include "modescore.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusServiceWatcher>
#include <QDBusVariant>
#include <QDebug>
#include <QFile>
#include <QMap>

static const char LOOKUP_SERVICE[] = "org.pulseaudio.Server";
static const char LOOKUP_PATH[] = "/org/pulseaudio/server_lookup1";
static const char LOOKUP_IF[] = "org.PulseAudio.ServerLookup1";
static const char CORE_PATH[] = "/org/pulseaudio/core1";
static const char CORE_IF[] = "org.PulseAudio.Core1";
static const char STREAM_IF[] = "org.PulseAudio.Core1.Stream";
static const char PROPS_IF[] = "org.freedesktop.DBus.Properties";

typedef QMap<QString, QByteArray> PropList;

static QDBusMessage getProperty(const QString &path, const char *iface, const char *name)
{
    QDBusMessage get = QDBusMessage::createMethodCall(QString(), path, QLatin1String(PROPS_IF), QStringLiteral("Get"));
    get << QString::fromLatin1(iface) << QString::fromLatin1(name);
    return get;
}

static QVariant replyValue(const QDBusMessage &reply)
{
    return reply.arguments().value(0).value<QDBusVariant>().variant();
}

MediaMute::MediaMute(QObject *parent) : QObject(parent)
{
    qDBusRegisterMetaType<PropList>();
    // what an earlier launcher of this boot muted
    const QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR");
    if (!runtime.isEmpty()) {
        mStatePath = runtime + QStringLiteral("/eos-media-mute");
        QFile f(mStatePath);
        if (f.open(QIODevice::ReadOnly)) {
            const QList<QByteArray> lines = f.readAll().split('\n');
            for (const QByteArray &line : lines) {
                if (line.startsWith(CORE_PATH))
                    mMuted.insert(QString::fromLatin1(line.trimmed()));
            }
            mLastRun = mMuted;
            if (!mLastRun.isEmpty())
                qInfo() << "MediaMute:" << mLastRun.size() << "media streams muted by the launcher before";
        }
    }
    // PulseAudio starts (it is socket activated) or restarts: its lookup name comes on the session bus
    QDBusConnection session = QDBusConnection::sessionBus();
    if (session.isConnected()) {
        mWatcher = new QDBusServiceWatcher(QLatin1String(LOOKUP_SERVICE), session,
                                           QDBusServiceWatcher::WatchForRegistration, this);
        connect(mWatcher, &QDBusServiceWatcher::serviceRegistered, this, &MediaMute::serverAppeared);
    }
}

MediaMute::~MediaMute()
{
    if (!mName.isEmpty())
        QDBusConnection::disconnectFromPeer(mName);
}

QStringList MediaMute::mutedStreams() const
{
    QStringList out(mMuted.begin(), mMuted.end());
    out.sort();
    return out;
}

bool MediaMute::connected() const
{
    return !mName.isEmpty() && QDBusConnection(mName).isConnected();
}

void MediaMute::setWanted(bool wanted)
{
    if (mStarted && wanted == mWanted)
        return;
    mStarted = true;
    mWanted = wanted;
    if (!wanted)
        mChecking.clear();
    if (connected())
        apply();
    else if (wanted || !mMuted.isEmpty())
        connectServer();   // also to unmute what the launcher before muted
}

// connected: mute the media streams and watch for new ones, or unmute the ones muted here
void MediaMute::apply()
{
    if (mWanted) {
        listen(true);
        scan();
        return;
    }
    listen(false);
    const QSet<QString> muted = mMuted;
    const QSet<QString> lastRun = mLastRun;
    mMuted.clear();
    mLastRun.clear();
    save();
    for (const QString &path : muted) {
        if (lastRun.contains(path))
            release(path);
        else
            setMute(path, false);
    }
}

void MediaMute::serverAppeared()
{
    if ((mWanted || !mMuted.isEmpty()) && !connected())
        connectServer();
}

void MediaMute::save()
{
    if (mStatePath.isEmpty())
        return;
    if (mMuted.isEmpty()) {
        QFile::remove(mStatePath);
        return;
    }
    QFile f(mStatePath);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qWarning() << "MediaMute: cannot write" << mStatePath;
        return;
    }
    for (const QString &path : mutedStreams())
        f.write(path.toLatin1() + '\n');
}

void MediaMute::connectServer()
{
    const QByteArray env = qgetenv("PULSE_DBUS_SERVER");
    if (!env.isEmpty()) {
        connectTo(QString::fromLocal8Bit(env));
        return;
    }
    QDBusConnection session = QDBusConnection::sessionBus();
    if (mLookup || !session.isConnected())
        return;
    mLookup = true;
    QDBusMessage get = QDBusMessage::createMethodCall(QLatin1String(LOOKUP_SERVICE), QLatin1String(LOOKUP_PATH),
                                                      QLatin1String(PROPS_IF), QStringLiteral("Get"));
    get << QString::fromLatin1(LOOKUP_IF) << QStringLiteral("Address");
    auto *w = new QDBusPendingCallWatcher(session.asyncCall(get), this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        const QDBusMessage reply = w->reply();
        w->deleteLater();
        mLookup = false;
        if (reply.type() == QDBusMessage::ErrorMessage) {
            // not running now: it registers the name when it starts (serverAppeared)
            qInfo() << "MediaMute: no PulseAudio server yet" << reply.errorName();
            return;
        }
        if (mWanted || !mMuted.isEmpty())
            connectTo(replyValue(reply).toString());
    });
}

void MediaMute::connectTo(const QString &address)
{
    if (connected() || address.isEmpty())
        return;
    if (!mName.isEmpty())
        QDBusConnection::disconnectFromPeer(mName);
    // the streams of a server that went away went with it (the list of the last run is kept for the first)
    mChecking.clear();
    mListening = false;
    mName = QStringLiteral("eos-media-mute-%1").arg(++mSerial);
    QDBusConnection c = QDBusConnection::connectToPeer(address, mName);
    if (!c.isConnected()) {
        qWarning() << "MediaMute: cannot reach PulseAudio:" << c.lastError().message();
        QDBusConnection::disconnectFromPeer(mName);
        mName.clear();
        return;
    }
    if (!mFirstConnection) {
        mMuted.clear();
        mLastRun.clear();
        save();
    }
    mFirstConnection = false;
    c.connect(QString(), QLatin1String(CORE_PATH), QLatin1String(CORE_IF), QStringLiteral("NewPlaybackStream"),
              this, SLOT(newStream(QDBusObjectPath)));
    c.connect(QString(), QLatin1String(CORE_PATH), QLatin1String(CORE_IF), QStringLiteral("PlaybackStreamRemoved"),
              this, SLOT(streamRemoved(QDBusObjectPath)));
    apply();
}

void MediaMute::call(const QDBusMessage &message, const std::function<void(const QDBusMessage &)> &done)
{
    if (!connected())
        return;
    auto *w = new QDBusPendingCallWatcher(QDBusConnection(mName).asyncCall(message), this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [done, message](QDBusPendingCallWatcher *w) {
        const QDBusMessage reply = w->reply();
        w->deleteLater();
        if (reply.type() == QDBusMessage::ErrorMessage) {
            // a stream that ended meanwhile is no error of ours
            qDebug() << "MediaMute:" << message.member() << message.path() << reply.errorName();
            return;
        }
        if (done)
            done(reply);
    });
}

// PulseAudio sends the core's signals only to a client that asked for them
void MediaMute::listen(bool on)
{
    if (on == mListening || !connected())
        return;
    mListening = on;
    for (const char *signal : { "NewPlaybackStream", "PlaybackStreamRemoved" }) {
        const QString name = QLatin1String(CORE_IF) + QLatin1Char('.') + QLatin1String(signal);
        QDBusMessage m = QDBusMessage::createMethodCall(QString(), QLatin1String(CORE_PATH), QLatin1String(CORE_IF),
                                                        on ? QStringLiteral("ListenForSignal")
                                                           : QStringLiteral("StopListeningForSignal"));
        m << name;
        if (on)
            m << QVariant::fromValue(QList<QDBusObjectPath>());   // every object
        call(m, nullptr);
    }
}

void MediaMute::scan()
{
    call(getProperty(QLatin1String(CORE_PATH), CORE_IF, "PlaybackStreams"), [this](const QDBusMessage &reply) {
        const QList<QDBusObjectPath> streams = qdbus_cast<QList<QDBusObjectPath>>(replyValue(reply));
        for (const QDBusObjectPath &p : streams)
            check(p.path());
    });
}

void MediaMute::newStream(const QDBusObjectPath &path)
{
    check(path.path());
}

void MediaMute::streamRemoved(const QDBusObjectPath &path)
{
    if (mMuted.remove(path.path()))
        save();
    mLastRun.remove(path.path());
    mChecking.remove(path.path());
}

static bool mediaStream(const QDBusMessage &propertyList)
{
    QByteArray role = qdbus_cast<PropList>(replyValue(propertyList)).value(QStringLiteral("media.role"));
    while (role.endsWith('\0'))
        role.chop(1);
    return ModesCore::isMediaRole(QString::fromUtf8(role));
}

// A media stream that is not muted yet is muted; one that is muted already (by its app, the user) is not
// ours and is left alone. A stream on the list (an earlier launcher muted it) is ours: it stays muted. A
// list entry that is no media stream (PulseAudio restarted meanwhile: the path is another stream's now) is
// dropped untouched.
void MediaMute::check(const QString &path)
{
    if (!mWanted || mChecking.contains(path))
        return;
    mChecking.insert(path);
    call(getProperty(path, STREAM_IF, "PropertyList"), [this, path](const QDBusMessage &reply) {
        if (!mWanted || !mChecking.contains(path))
            return;
        if (!mediaStream(reply)) {
            mChecking.remove(path);
            mLastRun.remove(path);
            if (mMuted.remove(path))
                save();
            return;
        }
        if (mMuted.contains(path)) {
            mChecking.remove(path);
            mLastRun.remove(path);
            setMute(path, true);
            return;
        }
        call(getProperty(path, STREAM_IF, "Mute"), [this, path](const QDBusMessage &reply) {
            const bool wasMuted = replyValue(reply).toBool();
            if (mWanted && mChecking.remove(path) && !wasMuted)
                setMute(path, true);
        });
    });
}

// not wanted any more: a stream of the list of an earlier launcher is unmuted once it is known to be a media
// stream still (not another stream on the same path after a PulseAudio restart)
void MediaMute::release(const QString &path)
{
    call(getProperty(path, STREAM_IF, "PropertyList"), [this, path](const QDBusMessage &reply) {
        if (!mWanted && mediaStream(reply))
            setMute(path, false);
    });
}

void MediaMute::setMute(const QString &path, bool mute)
{
    if (mute && !mMuted.contains(path)) {
        mMuted.insert(path);
        save();
    }
    QDBusMessage set = QDBusMessage::createMethodCall(QString(), path, QLatin1String(PROPS_IF), QStringLiteral("Set"));
    set << QString::fromLatin1(STREAM_IF) << QStringLiteral("Mute") << QVariant::fromValue(QDBusVariant(QVariant(mute)));
    call(set, [this, path, mute](const QDBusMessage &) {
        qInfo() << "MediaMute: media stream" << (mute ? "muted" : "unmuted");
        if (mute)
            emit streamMuted(path);
        else
            emit streamUnmuted(path);
    });
}
