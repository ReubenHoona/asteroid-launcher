/*
 * Test helpers: a private D-Bus daemon and fake D-Bus services (mce, BlueZ, GeoClue, PulseAudio).
 *
 * The units under test talk to QDBusConnection::systemBus() / sessionBus(). TestBus starts one private
 * dbus-daemon (tests/common/test-bus.conf) and points both DBUS_SYSTEM_BUS_ADDRESS and
 * DBUS_SESSION_BUS_ADDRESS at it, so nothing of the host is used. The fakes run in a worker thread
 * (FakeServiceHost): the units make blocking calls from the main thread, which a fake in the main
 * thread could never answer.
 */

#ifndef FAKESERVICE_H
#define FAKESERVICE_H

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusVirtualObject>
#include <QHash>
#include <QList>
#include <QMutex>
#include <QObject>
#include <QProcess>
#include <QThread>
#include <QVariantList>

#include <functional>

struct RecordedCall
{
    QString path;
    QString interface;
    QString member;
    QVariantList args;
};

// One object (and, with SubPath, everything below it) of a fake service. Records every call; answers
// with a responder set for the member, else with an empty reply when the caller waits for one.
class FakeObject : public QDBusVirtualObject
{
    Q_OBJECT
public:
    // returns the reply to send; an invalid QDBusMessage sends none
    using Responder = std::function<QDBusMessage(const QDBusMessage &call)>;

    explicit FakeObject(const QString &introspectionXml = QString(), QObject *parent = nullptr);

    void respond(const QString &member, Responder responder);
    QList<RecordedCall> calls() const;
    QList<RecordedCall> callsTo(const QString &member) const;
    void clear();

    QString introspect(const QString &path) const override;
    bool handleMessage(const QDBusMessage &message, const QDBusConnection &connection) override;

private:
    mutable QMutex m_mutex;
    QString m_xml;
    QList<RecordedCall> m_calls;
    QHash<QString, Responder> m_responders;
};

// The worker thread the fakes live in.
class FakeServiceHost
{
public:
    FakeServiceHost();
    ~FakeServiceHost();

    // Moves obj to the worker thread.
    void adopt(QObject *obj);
    // Runs fn in the worker thread and waits for it.
    void run(const std::function<void()> &fn);
    QThread *thread() { return &m_thread; }

private:
    QThread m_thread;
    QObject *m_anchor;
};

// A named connection to the private bus that owns `service` and exports objects.
class FakeService
{
public:
    FakeService(FakeServiceHost &host, const QString &service, const QString &connectionName);
    ~FakeService();

    // Exports obj (moved to the worker thread) at path and everything below it.
    void add(const QString &path, FakeObject *obj);
    bool registerName();
    bool unregisterName();
    QDBusConnection connection() const { return m_connection; }

private:
    FakeServiceHost &m_host;
    QString m_service;
    QString m_name;
    QDBusConnection m_connection;
    QList<FakeObject *> m_objects;
    QStringList m_paths;
};

// The private bus of a test process.
class TestBus
{
public:
    // Starts the daemon and sets the bus addresses; call before anything uses QDBusConnection.
    static bool start();
    static void stop();
    static QString address();
};

#endif // FAKESERVICE_H
