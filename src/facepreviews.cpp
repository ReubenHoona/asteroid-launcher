/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "facepreviews.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <QStandardPaths>

FacePreviews::FacePreviews(const QString &dir, QObject *parent)
    : QObject(parent)
    , m_dir(dir)
{
    if (m_dir.isEmpty())
        m_dir = QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation)
                + QStringLiteral("/asteroid-launcher/face-previews");
}

QString FacePreviews::fileName(const QString &id)
{
    static const QRegularExpression valid(QStringLiteral("^[a-z0-9_-]{1,120}$"));
    if (!valid.match(id).hasMatch())
        return QString();
    return id + QStringLiteral(".png");
}

QString FacePreviews::path(const QString &id) const
{
    const QString name = fileName(id);
    if (name.isEmpty() || !QDir().mkpath(m_dir))
        return QString();
    return m_dir + QLatin1Char('/') + name;
}

bool FacePreviews::exists(const QString &id) const
{
    const QString name = fileName(id);
    return !name.isEmpty() && QFileInfo(m_dir + QLatin1Char('/') + name).size() > 0;
}

QUrl FacePreviews::url(const QString &id) const
{
    return exists(id) ? QUrl::fromLocalFile(m_dir + QLatin1Char('/') + fileName(id)) : QUrl();
}

void FacePreviews::remove(const QString &id)
{
    const QString name = fileName(id);
    if (!name.isEmpty())
        QFile::remove(m_dir + QLatin1Char('/') + name);
}

int FacePreviews::keepOnly(const QStringList &ids)
{
    QStringList keep;
    for (const QString &id : ids)
        keep << fileName(id);
    int removed = 0;
    const QDir d(m_dir);
    const QStringList files = d.entryList({ QStringLiteral("*.png") }, QDir::Files);
    for (const QString &f : files)
        if (!keep.contains(f) && QFile::remove(d.filePath(f)))
            removed++;
    return removed;
}
