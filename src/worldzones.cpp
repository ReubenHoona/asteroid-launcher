/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "worldzones.h"

#include <QDateTime>
#include <QFile>
#include <QSet>
#include <QTimeZone>
#include <QVariantMap>
#include <algorithm>

namespace {
// the countries of continental South America (ISO 3166), stock's "South America" region
const QSet<QString> &southAmerica()
{
    static const QSet<QString> s = { QStringLiteral("AR"), QStringLiteral("BO"), QStringLiteral("BR"),
                                     QStringLiteral("CL"), QStringLiteral("CO"), QStringLiteral("EC"),
                                     QStringLiteral("FK"), QStringLiteral("GF"), QStringLiteral("GY"),
                                     QStringLiteral("PE"), QStringLiteral("PY"), QStringLiteral("SR"),
                                     QStringLiteral("UY"), QStringLiteral("VE") };
    return s;
}
const QString utcId = QStringLiteral("Etc/UTC");
}

WorldZones::WorldZones(QObject *parent)
    : QObject(parent)
    , m_tabFile(QStringLiteral("/usr/share/zoneinfo/zone.tab"))
{
}

void WorldZones::setTabFile(const QString &file)
{
    if (file == m_tabFile)
        return;
    m_tabFile = file;
    m_loaded = false;
    m_entries.clear();
    emit tabFileChanged();
}

const QStringList &WorldZones::regionKeys()
{
    static const QStringList k = { QStringLiteral("africa"), QStringLiteral("asia"), QStringLiteral("atlantic"),
                                   QStringLiteral("australia"), QStringLiteral("europe"), QStringLiteral("indian"),
                                   QStringLiteral("northamerica"), QStringLiteral("pacific"),
                                   QStringLiteral("southamerica"), QStringLiteral("universal") };
    return k;
}

QString WorldZones::regionOf(const QString &id, const QString &country)
{
    if (id == utcId)
        return QStringLiteral("universal");
    const QString area = id.section(QLatin1Char('/'), 0, 0);
    if (area == QLatin1String("America"))
        return southAmerica().contains(country) ? QStringLiteral("southamerica") : QStringLiteral("northamerica");
    if (area == QLatin1String("Africa") || area == QLatin1String("Asia") || area == QLatin1String("Atlantic")
        || area == QLatin1String("Australia") || area == QLatin1String("Europe") || area == QLatin1String("Indian")
        || area == QLatin1String("Pacific"))
        return area.toLower();
    // Antarctica and Arctic (research stations): stock has no such region
    return QString();
}

QString WorldZones::cityOf(const QString &id)
{
    if (id == utcId)
        return QStringLiteral("UTC");
    QString c = id.section(QLatin1Char('/'), -1);
    c.replace(QLatin1Char('_'), QLatin1Char(' '));
    return c;
}

QString WorldZones::codeOf(const QString &city)
{
    if (city == QLatin1String("UTC"))
        return city;
    // the letters of each word, without accents
    QStringList words;
    const QString plain = city.normalized(QString::NormalizationForm_D);
    QString w;
    for (const QChar ch : plain) {
        if (ch.isLetter() && ch.unicode() < 128) {
            w += ch.toUpper();
        } else if (ch.isSpace() || ch == QLatin1Char('-')) {
            if (!w.isEmpty())
                words << w;
            w.clear();
        }
    }
    if (!w.isEmpty())
        words << w;
    if (words.isEmpty())
        return QString();
    if (words.size() >= 3)
        return words.at(0).left(1) + words.at(1).left(1) + words.at(2).left(1);
    if (words.size() == 2 && words.at(1).size() >= 2)
        return words.at(0).left(1) + words.at(1).left(2);
    return (words.at(0) + (words.size() > 1 ? words.at(1) : QString())).left(3);
}

void WorldZones::load() const
{
    if (m_loaded)
        return;
    m_loaded = true;
    m_entries.clear();
    QFile file(m_tabFile);
    if (file.open(QIODevice::ReadOnly)) {
        const QList<QByteArray> lines = file.readAll().split('\n');
        for (const QByteArray &raw : lines) {
            if (raw.isEmpty() || raw.startsWith('#'))
                continue;
            // country code, coordinates, zone id, comments (tab separated)
            const QList<QByteArray> f = raw.split('\t');
            if (f.size() < 3)
                continue;
            const QString id = QString::fromLatin1(f.at(2)).trimmed();
            const QString region = regionOf(id, QString::fromLatin1(f.at(0)).trimmed());
            if (region.isEmpty() || !QTimeZone::isTimeZoneIdAvailable(id.toLatin1()))
                continue;
            m_entries.append({ id, region });
        }
    }
    if (QTimeZone::isTimeZoneIdAvailable(utcId.toLatin1()))
        m_entries.append({ utcId, QStringLiteral("universal") });
}

bool WorldZones::isZone(const QString &id) const
{
    return !id.isEmpty() && QTimeZone::isTimeZoneIdAvailable(id.toLatin1());
}

int WorldZones::offsetMinutes(const QString &id, double atMs) const
{
    if (!isZone(id))
        return NoZone;
    const QTimeZone z(id.toLatin1());
    if (!z.isValid())
        return NoZone;
    const QDateTime at = QDateTime::fromMSecsSinceEpoch(qint64(atMs), QTimeZone::UTC);
    return z.offsetFromUtc(at) / 60;
}

QStringList WorldZones::regions() const
{
    load();
    QStringList out;
    for (const QString &k : regionKeys())
        for (const Entry &e : m_entries)
            if (e.region == k) {
                out << k;
                break;
            }
    return out;
}

QString WorldZones::regionOfZone(const QString &id) const
{
    load();
    for (const Entry &e : m_entries)
        if (e.id == id)
            return e.region;
    return QString();
}

QVariantList WorldZones::zones(const QString &region, double atMs) const
{
    load();
    struct Z { QString id, city; int offset; };
    QVector<Z> zs;
    for (const Entry &e : m_entries)
        if (e.region == region)
            zs.append({ e.id, cityOf(e.id), offsetMinutes(e.id, atMs) });
    // stock iqj.compareTo: the offset now, then the name
    std::sort(zs.begin(), zs.end(), [](const Z &a, const Z &b) {
        if (a.offset != b.offset)
            return a.offset < b.offset;
        return a.city != b.city ? a.city < b.city : a.id < b.id;
    });
    QVariantList out;
    for (const Z &z : zs) {
        QVariantMap m;
        m.insert(QStringLiteral("id"), z.id);
        m.insert(QStringLiteral("city"), z.city);
        m.insert(QStringLiteral("code"), codeOf(z.city));
        m.insert(QStringLiteral("offset"), z.offset);
        out << m;
    }
    return out;
}
