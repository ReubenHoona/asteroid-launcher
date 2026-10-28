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
 * /sys/module/panel_boe_wf012fbm/parameters/aod_max_level (the index into
 * the stock AOD brightness steps: 6, 12, 24; 12 = DBV 42 of 255). The image
 * makes the parameter writable for the video group (eos-modem-up, as the
 * panel's lp_mode); applied at start and whenever the key changes.
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
    bool m_warned = false;
};

#endif // AODBRIGHTNESS_H
