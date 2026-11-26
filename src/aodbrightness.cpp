/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "aodbrightness.h"

#include <QDebug>
#include <QFile>
#include <MDConfItem>

#include "modescore.h"

static const char EXTRA_DIM_KEY[] = "/org/asteroidos/modes/extra-dim";
// the image's step (eos-panel.conf aod_max_level=8, DBV 24 of 255)
static const int DEFAULT_STEP = 8;
// (the burn-in mask's x2 is the display offload daemon's: BurnInMask.qml has the
// compositor send it "mask 1", CR-46; the dconf aod-mask-boost is retired)
static const char PARAM[] = "/sys/module/panel_boe_wf012fbm/parameters/aod_max_level";

AodBrightness::AodBrightness(QObject *parent) : QObject(parent),
    m_extraDim(new MDConfItem(QLatin1String(EXTRA_DIM_KEY), this))
{
    connect(m_extraDim, &MDConfItem::valueChanged, this, &AodBrightness::apply);
    apply();
}

void AodBrightness::apply()
{
    int step = DEFAULT_STEP;
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
    qDebug() << "AodBrightness:" << (m_extraDim->value(false).toBool() ? "extra dim" : "default") << "= panel AOD step" << step;
}
