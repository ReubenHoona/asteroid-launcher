// What the fake NotificationManager (fakenotificationmanager.cpp) records for the tests.
#ifndef FAKENOTIFICATIONMANAGER_H
#define FAKENOTIFICATIONMANAGER_H

#include <QList>
#include <QVariantHash>

struct FakeNotificationManagerLog
{
    static inline QList<uint> markedDisplayed;
};

// Hints of a notification as the tests post it
inline QVariantHash hints(std::initializer_list<std::pair<const char *, QVariant>> values)
{
    QVariantHash out;
    for (const auto &v : values)
        out.insert(QString::fromLatin1(v.first), v.second);
    return out;
}

#endif
