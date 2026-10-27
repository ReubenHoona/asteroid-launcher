#include "fakeservice.h"

#include <QDBusConnectionInterface>
#include <QDBusError>
#include <QDebug>
#include <QMetaObject>
#include <QMutexLocker>

FakeObject::FakeObject(const QString &introspectionXml, QObject *parent)
    : QDBusVirtualObject(parent), m_xml(introspectionXml)
{
}

void FakeObject::respond(const QString &member, Responder responder)
{
    QMutexLocker lock(&m_mutex);
    m_responders.insert(member, responder);
}

QList<RecordedCall> FakeObject::calls() const
{
    QMutexLocker lock(&m_mutex);
    return m_calls;
}

QList<RecordedCall> FakeObject::callsTo(const QString &member) const
{
    QMutexLocker lock(&m_mutex);
    QList<RecordedCall> found;
    for (const RecordedCall &call : m_calls) {
        if (call.member == member)
            found << call;
    }
    return found;
}

void FakeObject::clear()
{
    QMutexLocker lock(&m_mutex);
    m_calls.clear();
}

QString FakeObject::introspect(const QString &) const
{
    QMutexLocker lock(&m_mutex);
    return m_xml;
}

bool FakeObject::handleMessage(const QDBusMessage &message, const QDBusConnection &connection)
{
    if (message.interface() == QLatin1String("org.freedesktop.DBus.Introspectable"))
        return false; // QtDBus answers it from introspect()

    Responder responder;
    {
        QMutexLocker lock(&m_mutex);
        m_calls << RecordedCall { message.path(), message.interface(), message.member(), message.arguments() };
        responder = m_responders.value(message.member());
    }
    QDBusMessage reply;
    if (responder)
        reply = responder(message);
    else if (message.isReplyRequired())
        reply = message.createReply();
    if (reply.type() != QDBusMessage::InvalidMessage && message.isReplyRequired())
        connection.send(reply);
    return true;
}

FakeServiceHost::FakeServiceHost()
    : m_anchor(new QObject)
{
    m_anchor->moveToThread(&m_thread);
    m_thread.start();
}

FakeServiceHost::~FakeServiceHost()
{
    run([this] { delete m_anchor; });
    m_thread.quit();
    m_thread.wait();
}

void FakeServiceHost::adopt(QObject *obj)
{
    obj->moveToThread(&m_thread);
}

void FakeServiceHost::run(const std::function<void()> &fn)
{
    QMetaObject::invokeMethod(m_anchor, fn, Qt::BlockingQueuedConnection);
}

FakeService::FakeService(FakeServiceHost &host, const QString &service, const QString &connectionName)
    : m_host(host), m_service(service), m_name(connectionName),
      m_connection(QDBusConnection::connectToBus(TestBus::address(), connectionName))
{
}

FakeService::~FakeService()
{
    unregisterName();
    for (const QString &path : m_paths)
        m_connection.unregisterObject(path, QDBusConnection::UnregisterTree);
    QDBusConnection::disconnectFromBus(m_name);
    const QList<FakeObject *> objects = m_objects;
    m_host.run([objects] { qDeleteAll(objects); });
}

void FakeService::add(const QString &path, FakeObject *obj)
{
    m_objects << obj;
    m_paths << path;
    // registering gives obj a child: register first, then move it (and the child) to the worker thread
    m_connection.registerVirtualObject(path, obj, QDBusConnection::SubPath);
    m_host.adopt(obj);
}

bool FakeService::registerName()
{
    if (m_connection.registerService(m_service))
        return true;
    qWarning() << "FakeService: cannot own" << m_service << m_connection.isConnected() << m_connection.lastError();
    return false;
}

bool FakeService::unregisterName()
{
    return m_connection.unregisterService(m_service);
}

namespace {
QProcess *busDaemon = nullptr;
QString busAddress;
}

bool TestBus::start()
{
    if (busDaemon)
        return true;
    busDaemon = new QProcess;
    busDaemon->setProcessChannelMode(QProcess::ForwardedErrorChannel);
    busDaemon->start(QStringLiteral("dbus-daemon"),
                     { QStringLiteral("--config-file=" TEST_BUS_CONFIG), QStringLiteral("--nofork"),
                       QStringLiteral("--print-address=1") });
    if (!busDaemon->waitForStarted(5000))
        return false;
    while (!busDaemon->canReadLine()) {
        if (!busDaemon->waitForReadyRead(5000))
            return false;
    }
    busAddress = QString::fromUtf8(busDaemon->readLine()).trimmed();
    qputenv("DBUS_SYSTEM_BUS_ADDRESS", busAddress.toUtf8());
    qputenv("DBUS_SESSION_BUS_ADDRESS", busAddress.toUtf8());
    return !busAddress.isEmpty();
}

void TestBus::stop()
{
    if (!busDaemon)
        return;
    busDaemon->terminate();
    busDaemon->waitForFinished(2000);
    delete busDaemon;
    busDaemon = nullptr;
}

QString TestBus::address()
{
    return busAddress;
}
