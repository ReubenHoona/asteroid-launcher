/*
 * SPDX-FileCopyrightText: 2026 Timo Könnecke <github.com/moWerk>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include "watchfacereloader.h"

#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickItem>
#include <QColor>
#include <QDir>
#include <QFile>
#include <QRegularExpression>
#include <QStandardPaths>

WatchfaceReloader::WatchfaceReloader(QQmlEngine *engine, QObject *parent)
    : QObject(parent)
    , m_engine(engine)
{
    // Same location the settings watchface store installs into.
    m_dir = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
            + QStringLiteral("/asteroid-launcher/watchfaces");
    QDir().mkpath(m_dir);
    m_watcher.addPath(m_dir);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged,
            this, &WatchfaceReloader::onDirectoryChanged);
}

bool WatchfaceReloader::usesSeconds(const QUrl &face)
{
    const QString path = face.isLocalFile() ? face.toLocalFile() : face.toString();
    auto it = m_usesSeconds.constFind(path);
    if (it != m_usesSeconds.constEnd())
        return it.value();
    bool seconds = true;
    QFile file(path);
    if (!path.isEmpty() && file.open(QIODevice::ReadOnly)) {
        static const QRegularExpression re(QStringLiteral("getSeconds|getMilliseconds|\"ss\"|:ss\"|'ss'"));
        seconds = re.match(QString::fromUtf8(file.readAll())).hasMatch();
    }
    m_usesSeconds.insert(path, seconds);
    return seconds;
}

// -1: no item named second*; 0: all hidden; 1: one is visible
static int secondsItems(QQuickItem *item)
{
    int found = -1;
    QQmlContext *ctx = qmlContext(item);
    const QString id = ctx ? ctx->nameForObject(item) : QString();
    if (id.startsWith(QLatin1String("second"), Qt::CaseInsensitive)) {
        if (item->isVisible() && item->opacity() > 0)
            return 1;
        found = 0;
    }
    const QList<QQuickItem *> children = item->childItems();
    for (QQuickItem *child : children) {
        const int r = secondsItems(child);
        if (r == 1)
            return 1;
        if (r == 0)
            found = 0;
    }
    return found;
}

static void setHidden(QQuickItem *item, bool hide)
{
    static const char KEY[] = "_eosShown";
    const QVariant kept = item->property(KEY);
    if (hide) {
        if (!kept.isValid())
            item->setProperty(KEY, item->property("visible"));   // as the face had it
        item->setVisible(false);
    } else if (kept.isValid()) {
        item->setVisible(kept.toBool());
        item->setProperty(KEY, QVariant());
    }
}

static void setOutline(QQuickItem *item, bool outline)
{
    static const char COLOR[] = "_eosColor";
    static const char STYLE[] = "_eosStyle";
    static const char STYLECOLOR[] = "_eosStyleColor";
    const bool kept = item->property(COLOR).isValid();
    if (outline) {
        if (!kept) {
            item->setProperty(COLOR, item->property("color"));
            item->setProperty(STYLE, item->property("style"));
            item->setProperty(STYLECOLOR, item->property("styleColor"));
        }
        // the letters' edge only, in grey: few lit pixels on the always-on
        // screen (QQuickText::Outline is 1)
        item->setProperty("style", 1);
        item->setProperty("styleColor", QColor(0x9e, 0x9e, 0x9e));
        item->setProperty("color", QColor(Qt::black));
    } else if (kept) {
        item->setProperty("color", item->property(COLOR));
        item->setProperty("style", item->property(STYLE));
        item->setProperty("styleColor", item->property(STYLECOLOR));
        item->setProperty(COLOR, QVariant());
        item->setProperty(STYLE, QVariant());
        item->setProperty(STYLECOLOR, QVariant());
    }
}

static void applyOptions(QQuickItem *item, bool showDate, bool showSeconds, bool ambient, bool outline)
{
    QQmlContext *ctx = qmlContext(item);
    const QString id = ctx ? ctx->nameForObject(item).toLower() : QString();
    if (!id.isEmpty()) {
        if (id.startsWith(QLatin1String("second")))
            setHidden(item, !showSeconds || ambient);
        else if (id.startsWith(QLatin1String("date")) || id.startsWith(QLatin1String("day"))
                 || id.startsWith(QLatin1String("month")) || id.startsWith(QLatin1String("week")))
            setHidden(item, !showDate);
    }
    if (item->inherits("QQuickText"))
        setOutline(item, ambient && outline);
    const QList<QQuickItem *> children = item->childItems();
    for (QQuickItem *child : children)
        applyOptions(child, showDate, showSeconds, ambient, outline);
}

void WatchfaceReloader::applyFaceOptions(QQuickItem *face, bool showDate, bool showSeconds,
                                         bool ambient, const QString &ambientStyle)
{
    if (face)
        applyOptions(face, showDate, showSeconds, ambient, ambientStyle == QLatin1String("outline"));
}

bool WatchfaceReloader::secondsShown(QQuickItem *item, const QUrl &face)
{
    if (!usesSeconds(face))
        return false;
    if (!item)
        return true;
    return secondsItems(item) != 0;
}

void WatchfaceReloader::onDirectoryChanged(const QString &)
{
    m_usesSeconds.clear();
    if (!m_engine)
        return;

    // Clearing the component cache forces the next QML load to re-read the
    // directory, so a just-installed watchface becomes loadable immediately.
    m_engine->clearComponentCache();
    emit reloadNeeded();

    // QFileSystemWatcher drops a path that momentarily disappears (some tools
    // replace directories atomically); re-add it so we keep watching.
    if (!m_watcher.directories().contains(m_dir) && QDir(m_dir).exists())
        m_watcher.addPath(m_dir);
}
