/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * A stand-in for lipstick's compositor in tests/tst_huboffload_flip.cpp: HubOffload only asks it for the
 * display offload daemon's status and hands it the finished layout. It keeps what it was given.
 */

#ifndef LIPSTICKCOMPOSITOR_H
#define LIPSTICKCOMPOSITOR_H

#include <QString>
#include <QStringList>

class LipstickCompositor
{
public:
    static LipstickCompositor *instance()
    {
        static LipstickCompositor c;
        return &c;
    }
    QString offloadStatus() { return layout ? QStringLiteral("layout=1") : QStringLiteral("layout=0"); }
    bool setOffloadLayout(const QString &path, qint64 validUntil = 0, qint64 moveAfter = 0)
    {
        layouts << path;
        lastValidUntil = validUntil;
        lastMoveAfter = moveAfter;
        layout = true;
        return true;
    }
    void clearOffloadLayout()
    {
        cleared++;
        layout = false;
    }

    QStringList layouts;
    qint64 lastValidUntil = 0, lastMoveAfter = 0;
    int cleared = 0;
    bool layout = false;
};

#endif // LIPSTICKCOMPOSITOR_H
