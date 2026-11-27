/*
 * Copyright (C) 2026 eos
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
#include <QJSValue>
#include <QPen>
#include <QLocale>
#include <QPainter>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRadialGradient>
#include <QStandardPaths>
#include <algorithm>
#include <functional>
#include <QTextLayout>
#include <QTime>
#include <cmath>

#include <lipstickcompositor.h>

#include "eoshubdigits.h"
#include "eoshubflip.h"

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
bool usable(QQuickItem *it, QString *why, bool *turned)
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
    // upright, or turned by 180 degrees with the compositor's root (the wrist flip, crown on the left:
    // W3-launcher-wrist); a Text in any other transform cannot be drawn by the hub
    const QPointF o = it->mapToScene(QPointF(0, 0));
    const int turn = EosHub::sceneTurn(it->mapToScene(QPointF(1, 1)) - o);
    if (turn == 0) {
        *why = name + " is rotated or scaled";
        return false;
    }
    *turned = turn < 0;
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
// rasterised at the sub-pixel phase of the item-local pen x. Under the wrist
// flip the same, with the quad turned: EosHub::glyphOrigin, spriteTopLeft.
using EosHub::glyphOrigin;

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
    bool turned = false;        // the cells are turned by 180 degrees (the wrist flip)
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
    // the scene graph under a 180 degree turn draws the glyph bitmap turned in itself
    if (a->turned)
        EosHub::turnCells180(&a->strip, cw, a->cells, ch);
    a->ink = ink.translated(-ox, -oy);
    return true;
}

// Where a digit of the atlas can be, over its digit cells (not the blank one): a pixel with
// coverage, or one the coverage encloses (the outline style's black fill, a counter) - every
// zero pixel not reachable from the cell's edge. 1 = a digit can cover it. cw x ch bytes, in the
// strip's (= the sprite's) orientation.
QByteArray digitMask(const Atlas &a)
{
    const int cw = a.ink.width(), ch = a.ink.height(), stride = cw * a.cells;
    const int n = a.hi - a.lo + 1;
    QByteArray mask(cw * ch, 0);
    QVector<uchar> out(cw * ch);
    QVector<int> q;
    q.reserve(cw * ch);
    for (int c = 0; c < n && c < a.cells; c++) {
        const uchar *cell = reinterpret_cast<const uchar *>(a.strip.constData()) + c * cw;
        std::fill(out.begin(), out.end(), uchar(0));
        q.clear();
        auto push = [&](int x, int y) {
            const int i = y * cw + x;
            if (!out[i] && !cell[y * stride + x]) {
                out[i] = 1;
                q << i;
            }
        };
        for (int x = 0; x < cw; x++) {
            push(x, 0);
            push(x, ch - 1);
        }
        for (int y = 0; y < ch; y++) {
            push(0, y);
            push(cw - 1, y);
        }
        for (int k = 0; k < q.size(); k++) {
            const int x = q[k] % cw, y = q[k] / cw;
            if (x > 0)
                push(x - 1, y);
            if (x < cw - 1)
                push(x + 1, y);
            if (y > 0)
                push(x, y - 1);
            if (y < ch - 1)
                push(x, y + 1);
        }
        for (int i = 0; i < cw * ch; i++)
            if (!out[i])
                mask[i] = 1;
    }
    return mask;
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

// The visible items of a face with an objectName, in tree (drawing) order
void collectNamed(QQuickItem *item, const QString &name, QList<QQuickItem *> *out)
{
    if (!item->isVisible())
        return;
    if (item->objectName() == name)
        *out << item;
    const QList<QQuickItem *> children = item->childItems();
    for (QQuickItem *c : children)
        collectNamed(c, name, out);
}

// ---- the dial and the covers (huboffload.h) ----

const int kDialSlots = 60;
// the numeral slots with cells of their own per atlas: with the 60 shared cells (60 + 12 x 16 = 252), and in each
// further atlas (1 + 12 x 21 = 253); an atlas has at most 256 cells
const int kOwnFirst = 16;
const int kOwnMore = 21;

// A row of A8 cells that are pictures, not digits: the dial's numerals (cell v = value v, blank
// unless a multiple of 5, then 12 more for each slot a cover reaches) and its long ticks (cell j =
// the tick of slot j, then a blank one). ch rows of cw * n bytes, in the panel's orientation.
struct Cells {
    int cw = 0, ch = 0, n = 0;
    QByteArray strip;
    uint32_t rgba = 0;
    int typeface = -1;
    // a tick atlas: its cells leave out what the background shows of their colour (fitDial)
    bool cutUnder = false;
};

// One sprite of them: a slot at a fixed panel pixel whose glyph is an expression of the hub's
// minute, showing one of the cells lo..hi (or a blank one)
struct CellSprite {
    int cells;
    QPoint at;
    QString expr;
    int slot = -1;
    int lo = 0, hi = 0;
    bool onBlack = false;       // a numeral: the background must be black under it
    int base = -1;              // a numeral slot's own cells: the cells group of the shared ones (value 5 v)
};

int cellsBytes(const Cells &c)
{
    return ((c.cw + 15) & ~15) * c.n * c.ch;
}

uint32_t tint(const QColor &c, qreal opacity)
{
    const qreal o = opacity * c.alphaF();
    return (uint32_t(qRound(c.red() * o)) << 24) | (uint32_t(qRound(c.green() * o)) << 16) |
           (uint32_t(qRound(c.blue() * o)) << 8) | 0xff;
}

uchar *cellPixel(Cells *c, int cell, int x, int y)
{
    return reinterpret_cast<uchar *>(c->strip.data()) + y * c->cw * c->n + cell * c->cw + x;
}

uchar cellAt(const Cells &c, int cell, int x, int y)
{
    return uchar(c.strip.constData()[y * c.cw * c.n + cell * c.cw + x]);
}

// whether every pixel of the cells lo..hi is 0
bool cellsEmpty(const Cells &c, int lo, int hi)
{
    for (int i = lo; i <= hi; i++)
        for (int y = 0; y < c.ch; y++)
            for (int x = 0; x < c.cw; x++)
                if (cellAt(c, i, x, y))
                    return false;
    return true;
}

// A QML function of the dial (eosHubSlotOrigin, eosHubTick) for slot j; a JS object comes back as
// a map, Qt.point as a point
QVariant callDial(QQuickItem *dial, const char *fn, int j)
{
    QVariant r;
    if (!QMetaObject::invokeMethod(dial, fn, Q_RETURN_ARG(QVariant, r), Q_ARG(QVariant, QVariant(j))))
        return QVariant();
    if (r.canConvert<QJSValue>())
        r = r.value<QJSValue>().toVariant();
    return r;
}

// pictures drawn in panel coordinates: one cell per entry, each at its own whole-pixel origin,
// all the size of the largest
struct Picture {
    QRectF bounds;              // panel px it covers
    std::function<void(QPainter *, const QPointF &origin)> paint;
};

void renderPictures(const QList<Picture> &pics, bool blank, Cells *c, QList<QPoint> *origins)
{
    int cw = 1, ch = 1;
    origins->clear();
    for (const Picture &p : pics) {
        const QRect r = p.bounds.toAlignedRect();
        *origins << r.topLeft();
        cw = qMax(cw, r.width());
        ch = qMax(ch, r.height());
    }
    c->cw = cw;
    c->ch = ch;
    c->n = pics.size() + (blank ? 1 : 0);
    c->strip = QByteArray(cw * c->n * ch, 0);
    for (int i = 0; i < pics.size(); i++) {
        QImage img(cw, ch, QImage::Format_Grayscale8);
        img.fill(0);
        QPainter p(&img);
        p.setRenderHint(QPainter::Antialiasing);
        pics[i].paint(&p, QPointF((*origins)[i]));
        p.end();
        for (int y = 0; y < ch; y++)
            memcpy(c->strip.data() + y * cw * c->n + i * cw, img.constScanLine(y), cw);
    }
}

// What of the dial the face's covers leave to be seen, per panel pixel: 255 all of it, 0 none
// (off the panel too). The covers in the face's order, each a fill or a border, as the AP draws them.
struct Keep {
    QImage cov = QImage(EL_FB_W, EL_FB_H, QImage::Format_Grayscale8);
    QImage near;                // cov grown by a pixel: where the scene graph's edge may reach
    Keep() { cov.fill(0); }
    int at(int x, int y) const
    {
        if (x < 0 || y < 0 || x >= cov.width() || y >= cov.height())
            return 0;
        return 255 - cov.constScanLine(y)[x];
    }
    bool reaches(int x, int y) const
    {
        return x < 0 || y < 0 || x >= near.width() || y >= near.height() || near.constScanLine(y)[x] > 0;
    }
    void grow()
    {
        near = cov.copy();
        for (int y = 0; y < cov.height(); y++)
            for (int x = 0; x < cov.width(); x++) {
                int m = 0;
                for (int dy = -1; dy <= 1; dy++)
                    for (int dx = -1; dx <= 1; dx++)
                        if (y + dy >= 0 && y + dy < cov.height() && x + dx >= 0 && x + dx < cov.width())
                            m = qMax(m, int(cov.constScanLine(y + dy)[x + dx]));
                near.scanLine(y)[x] = uchar(m);
            }
    }
};

/*
 * The inner dial of a face (Concentric): an item named eosHubDial with
 *   eosHubMinute           the whole minute it shows now (the always-on face)
 *   eosHubSlotOrigin(j)    the top-left (the dial's px) of a numeral Text at slot j, j * 6 degrees
 *                          counter-clockwise from 3 o'clock, at a whole minute
 *   eosHubTick(j)          {x1, y1, x2, y2}: the long tick of slot j (the dial's px), eosHubTickWidth
 *                          wide in eosHubTickColor
 * and in it the 12 numeral Texts "00" ... "55" named eosHubDialNumeral and the long ticks named
 * eosHubDialTick (none: the dial has no ticks). Slot j shows value (minute + j) % 60 when it is a
 * multiple of 5 (and its long tick then): the hub picks the glyph from its minute, so the dial
 * turns with no AP wake.
 * Everything else is the background, drawn once by the AP: what does not turn (the short ticks,
 * which stand still always-on) and what the face draws over the dial, the Rectangles named
 * eosHubCover (a fill or a border: the black disk, the circle) and the shades named eosHubShade (a
 * radial ramp to black over half a disc: Half Dial's vignette), which cut the cells as a cover of
 * partial alpha does. The hub never draws a sprite over
 * anything but black (2026-11-24 review: tinted cells over black are what the frame read-back on
 * the watch checked, aod91 REPORT-m1 T2, Z1, Z2; how the hub blends over colour is not known):
 *  - the covers' part is cut out of the cells: a numeral slot that a cover reaches has 12 cells of
 *    its own (value v at ((({1} + j) % 60) / 5), the integer division of the stock digit
 *    expressions), a slot the covers hide wholly has no sprite, a long tick's cell is cut too;
 *  - a long tick's cell leaves out what the background has of it already (the short tick under
 *    it, fitDial), so drawn over the background or added to it, the result is the same;
 *  - under a numeral slot the background must be black where a numeral can be (else no layout).
 */
