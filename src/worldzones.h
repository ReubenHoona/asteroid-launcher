/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef WORLDZONES_H
#define WORLDZONES_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVector>

/*
 * The World clock complication's time zones (A-13), as stock's
 * WorldClockProviderService: the slot keeps a zone id ("worldclock:<id>"),
 * the time is the zone's at that moment (summer time included: QTimeZone,
 * the image's tz database), the complication's title is the zone's short
 * code and a tap opens the zone chooser (stock ACTION_CHOOSE_TIMEZONE:
 * regions, then the zones of a region as "City (CODE)", sorted by their
 * offset now and then by name).
 *
 * Stock's chooser lists the zones of its own resource table. The list here
 * is the image's tz database instead (zone.tab, as Settings' time zone page
 * reads it): every zone it has, the city its id names, the region from the
 * id's area (America split into North and South by the country, as stock's
 * regions), plus UTC. Stock's codes are hand made ("NYC"); here the code is
 * made from the city's name: three letters of one word ("LON"), the first
 * letter and two of the second word for two words, the initials of three or
 * more words ("SLC").
 *
 * Nothing here runs by itself: zone.tab is read once, when the chooser
 * first asks for it; an offset is one QTimeZone lookup.
 */
class WorldZones : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString tabFile READ tabFile WRITE setTabFile NOTIFY tabFileChanged)
public:
    explicit WorldZones(QObject *parent = nullptr);

    // not a zone (offsetMinutes)
    enum { NoZone = -100000 };

    QString tabFile() const { return m_tabFile; }
    void setTabFile(const QString &file);

    // the zone's offset from UTC at atMs (ms since the epoch), in minutes; NoZone if id is not a zone
    Q_INVOKABLE int offsetMinutes(const QString &id, double atMs) const;
    Q_INVOKABLE bool isZone(const QString &id) const;
    // the city the id names ("America/Argentina/Buenos_Aires" -> "Buenos Aires"; "Etc/UTC" -> "UTC")
    Q_INVOKABLE QString city(const QString &id) const { return cityOf(id); }
    // the short code shown as the complication's title
    Q_INVOKABLE QString code(const QString &id) const { return codeOf(cityOf(id)); }
    // the regions that have zones, keys in a fixed order (the chooser sorts them by their names)
    Q_INVOKABLE QStringList regions() const;
    // the zones of a region at atMs: [{ id, city, code, offset (minutes) }], by offset then city
    Q_INVOKABLE QVariantList zones(const QString &region, double atMs) const;
    // the region of a zone ("" when the chooser does not list it)
    Q_INVOKABLE QString regionOfZone(const QString &id) const;

    static QString cityOf(const QString &id);
    static QString codeOf(const QString &city);
    // the region key of a zone id and its zone.tab country code ("" when not listed)
    static QString regionOf(const QString &id, const QString &country);
    // the region keys, in the order regions() keeps
    static const QStringList &regionKeys();

signals:
    void tabFileChanged();

private:
    struct Entry { QString id; QString region; };
    void load() const;

    QString m_tabFile;
    mutable bool m_loaded = false;
    mutable QVector<Entry> m_entries;
};

#endif // WORLDZONES_H
