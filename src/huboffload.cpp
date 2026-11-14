/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "huboffload.h"

#include <QColor>
#include <QDate>
#include <QDebug>
#include <QFile>
#include <QFont>
#include <QFontMetricsF>
#include <QGlyphRun>
#include <QImage>
#include <QLocale>
#include <QPainter>
#include <QQuickItem>
#include <QQuickWindow>
#include <QStandardPaths>
#include <QTextLayout>
#include <QTime>
#include <cmath>

#include <lipstickcompositor.h>

#include "eoshubdigits.h"

extern "C" {
#include "eoslayout.h"
}

namespace {

// QQuickText enum values (qquicktext_p.h)
enum { NativeRendering = 1 };
enum { StyleNormal = 0, StyleOutline = 1 };
enum { WrapNone = 0, ElideNone = 3, FixedSize = 0, PlainText = 0, AutoText = 2 };

const int kPhases = 4;          // QFontEngineFT sub-pixel positions per pixel
// the A8 atlases of one layout, together: the hub keeps them in its graphics
// heap and they cost about 1 s of upload per 100 KB
const int kAtlasBudget = 384 * 1024;

qreal effectiveOpacity(QQuickItem *item)
{
    qreal o = 1.0;
    for (QQuickItem *i = item; i; i = i->parentItem())
        o *= i->opacity();
    return o;
}

// A digit string laid out as QQuickText lays out its single line
// (NativeRendering: no design metrics asked for; the FreeType engine uses
// them anyway with slight hinting, so the pens are fractional)
struct Line {
    QList<qreal> pen;           // pen x of each glyph
    qreal ascent = 0;
    qreal width = 0;            // natural width (QQuickText's implicit width)
};

bool layoutLine(const QFont &font, const QString &text, Line *l)
{
    QTextLayout layout(text, font);
    QTextOption opt;
    opt.setWrapMode(QTextOption::NoWrap);
    opt.setUseDesignMetrics(false);
    layout.setTextOption(opt);
    layout.setCacheEnabled(true);
    layout.beginLayout();
    QTextLine line = layout.createLine();
    if (!line.isValid())
        return false;
    line.setLineWidth(1e6);
    layout.endLayout();
    l->pen.clear();
    const QList<QGlyphRun> runs = layout.glyphRuns();
    for (const QGlyphRun &r : runs)
        for (const QPointF &p : r.positions())
            l->pen << p.x();
    l->ascent = line.ascent();
    l->width = line.naturalTextWidth();
    return l->pen.size() == text.size();
}

// Every digit one advance wide and no kerning between digits: then a slot
// shows any digit at the same pen and one sprite per slot is exact
bool tabular(const QFont &font, qreal *step, QChar zero = QLatin1Char('0'))
{
    Line l;
    if (!layoutLine(font, EosHub::localized(QStringLiteral("0123456789"), zero), &l))
        return false;
    *step = l.pen[1] - l.pen[0];
    for (int i = 0; i < 10; i++)
        if (std::fabs(l.pen[i] - l.pen[0] - i * *step) > 1.0 / 128)
            return false;
    for (int a = 0; a < 10; a++) {
        for (int b = 0; b < 10; b++) {
            Line p;
            if (!layoutLine(font, EosHub::localized(QString::number(a) + QString::number(b), zero), &p) ||
                std::fabs(p.pen[1] - p.pen[0] - *step) > 1.0 / 128 ||
                std::fabs(p.width - 2 * *step) > 1.0 / 128)
                return false;
        }
    }
    return true;
}

bool whole(qreal v)
{
    return std::fabs(v - std::round(v)) < 1e-6;
}

// An item with layer.enabled (the faces use it for a DropShadow) draws its
// children into a texture, and the effect draws that onto the screen. The
// digits stay where the scene graph put them only when the layer sits on
// whole pixels with a whole size (not so in nightstand, where the faces
// scale it to 80-86 %: the texture is then resampled), and only a drop
// shadow leaves them as they are.
bool layerOk(QQuickItem *a)
{
    QObject *layer = a->property("layer").value<QObject *>();
    if (!layer || !layer->property("enabled").toBool())
        return true;
    const QPointF p = a->mapToScene(QPointF(0, 0));
    const QSize ts = layer->property("textureSize").toSize();
    if (!whole(p.x()) || !whole(p.y()) || !whole(a->width()) || !whole(a->height()) ||
        (ts.isValid() && ts != QSize(qRound(a->width()), qRound(a->height()))))
        return false;
    if (!layer->property("effect").value<QObject *>())
        return true;
    // the effect item: a sibling whose source is the layer's texture (a
    // ShaderEffectSource of the layered item, also a sibling)
    if (QQuickItem *parent = a->parentItem()) {
        const QList<QQuickItem *> siblings = parent->childItems();
        for (QQuickItem *s : siblings) {
            QObject *src = s->property("source").value<QObject *>();
            if (s != a && src && (src == a || src->property("sourceItem").value<QObject *>() == a))
                return QLatin1String(s->metaObject()->className()).startsWith(QLatin1String("DropShadow"));
        }
    }
    return false;
}

// A Text item the hub can stand in for: one line of plain text drawn with
// the native glyph rasteriser at its implicit size, not rotated or scaled
bool usable(QQuickItem *it, QString *why)
{
    const QString name = it->objectName();
    if (!it->inherits("QQuickText")) {
        *why = name + " is not a Text";
        return false;
    }
    const QString text = it->property("text").toString();
    const int format = it->property("textFormat").toInt();
    if (it->property("renderType").toInt() != NativeRendering ||
        !(format == PlainText || (format == AutoText && !text.contains(QLatin1Char('<')))) ||
        it->property("wrapMode").toInt() != WrapNone ||
        it->property("elide").toInt() != ElideNone ||
        it->property("fontSizeMode").toInt() != FixedSize ||
        it->property("lineCount").toInt() != 1 ||
        it->property("lineHeight").toReal() != 1.0) {
        *why = name + " is not plain native text on one line";
        return false;
    }
    if (std::fabs(it->width() - it->implicitWidth()) > 1e-3 ||
        std::fabs(it->height() - it->implicitHeight()) > 1e-3) {
        *why = name + " has an explicit size";
        return false;
    }
    const QPointF o = it->mapToScene(QPointF(0, 0));
    const QPointF d = it->mapToScene(QPointF(1, 1)) - o;
    if (std::fabs(d.x() - 1) > 1e-6 || std::fabs(d.y() - 1) > 1e-6) {
        *why = name + " is rotated or scaled";
        return false;
    }
    for (QQuickItem *i = it; i; i = i->parentItem()) {
        if (!i->isVisible() || i->opacity() <= 0) {
            *why = name + " is hidden";
            return false;
        }
        if (!layerOk(i)) {
            *why = name + " is drawn through a layer that moves or changes it";
            return false;
        }
    }
    return true;
}

// Where the scene graph draws a glyph of a native-rendered Text (Qt 6.11
// QSGTextMaskMaterial::populate + textmask.vert): the pen x is floored and
// the baseline y rounded inside the item, then the quad is snapped to the
// pixel grid in the scene (floor(v + 0.5)). The glyph image itself is
// rasterised at the sub-pixel phase of the item-local pen x.
QPoint glyphOrigin(const QPointF &item, qreal penX, qreal baseY)
{
    return QPoint(int(std::floor(item.x() + 0.5)) + int(std::floor(penX)),
                  int(std::floor(item.y() + 0.5)) + int(std::lround(baseY)));
}

int phaseOf(qreal penX)
{
    return int(std::floor((penX - std::floor(penX)) * kPhases));
}

// The digits lo..hi (and a blank cell after them when a slot can be empty)
// of one font at one sub-pixel phase, cropped to their ink, as one row of A8
// cells: only what the slots using it can show (the tens of the minutes are
// 0..5), which keeps the big faces' atlases small. outline: the coverage of
// QSGOutlinedTextMaterial's ring (the four 1-pixel neighbours, less the
// glyph) instead of the glyph.
struct Atlas {
    QFont font;
    int phase = 0;
    bool outline = false;
    QChar zero = QLatin1Char('0');      // the digit set (locale digits, locale-formats-10)
    int lo = 9, hi = 0;
    bool blank = false;
    QRect ink;                  // cell rectangle relative to the glyph origin
    QByteArray strip;
    int cells = 0;
    int typeface = -1;
};

bool renderAtlas(Atlas *a, qreal ascent, qreal step)
{
    const QFontMetricsF fm(a->font);
    const int pad = int(std::ceil(fm.height() / 2)) + 2;
    const int w = int(std::ceil(step)) + 2 * pad, h = int(std::ceil(fm.height())) + 2 * pad;
    const int ox = pad, oy = pad + int(std::lround(ascent));
    QList<QImage> glyphs;
    QRect ink;
    for (int i = a->lo; i <= a->hi; i++) {
        QImage img(w, h, QImage::Format_Grayscale8);
        img.fill(0);
        QPainter p(&img);
        p.setRenderHint(QPainter::TextAntialiasing);
        p.setFont(a->font);
        p.setPen(Qt::white);
        // the raster engine floors x and takes the phase from its fraction,
        // as the scene graph does with the item-local pen
        p.drawText(QPointF(ox + qreal(a->phase) / kPhases, oy), QString(QChar(a->zero.unicode() + i)));
        p.end();
        if (a->outline) {
            QImage o(w, h, QImage::Format_Grayscale8);
            o.fill(0);
            for (int y = 1; y < h - 1; y++) {
                const uchar *up = img.constScanLine(y - 1), *mid = img.constScanLine(y),
                            *dn = img.constScanLine(y + 1);
                uchar *d = o.scanLine(y);
                for (int x = 1; x < w - 1; x++) {
                    const int s = qMin(255, up[x] + dn[x] + mid[x - 1] + mid[x + 1]);
                    d[x] = uchar(qMax(0, s - mid[x]));
                }
            }
            img = o;
        }
        for (int y = 0; y < h; y++) {
            const uchar *s = img.constScanLine(y);
            for (int x = 0; x < w; x++)
                if (s[x])
                    ink |= QRect(x, y, 1, 1);
        }
        glyphs << img;
    }
    if (ink.isEmpty() || ink.left() == 0 || ink.top() == 0 || ink.right() == w - 1 ||
        ink.bottom() == h - 1)
        return false;           // no ink, or it touches the canvas edge
    const int cw = ink.width(), ch = ink.height();
    a->cells = glyphs.size() + (a->blank ? 1 : 0);
    a->strip = QByteArray(cw * a->cells * ch, 0);
    for (int i = 0; i < glyphs.size(); i++)
        for (int y = 0; y < ch; y++)
            memcpy(a->strip.data() + y * cw * a->cells + i * cw,
                   glyphs[i].constScanLine(ink.top() + y) + ink.left(), cw);
    a->ink = ink.translated(-ox, -oy);
    return true;
}

// the bytes of an atlas on the hub (cells padded to 16 pixels, as the HAL)
int atlasBytes(const Atlas &a)
{
    return ((a.ink.width() + 15) & ~15) * a.cells * a.ink.height();
}

// One sprite: a glyph slot of a text item at a fixed pixel. Its digit is an
// expression of the hub's time (lo..hi); when `empty` is true (an
// expression too) the slot shows the blank cell.
struct Sprite {
    int atlas;
    QPoint origin;
    QString digit;
    int lo, hi;
    QString empty;
    uint32_t rgba;
};

// the atlas cell for a sprite's digit
QString cellExpr(const Sprite &s, const Atlas &a)
{
    const QString d = a.lo ? QString("(%1 - %2)").arg(s.digit).arg(a.lo) : s.digit;
    if (s.empty.isEmpty())
        return d;
    return QString("(%1 ? %2 : %3)").arg(s.empty).arg(a.hi - a.lo + 1).arg(d);
}

// The scene position of a Text item showing `width` worth of text: the face
// places it from its width (anchors, x bindings), so give it that width for
// a moment. *moved: another text of the face moved with it.
QPointF probe(QQuickItem *it, qreal width, const QList<QQuickItem *> &others, bool *moved)
{
    QList<QPointF> before;
    for (QQuickItem *o : others)
        before << o->mapToScene(QPointF(0, 0));
    it->setWidth(width);
    const QPointF p = it->mapToScene(QPointF(0, 0));
    for (int i = 0; i < others.size(); i++)
        if (others[i]->mapToScene(QPointF(0, 0)) != before[i])
            *moved = true;
    it->resetWidth();
    return p;
}

void collectTexts(QQuickItem *item, QList<QQuickItem *> *out)
{
    if (item->inherits("QQuickText") && item->isVisible())
        *out << item;
    const QList<QQuickItem *> children = item->childItems();
    for (QQuickItem *c : children)
        collectTexts(c, out);
}

} // namespace