bool buildDial(QQuickItem *face, const QDateTime &shown, bool turned, QList<Cells> *cells,
               QList<CellSprite> *out, QList<QQuickItem *> *hide, QImage *coverOut, QString *why)
{
    QQuickItem *dial = face->findChild<QQuickItem *>(QStringLiteral("eosHubDial"));
    if (!dial || !dial->isVisible())
        return true;
    const int minute = shown.time().minute();
    if (dial->property("eosHubMinute").toInt() != minute) {
        *why = QString("the dial shows minute %1, not %2").arg(dial->property("eosHubMinute").toInt()).arg(minute);
        return false;
    }

    // the covers, in the face's order: what of the dial they leave (they stay in the background)
    Keep keep;
    QList<QQuickItem *> covers;
    collectNamed(face, QStringLiteral("eosHubCover"), &covers);
    {
        QPainter p(&keep.cov);
        p.setRenderHint(QPainter::Antialiasing);
        for (QQuickItem *cv : covers) {
            if (!cv->inherits("QQuickRectangle")) {
                *why = "a cover is not a Rectangle";
                return false;
            }
            const QPointF o0 = cv->mapToScene(QPointF(0, 0));
            if (EosHub::sceneTurn(cv->mapToScene(QPointF(1, 1)) - o0) == 0) {
                *why = "a cover is rotated or scaled";
                return false;
            }
            const QRectF r = cv->mapRectToScene(QRectF(0, 0, cv->width(), cv->height()));
            const QColor fill = cv->property("color").value<QColor>();
            QObject *border = cv->property("border").value<QObject *>();
            const qreal bw = border ? border->property("width").toReal() : 0;
            const QColor bc = border ? border->property("color").value<QColor>() : QColor();
            const bool filled = fill.alpha() > 0, stroked = bw > 0 && bc.alpha() > 0;
            if (filled == stroked) {
                *why = "a cover has to be a fill or a border";
                return false;
            }
            const qreal radius = qMin(cv->property("radius").toReal(), qMin(r.width(), r.height()) / 2);
            p.setOpacity(effectiveOpacity(cv) * (filled ? fill.alphaF() : bc.alphaF()));
            if (filled) {
                p.setPen(Qt::NoPen);
                p.setBrush(Qt::white);
                p.drawRoundedRect(r, radius, radius);
            } else {
                // a Rectangle's border is inside its bounds
                p.setPen(QPen(Qt::white, bw));
                p.setBrush(Qt::NoBrush);
                p.drawRoundedRect(r.adjusted(bw / 2, bw / 2, -bw / 2, -bw / 2), radius - bw / 2, radius - bw / 2);
            }
        }
    }
    // the shades (Concentric's Half Dial vignette, R5 A-06): black of a radial ramp over one half of a disc,
    // drawn over the dial, so they leave (1 - alpha) of it to be seen: a cover of partial alpha. An item named
    // eosHubShade gives eosHubShadeCenter (its px), eosHubShadeRadius, eosHubShadeFrom (the fraction of the
    // radius the black starts at) and eosHubShadeSide (a vector from the centre into the darkened half)
    QList<QQuickItem *> shades;
    collectNamed(face, QStringLiteral("eosHubShade"), &shades);
    for (QQuickItem *sh : shades) {
        const QPointF local = sh->property("eosHubShadeCenter").toPointF();
        const QPointF c = sh->mapToScene(local);
        const QPointF side = sh->mapToScene(local + sh->property("eosHubShadeSide").toPointF()) - c;
        const qreal r = sh->property("eosHubShadeRadius").toReal();
        const qreal from = sh->property("eosHubShadeFrom").toReal();
        if (!(r > 0) || !(from >= 0 && from < 1) || side.isNull()) {
            *why = "a shade has no geometry";
            return false;
        }
        QRadialGradient g(c, r);
        g.setColorAt(0, QColor(255, 255, 255, 0));
        g.setColorAt(from, QColor(255, 255, 255, 0));
        g.setColorAt(1, QColor(255, 255, 255, 255));
        QPainter p(&keep.cov);
        p.setRenderHint(QPainter::Antialiasing);
        p.setOpacity(effectiveOpacity(sh));
        p.setPen(Qt::NoPen);
        p.setBrush(g);
        // the half centred on `side` (QPainter's angles: counter-clockwise from 3 o'clock, 1/16 degree)
        const qreal deg = std::atan2(-side.y(), side.x()) * 180 / M_PI;
        p.drawPie(QRectF(c.x() - r, c.y() - r, 2 * r, 2 * r), int(std::lround((deg - 90) * 16)), 180 * 16);
    }
    keep.grow();

    // the numerals: one atlas of 60 cells (value v; blank unless a multiple of 5), one sprite per slot
    QList<QQuickItem *> numerals;
    collectNamed(dial, QStringLiteral("eosHubDialNumeral"), &numerals);
    if (numerals.size() != kDialSlots / 5) {
        *why = QString("the dial has %1 numerals, not 12").arg(numerals.size());
        return false;
    }
    const QFont font = numerals[0]->property("font").value<QFont>();
    const QColor color = numerals[0]->property("color").value<QColor>();
    const qreal opacity = effectiveOpacity(numerals[0]);
    const qreal padL = numerals[0]->property("leftPadding").toReal();
    const qreal padT = numerals[0]->property("topPadding").toReal();
    for (QQuickItem *n : numerals) {
        bool t = false;
        if (!usable(n, why, &t))
            return false;
        const int v = n->property("text").toString().toInt();
        if (t != turned || n->property("font").value<QFont>() != font ||
            n->property("color").value<QColor>() != color || effectiveOpacity(n) != opacity ||
            n->property("text").toString() != QStringLiteral("%1").arg(v, 2, 10, QLatin1Char('0')) || v % 5) {
            *why = "the dial's numerals differ (font, colour, text or turn)";
            return false;
        }
        // where the AP has it is where the hub's slot puts it (the layout holds for every minute)
        const int slot = ((v - minute) % kDialSlots + kDialSlots) % kDialSlots;
        const QPointF o = callDial(dial, "eosHubSlotOrigin", slot).toPointF();
        const QPointF d = dial->mapToScene(o) - n->mapToScene(QPointF(0, 0));
        if (std::fabs(d.x()) > 1e-3 || std::fabs(d.y()) > 1e-3) {
            *why = QString("dial numeral %1 is not at its slot %2").arg(v).arg(slot);
            return false;
        }
    }
    Line line;
    if (!layoutLine(font, QStringLiteral("00"), &line)) {
        *why = "dial numerals: no text layout";
        return false;
    }
    const qreal penX = padL + line.pen[0];
    if (!whole(penX)) {
        *why = "dial numerals: the pen is not on a whole pixel";
        return false;
    }
    // the cells: each string drawn as the scene graph draws the Text (QPainter's raster engine
    // places the second digit at the same fractional pen), cropped to the ink of all 12
    const QFontMetricsF fm(font);
    const int pad = int(std::ceil(fm.height())) + 2;
    const int w = int(std::ceil(2 * fm.maxWidth())) + 2 * pad, h = int(std::ceil(fm.height())) + 2 * pad;
    const int ox = pad, oy = pad + int(std::lround(line.ascent));
    QList<QImage> imgs;
    QRect ink;
    for (int v = 0; v < kDialSlots; v += 5) {
        QImage img(w, h, QImage::Format_Grayscale8);
        img.fill(0);
        QPainter p(&img);
        p.setRenderHint(QPainter::TextAntialiasing);
        p.setFont(font);
        p.setPen(Qt::white);
        p.drawText(QPointF(ox, oy), QStringLiteral("%1").arg(v, 2, 10, QLatin1Char('0')));
        p.end();
        for (int y = 0; y < h; y++) {
            const uchar *s = img.constScanLine(y);
            for (int x = 0; x < w; x++)
                if (s[x])
                    ink |= QRect(x, y, 1, 1);
        }
        imgs << img;
    }
    if (ink.isEmpty() || ink.left() == 0 || ink.top() == 0 || ink.right() == w - 1 || ink.bottom() == h - 1) {
        *why = "dial numerals: no glyphs";
        return false;
    }
    Cells base;
    base.cw = ink.width();
    base.ch = ink.height();
    base.n = kDialSlots;
    base.strip = QByteArray(base.cw * base.n * base.ch, 0);
    for (int i = 0; i < imgs.size(); i++)
        for (int y = 0; y < base.ch; y++)
            memcpy(base.strip.data() + y * base.cw * base.n + (i * 5) * base.cw,
                   imgs[i].constScanLine(ink.top() + y) + ink.left(), base.cw);
    if (turned)
        EosHub::turnCells180(&base.strip, base.cw, base.n, base.ch);
    const QRect cellInk = ink.translated(-ox, -oy);
    // where any numeral can have ink in a cell
    QByteArray any(base.cw * base.ch, 0);
    for (int v = 0; v < kDialSlots; v += 5)
        for (int y = 0; y < base.ch; y++)
            for (int x = 0; x < base.cw; x++)
                any[y * base.cw + x] = char(qMax(uchar(any[y * base.cw + x]), cellAt(base, v, x, y)));

    // slot by slot: the shared cells where no cover reaches, cells of its own where one does, no
    // sprite where the covers hide every numeral
    struct Own { int slot; QPoint at; };
    QList<Own> own;
    QList<CellSprite> numeralSprites;
    int hidden = 0;
    const int numeralCells = cells->size();
    for (int j = 0; j < kDialSlots; j++) {
        const QPointF o = dial->mapToScene(callDial(dial, "eosHubSlotOrigin", j).toPointF());
        const QPoint origin = glyphOrigin(o, penX, padT + line.ascent, turned);
        const QPoint at = EosHub::spriteTopLeft(origin, cellInk, turned);
        bool reached = false, seen = false;
        for (int y = 0; y < base.ch; y++)
            for (int x = 0; x < base.cw; x++) {
                const int a = uchar(any[y * base.cw + x]);
                if (!a)
                    continue;
                const int k = keep.at(at.x() + x, at.y() + y);
                reached |= keep.reaches(at.x() + x, at.y() + y);
                seen |= (a * k + 127) / 255 > 0;
            }
        if (!seen) {
            hidden++;
            continue;
        }
        if (!reached) {
            numeralSprites << CellSprite{ numeralCells, at, QString("(({1} + %1) % %2)").arg(j).arg(kDialSlots),
                                          j, 0, kDialSlots - 1, true };
            continue;
        }
        // an atlas has at most 256 cells (eoslayout.c el_glyph_atlas_a8): the first kOwnFirst slots of their own
        // go with the shared cells (value v at b + v / 5, cell 1 blank: there is no numeral 1), the rest in
        // atlases of kOwnMore slots each (cell 0 blank, the slot's 12 from 1 + 12 k) (R5 A-06: Half Dial's
        // vignette gives many slots cells of their own)
        const int i = own.size();
        own << Own{ j, at };
        const bool first = i < kOwnFirst;
        const int group = first ? 0 : 1 + (i - kOwnFirst) / kOwnMore;
        const int b = first ? kDialSlots + 12 * i : 1 + 12 * ((i - kOwnFirst) % kOwnMore);
        numeralSprites << CellSprite{ numeralCells + group, at,
                                      QString("((({1} + %1) % 5) == 0 ? ((({1} + %1) % %2) / 5 + %3) : %4)")
                                          .arg(j).arg(kDialSlots).arg(b).arg(first ? 1 : 0),
                                      j, b, b + 11, true, numeralCells };
    }
    auto ownCells = [&](int i, Cells *into, int at) {
        for (int v = 0; v < 12; v++)
            for (int y = 0; y < into->ch; y++)
                for (int x = 0; x < into->cw; x++) {
                    const int k = keep.at(own[i].at.x() + x, own[i].at.y() + y);
                    *cellPixel(into, at + v, x, y) = uchar((cellAt(base, v * 5, x, y) * k + 127) / 255);
                }
    };
    Cells nc;
    nc.cw = base.cw;
    nc.ch = base.ch;
    nc.n = kDialSlots + 12 * qMin(int(own.size()), kOwnFirst);
    nc.strip = QByteArray(nc.cw * nc.n * nc.ch, 0);
    nc.rgba = tint(color, opacity);
    for (int y = 0; y < nc.ch; y++)
        memcpy(nc.strip.data() + y * nc.cw * nc.n, base.strip.constData() + y * base.cw * base.n, base.cw * base.n);
    for (int i = 0; i < own.size() && i < kOwnFirst; i++)
        ownCells(i, &nc, kDialSlots + 12 * i);
    *cells << nc;
    for (int g = 0; kOwnFirst + g * kOwnMore < own.size(); g++) {
        const int from = kOwnFirst + g * kOwnMore, count = qMin(kOwnMore, int(own.size()) - from);
        Cells more;
        more.cw = base.cw;
        more.ch = base.ch;
        more.n = 1 + 12 * count;
        more.strip = QByteArray(more.cw * more.n * more.ch, 0);
        more.rgba = nc.rgba;
        for (int i = 0; i < count; i++)
            ownCells(from + i, &more, 1 + 12 * i);
        *cells << more;
    }

    // the long ticks: cell j the tick of slot j as it lies on the panel, less the covers, cell 60 blank
    QList<QQuickItem *> ticks;
    collectNamed(dial, QStringLiteral("eosHubDialTick"), &ticks);
    QList<CellSprite> tickSprites;
    if (!ticks.isEmpty()) {
        if (ticks.size() != kDialSlots / 5) {
            *why = QString("the dial has %1 long ticks, not 12").arg(ticks.size());
            return false;
        }
        const qreal tw = dial->property("eosHubTickWidth").toReal();
        const QColor tc = dial->property("eosHubTickColor").value<QColor>();
        QList<Picture> pics;
        for (int j = 0; j < kDialSlots; j++) {
            const QVariantMap m = callDial(dial, "eosHubTick", j).toMap();
            if (!m.contains(QStringLiteral("x1")) || tw <= 0) {
                *why = "the dial's ticks have no geometry";
                return false;
            }
            const QPointF a = dial->mapToScene(QPointF(m.value("x1").toReal(), m.value("y1").toReal()));
            const QPointF b = dial->mapToScene(QPointF(m.value("x2").toReal(), m.value("y2").toReal()));
            // a flat-capped bar: half its width out from the centre line, none past its ends (the 14 px
            // ticks fit 16 px cells); less a hair of rounding noise
            const QPointF dir = (b - a) / std::hypot(b.x() - a.x(), b.y() - a.y());
            const qreal ex = tw / 2 * std::fabs(dir.y()) - 1e-4, ey = tw / 2 * std::fabs(dir.x()) - 1e-4;
            const QRectF r = QRectF(a, b).normalized().adjusted(-ex, -ey, ex, ey);
            pics << Picture{ r, [a, b, tw](QPainter *p, const QPointF &origin) {
                p->setPen(QPen(Qt::white, tw, Qt::SolidLine, Qt::FlatCap));
                p->drawLine(a - origin, b - origin);
            } };
        }
        Cells tcs;
        QList<QPoint> at;
        renderPictures(pics, true, &tcs, &at);
        tcs.rgba = tint(tc, effectiveOpacity(ticks[0]));
        tcs.cutUnder = true;
        for (int j = 0; j < kDialSlots; j++)
            for (int y = 0; y < tcs.ch; y++)
                for (int x = 0; x < tcs.cw; x++) {
                    uchar *px = cellPixel(&tcs, j, x, y);
                    *px = uchar((*px * keep.at(at[j].x() + x, at[j].y() + y) + 127) / 255);
                }
        const int ti = cells->size();
        *cells << tcs;
        for (int j = 0; j < kDialSlots; j++)
            tickSprites << CellSprite{ ti, at[j], QString("((({1} + %1) % 5) == 0 ? %1 : %2)").arg(j).arg(kDialSlots),
                                       j, j, j, false };
    }
    // drawn as the face has them: the ticks, then the numerals
    *out << tickSprites << numeralSprites;
    *hide << numerals << ticks;
    *coverOut = keep.near;
    qDebug().noquote() << QString("hub offload: dial of %1 numeral slots (%2 with cells of their own, %3 under "
                                  "the covers), %4 covers in the background")
                          .arg(numeralSprites.size()).arg(own.size()).arg(hidden).arg(covers.size());
    return true;
}

