/*
 * Copyright (C) 2017 Florent Revest <revestflo@gmail.com>
 * All rights reserved.
 *
 * You may use this file under the terms of BSD license as follows:
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of the author nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include "firstrun.h"

#include <QDateTime>
#include <QDebug>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusVariant>
#include <QFile>
#include <QRegularExpression>
#include <QTimeZone>

#include <cmath>

namespace {

// ISO 6709 sign-degrees-minutes[-seconds], e.g. "+4230" or "-0361029"
double parseIso6709(const QString &value, int degreeDigits)
{
    const double sign = value.startsWith(QLatin1Char('-')) ? -1.0 : 1.0;
    const QString digits = value.mid(1);
    const double degrees = digits.left(degreeDigits).toDouble();
    const double minutes = digits.mid(degreeDigits, 2).toDouble();
    const double seconds = digits.length() > degreeDigits + 2 ? digits.mid(degreeDigits + 2, 2).toDouble() : 0.0;
    return sign * (degrees + minutes / 60.0 + seconds / 3600.0);
}

// Great-circle distance in radians between two positions in degrees
double angularDistance(double lat1, double lon1, double lat2, double lon2)
{
    const double rad = M_PI / 180.0;
    const double dLat = (lat2 - lat1) * rad;
    const double dLon = (lon2 - lon1) * rad;
    const double a = std::sin(dLat / 2) * std::sin(dLat / 2)
            + std::cos(lat1 * rad) * std::cos(lat2 * rad) * std::sin(dLon / 2) * std::sin(dLon / 2);
    return 2 * std::atan2(std::sqrt(a), std::sqrt(1 - a));
}

}

FirstRun::FirstRun()
{
    m_mceDbus = new QDBusInterface("com.nokia.mce", "/com/nokia/mce/request", "com.nokia.mce.request", QDBusConnection::systemBus());
    firstRunDone = new MDConfItem("/org/asteroidos/launcher/firstRunDone", this);
}

bool FirstRun::isFirstRun()
{
    return !firstRunDone->value(false).toBool();;
}

void FirstRun::startFirstRun()
{
    m_mceDbus->asyncCall("set_config", QDBusObjectPath("/system/osso/dsm/display/inhibit_blank_mode").path(), QVariant::fromValue(QDBusVariant(3)));
    m_mceDbus->asyncCall("req_tklock_mode_change", "unlocked");
    m_mceDbus->asyncCall("set_config", QDBusObjectPath("/system/osso/dsm/locks/tklock_blank_disable").path(), QVariant::fromValue(QDBusVariant(1)));
}

void FirstRun::stopFirstRun()
{
    m_mceDbus->asyncCall("set_config", QDBusObjectPath("/system/osso/dsm/display/inhibit_blank_mode").path(), QVariant::fromValue(QDBusVariant(0)));
    m_mceDbus->asyncCall("req_tklock_mode_change", "locked");
    m_mceDbus->asyncCall("set_config", QDBusObjectPath("/system/osso/dsm/locks/tklock_blank_disable").path(), QVariant::fromValue(QDBusVariant(0)));

    firstRunDone->set(true);
}

QString FirstRun::timezoneForPosition(double latitude, double longitude) const
{
    // zone1970.tab lists every zone with the position of its principal city;
    // zone.tab is the older format of the same data.
    const QStringList tables = { QStringLiteral("/usr/share/zoneinfo/zone1970.tab"),
                                 QStringLiteral("/usr/share/zoneinfo/zone.tab") };
    static const QRegularExpression coordinates(QStringLiteral("^([+-]\\d{4}(?:\\d{2})?)([+-]\\d{5}(?:\\d{2})?)$"));

    for (const QString &table : tables) {
        QFile file(table);
        if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
            continue;

        QString nearest;
        double nearestDistance = 0;
        while (!file.atEnd()) {
            const QString line = QString::fromUtf8(file.readLine()).trimmed();
            if (line.isEmpty() || line.startsWith(QLatin1Char('#')))
                continue;
            const QStringList fields = line.split(QLatin1Char('\t'));
            if (fields.size() < 3)
                continue;
            const QRegularExpressionMatch match = coordinates.match(fields.at(1));
            if (!match.hasMatch())
                continue;
            const double zoneLatitude = parseIso6709(match.captured(1), 2);
            const double zoneLongitude = parseIso6709(match.captured(2), 3);
            const double distance = angularDistance(latitude, longitude, zoneLatitude, zoneLongitude);
            if (nearest.isEmpty() || distance < nearestDistance) {
                nearest = fields.at(2);
                nearestDistance = distance;
            }
        }
        if (!nearest.isEmpty())
            return nearest;
    }
    qWarning() << "FirstRun: no time zone table found";
    return QString();
}

QVariantMap FirstRun::localDateTime(const QString &timeZone, qint64 utcSeconds) const
{
    const QTimeZone zone(timeZone.toUtf8());
    if (!zone.isValid())
        return QVariantMap();

    const QDateTime local = QDateTime::fromSecsSinceEpoch(utcSeconds, zone);
    return QVariantMap {
        { QStringLiteral("year"), local.date().year() },
        { QStringLiteral("month"), local.date().month() },
        { QStringLiteral("day"), local.date().day() },
        { QStringLiteral("hour"), local.time().hour() },
        { QStringLiteral("minute"), local.time().minute() },
    };
}

void FirstRun::requestGpsSatellites()
{
    const QDBusMessage call = QDBusMessage::createMethodCall(
                QStringLiteral("org.freedesktop.Geoclue.Providers.Hybris"),
                QStringLiteral("/org/freedesktop/Geoclue/Providers/Hybris"),
                QStringLiteral("org.freedesktop.Geoclue.Satellite"),
                QStringLiteral("GetSatellite"));
    QDBusPendingCallWatcher *watcher =
            new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(call), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *finished) {
        finished->deleteLater();
        // (timestamp, used, visible, used PRNs, [(prn, elevation, azimuth, snr)])
        const QDBusMessage reply = finished->reply();
        const QVariantList args = reply.arguments();
        if (reply.type() != QDBusMessage::ReplyMessage || args.size() < 5)
            return;

        int heard = 0;
        const QDBusArgument satellites = args.at(4).value<QDBusArgument>();
        satellites.beginArray();
        while (!satellites.atEnd()) {
            int prn, elevation, azimuth, snr;
            satellites.beginStructure();
            satellites >> prn >> elevation >> azimuth >> snr;
            satellites.endStructure();
            if (snr > 0)
                heard++;
        }
        satellites.endArray();
        emit gpsSatellitesChanged(args.at(1).toInt(), heard);
    });
}

