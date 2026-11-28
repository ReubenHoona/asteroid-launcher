/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Media sounds off in a mode (src/mediamute.h, C-11) against a fake PulseAudio D-Bus server: a peer server
 * (QDBusServer) in a thread of the test that answers as module-dbus-protocol does (the core's PlaybackStreams,
 * ListenForSignal and StopListeningForSignal, NewPlaybackStream and PlaybackStreamRemoved sent to a client that
 * listens only, each stream's PropertyList a{say} and Mute), and the server lookup on the session bus
 * (org.pulseaudio.Server, /org/pulseaudio/server_lookup1 Address):
 *   dbus-run-session -- tst_mediamute
 *   - PulseAudio not running when muting is wanted: nothing; it starts (the lookup name comes): the media
 *     streams (music, video, game) muted; the others (x-maemo, event, phone, alarm, none) and a media stream its
 *     app had muted left as they are
 *   - a media stream that starts while muting is wanted is muted, a stream of another role is not; one that
 *     ends is forgotten
 *   - not wanted any more: the streams muted here unmuted, the app's own mute kept, no more signals asked for;
 *     a media stream that starts then plays on; wanted again: muted again
 *   - PulseAudio restarted (a new server, the lookup name again): reconnected, its media streams muted
 *   - a launcher that starts again: the list in $XDG_RUNTIME_DIR names what it muted before: those are
 *     unmuted when no mode wants it (and taken as its own when one does); an entry that is another
 *     stream's now (no media role) is left alone
 *   - $PULSE_DBUS_SERVER: the server's address without the lookup
 * Plain checks (no QtTest).
 */

#include "mediamute.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusObjectPath>
#include <QDBusServer>
#include <QDBusVariant>
#include <QDBusVirtualObject>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QMap>
#include <QMutex>
#include <QMutexLocker>
#include <QSet>
#include <QThread>
#include <cstdio>
#include <functional>

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

typedef QMap<QString, QByteArray> PropList;

static const QString CORE = QStringLiteral("/org/pulseaudio/core1");
static const QString CORE_IF = QStringLiteral("org.PulseAudio.Core1");
static const QString STREAM_IF = QStringLiteral("org.PulseAudio.Core1.Stream");
static const QString PROPS_IF = QStringLiteral("org.freedesktop.DBus.Properties");

static QString streamPath(int n) { return CORE + QStringLiteral("/playback_stream%1").arg(n); }

// PulseAudio's D-Bus protocol, the part the mute uses
class FakePulse : public QDBusVirtualObject
{
    Q_OBJECT
public:
    struct Stream {
        QByteArray role;   // "" no media.role
        bool mute = false;
    };
    mutable QMutex lock;
    QMap<QString, Stream> streams;
    QSet<QString> listening;
    int sets = 0;
    QString address;
    QString peer;          // the server side of the client's connection
    QDBusServer *server = nullptr;

    QString introspect(const QString &) const override { return QString(); }

    bool handleMessage(const QDBusMessage &m, const QDBusConnection &c) override
    {
        QMutexLocker l(&lock);
        const QString path = m.path(), iface = m.interface(), member = m.member();
        const QList<QVariant> a = m.arguments();
        QDBusMessage reply;
        if (iface == PROPS_IF && member == QLatin1String("Get")) {
            const QString prop = a.value(1).toString();
            if (path == CORE && a.value(0).toString() == CORE_IF && prop == QLatin1String("PlaybackStreams")) {
                QList<QDBusObjectPath> list;
                for (auto it = streams.constBegin(); it != streams.constEnd(); ++it)
                    list << QDBusObjectPath(it.key());
                reply = m.createReply(QVariant::fromValue(QDBusVariant(QVariant::fromValue(list))));
            } else if (streams.contains(path) && a.value(0).toString() == STREAM_IF && prop == QLatin1String("PropertyList")) {
                PropList p;
                p.insert(QStringLiteral("application.name"), QByteArray("test", 5));   // with its NUL, as PulseAudio
                if (!streams[path].role.isEmpty())
                    p.insert(QStringLiteral("media.role"), streams[path].role + '\0');
                reply = m.createReply(QVariant::fromValue(QDBusVariant(QVariant::fromValue(p))));
            } else if (streams.contains(path) && a.value(0).toString() == STREAM_IF && prop == QLatin1String("Mute")) {
                reply = m.createReply(QVariant::fromValue(QDBusVariant(QVariant(streams[path].mute))));
            } else {
                reply = m.createErrorReply(QStringLiteral("org.PulseAudio.Core1.NoSuchPropertyError"), QStringLiteral("no such object"));
            }
        } else if (iface == PROPS_IF && member == QLatin1String("Set")) {
            if (streams.contains(path) && a.value(0).toString() == STREAM_IF && a.value(1).toString() == QLatin1String("Mute")) {
                streams[path].mute = a.value(2).value<QDBusVariant>().variant().toBool();
                sets++;
                reply = m.createReply();
            } else {
                reply = m.createErrorReply(QStringLiteral("org.PulseAudio.Core1.NoSuchPropertyError"), QStringLiteral("no such object"));
            }
        } else if (path == CORE && iface == CORE_IF && member == QLatin1String("ListenForSignal")) {
            listening.insert(a.value(0).toString());
            reply = m.createReply();
        } else if (path == CORE && iface == CORE_IF && member == QLatin1String("StopListeningForSignal")) {
            listening.remove(a.value(0).toString());
            reply = m.createReply();
        } else {
            return false;
        }
        c.send(reply);
        return true;
    }

public slots:
    void start()
    {
        server = new QDBusServer(QStringLiteral("unix:tmpdir=/tmp"), this);
        address = server->address();
        connect(server, &QDBusServer::newConnection, this, [this](const QDBusConnection &conn) {
            QDBusConnection c(conn);
            c.registerVirtualObject(CORE, this, QDBusConnection::SubPath);
            QMutexLocker l(&lock);
            peer = conn.name();
        });
    }

public:
    // from the main thread
    void add(int n, const QByteArray &role, bool mute = false)
    {
        QString to;
        {
            QMutexLocker l(&lock);
            Stream s;
            s.role = role;
            s.mute = mute;
            streams.insert(streamPath(n), s);
            if (listening.contains(CORE_IF + QStringLiteral(".NewPlaybackStream")))
                to = peer;
        }
        if (!to.isEmpty()) {
            QDBusMessage sig = QDBusMessage::createSignal(CORE, CORE_IF, QStringLiteral("NewPlaybackStream"));
            sig << QVariant::fromValue(QDBusObjectPath(streamPath(n)));
            QDBusConnection(to).send(sig);
        }
    }
    void remove(int n)
    {
        QString to;
        {
            QMutexLocker l(&lock);
            streams.remove(streamPath(n));
            if (listening.contains(CORE_IF + QStringLiteral(".PlaybackStreamRemoved")))
                to = peer;
        }
        if (!to.isEmpty()) {
            QDBusMessage sig = QDBusMessage::createSignal(CORE, CORE_IF, QStringLiteral("PlaybackStreamRemoved"));
            sig << QVariant::fromValue(QDBusObjectPath(streamPath(n)));
            QDBusConnection(to).send(sig);
        }
    }
    bool muted(int n) const
    {
        QMutexLocker l(&lock);
        return streams.value(streamPath(n)).mute;
    }
    int listens() const
    {
        QMutexLocker l(&lock);
        return listening.size();
    }
    int setCount() const
    {
        QMutexLocker l(&lock);
        return sets;
    }
    QString peerName() const
    {
        QMutexLocker l(&lock);
        return peer;
    }
};

// the server lookup PulseAudio puts on the session bus
class FakeLookup : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.PulseAudio.ServerLookup1")
    Q_PROPERTY(QString Address READ address)
public:
    QMutex lock;
    QString addr;
    QString address()
    {
        QMutexLocker l(&lock);
        return addr;
    }
};

