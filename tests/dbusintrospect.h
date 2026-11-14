/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * What Nemo.DBus sees of a remote object: the introspection XML. A DBusInterface
 * connects only the signals (and calls only the methods) that this XML lists, so
 * the D-Bus tests assert it. The object lives in the test's own thread, so the
 * call is asynchronous with a local event loop.
 */

#ifndef TESTS_DBUSINTROSPECT_H
#define TESTS_DBUSINTROSPECT_H

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QEventLoop>
#include <QHash>
#include <QString>
#include <QStringList>
#include <QXmlStreamReader>

// The reply of any method call, with the event loop running while it waits
inline QDBusMessage busCall(QDBusConnection &client, const QString &service, const QString &path,
                            const QString &iface, const QString &method,
                            const QVariantList &args = QVariantList())
{
    QDBusMessage m = QDBusMessage::createMethodCall(service, path, iface, method);
    m.setArguments(args);
    QDBusPendingCall pc = client.asyncCall(m, 3000);
    QDBusPendingCallWatcher w(pc);
    QEventLoop loop;
    QObject::connect(&w, &QDBusPendingCallWatcher::finished, &loop, &QEventLoop::quit);
    if (!pc.isFinished())
        loop.exec();
    return pc.reply();
}

struct Introspected
{
    // "<interface>.<member>" -> the argument types in order ("s", "i", "a{sv}"), per kind
    QHash<QString, QStringList> signalsOf;
    QHash<QString, QStringList> methodsOf;
    // "<interface>.<member>" -> the argument names in order
    QHash<QString, QStringList> signalNames;
    bool hasSignal(const QString &key) const { return signalsOf.contains(key); }
    bool hasMethod(const QString &key) const { return methodsOf.contains(key); }
};

inline Introspected introspect(QDBusConnection &client, const QString &service, const QString &path)
{
    Introspected out;
    const QDBusMessage r = busCall(client, service, path, QStringLiteral("org.freedesktop.DBus.Introspectable"),
                                   QStringLiteral("Introspect"));
    if (r.type() != QDBusMessage::ReplyMessage || r.arguments().isEmpty())
        return out;
    QXmlStreamReader xml(r.arguments().at(0).toString());
    QString iface, kind, member;
    QStringList types, names;
    while (!xml.atEnd()) {
        xml.readNext();
        if (xml.isStartElement()) {
            const QString n = xml.name().toString();
            if (n == QLatin1String("interface")) {
                iface = xml.attributes().value(QLatin1String("name")).toString();
            } else if (n == QLatin1String("signal") || n == QLatin1String("method")) {
                kind = n;
                member = xml.attributes().value(QLatin1String("name")).toString();
                types.clear();
                names.clear();
            } else if (n == QLatin1String("arg") && !kind.isEmpty()) {
                // method arguments: only "in" count as the call's; the answer is "out"
                const QString dir = xml.attributes().value(QLatin1String("direction")).toString();
                if (kind == QLatin1String("signal") || dir != QLatin1String("out")) {
                    types << xml.attributes().value(QLatin1String("type")).toString();
                    names << xml.attributes().value(QLatin1String("name")).toString();
                }
            }
        } else if (xml.isEndElement()) {
            const QString n = xml.name().toString();
            if (n == QLatin1String("signal")) {
                out.signalsOf.insert(iface + QLatin1Char('.') + member, types);
                out.signalNames.insert(iface + QLatin1Char('.') + member, names);
                kind.clear();
            } else if (n == QLatin1String("method")) {
                out.methodsOf.insert(iface + QLatin1Char('.') + member, types);
                kind.clear();
            }
        }
    }
    return out;
}

#endif