HubOffload::HubOffload(QObject *parent) : QObject(parent)
{
}

bool HubOffload::build(QQuickItem *face, QQuickItem *hour, QQuickItem *minute, bool use12h,
                       const QDateTime &shown, QDateTime *until, QString *why)
{
    QQuickWindow *win = face->window();
    if (!win) {
        *why = "no window";
        return false;
    }
    QQuickItem *items[2] = { hour, minute };
    for (QQuickItem *it : items)
        if (!usable(it, why))
            return false;

    // the texts must be what the hub will draw for this time, in the digits
    // the face writes: ASCII or the locale's (locale-formats-10: one rule for
    // the face, the time texts and the hub, never the AP's drawing for a locale)
    const int h24 = shown.time().hour(), h12 = (h24 + 11) % 12 + 1;
    const QString hourText = use12h ? QString::number(h12)
                                    : QStringLiteral("%1").arg(h24, 2, 10, QLatin1Char('0'));
    const QString minuteText = QStringLiteral("%1").arg(shown.time().minute(), 2, 10, QLatin1Char('0'));
    const QChar localeZero = EosHub::zeroOfLocale(QLocale().zeroDigit());
    const QChar zero = EosHub::digitSet(hour->property("text").toString(), hourText,
                                        minute->property("text").toString(), minuteText, localeZero);
    if (zero.isNull()) {
        *why = QString("the face shows %1:%2, not %3:%4")
               .arg(hour->property("text").toString(), minute->property("text").toString(),
                    hourText, minuteText);
        return false;
    }

    QList<QQuickItem *> others;
    collectTexts(face, &others);
    others.removeAll(hour);
    others.removeAll(minute);

    QList<Atlas> atlases;
    QList<qreal> ascents, steps;        // per atlas, for rendering it
    QList<Sprite> sprites;
    bool hourWidthMoves = false;
    for (QQuickItem *it : items) {
        const QFont font = it->property("font").value<QFont>();
        qreal step;
        if (!tabular(font, &step, zero)) {
            *why = it->objectName() + ": the digits are not tabular";
            return false;
        }
        const qreal padL = it->property("leftPadding").toReal();
        const qreal padR = it->property("rightPadding").toReal();
        const qreal padT = it->property("topPadding").toReal();
        const QString text = it->property("text").toString();
        Line cur;
        if (!layoutLine(font, text, &cur) ||
            std::fabs(cur.width + padL + padR - it->implicitWidth()) > 1e-3) {
            *why = it->objectName() + ": its width is not the digits' width";
            return false;
        }
        const QPointF here = it->mapToScene(QPointF(0, 0));
        // the colour on the black the item leaves in the background; the
        // ring colour in the outline style (its fill is black)
        const int style = it->property("style").toInt();
        QColor c = it->property("color").value<QColor>();
        const QColor sc = it->property("styleColor").value<QColor>();
        bool outline = false;
        if (style != StyleNormal) {
            // a dark outline or shadow does not show on the black
            const qreal light = qMax(sc.redF(), qMax(sc.greenF(), sc.blueF())) * sc.alphaF();
            if (style == StyleOutline && light > 0.05) {
                outline = true;
                c = sc;
            } else if (light > 0.05) {
                *why = it->objectName() + ": raised or sunken text";
                return false;
            }
        }
        const qreal o = effectiveOpacity(it) * c.alphaF();
        const uint32_t rgba = (uint32_t(qRound(c.red() * o)) << 24) |
                              (uint32_t(qRound(c.green() * o)) << 16) |
                              (uint32_t(qRound(c.blue() * o)) << 8) | 0xff;

        // the digit strings this item shows: two digits, and in 12 h the
        // one-digit hours too, each where the face puts it. Per slot: the
        // digit (the stock HAL's time.*.digitN), its range, and when the
        // slot is empty (the other hour string is on screen)
        struct Slot { QString digit; int lo, hi; QString empty; };
        struct Variant { int len; QPointF pos; QList<Slot> slot; };
        QList<Variant> variants;
        if (it == minute) {
            variants << Variant{ 2, here, { { EL_EXPR_MIN_D1, 0, 5, {} },
                                            { EL_EXPR_MIN_D2, 0, 9, {} } } };
        } else if (!use12h) {
            variants << Variant{ 2, here, { { EL_EXPR_HOUR24_D1, 0, 2, {} },
                                            { EL_EXPR_HOUR24_D2, 0, 9, {} } } };
        } else {
            const QString h = QStringLiteral(EL_EXPR_HOUR12);
            const QString one = QString("(%1 > 9)").arg(h), two = QString("(%1 < 10)").arg(h);
            const int len = text.size();
            const QPointF other = probe(it, (3 - len) * step + padL + padR, others, &hourWidthMoves);
            if (it->mapToScene(QPointF(0, 0)) != here || it->width() != it->implicitWidth()) {
                *why = "the hour did not go back to its place";
                return false;
            }
            variants << Variant{ 1, len == 1 ? here : other, { { h, 1, 9, one } } };
            variants << Variant{ 2, len == 2 ? here : other,
                                 { { QStringLiteral("1"), 1, 1, two },
                                   { QString("(%1%10)").arg(h), 0, 2, two } } };
        }
        for (const Variant &v : variants) {
            Line l;
            if (!layoutLine(font, QString(v.len, zero), &l))
                return false;
            for (int k = 0; k < v.len; k++) {
                const qreal penX = padL + l.pen[k];
                const int phase = phaseOf(penX);
                int ai = 0;
                while (ai < atlases.size() && !(atlases[ai].font == font &&
                       atlases[ai].phase == phase && atlases[ai].outline == outline &&
                       atlases[ai].zero == zero))
                    ai++;
                if (ai == atlases.size()) {
                    Atlas a;
                    a.font = font;
                    a.phase = phase;
                    a.outline = outline;
                    a.zero = zero;
                    atlases << a;
                    ascents << cur.ascent;
                    steps << step;
                }
                const Slot &s = v.slot[k];
                Atlas &a = atlases[ai];
                a.lo = qMin(a.lo, s.lo);
                a.hi = qMax(a.hi, s.hi);
                a.blank |= !s.empty.isEmpty();
                sprites << Sprite{ ai, glyphOrigin(v.pos, penX, padT + l.ascent), s.digit, s.lo,
                                   s.hi, s.empty, rgba };
            }
        }
    }
    int bytes = 0;
    for (int i = 0; i < atlases.size(); i++) {
        if (!renderAtlas(&atlases[i], ascents[i], steps[i])) {
            *why = "no glyphs";
            return false;
        }
        bytes += atlasBytes(atlases[i]);
    }
    if (bytes > kAtlasBudget) {
        *why = QString("digit atlases of %1 KB, more than %2 KB").arg(bytes / 1024)
               .arg(kAtlasBudget / 1024);
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
    // the hub draws the digits over it: it must be black where they go, as
    // the AP's own digits cover it. An overlay (Ambient Lite) has the blurred
    // application there on purpose: the glyphs blend over it as the AP's did.
    for (const Sprite &s : sprites) {
        if (m_overlay)
            break;
        const Atlas &a = atlases[s.atlas];
        const QRect r = a.ink.translated(s.origin) & bg.rect();
        for (int y = r.top(); y <= r.bottom(); y++) {
            const uchar *p = bg.constScanLine(y) + 4 * r.left();
            for (int x = 0; x < r.width(); x++, p += 4) {
                if (qMax(p[0], qMax(p[1], p[2])) > 24) {
                    *why = QString("the background under the digits is not black at %1,%2")
                           .arg(r.left() + x).arg(y);
                    return false;
                }
            }
        }
    }

    el_layout *L = el_begin();
    if (!L || el_background_rgba(L, bg.constBits(), EL_FB_W, EL_FB_H, bg.bytesPerLine())) {
        *why = QString("background: %1").arg(L ? el_error(L) : "alloc");
        el_free(L);
        return false;
    }
    for (Atlas &a : atlases) {
        a.typeface = el_glyph_atlas_a8(L, a.cells, a.ink.width(), a.ink.height(),
                                       reinterpret_cast<const uint8_t *>(a.strip.constData()),
                                       a.ink.width() * a.cells, nullptr);
        if (a.typeface < 0) {
            *why = QString("atlas: %1").arg(el_error(L));
            el_free(L);
            return false;
        }
    }
    for (const Sprite &s : sprites) {
        const Atlas &a = atlases[s.atlas];
        const QByteArray e = cellExpr(s, a).toLatin1();
        const char *expr = e.constData();
        const QPoint at = s.origin + a.ink.topLeft();
        // (the host test of the layouts checks these lines)
        qDebug() << "hub offload: sprite at" << at << "phase" << a.phase << "glyph origin"
                 << s.origin << "cells" << a.lo << a.hi << a.blank << expr;
        if (el_sprite_text(L, a.typeface, at.x(), at.y(), s.rgba, 1, &expr, nullptr)) {
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

    *until = EosHub::validUntil(shown, use12h, hourWidthMoves, !m_overlay);
    const qint64 moveAfter = m_moveMinutes > 0 ? shown.toSecsSinceEpoch() + 60LL * m_moveMinutes : 0;
    if (!LipstickCompositor::instance() ||
        !LipstickCompositor::instance()->setOffloadLayout(path, until->isValid() ? until->toSecsSinceEpoch() : 0,
                                                          moveAfter)) {
        *why = "the display offload daemon refused the layout";
        return false;
    }
    qInfo().noquote() << QString("hub offload: layout of %1 messages loaded (%2 sprites, "
                                 "atlases %3 KB), valid until %4")
                         .arg(count).arg(sprites.size()).arg(bytes / 1024)
                         .arg(until->isValid() ? until->toString(QStringLiteral("ddd HH:mm")) : QStringLiteral("it changes"));
    return true;
}

bool HubOffload::update(QQuickItem *face, bool use12h, const QString &faceSource,
                        const QDateTime &shown, int moveMinutes)
{
    m_moveMinutes = moveMinutes;
    QQuickItem *hour = face ? face->findChild<QQuickItem *>("eosHubHour") : nullptr;
    QQuickItem *minute = face ? face->findChild<QQuickItem *>("eosHubMinute") : nullptr;
    QString why;

    // no daemon: nothing to build for; a daemon without a layout (it was
    // restarted): build and send it again
    const QString status = LipstickCompositor::instance() ?
                           LipstickCompositor::instance()->offloadStatus() : QString();
    if (status.isEmpty()) {
        m_loaded = false;
        return false;
    }
    const bool daemonHasLayout = status.contains(QLatin1String("layout=1"));
    if (!daemonHasLayout)
        m_loaded = false;
    // a face without a layout: the AP draws it (stock: no layout, no
    // offload); a layout the daemon kept from before goes too
    if (!hour || !minute) {
        drop(daemonHasLayout);
        return false;
    }
    const QPointF hp = hour->mapToScene(QPointF(0, 0));
    const QPointF mp = minute->mapToScene(QPointF(0, 0));
    // what the layout depends on: the face, where the digits are (the
    // burn-in shift moves them) and how they look; the background holds
    // until m_until
    const QString key = QStringLiteral("%1|%2|%3,%4|%5,%6|%7|%8")
        .arg(faceSource).arg(use12h)
        .arg(hp.x()).arg(hp.y()).arg(mp.x()).arg(mp.y())
        .arg(effectiveOpacity(hour))
        .arg(hour->property("style").toInt());
    if (m_loaded && key == m_key && (!m_until.isValid() || shown < m_until))
        return true;
    // a face that cannot be offloaded as it is: try again in the next hour
    // or when it changes, not at every minute the AP draws it
    const QString failKey = key + shown.toString(QStringLiteral("|yyyyMMddHH"));
    if (!m_loaded && failKey == m_failedKey)
        return false;
    if (!build(face, hour, minute, use12h, shown, &m_until, &why)) {
        qWarning() << "hub offload: no layout:" << why;
        // never leave an old layout to the hub: the AP draws this face
        drop(daemonHasLayout);
        m_failedKey = failKey;
        return false;
    }
    m_loaded = true;
    m_key = key;
    m_failedKey.clear();
    return true;
}

bool HubOffload::updateOverlay(QQuickItem *overlay, bool use12h, const QString &layoutKey,
                               const QDateTime &shown)
{
    // Ambient Lite or the media layout: the time items of the overlay, the rest
    // (the blurred application, the media buttons) the background. layoutKey
    // names what the background shows; another one is a new layout.
    m_overlay = true;
    const bool ok = update(overlay, use12h, layoutKey, shown, 0);
    m_overlay = false;
    return ok;
}

bool HubOffload::eligible(QQuickItem *face) const
{
    return face && face->findChild<QQuickItem *>("eosHubHour") && face->findChild<QQuickItem *>("eosHubMinute");
}

void HubOffload::drop(bool daemonHasLayout)
{
    if ((m_loaded || daemonHasLayout) && LipstickCompositor::instance())
        LipstickCompositor::instance()->clearOffloadLayout();
    m_loaded = false;
    m_key.clear();
}

void HubOffload::clear()
{
    if (m_loaded)
        drop(true);
}

void HubOffload::invalidate()
{
    drop(true);
    m_failedKey.clear();
}
