/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "aodbrightness.h"

#include <QDebug>
#include <QFile>
#include <MDConfItem>

static const char KEY[] = "/org/asteroidos/settings/always-on-brightness";
static const char PARAM[] = "/sys/module/panel_boe_wf012fbm/parameters/aod_max_level";

AodBrightness::AodBrightness(QObject *parent) : QObject(parent),
    m_level(new MDConfItem(QLatin1String(KEY), this))
{
    connect(m_level, &MDConfItem::valueChanged, this, &AodBrightness::apply);
    apply();
}

void AodBrightness::apply()
{
    const QString level = m_level->value(QStringLiteral("medium")).toString();
    const int step = level == QLatin1String("low") ? 6 : level == QLatin1String("high") ? 12 : 8;
    QFile param(QString::fromLatin1(PARAM));
    if (!param.exists())
        return;   // another panel, or the driver not loaded
    if (param.open(QIODevice::ReadOnly)) {
        const bool same = param.readAll().trimmed().toInt() == step;
        param.close();
        if (same)
            return;
    }
    if (!param.open(QIODevice::WriteOnly) || param.write(QByteArray::number(step) + '\n') < 0) {
        if (!m_warned)
            qWarning() << "AodBrightness: cannot write" << PARAM << param.errorString();
        m_warned = true;
        return;
    }
    qDebug() << "AodBrightness:" << level << "= panel AOD step" << step;
}
