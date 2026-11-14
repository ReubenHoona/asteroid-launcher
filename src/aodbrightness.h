/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef AODBRIGHTNESS_H
#define AODBRIGHTNESS_H

#include <QObject>

class MDConfItem;

/*
 * Settings > Display > Always-on brightness: dconf
 * /org/asteroidos/settings/always-on-brightness "low", "medium" (default) or
 * "high" sets how bright the panel is in always-on mode, through the BOE
 * panel driver's runtime parameter
 * /sys/module/panel_boe_wf012fbm/parameters/aod_max_level, a step of the
 * stock AOD brightness table: low 6, medium 8 (DBV 24 of 255: the image's
 * default, eos-panel.conf, the user's choice), high 12 (DBV 42). The image
 * makes the parameter writable for the video group (eos-modem-up, as the
 * panel's lp_mode); applied at start and whenever the key changes, written
 * only when it differs (the default needs no write). In Extra dim
 * (/org/asteroidos/modes/extra-dim, modes.h) the step is at most 4.
 */
class AodBrightness : public QObject
{
    Q_OBJECT
public:
    explicit AodBrightness(QObject *parent = nullptr);

private slots:
    void apply();

private:
    MDConfItem *m_level;
    MDConfItem *m_extraDim;
    MDConfItem *m_boost;
    bool m_warned = false;
};

#endif // AODBRIGHTNESS_H