// After the background is grabbed: a tick atlas's cells leave out what the background shows of
// their colour at their slots (the short tick under a long one), so the hub adds only what the
// background lacks; a numeral slot's own cells are cut by what the background shows of a cover
// too (a light cover's edge as the scene graph drew it: the AP drew the cover over the numeral);
// a numeral slot must lie on black where a numeral can be (but next to the covers, where its cells
// are cut by them); a slot whose cells are empty then has no sprite. False: the dial would need the
// hub to draw over colour.
bool fitDial(const QImage &bg, const QImage &cover, QList<Cells> *cells, QList<CellSprite> *sprites, QString *why)
{
    auto covered = [&cover](int x, int y) -> bool {
        return x >= 0 && y >= 0 && x < cover.width() && y < cover.height() && cover.constScanLine(y)[x] > 0;
    };
    auto bgAt = [&bg](int x, int y) -> int {
        if (x < 0 || y < 0 || x >= bg.width() || y >= bg.height())
            return 0;
        const uchar *p = bg.constScanLine(y) + 4 * x;
        return qMax(p[0], qMax(p[1], p[2]));
    };
    for (CellSprite &s : *sprites) {
        Cells &c = (*cells)[s.cells];
        if (c.cutUnder) {
            const int top = qMax(int(c.rgba >> 24), qMax(int((c.rgba >> 16) & 0xff), int((c.rgba >> 8) & 0xff)));
            for (int i = s.lo; i <= s.hi; i++)
                for (int y = 0; y < c.ch; y++)
                    for (int x = 0; x < c.cw; x++) {
                        uchar *px = cellPixel(&c, i, x, y);
                        const int under = top > 0 ? qMin(255, (bgAt(s.at.x() + x, s.at.y() + y) * 255 + top / 2) / top) : 255;
                        *px = uchar(qMax(0, int(*px) - under));
                    }
        }
        if (s.onBlack && s.base >= 0) {
            // value v's own cell, from the shared one of value 5 v
            const Cells &shared = (*cells)[s.base];
            for (int i = s.lo; i <= s.hi; i++)
                for (int y = 0; y < c.ch; y++)
                    for (int x = 0; x < c.cw; x++) {
                        uchar *px = cellPixel(&c, i, x, y);
                        const int lit = (cellAt(shared, (i - s.lo) * 5, x, y) * (255 - bgAt(s.at.x() + x, s.at.y() + y)) + 127) / 255;
                        *px = uchar(qMin(int(*px), lit));
                    }
        }
        if (s.onBlack) {
            for (int y = 0; y < c.ch; y++)
                for (int x = 0; x < c.cw; x++) {
                    bool inked = false;
                    for (int i = s.lo; i <= s.hi && !inked; i++)
                        inked = cellAt(c, i, x, y) > 0;
                    if (inked && bgAt(s.at.x() + x, s.at.y() + y) > 24 && !covered(s.at.x() + x, s.at.y() + y)) {
                        *why = QString("the background under dial slot %1 is not black at %2,%3")
                               .arg(s.slot).arg(s.at.x() + x).arg(s.at.y() + y);
                        return false;
                    }
                }
        }
    }
    for (int i = sprites->size() - 1; i >= 0; i--)
        if (cellsEmpty((*cells)[(*sprites)[i].cells], (*sprites)[i].lo, (*sprites)[i].hi))
            sprites->removeAt(i);
    return true;
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
    bool turnedOf[2] = { false, false };
    for (int i = 0; i < 2; i++)
        if (!usable(items[i], why, &turnedOf[i]))
            return false;
    if (turnedOf[0] != turnedOf[1]) {
        *why = "the hour and the minute are turned differently";
        return false;
    }
    // the wrist flip: the picture is turned 180 degrees (see eoshubflip.h)
    const bool turned = turnedOf[0];

    // the texts must be what the hub will draw for this time, in the digits
    // the face writes: ASCII or the locale's (locale-formats-10: one rule for
    // the face, the time texts and the hub, never the AP's drawing for a locale)
    const int h24 = shown.time().hour(), h12 = (h24 + 11) % 12 + 1;
    // a face whose 12 h hour keeps its leading zero ("06", Concentric) says so on the hour item
    const bool zeroPad = use12h && hour->property("eosHubZeroPad").toBool();
    const QString hourText = use12h && !zeroPad ? QString::number(h12)
                                                : QStringLiteral("%1").arg(use12h ? h12 : h24, 2, 10, QLatin1Char('0'));
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
        } else if (zeroPad) {
            // 01 .. 12: always two digits where the face has them
            variants << Variant{ 2, here, { { EL_EXPR_HOUR12_D1, 0, 1, {} },
                                            { EL_EXPR_HOUR12_D2, 0, 9, {} } } };
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
                    a.turned = turned;
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
                sprites << Sprite{ ai, glyphOrigin(v.pos, penX, padT + l.ascent, turned), s.digit, s.lo,
                                   s.hi, s.empty, rgba };
            }
        }
    }
    // a face's turning dial (Concentric): sprites on fixed slots, under the time; what covers it stays
    // in the background and is cut out of the cells
    QList<Cells> dialCells;
    QList<CellSprite> dialSprites;
    QList<QQuickItem *> dialItems;
    QImage dialCover;
    if (!m_overlay && !buildDial(face, shown, turned, &dialCells, &dialSprites, &dialItems, &dialCover, why))
        return false;

    int bytes = 0;
    for (int i = 0; i < atlases.size(); i++) {
        if (!renderAtlas(&atlases[i], ascents[i], steps[i])) {
            *why = "no glyphs";
            return false;
        }
        bytes += atlasBytes(atlases[i]);
    }
    for (const Cells &c : dialCells)
        bytes += cellsBytes(c);
    if (bytes > kAtlasBudget) {
        *why = QString("digit atlases of %1 KB, more than %2 KB").arg(bytes / 1024)
               .arg(kAtlasBudget / 1024);
        return false;
    }

    // the background: the ambient screen with the time items hidden (and the dial's numerals and
    // long ticks: the hub draws them)
    hour->setVisible(false);
    minute->setVisible(false);
    for (QQuickItem *i : dialItems)
        i->setVisible(false);
    QImage bg = win->grabWindow();
    hour->setVisible(true);
    minute->setVisible(true);
    for (QQuickItem *i : dialItems)
        i->setVisible(true);
    if (bg.isNull()) {
        *why = "grab failed";
        return false;
    }
    bg = bg.convertToFormat(QImage::Format_RGBA8888).scaled(EL_FB_W, EL_FB_H);
    if (!dialSprites.isEmpty() && !fitDial(bg, dialCover, &dialCells, &dialSprites, why))
        return false;
    // the hub draws the digits over it: it must be black where they go, as
    // the AP's own digits cover it (the outline style's fill is black). Only
    // where a digit can be: the rest of a slot's cell rectangle shows the
    // background on the AP as well (2026-11-17: the steps line under the
    // minutes reached the cell's bottom row, under no digit). An overlay
    // (Ambient Lite) has the blurred application there on purpose: the
    // glyphs blend over it as the AP's did.
    if (!m_overlay) {
        QList<QByteArray> masks;
        for (const Atlas &a : atlases)
            masks << digitMask(a);
        for (const Sprite &s : sprites) {
            const Atlas &a = atlases[s.atlas];
            const QByteArray &mask = masks[s.atlas];
            const QRect cell(EosHub::spriteTopLeft(s.origin, a.ink, turned), a.ink.size());
            const QRect r = cell & bg.rect();
            int bad = 0;
            QRect where;
            for (int y = r.top(); y <= r.bottom(); y++) {
                const uchar *p = bg.constScanLine(y) + 4 * r.left();
                const char *m = mask.constData() + (y - cell.top()) * cell.width() + (r.left() - cell.left());
                for (int x = 0; x < r.width(); x++, p += 4) {
                    if (m[x] && qMax(p[0], qMax(p[1], p[2])) > 24) {
                        bad++;
                        where |= QRect(r.left() + x, y, 1, 1);
                    }
                }
            }
            if (bad) {
                *why = QString("the background under the digits is not black at %1,%2 (%3 pixels in %4,%5 %6x%7, cell %8,%9 %10x%11)")
                       .arg(where.left()).arg(where.top()).arg(bad).arg(where.left()).arg(where.top())
                       .arg(where.width()).arg(where.height()).arg(cell.left()).arg(cell.top())
                       .arg(cell.width()).arg(cell.height());
                // the grab, for a look (the runtime directory: RAM)
                bg.save(QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation) +
                        "/eos-hub-refused.png");
                return false;
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
    for (Cells &c : dialCells) {
        c.typeface = el_glyph_atlas_a8(L, c.n, c.cw, c.ch, reinterpret_cast<const uint8_t *>(c.strip.constData()),
                                       c.cw * c.n, nullptr);
        if (c.typeface < 0) {
            *why = QString("dial cells: %1").arg(el_error(L));
            el_free(L);
            return false;
        }
    }
    // the dial first, as the face draws it; the time over all
    QStringList where;
    for (int i = 0; i < dialCells.size(); i++)
        where << QString("%1x%2x%3:").arg(dialCells[i].cw).arg(dialCells[i].ch).arg(dialCells[i].n);
    for (const CellSprite &s : dialSprites) {
        const Cells &c = dialCells[s.cells];
        const QByteArray e = s.expr.toLatin1();
        const char *expr = e.constData();
        where[s.cells] += QString(" %1:%2,%3").arg(s.slot).arg(s.at.x()).arg(s.at.y());
        if (el_sprite_text(L, c.typeface, s.at.x(), s.at.y(), c.rgba, 1, &expr, nullptr)) {
            *why = QString("dial: %1").arg(el_error(L));
            el_free(L);
            return false;
        }
    }
    // (the host test of the layouts checks these lines: cells w x h x n, then each sprite's slot and
    // top-left)
    for (int i = 0; i < where.size(); i++)
        qDebug().noquote() << "hub offload: dial cells" << i << where[i];
    for (const Sprite &s : sprites) {
        const Atlas &a = atlases[s.atlas];
        const QByteArray e = cellExpr(s, a).toLatin1();
        const char *expr = e.constData();
        const QPoint at = EosHub::spriteTopLeft(s.origin, a.ink, turned);
        // (the host test of the layouts checks these lines)
        qDebug() << "hub offload: sprite at" << at << "phase" << a.phase << "glyph origin"
                 << s.origin << "cells" << a.lo << a.hi << a.blank << expr;
        if (turned)
            qDebug() << "hub offload: sprite size" << a.ink.size() << "turned 180 (wrist flip)";
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
                         .arg(count).arg(sprites.size() + dialSprites.size()).arg(bytes / 1024)
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
    // the picture's turn is part of what the layout depends on (a change of the wrist and crown
    // setting builds the turned one once, not at every minute)
    const int turn = EosHub::sceneTurn(hour->mapToScene(QPointF(1, 1)) - hp);
    // what the layout depends on: the face, where the digits are (the
    // burn-in shift moves them) and how they look; the background holds
    // until m_until
    const QString key = QStringLiteral("%1|%2|%3,%4|%5,%6|%7|%8|%9")
        .arg(faceSource).arg(use12h)
        .arg(hp.x()).arg(hp.y()).arg(mp.x()).arg(mp.y())
        .arg(effectiveOpacity(hour))
        .arg(hour->property("style").toInt())
        .arg(turn);
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
