/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "aodbrightness.h"

#include <QDebug>
#include <QFile>
#include <MDConfItem>

#include "modescore.h"

static const char KEY[] = "/org/asteroidos/settings/always-on-brightness";
static const char EXTRA_DIM_KEY[] = "/org/asteroidos/modes/extra-dim";
// set by compositor/BurnInMask.qml while the AP-drawn always-on screen has the
// burn-in mask (stock: brightness x2 while it shows, ambient-aod-07)
static const char BOOST_KEY[] = "/org/asteroidos/launcher/aod-mask-boost";
static const int MASK_BOOST_STEP = 12;   // DBV 42 of 255 (the medium step 8 is DBV 24)
static const char PARAM[] = "/sys/module/panel_boe_wf012fbm/parameters/aod_max_level";

AodBrightness::AodBrightness(QObject *parent) : QObject(parent),
    m_level(new MDConfItem(QLatin1String(KEY), this)),
    m_extraDim(new MDConfItem(QLatin1String(EXTRA_DIM_KEY), this)),
    m_boost(new MDConfItem(QLatin1String(BOOST_KEY), this))
{
    connect(m_boost, &MDConfItem::valueChanged, this, &AodBrightness::apply);
    connect(m_level, &MDConfItem::valueChanged, this, &AodBrightness::apply);
    connect(m_extraDim, &MDConfItem::valueChanged, this, &AodBrightness::apply);
    apply();
}

void AodBrightness::apply()
{
    const QString level = m_level->value(QStringLiteral("medium")).toString();
    int step = level == QLatin1String("low") ? 6 : level == QLatin1String("high") ? 12 : 8;
    if (m_boost->value(false).toBool())
        step = qMax(step, MASK_BOOST_STEP);
    if (m_extraDim->value(false).toBool())
        step = qMin(step, int(ModesCore::ExtraDimAodStep));
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
    qDebug() << "AodBrightness:" << level << (m_extraDim->value(false).toBool() ? "(extra dim)" : "") << "= panel AOD step" << step;
}
