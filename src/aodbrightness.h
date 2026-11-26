/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef AODBRIGHTNESS_H
#define AODBRIGHTNESS_H

#include <QObject>

class MDConfItem;

/*
 * The panel's step for the AP-drawn always-on screen: the BOE panel driver's
 * runtime parameter /sys/module/panel_boe_wf012fbm/parameters/aod_max_level,
 * a step of the stock AOD brightness table. Stock has no Always-on
 * brightness setting (DECISIONS.md Q20: the Settings row went, nothing writes
 * /org/asteroidos/settings/always-on-brightness any more, so its reader went
 * too): the step is the image's default 8 (DBV 24 of 255, eos-panel.conf),
 * at most 4 in Extra dim (/org/asteroidos/modes/extra-dim, modes.h). The
 * image makes the parameter writable for the video group (eos-modem-up, as
 * the panel's lp_mode); applied at start and when Extra dim changes, written
 * only when it differs (the default needs no write). The sensor hub's
 * always-on brightness and the burn-in mask's x2 are the display offload
 * daemon's.
 */
class AodBrightness : public QObject
{
    Q_OBJECT
public:
    explicit AodBrightness(QObject *parent = nullptr);

private slots:
    void apply();

private:
    MDConfItem *m_extraDim;
    bool m_warned = false;
};

#endif // AODBRIGHTNESS_H
