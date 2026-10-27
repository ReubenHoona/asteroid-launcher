// A fake mce (com.nokia.mce, /com/nokia/mce/request) on the private system bus.
#ifndef TEST_MCE_H
#define TEST_MCE_H

#include "fakeservice.h"

#include <QDBusVariant>

inline QString mceIntrospection()
{
    return QStringLiteral(
        "<interface name=\"com.nokia.mce.request\">"
        "<method name=\"get_config\"><arg type=\"o\" direction=\"in\"/><arg type=\"v\" direction=\"out\"/></method>"
        "<method name=\"set_config\"><arg type=\"s\" direction=\"in\"/><arg type=\"v\" direction=\"in\"/>"
        "<arg type=\"b\" direction=\"out\"/></method>"
        "<method name=\"req_display_state_on\"/>"
        "<method name=\"req_tklock_mode_change\"><arg type=\"s\" direction=\"in\"/></method>"
        "<method name=\"notification_begin_req\"><arg type=\"s\" direction=\"in\"/><arg type=\"i\" direction=\"in\"/>"
        "<arg type=\"i\" direction=\"in\"/></method>"
        "<method name=\"notification_end_req\"><arg type=\"s\" direction=\"in\"/><arg type=\"i\" direction=\"in\"/></method>"
        "</interface>");
}

// "set_config key value" / "req_tklock_mode_change mode" ... as one string per call, in order
inline QStringList mceRequests(const FakeObject *mce)
{
    QStringList out;
    for (const RecordedCall &call : mce->calls()) {
        QStringList parts { call.member };
        for (const QVariant &arg : call.args) {
            if (arg.metaType() == QMetaType::fromType<QDBusVariant>())
                parts << arg.value<QDBusVariant>().variant().toString();
            else if (arg.metaType() == QMetaType::fromType<QDBusObjectPath>())
                parts << arg.value<QDBusObjectPath>().path();
            else
                parts << arg.toString();
        }
        out << parts.join(QLatin1Char(' '));
    }
    return out;
}

#endif