static bool waitFor(const std::function<bool()> &cond, int ms = 10000)
{
    QElapsedTimer t;
    t.start();
    while (!cond() && t.elapsed() < ms)
        QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
    return cond();
}

static void spin(int ms) { waitFor([] { return false; }, ms); }

static FakePulse *startPulse(QThread *thread)
{
    auto *p = new FakePulse;
    p->moveToThread(thread);
    QMetaObject::invokeMethod(p, "start", Qt::BlockingQueuedConnection);
    return p;
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    if (qEnvironmentVariableIsEmpty("DBUS_SESSION_BUS_ADDRESS")) {
        fprintf(stderr, "needs a private session bus (see the top of the source)\n");
        return 2;
    }
    qunsetenv("PULSE_DBUS_SERVER");
    const QString runtime = QDir::tempPath() + QStringLiteral("/tst_mediamute-%1").arg(QCoreApplication::applicationPid());
    QDir().mkpath(runtime);
    qputenv("XDG_RUNTIME_DIR", runtime.toLocal8Bit());
    const QString list = runtime + QStringLiteral("/eos-media-mute");
    qDBusRegisterMetaType<PropList>();

    QThread fakeThread;
    fakeThread.start();
    FakePulse *pa = startPulse(&fakeThread);
    CHECK(!pa->address.isEmpty());
    pa->add(1, "music");
    pa->add(2, "x-maemo");            // the image's role of a stream that names none (module-match)
    pa->add(3, "video", true);        // muted by its app
    pa->add(4, "game");
    pa->add(5, "event");
    pa->add(6, "phone");
    pa->add(7, "");

    FakeLookup lookup;
    lookup.moveToThread(&fakeThread);
    QDBusConnection lookupConn = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("fake-lookup"));
    CHECK(lookupConn.registerObject(QStringLiteral("/org/pulseaudio/server_lookup1"), &lookup, QDBusConnection::ExportAllProperties));

    // ---- PulseAudio not running yet ----
    auto *mm = new MediaMute;
    int mutedSignals = 0, unmutedSignals = 0;
    QObject::connect(mm, &MediaMute::streamMuted, [&] { mutedSignals++; });
    QObject::connect(mm, &MediaMute::streamUnmuted, [&] { unmutedSignals++; });
    mm->setWanted(false);
    spin(300);
    CHECK(!mm->connected());          // nothing to do: no connection
    mm->setWanted(true);
    spin(800);
    CHECK(!mm->connected());
    CHECK(pa->setCount() == 0);

    // it starts: its lookup name comes on the session bus
    {
        QMutexLocker l(&lookup.lock);
        lookup.addr = pa->address;
    }
    CHECK(lookupConn.registerService(QStringLiteral("org.pulseaudio.Server")));
    CHECK(waitFor([&] { return mm->connected(); }));
    CHECK(waitFor([&] { return pa->muted(1) && pa->muted(4); }));
    spin(300);
    CHECK(!pa->muted(2) && !pa->muted(5) && !pa->muted(6) && !pa->muted(7));
    CHECK(pa->muted(3));
    CHECK(mm->mutedStreams() == QStringList({ streamPath(1), streamPath(4) }));
    CHECK(pa->listens() == 2);
    CHECK(pa->setCount() == 2);
    CHECK(waitFor([&] { return mutedSignals == 2; }));
    // the list for a launcher that starts again
    CHECK(QFile::exists(list));

    // ---- streams that start and end meanwhile ----
    pa->add(8, "music");
    CHECK(waitFor([&] { return pa->muted(8); }));
    pa->add(9, "alarm");
    pa->add(10, "x-eos-volume-ring");
    spin(400);
    CHECK(!pa->muted(9) && !pa->muted(10));
    pa->remove(8);
    CHECK(waitFor([&] { return !mm->mutedStreams().contains(streamPath(8)); }));

    // ---- not wanted any more ----
    mm->setWanted(false);
    CHECK(waitFor([&] { return !pa->muted(1) && !pa->muted(4); }));
    CHECK(pa->muted(3));              // the app's own mute stays
    CHECK(mm->mutedStreams().isEmpty());
    CHECK(waitFor([&] { return pa->listens() == 0; }));
    CHECK(waitFor([&] { return !QFile::exists(list); }));
    CHECK(waitFor([&] { return unmutedSignals == 2; }));
    pa->add(11, "music");
    spin(400);
    CHECK(!pa->muted(11));
    // wanted again
    mm->setWanted(true);
    CHECK(waitFor([&] { return pa->muted(1) && pa->muted(4) && pa->muted(11); }));
    CHECK(!pa->muted(2));

    // ---- PulseAudio restarts ----
    FakePulse *pa2 = startPulse(&fakeThread);
    pa2->add(1, "music");
    pa2->add(2, "event");
    CHECK(lookupConn.unregisterService(QStringLiteral("org.pulseaudio.Server")));
    QDBusConnection::disconnectFromPeer(pa->peerName());
    CHECK(waitFor([&] { return !mm->connected(); }));
    {
        QMutexLocker l(&lookup.lock);
        lookup.addr = pa2->address;
    }
    CHECK(lookupConn.registerService(QStringLiteral("org.pulseaudio.Server")));
    CHECK(waitFor([&] { return mm->connected() && pa2->muted(1); }));
    spin(300);
    CHECK(!pa2->muted(2));
    CHECK(mm->mutedStreams() == QStringList({ streamPath(1) }));

    // ---- the launcher starts again (as after a crash: nothing is undone at the exit) ----
    delete mm;
    CHECK(QFile::exists(list));
    pa2->add(3, "music", true);       // muted by its app meanwhile
    auto *again = new MediaMute;
    again->setWanted(false);          // no mode on any more: what the launcher before muted is unmuted
    CHECK(waitFor([&] { return !pa2->muted(1); }));
    spin(300);
    CHECK(pa2->muted(3));
    CHECK(!QFile::exists(list));
    // and with a mode still on: its streams are its own (unmuted when the mode ends)
    again->setWanted(true);
    CHECK(waitFor([&] { return pa2->muted(1); }));
    delete again;
    auto *third = new MediaMute;
    third->setWanted(true);
    CHECK(waitFor([&] { return third->connected(); }));
    spin(400);
    CHECK(third->mutedStreams() == QStringList({ streamPath(1) }));
    third->setWanted(false);
    CHECK(waitFor([&] { return !pa2->muted(1); }));
    CHECK(pa2->muted(3));
    delete third;

    // an entry of the list that is another stream's now (PulseAudio restarted meanwhile): left alone
    {
        QFile f(list);
        CHECK(f.open(QIODevice::WriteOnly));
        f.write((streamPath(2) + QLatin1Char('\n')).toLatin1());
    }
    const int setsBefore = pa2->setCount();
    auto *stale = new MediaMute;
    stale->setWanted(false);
    spin(800);
    CHECK(pa2->setCount() == setsBefore);
    stale->setWanted(true);
    spin(800);
    CHECK(!pa2->muted(2));
    CHECK(!stale->mutedStreams().contains(streamPath(2)));
    stale->setWanted(false);
    delete stale;

    // ---- $PULSE_DBUS_SERVER: no lookup ----
    CHECK(lookupConn.unregisterService(QStringLiteral("org.pulseaudio.Server")));
    FakePulse *pa3 = startPulse(&fakeThread);
    pa3->add(5, "video");
    qputenv("PULSE_DBUS_SERVER", pa3->address.toLocal8Bit());
    auto *direct = new MediaMute;
    direct->setWanted(true);
    CHECK(waitFor([&] { return pa3->muted(5); }));
    direct->setWanted(false);
    CHECK(waitFor([&] { return !pa3->muted(5); }));
    delete direct;

    fakeThread.quit();
    fakeThread.wait();
    QDir(runtime).removeRecursively();
    if (failures)
        fprintf(stderr, "tst_mediamute: %d of %d checks failed\n", failures, checks);
    else
        fprintf(stderr, "tst_mediamute: all %d checks passed\n", checks);
    return failures ? 1 : 0;
}

#include "tst_mediamute.moc"
