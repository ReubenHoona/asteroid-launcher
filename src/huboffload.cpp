/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "huboffload.h"

#include <QColor>
#include <QDate>
#include <QDateTime>
#include <QDebug>
#include <QFile>
#include <QFont>
#include <QFontMetricsF>
#include <QImage>
#include <QPainter>
#include <QQuickItem>
#include <QQuickWindow>
#include <QStandardPaths>
#include <QTime>
#include <cmath>

#include <lipstickcompositor.h>

extern "C" {
#include "eoslayout.h"
}

HubOffload::HubOffload(QObject *parent) : QObject(parent)
{
}

static qreal effectiveOpacity(QQuickItem *item)
{
    qreal o = 1.0;
    for (QQuickItem *i = item; i; i = i->parentItem())
        o *= i->opacity();
    return o;
}

// One row of A8 cells for the digits 0..9 in the item's font, each cell the
// digit's advance wide and the line high, the glyph on the line's baseline,
// as the QML Text draws it (NativeRendering: the raster engine's glyphs).
static bool digitAtlas(const QFont &font, QByteArray *strip, int *cellW, int *cellH,
                       qreal *advance)
{
    QFontMetricsF fm(font);
    const qreal adv = fm.horizontalAdvance(QLatin1Char('0'));
    for (char c = '1'; c <= '9'; c++) {
        // the hub draws each slot one advance after the other: tabular
        // digits only (Roboto's are)
        if (std::fabs(fm.horizontalAdvance(QLatin1Char(c)) - adv) > 0.01)
            return false;
    }
    const int w = int(std::ceil(adv));
    const int h = int(std::ceil(fm.height()));
    QImage img(w * 10, h, QImage::Format_Grayscale8);
    img.fill(0);
    QPainter p(&img);
    p.setRenderHint(QPainter::TextAntialiasing);
    p.setFont(font);
    p.setPen(Qt::white);
    for (int i = 0; i < 10; i++)
        p.drawText(QPointF(i * w, fm.ascent()), QString(QChar('0' + i)));
    p.end();
    strip->resize(w * 10 * h);
    for (int y = 0; y < h; y++)
        memcpy(strip->data() + y * w * 10, img.constScanLine(y), w * 10);
    *cellW = w;
    *cellH = h;
    *advance = adv;
    return true;
}

bool HubOffload::build(QQuickItem *face, QQuickItem *hour, QQuickItem *minute, QString *why)
{
    QQuickWindow *win = face->window();
    if (!win) {
        *why = "no window";
        return false;
    }

    // the background: the ambient screen with the time items hidden
    hour->setVisible(false);
    minute->setVisible(false);
    QImage bg = win->grabWindow();
    hour->setVisible(true);
    minute->setVisible(true);
    if (bg.isNull()) {
        *why = "grab failed";
        return false;
    }
    bg = bg.convertToFormat(QImage::Format_RGBA8888).scaled(EL_FB_W, EL_FB_H);

    el_layout *L = el_begin();
    if (!L || el_background_rgba(L, bg.constBits(), EL_FB_W, EL_FB_H, bg.bytesPerLine())) {
        *why = QString("background: %1").arg(L ? el_error(L) : "alloc");
        el_free(L);
        return false;
    }

    QQuickItem *items[2] = { hour, minute };
    static const char *const exprs[2][2] = {
        { EL_EXPR_HOUR24_D1, EL_EXPR_HOUR24_D2 },
        { EL_EXPR_MIN_D1, EL_EXPR_MIN_D2 },
    };
    for (int k = 0; k < 2; k++) {
        QQuickItem *it = items[k];
        const QFont font = it->property("font").value<QFont>();
        const QColor c = it->property("color").value<QColor>();
        const qreal o = effectiveOpacity(it) * c.alphaF();
        QByteArray strip;
        int cw, ch;
        qreal adv;
        if (!digitAtlas(font, &strip, &cw, &ch, &adv)) {
            *why = "digits are not tabular";
            el_free(L);
            return false;
        }
        float advances[10];
        for (float &a : advances)
            a = float(adv);
        const int tf = el_glyph_atlas_a8(L, 10, cw, ch,
                                         reinterpret_cast<const uint8_t *>(strip.constData()),
                                         cw * 10, advances);
        // the opacity goes into the colour: the hub draws on the background,
        // which is black where the item was
        const uint32_t rgba = (uint32_t(qRound(c.red() * o)) << 24) |
                              (uint32_t(qRound(c.green() * o)) << 16) |
                              (uint32_t(qRound(c.blue() * o)) << 8) | 0xff;
        const QPointF pos = it->mapToScene(QPointF(0, 0));
        if (tf < 0 || el_sprite_text(L, tf, float(pos.x()), float(pos.y()), rgba, 2,
                                     exprs[k], nullptr)) {
            *why = QString("digits: %1").arg(el_error(L));
            el_free(L);
            return false;
        }
    }

    el_msgs m;
    if (el_finish(L, &m)) {
        *why = QString("finish: %1").arg(el_error(L));
        el_free(L);
        return false;
    }
    const QString path = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation) +
                         "/eos-hub-layout.bin";
    QFile f(path);
    bool ok = f.open(QIODevice::WriteOnly | QIODevice::Truncate);
    for (int i = 0; ok && i < m.count; i++) {
        const char len = char(m.msg[i].len);
        ok = f.write(&len, 1) == 1 &&
             f.write(reinterpret_cast<const char *>(m.msg[i].b), m.msg[i].len) == m.msg[i].len;
    }
    f.close();
    const int count = m.count;
    el_msgs_free(&m);
    el_free(L);
    if (!ok) {
        *why = "cannot write " + path;
        return false;
    }

    // valid until the next local midnight: the date is on the background
    const QDateTime midnight(QDate::currentDate().addDays(1), QTime(0, 0));
    if (!LipstickCompositor::instance() ||
        !LipstickCompositor::instance()->setOffloadLayout(path, midnight.toSecsSinceEpoch())) {
        *why = "the display offload daemon refused the layout";
        return false;
    }
    qInfo() << "hub offload: layout of" << count << "messages loaded";
    return true;
}

bool HubOffload::update(QQuickItem *face, bool use12h, const QString &faceSource)
{
    QQuickItem *hour = face ? face->findChild<QQuickItem *>("eosHubHour24") : nullptr;
    QQuickItem *minute = face ? face->findChild<QQuickItem *>("eosHubMinute") : nullptr;
    QString why;

    // 12 h: the hour's width changes (no centring on the hub yet)
    if (!hour || !minute || use12h) {
        clear();
        return false;
    }
    const QPointF hp = hour->mapToScene(QPointF(0, 0));
    const QPointF mp = minute->mapToScene(QPointF(0, 0));
    const QString key = QStringLiteral("%1|%2|%3,%4|%5,%6|%7")
        .arg(faceSource, QDate::currentDate().toString(Qt::ISODate))
        .arg(hp.x()).arg(hp.y()).arg(mp.x()).arg(mp.y())
        .arg(effectiveOpacity(hour));
    if (m_loaded && key == m_key)
        return true;
    m_loaded = build(face, hour, minute, &why);
    m_key = m_loaded ? key : QString();
    if (!m_loaded)
        qWarning() << "hub offload: no layout:" << why;
    return m_loaded;
}

void HubOffload::clear()
{
    if (!m_loaded)
        return;
    if (LipstickCompositor::instance())
        LipstickCompositor::instance()->clearOffloadLayout();
    m_loaded = false;
    m_key.clear();
}
