/***************************************************************************
**
** Copyright (C) 2013 Jolla Ltd.
** Contact: Aaron Kennedy <aaron.kennedy@jollamobile.com>
**
** This file is part of lipstick.
**
** This library is free software; you can redistribute it and/or
** modify it under the terms of the GNU Lesser General Public
** License version 2.1 as published by the Free Software Foundation
** and appearing in the file LICENSE.LGPL included in the packaging
** of this file.
**
****************************************************************************/

#include <QWaylandSeat>
#include <QDesktopServices>
#include <QClipboard>
#include <QSettings>
#include <QMimeData>
#include <QtGui/qpa/qplatformnativeinterface.h>
#include "homeapplication.h"
#include "lipstickcompositor.h"
#include <time.h>
#include "lipstickcompositorwindow.h"
#include "lipstickcompositoradaptor.h"
#include "lipsticksettings.h"
#include "asteroidgesturesextension.h"
#include "eosoffloadpolicy.h"
#include "appwatcher.h"
#include <signal.h>
#include <qpa/qwindowsysteminterface.h>
#include <private/qguiapplication_p.h>
#include <QtGui/qpa/qplatformintegration.h>
#include <QWaylandQuickShellSurfaceItem>

#include <mce/dbus-names.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/time.h>
#include <unistd.h>
#include <mce/mode-names.h>


#define MCE_DISPLAY_LPM_SET_SUPPORTED "set_lpm_supported"


LipstickCompositor *LipstickCompositor::m_instance = 0;

LipstickCompositor::LipstickCompositor()
    : m_totalWindowCount(0)
    , m_nextWindowId(1)
    , m_homeActive(true)
    , m_shaderEffect(0)
    , m_fullscreenSurface(0)
    , m_directRenderingActive(false)
    , m_topmostWindowId(0)
    , m_topmostWindowProcessId(0)
    , m_topmostWindowOrientation(Qt::PrimaryOrientation)
    , m_screenOrientation(Qt::PrimaryOrientation)
    , m_displayState(0)
    , m_retainedSelection(0)
    , m_currentDisplayState(QMceDisplay::DisplayOn)
    , m_updatesEnabled(true)
    , m_completed(false)
    , m_onUpdatesDisabledUnfocusedWindowId(0)
    , m_fakeRepaintTriggered(false)
{
    m_window = new QQuickWindow();
    m_window->setColor(Qt::black);

    m_output = new QWaylandQuickOutput(this, m_window);
    m_output->setSizeFollowsWindow(true);
    connect(this, &QWaylandCompositor::surfaceCreated, this, &LipstickCompositor::onSurfaceCreated);

    m_xdgShell = new QWaylandXdgShell(this);
    connect(m_xdgShell, &QWaylandXdgShell::toplevelCreated, this, &LipstickCompositor::onToplevelCreated);
    // eos: the pong of the ping sent after a touch (EosAnr)
    connect(m_xdgShell, &QWaylandXdgShell::pong, this, &LipstickCompositor::onAnrPong);
    m_anrTimer = new QTimer(this);
    m_anrTimer->setSingleShot(true);
    m_anrTimer->setInterval(int(EosAnr::TimeoutMs));
    connect(m_anrTimer, &QTimer::timeout, this, &LipstickCompositor::onAnrTimeout);

    m_wm = new QWaylandQtWindowManager(this);
    connect(m_wm, &QWaylandQtWindowManager::openUrl, this, &LipstickCompositor::openUrl);

    m_gesturesManager = new AsteroidGesturesManager(this);

    setRetainedSelectionEnabled(true);

    if (m_instance) qFatal("LipstickCompositor: Only one compositor instance per process is supported");
    m_instance = this;

    m_orientationLock = new MDConfItem("/lipstick/orientationLock", this);
    connect(m_orientationLock, SIGNAL(valueChanged()), SIGNAL(orientationLockChanged()));

    // Load legacy settings from the config file and delete it from there
    QSettings legacySettings("nemomobile", "lipstick");
    QString legacyOrientationKey("Compositor/orientationLock");
    if (legacySettings.contains(legacyOrientationKey)) {
        m_orientationLock->set(legacySettings.value(legacyOrientationKey));
        legacySettings.remove(legacyOrientationKey);
    }

    connect(m_window, SIGNAL(visibleChanged(bool)), this, SLOT(onVisibleChanged(bool)));
    QObject::connect(HomeApplication::instance(), SIGNAL(aboutToDestroy()), this, SLOT(homeApplicationAboutToDestroy()));

    emit HomeApplication::instance()->homeActiveChanged();

    QDesktopServices::setUrlHandler("http", this, "openUrl");
    QDesktopServices::setUrlHandler("https", this, "openUrl");
    QDesktopServices::setUrlHandler("mailto", this, "openUrl");

    connect(QGuiApplication::clipboard(), SIGNAL(dataChanged()), SLOT(clipboardDataChanged()));

    m_timedDbus = new Maemo::Timed::Interface();
    if( !m_timedDbus->isValid() )
    {
      qWarning() << "invalid dbus interface:" << m_timedDbus->lastError();
    }

    QTimer::singleShot(0, this, SLOT(initialize()));
}

LipstickCompositor::~LipstickCompositor()
{
    // eos: no application stays stopped
    m_freezer.thawAll();
    // ~QWindow can a call into onVisibleChanged and QWaylandCompositor after we
    // are destroyed, so disconnect it.
    disconnect(m_window, SIGNAL(visibleChanged(bool)), this, SLOT(onVisibleChanged(bool)));

    delete m_timedDbus;
    delete m_shaderEffect;
}

LipstickCompositor *LipstickCompositor::instance()
{
    return m_instance;
}

void LipstickCompositor::homeApplicationAboutToDestroy()
{
    m_window->hide();
    m_window->releaseResources();

    // When destroying LipstickCompositor ~QQuickWindow() is called after
    // ~QWaylandQuickCompositor(), so changes to the items in the window may end
    // up calling code such as LipstickCompositorWindow::handleTouchCancel(),
    // which will try to use the compositor, at that point not usable anymore.
    // So delete all the windows here.
    foreach (LipstickCompositorWindow *w, m_windows) {
        delete w;
    }

    m_instance = 0;
    delete this;
}

void LipstickCompositor::onVisibleChanged(bool visible)
{
    if (!visible) {
        m_output->sendFrameCallbacks();
    }
}

static LipstickCompositorWindow *surfaceWindow(QWaylandSurface *surface)
{
    return surface->views().isEmpty() ? 0 : static_cast<LipstickCompositorWindow *>(surface->views().first()->renderObject());
}

void LipstickCompositor::onToplevelCreated(QWaylandXdgToplevel * topLevel, QWaylandXdgSurface * shellSurface)
{
    QWaylandSurface *surface = shellSurface->surface();
    LipstickCompositorWindow *window = surfaceWindow(surface);
    if(window) {
        connect(topLevel, &QWaylandXdgToplevel::titleChanged, this, &LipstickCompositor::surfaceTitleChanged);
        connect(topLevel, &QWaylandXdgToplevel::setFullscreen, this, &LipstickCompositor::surfaceSetFullScreen);
    }
}

void LipstickCompositor::onSurfaceCreated(QWaylandSurface *surface)
{
    LipstickCompositorWindow *item = surfaceWindow(surface);
    if (!item)
        item = createView(surface);
    connect(surface, SIGNAL(hasContentChanged()), this, SLOT(onHasContentChanged()));
    connect(surface, SIGNAL(damaged(QRegion)), this, SLOT(surfaceDamaged(QRegion)));
    connect(surface, SIGNAL(redraw()), this, SLOT(windowSwapped()));
}

bool LipstickCompositor::openUrl(QWaylandClient *client, const QUrl &url)
{
    Q_UNUSED(client)
    Q_UNUSED(url)
    return false;
}

void LipstickCompositor::retainedSelectionReceived(QMimeData *mimeData)
{
    if (!m_retainedSelection)
        m_retainedSelection = new QMimeData;

    // Make a copy to allow QClipboard to take ownership of our data
    m_retainedSelection->clear();
    foreach (const QString &format, mimeData->formats())
        m_retainedSelection->setData(format, mimeData->data(format));

    QGuiApplication::clipboard()->setMimeData(m_retainedSelection.data());
}

int LipstickCompositor::windowCount() const
{
    return m_mappedSurfaces.count();
}

int LipstickCompositor::ghostWindowCount() const
{
    return m_totalWindowCount - windowCount();
}

bool LipstickCompositor::homeActive() const
{
    return m_homeActive;
}

void LipstickCompositor::setHomeActive(bool a)
{
    if (a == m_homeActive)
        return;

    m_homeActive = a;

    emit homeActiveChanged();
    emit HomeApplication::instance()->homeActiveChanged();
}

bool LipstickCompositor::debug() const
{
    static enum { Yes, No, Unknown } status = Unknown;
    if (status == Unknown) {
        QByteArray v = qgetenv("LIPSTICK_COMPOSITOR_DEBUG");
        bool value = !v.isEmpty() && v != "0" && v != "false";
        if (value) status = Yes;
        else status = No;
    }
    return status == Yes;
}

QObject *LipstickCompositor::windowForId(int id) const
{
    QObject *window = m_windows.value(id, NULL);
    return window;
}

void LipstickCompositor::closeClientForWindowId(int id)
{
    LipstickCompositorWindow *window = m_windows.value(id, 0);

    // eos: a stopped process cannot hear the quit
    if (window)
        m_freezer.thaw(window->processId());

    if (window && window->surface()) {
        QWaylandQtWindowManager *wmExtension = QWaylandQtWindowManager::findIn(this);
        if (wmExtension)
            wmExtension->sendQuitMessage(window->surface()->client());
        else
            window->surface()->client()->close();
    }   
}

bool LipstickCompositor::freezeClientForWindowId(int id, bool freeze)
{
    LipstickCompositorWindow *window = m_windows.value(id, 0);
    if (!window || window->processId() <= 1)
        return false;
    const qint64 pid = window->processId();
    // never the compositor itself (an in-process window)
    if (window->isInProcess())
        return false;
    return freeze ? m_freezer.freeze(pid) : m_freezer.thaw(pid);
}

bool LipstickCompositor::isClientFrozen(int id) const
{
    LipstickCompositorWindow *window = m_windows.value(id, 0);
    return window && m_freezer.isFrozen(window->processId());
}

qint64 LipstickCompositor::bootTimeMs() const
{
    struct timespec ts;
    if (clock_gettime(CLOCK_BOOTTIME, &ts) != 0)
        return 0;
    return qint64(ts.tv_sec) * 1000 + ts.tv_nsec / 1000000;
}

// eos (system-dialogs-misc-03): the app in front is pinged after a touch
void LipstickCompositor::noteTouchDelivered(LipstickCompositorWindow *window)
{
    if (!window || window->isInProcess() || !window->surface())
        return;
    // only the app in front, only with the display on
    if (m_currentDisplayState != QMceDisplay::DisplayOn || window->windowId() != m_topmostWindowId)
        return;
    if (!m_anr.touched(window->windowId(), bootTimeMs()))
        return;
    m_anrSerial = m_xdgShell->ping(window->surface()->client());
    m_anrTimer->start();
}

void LipstickCompositor::onAnrPong(uint serial)
{
    if (serial != m_anrSerial)
        return;
    m_anr.ponged();
    m_anrTimer->stop();
}

void LipstickCompositor::onAnrTimeout()
{
    if (!m_anr.expired(m_currentDisplayState == QMceDisplay::DisplayOn, m_topmostWindowId))
        return;
    LipstickCompositorWindow *window = m_windows.value(m_anr.window(), 0);
    if (!window) {
        m_anr.closed();
        return;
    }
    emit clientNotResponding(window->windowId(), window->appKey(), window->title());
}

void LipstickCompositor::waitForClientForWindowId(int id)
{
    LipstickCompositorWindow *window = m_windows.value(id, 0);
    if (!window || !window->surface() || m_currentDisplayState != QMceDisplay::DisplayOn) {
        m_anr.closed();
        return;
    }
    m_anr.waited(bootTimeMs());
    m_anrSerial = m_xdgShell->ping(window->surface()->client());
    m_anrTimer->start();
}

void LipstickCompositor::killClientForWindowId(int id)
{
    LipstickCompositorWindow *window = m_windows.value(id, 0);
    m_anr.closed();
    m_anrTimer->stop();
    if (!window || window->isInProcess() || window->processId() <= 1)
        return;
    // a stopped process takes SIGKILL too, but the launcher's own end of it is no crash
    AppWatcher::instance()->noteDeliberate(window->processId());
    ::kill(pid_t(window->processId()), SIGKILL);
}

QWaylandSurface *LipstickCompositor::surfaceForId(int id) const
{
    LipstickCompositorWindow *window = m_windows.value(id, 0);
    return window?window->surface():0;
}

bool LipstickCompositor::completed()
{
    return m_completed;
}

void LipstickCompositor::clearKeyboardFocus()
{
//    defaultInputDevice()->setKeyboardFocus(NULL);
}

void LipstickCompositor::setDisplayOff()
{
    QDBusMessage message = QDBusMessage::createMethodCall(MCE_SERVICE,
            MCE_REQUEST_PATH, MCE_REQUEST_IF, MCE_DISPLAY_OFF_REQ);
    QDBusConnection::systemBus().asyncCall(message);
}

void LipstickCompositor::surfaceDamaged(const QRegion &)
{
    if (!m_window->isVisible()) {
        // If the compositor is not visible, do not throttle.
        // make it conditional to QT_WAYLAND_COMPOSITOR_NO_THROTTLE?
        m_output->sendFrameCallbacks();
    }
}

void LipstickCompositor::setFullscreenSurface(QWaylandSurface *surface)
{
    if (surface == m_fullscreenSurface)
        return;

    // Prevent flicker when returning to composited mode
    if (!surface && m_fullscreenSurface) {
        foreach (QWaylandView *view, m_fullscreenSurface->views())
            static_cast<LipstickCompositorWindow *>(view->renderObject())->update();
    }

    m_fullscreenSurface = surface;

    emit fullscreenSurfaceChanged();
}

QObject *LipstickCompositor::clipboard() const
{
    return QGuiApplication::clipboard();
}

void LipstickCompositor::setTopmostWindowId(int id)
{
    if (id != m_topmostWindowId) {
        m_topmostWindowId = id;
        emit topmostWindowIdChanged();

        int pid = -1;
        QWaylandSurface *surface = surfaceForId(m_topmostWindowId);

        if (surface)
            pid = surface->client()->processId();

        if (m_topmostWindowProcessId != pid) {
            m_topmostWindowProcessId = pid;
            emit privateTopmostWindowProcessIdChanged(m_topmostWindowProcessId);
        }
    }
}

LipstickCompositorWindow *LipstickCompositor::createView(QWaylandSurface *surface)
{
    int id = m_nextWindowId++;
    LipstickCompositorWindow *item = new LipstickCompositorWindow(id, "", surface, m_window->contentItem());
    QObject::connect(item, SIGNAL(destroyed(QObject*)), this, SLOT(windowDestroyed()));
    m_windows.insert(item->windowId(), item);
    return item;
}

void LipstickCompositor::onSurfaceDying()
{
    QWaylandSurface *surface = static_cast<QWaylandSurface *>(sender());
    LipstickCompositorWindow *item = surfaceWindow(surface);

    if (surface == m_fullscreenSurface)
        setFullscreenSurface(0);

    if (item) {
        item->m_windowClosed = true;
        item->tryRemove();
    }
}

void LipstickCompositor::initialize()
{
    m_displayState = new QMceDisplay(this);
    reactOnDisplayStateChanges(m_displayState->state());
    connect(m_displayState, &QMceDisplay::stateChanged,
            this, &LipstickCompositor::onDisplayStateChanged);

    new LipstickCompositorAdaptor(this);

    QDBusConnection systemBus = QDBusConnection::systemBus();
    if (!systemBus.registerService("org.nemomobile.compositor")) {
        qWarning("Unable to register D-Bus service org.nemomobile.compositor: %s", systemBus.lastError().message().toUtf8().constData());
    }
    if (!systemBus.registerObject("/", this)) {
        qWarning("Unable to register object at path /: %s", systemBus.lastError().message().toUtf8().constData());
    }
    QDBusMessage message = QDBusMessage::createMethodCall(MCE_SERVICE, MCE_REQUEST_PATH, MCE_REQUEST_IF, MCE_DISPLAY_LPM_SET_SUPPORTED);
    message.setArguments(QVariantList() << ambientSupported());
    QDBusConnection::systemBus().asyncCall(message);
}

void LipstickCompositor::windowDestroyed(LipstickCompositorWindow *item)
{
    int id = item->windowId();

    m_windows.remove(id);
    surfaceUnmapped(item);
}

void LipstickCompositor::onHasContentChanged()
{
    QWaylandSurface *surface = qobject_cast<QWaylandSurface *>(sender());

    if(surface->isCursorSurface())
        return;

    if(surface->hasContent())
        surfaceMapped(surface);
    else
        surfaceUnmapped(surface);
}

void LipstickCompositor::surfaceMapped(QWaylandSurface *surface)
{
    LipstickCompositorWindow *item = surfaceWindow(surface);
    if (!item)
        item = createView(surface);

    // The surface was mapped for the first time
    if (item->m_mapped)
        return;

    QVariantMap properties = item->windowProperties();

    item->m_mapped = true;
    item->m_category = properties.value("CATEGORY").toString();

    if (!item->parentItem()) {
        // TODO why contentItem?
        item->setParentItem(m_window->contentItem());
    }

    QObject::connect(surface, &QWaylandSurface::surfaceDestroyed, this, &LipstickCompositor::onSurfaceDying);

    m_totalWindowCount++;
    m_mappedSurfaces.insert(item->windowId(), item);

    item->setTouchEventsEnabled(true);

    emit windowCountChanged();
    emit windowAdded(item);

    windowAdded(item->windowId());

    emit availableWinIdsChanged();
}

void LipstickCompositor::surfaceTitleChanged()
{
    QWaylandXdgToplevel *xdgShellSurface = qobject_cast<QWaylandXdgToplevel*>(sender());
    LipstickCompositorWindow *window = surfaceWindow(xdgShellSurface->xdgSurface()->surface());
    if (window) {
        window->setTitle(xdgShellSurface->title());
        emit window->titleChanged();

        int windowId = window->windowId();

    }
}

void LipstickCompositor::surfaceSetFullScreen(QWaylandOutput *output)
{
    QWaylandXdgToplevel *xdgShellSurface = qobject_cast<QWaylandXdgToplevel*>(sender());

    QWaylandOutput *designatedOutput = output ? output : m_output;
    if (!designatedOutput)
        return;

    xdgShellSurface->sendFullscreen(designatedOutput->geometry().size() / designatedOutput->scaleFactor());
}

void LipstickCompositor::windowSwapped()
{
    m_output->sendFrameCallbacks();
}

void LipstickCompositor::windowDestroyed()
{
    m_totalWindowCount--;
    m_windows.remove(static_cast<LipstickCompositorWindow *>(sender())->windowId());
    emit ghostWindowCountChanged();
}

void LipstickCompositor::surfaceUnmapped(QWaylandSurface *surface)
{
    if (surface == m_fullscreenSurface)
        setFullscreenSurface(0);

    LipstickCompositorWindow *window = surfaceWindow(surface);
    if (window)
        emit windowHidden(window);
}

void LipstickCompositor::surfaceUnmapped(LipstickCompositorWindow *item)
{
    int id = item->windowId();

    if (m_mappedSurfaces.remove(id) == 0) {
        // It was unmapped already so nothing to do
        return;
    }

    emit windowCountChanged();
    emit windowRemoved(item);

    item->m_windowClosed = true;
    item->tryRemove();

    emit ghostWindowCountChanged();

    windowRemoved(id);

    emit availableWinIdsChanged();
}

void LipstickCompositor::windowAdded(int id)
{
}

void LipstickCompositor::windowRemoved(int id)
{
}

QQmlComponent *LipstickCompositor::shaderEffectComponent()
{
    const char *qml_source =
        "import QtQuick 2.0\n"
        "ShaderEffect {\n"
            "property QtObject window\n"
            "property ShaderEffectSource source: ShaderEffectSource { sourceItem: window }\n"
        "}";

    if (!m_shaderEffect) {
        m_shaderEffect = new QQmlComponent(qmlEngine(this));
        m_shaderEffect->setData(qml_source, QUrl());
    }
    return m_shaderEffect;
}

void LipstickCompositor::setTopmostWindowOrientation(Qt::ScreenOrientation topmostWindowOrientation)
{
    if (m_topmostWindowOrientation != topmostWindowOrientation) {
        m_topmostWindowOrientation = topmostWindowOrientation;
        emit topmostWindowOrientationChanged();
    }
}

void LipstickCompositor::setScreenOrientation(Qt::ScreenOrientation screenOrientation)
{
    if (m_screenOrientation != screenOrientation) {
        if (debug())
            qDebug() << "Setting screen orientation on QWaylandCompositor";

        QSize physSize = m_output->physicalSize();
        switch(screenOrientation) {
        case Qt::PrimaryOrientation:
            m_output->setTransform(QWaylandOutput::TransformNormal);
            break;
        case Qt::LandscapeOrientation:
            if(physSize.width() > physSize.height())
                m_output->setTransform(QWaylandOutput::TransformNormal);
            else
                m_output->setTransform(QWaylandOutput::Transform90);
            break;
        case Qt::PortraitOrientation:
            if(physSize.width() > physSize.height())
                m_output->setTransform(QWaylandOutput::Transform90);
            else
                m_output->setTransform(QWaylandOutput::TransformNormal);
            break;
        case Qt::InvertedLandscapeOrientation:
            if(physSize.width() > physSize.height())
                m_output->setTransform(QWaylandOutput::Transform180);
            else
                m_output->setTransform(QWaylandOutput::Transform270);
            break;
        case Qt::InvertedPortraitOrientation:
            if(physSize.width() > physSize.height())
                m_output->setTransform(QWaylandOutput::Transform270);
            else
                m_output->setTransform(QWaylandOutput::Transform180);
            break;
        }
        QWindowSystemInterface::handleScreenOrientationChange(qApp->primaryScreen(),screenOrientation);

        m_screenOrientation = screenOrientation;
        emit screenOrientationChanged();
    }
}

void LipstickCompositor::onDisplayStateChanged()
{
    reactOnDisplayStateChanges(m_displayState->state());
}

void LipstickCompositor::reactOnDisplayStateChanges(QMceDisplay::State state)
{
    if (m_currentDisplayState == state) {
        return;
    }

    if (state == QMceDisplay::DisplayOn) {
        m_window->setVisible(true);
        emit displayOn();
    } else if (state == QMceDisplay::DisplayOff) {
        QCoreApplication::postEvent(this, new QTouchEvent(QEvent::TouchCancel));
        emit displayOff();
    }

    bool changeInDimming = (state == QMceDisplay::DisplayDim) != (m_currentDisplayState == QMceDisplay::DisplayDim);

    bool changeInAmbient = ((state == QMceDisplay::DisplayOff) != (m_currentDisplayState == QMceDisplay::DisplayOff)) && ambientEnabled();

    bool enterAmbient = changeInAmbient && (state == QMceDisplay::DisplayOff);
    bool leaveAmbient = changeInAmbient && (state != QMceDisplay::DisplayOff);

    m_currentDisplayState = state;

    // eos: no ping is waited for with the display off (a dialog that is up stays)
    if (state != QMceDisplay::DisplayOn && !m_anr.shown()) {
        m_anrTimer->stop();
        m_anr.closed();
    }

    if (changeInDimming) {
        emit displayDimmedChanged();
    }
    if (changeInAmbient) {
        emit displayAmbientChanged();
    }
    if (enterAmbient) {
        emit displayAmbientEntered();
    }
    if (leaveAmbient) {
        emit displayAmbientLeft();
    }
}

void LipstickCompositor::clipboardDataChanged()
{
    const QMimeData *mimeData = QGuiApplication::clipboard()->mimeData();
    if (mimeData && mimeData != m_retainedSelection)
        overrideSelection(const_cast<QMimeData *>(mimeData));
}

bool LipstickCompositor::ambientSupported() const
{
    return QGuiApplication::platformNativeInterface()->nativeResourceForIntegration("AmbientSupported");
}

void LipstickCompositor::setAmbientEnabled(bool enabled)
{
    if (!ambientSupported()) {
        return;
    }

    if (m_ambientModeEnabled == enabled) {
        return;
    }

    m_ambientModeEnabled = enabled;
    if (m_ambientModeEnabled) {
        QGuiApplication::platformNativeInterface()->nativeResourceForIntegration("AmbientEnable");
    } else {
        QGuiApplication::platformNativeInterface()->nativeResourceForIntegration("AmbientDisable");
    }
    emit ambientEnabledChanged();

    // Make window visible.
    reactOnDisplayStateChanges(QMceDisplay::DisplayOn);
    // Fire events because enabled changes are not incorporated in above function.
    emit displayAmbientChanged();
    emit displayAmbientLeft();
}

void LipstickCompositor::scheduleAmbientUpdate()
{
    if (!ambientEnabled()) {
        return;
    }
    // eos: the hub draws the time, the AP needs no wakeup per minute (stock:
    // only the layout's minutes_valid schedules an AP update)
    const bool offloaded = m_displayOffloaded;
    QMap<QString,QVariant> match;
    match.insert("type", QVariant(QString("wakeup")));
    QDBusReply< QList<QVariant> > reply = m_timedDbus->query_sync(match);

    if( !reply.isValid() ) {
        qWarning() << "'query' call failed:" << m_timedDbus->lastError();
        return;
    }

    uint cookie = 0;
    QList<QVariant> cookies = reply.value();
    // eos: a layout that never expires needs no AP wakeup at all
    if (offloaded && m_offloadValidUntil == 0) {
        for (const QVariant &c : cookies) {
            bool ok = true;
            uint id = c.toUInt(&ok);
            if (ok)
                m_timedDbus->cancel_sync(id);
        }
        return;
    }
    // Cancel all wakeup cookies except one.
    while (!cookies.isEmpty()) {
        bool ok = true;
        cookie = cookies.takeFirst().toUInt(&ok);
        if (!ok) {
            cookie = 0;
            continue;
        }
        // If the current cookie isn't the last one in the list.
        if (!cookies.isEmpty()) {
            QDBusReply<bool> res = m_timedDbus->cancel_sync(cookie);
            if (!res.isValid()) {
                qWarning() << "'cancel' call failed:" << m_timedDbus->lastError();
            } else {
                qWarning() << "cookie " << cookie << " deleted " << res.value();
            }
        }
    }

    // Add new wakeup event
    Maemo::Timed::Event wakeupEvent;

    time_t currentTime;
    struct tm* timeinfo;
    time(&currentTime);
    // We don't want to update the screen 60 seconds after the screen is off.
    // The screen should be updated when the minute digit changes.
    timeinfo = localtime(&currentTime);
    timeinfo->tm_sec = 0;

    time_t wakeupTime = mktime(timeinfo);
    if (wakeupTime == -1) {
        wakeupTime = currentTime;
    }
    wakeupTime += 60;
    // eos: while the hub draws, only the layout's expiry wakes the AP; one
    // that has expired already (the wakeup came a moment early, or the
    // rebuild failed) gets the next minute's wakeup, to rebuild it
    if (offloaded && m_offloadValidUntil > currentTime)
        wakeupTime = m_offloadValidUntil;
    wakeupEvent.setTicker(wakeupTime);
    wakeupEvent.setAttribute(QLatin1String("APPLICATION"), QLatin1String("wakup_alarm"));
    wakeupEvent.setAttribute(QLatin1String("type"), QLatin1String("wakeup"));
    wakeupEvent.setBootFlag();
    wakeupEvent.setKeepAliveFlag();
    // No reminder flag: timed hands reminders to the alarm presenter (voland),
    // which then showed this per-minute ambient tick as an alarm at "00:00".
    // The alarm flag alone still wakes the device for the ambient update.
    wakeupEvent.setAlarmFlag();
    wakeupEvent.setSingleShotFlag();

    if (cookie) {
        QDBusReply<uint> res = m_timedDbus->replace_event_sync(wakeupEvent, cookie);
    } else {
        QDBusReply<uint> res = m_timedDbus->add_event_sync(wakeupEvent);
    }
}

QByteArray LipstickCompositor::offloadRequest(const QByteArray &request, int timeoutSec)
{
    struct sockaddr_un sa;
    struct timeval tv = { timeoutSec, 0 };
    char reply[512];
    ssize_t n = -1;
    int s = socket(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0);

    if (s < 0)
        return QByteArray();
    memset(&sa, 0, sizeof(sa));
    sa.sun_family = AF_UNIX;
    strncpy(sa.sun_path, "/run/eos-display-offload/socket", sizeof(sa.sun_path) - 1);
    setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    if (::connect(s, reinterpret_cast<struct sockaddr *>(&sa), sizeof(sa)) == 0 &&
        ::send(s, request.constData(), request.size(), MSG_NOSIGNAL) == request.size())
        n = ::recv(s, reply, sizeof(reply) - 1, 0);
    ::close(s);
    if (n <= 0) {
        // no daemon: the AP keeps drawing the always-on display
        return QByteArray();
    }
    return QByteArray(reply, n);
}

// why: "blank" (mce stopped the updates) or "ambient" (after an ambient
// update), for the daemon's log
void LipstickCompositor::offloadSuspend(const char *why)
{
    // A layout this compositor did not send (a launcher restart left it with
    // the daemon) or one past its expiry would show a stale face or date:
    // clear it before the display may be handed over, the next ambient
    // update sends the new one (stock: the layout is cleared when the face
    // changes and a new one is sent before it can be shown)
    // (also when the burn-in protection is due to move the face: the AP then
    // sends the moved layout at the ambient update after the blank, the one
    // handover of this display off)
    const qint64 now = time(nullptr);
    if (EosOffload::dropAtSuspend(m_offloadLayout == OffloadLayoutUnknown,
                                  m_offloadLayout == OffloadLayoutSet,
                                  m_offloadValidUntil, m_offloadMoveAfter, now)) {
        if (m_offloadLayout == OffloadLayoutSet && !EosOffload::expired(m_offloadValidUntil, now))
            qInfo() << "hub offload: burn-in move due, the next layout comes from the AP";
        clearOffloadLayout();
    }
    m_offloadDisplayReady = true;
    const bool offloaded = offloadRequest(QByteArray("suspend ") + why).startsWith("ok offloaded");
    if (offloaded != m_displayOffloaded) {
        m_displayOffloaded = offloaded;
        emit displayOffloadedChanged();
    }
}

// why: "unblank" (mce turns the display on) or "ambient" (an ambient update)
void LipstickCompositor::offloadResume(const char *why)
{
    // also when the hub did not take the display (no layout yet): the
    // daemon must not keep it "ready" while it turns on
    if (!m_offloadDisplayReady)
        return;
    offloadRequest(QByteArray("resume ") + why);
    m_offloadDisplayReady = false;
    if (m_displayOffloaded) {
        m_displayOffloaded = false;
        emit displayOffloadedChanged();
    }
}

// A mode keeps the always-on screen off (Bedtime, Theater, Battery saver:
// the launcher's modes engine, bound by MainScreen): the hub must not draw
// it either. Starting while the hub draws, the panel goes back to the AP at
// once (which has it blank, mce's low power mode being off meanwhile).
void LipstickCompositor::setOffloadBlocked(bool blocked)
{
    if (m_offloadBlocked == blocked)
        return;
    m_offloadBlocked = blocked;
    qInfo() << "hub offload:" << (blocked ? "blocked: a mode keeps the always-on screen off" : "allowed again");
    if (EosOffload::atBlockChange(blocked) == EosOffload::Release)
        offloadRelease("modes");
    emit offloadBlockedChanged();
}

// The display is not ready for the hub, whatever the daemon was told before
// (an earlier launcher may have left it ready): the panel is the AP's
void LipstickCompositor::offloadRelease(const char *why)
{
    offloadRequest(QByteArray("resume ") + why);
    m_offloadDisplayReady = false;
    if (m_displayOffloaded) {
        m_displayOffloaded = false;
        emit displayOffloadedChanged();
    }
}

bool LipstickCompositor::offloadAmbientUpdateWanted() const
{
    return EosOffload::ambientUpdateWanted(m_displayOffloaded, m_offloadValidUntil,
                                           time(nullptr));
}

bool LipstickCompositor::setOffloadLayout(const QString &path, qint64 validUntil,
                                          qint64 moveAfter)
{
    m_offloadValidUntil = validUntil;
    m_offloadMoveAfter = moveAfter;
    // the upload is about 1-5 ms per 255-byte message on the hub's SPI link
    const bool ok = offloadRequest("layout " + path.toLocal8Bit(), 15).startsWith("ok");
    // (a failed upload leaves the daemon without a layout)
    m_offloadLayout = ok ? OffloadLayoutSet : OffloadLayoutNone;
    return ok;
}

void LipstickCompositor::clearOffloadLayout()
{
    offloadRequest("clear");
    m_offloadLayout = OffloadLayoutNone;
    if (m_displayOffloaded) {
        m_displayOffloaded = false;
        emit displayOffloadedChanged();
    }
}

void LipstickCompositor::setOffWristWake(qint64 epochSec)
{
    // the events of this one's type: keep one to replace, cancel the others
    QMap<QString,QVariant> match;
    match.insert("type", QVariant(QString("offwrist")));
    QDBusReply< QList<QVariant> > reply = m_timedDbus->query_sync(match);
    if (!reply.isValid()) {
        qWarning() << "off-wrist wake: 'query' call failed:" << m_timedDbus->lastError();
        return;
    }
    uint cookie = 0;
    QList<QVariant> cookies = reply.value();
    while (!cookies.isEmpty()) {
        bool ok = true;
        const uint id = cookies.takeFirst().toUInt(&ok);
        if (!ok)
            continue;
        if (epochSec > 0 && cookies.isEmpty()) {
            cookie = id;
        } else {
            m_timedDbus->cancel_sync(id);
        }
    }
    if (epochSec <= 0)
        return;

    Maemo::Timed::Event event;
    event.setTicker(epochSec);
    event.setAttribute(QLatin1String("APPLICATION"), QLatin1String("eos_offwrist"));
    event.setAttribute(QLatin1String("type"), QLatin1String("offwrist"));
    event.setBootFlag();
    event.setKeepAliveFlag();
    // as the ambient minute's wake-up: the alarm flag wakes the device, no
    // reminder flag (the alarm presenter would show it)
    event.setAlarmFlag();
    event.setSingleShotFlag();
    if (cookie)
        m_timedDbus->replace_event_sync(event, cookie);
    else
        m_timedDbus->add_event_sync(event);
}

void LipstickCompositor::setAmbientUpdatesEnabled(bool enabled)
{
    // eos: ambient updates only while mce has the display blanked. Once mce
    // turns it on (setUpdatesEnabled(true)) and before its display state
    // says so, the launcher's ambient minute timer could still start an
    // ambient update, and its end hid the window and told the display
    // offload daemon the display was ready while it was turning on
    if (m_updatesEnabled)
        return;
    if (enabled) {
        if (m_currentDisplayState == QMceDisplay::DisplayOn) {
            return;
        }
        if (!ambientEnabled()) {
            return;
        }
    }
    setUpdatesEnabled(enabled, true);;
    if (enabled) {
        emit displayAmbientUpdate();
    }
}

void LipstickCompositor::setUpdatesEnabled(bool enabled, bool inAmbientMode)
{
    if ((m_updatesEnabled != enabled) || inAmbientMode) {
        if (!inAmbientMode) {
            m_updatesEnabled = enabled;
        }
        if (!enabled) {
            emit displayAboutToBeOff();
            LipstickCompositorWindow *topmostWindow = qobject_cast<LipstickCompositorWindow *>(windowForId(topmostWindowId()));
            if (topmostWindow != 0 && topmostWindow->hasFocus()) {
                m_onUpdatesDisabledUnfocusedWindowId = topmostWindow->windowId();
                clearKeyboardFocus();
            }
            m_window->hide();
            if (m_window->handle() && !inAmbientMode) {
                QGuiApplication::platformNativeInterface()->nativeResourceForIntegration("DisplayOff");
            }
            // trigger frame callbacks which are pending already at this time
            surfaceCommitted();

            // eos: the AP stopped drawing and the panel is in its low-power
            // mode: the hub may take it (stock: startDisplayControl after a
            // suspended display state); not while a mode keeps the always-on
            // screen off (eosoffloadpolicy.h): the panel stays the AP's, blank
            switch (EosOffload::atDisplayOff(ambientEnabled(), m_offloadBlocked)) {
            case EosOffload::Suspend:
                offloadSuspend(inAmbientMode ? "ambient" : "blank");
                break;
            case EosOffload::Release:
                offloadRelease("blocked");
                break;
            case EosOffload::NoRequest:
                break;
            }

            scheduleAmbientUpdate();
        } else {
            // eos: before the panel mode changes or the AP draws, the hub
            // gives the panel back (stock: endDisplayControl first)
            offloadResume(inAmbientMode ? "ambient" : "unblank");
            if (m_window->handle() && !inAmbientMode) {
                QGuiApplication::platformNativeInterface()->nativeResourceForIntegration("DisplayOn");
            }
            emit displayAboutToBeOn();
            m_window->showFullScreen();
            if (m_onUpdatesDisabledUnfocusedWindowId > 0) {
                if (!LipstickSettings::instance()->lockscreenVisible()) {
                    LipstickCompositorWindow *topmostWindow = qobject_cast<LipstickCompositorWindow *>(windowForId(topmostWindowId()));
                    if (topmostWindow != 0 && topmostWindow->windowId() == m_onUpdatesDisabledUnfocusedWindowId) {
                        topmostWindow->takeFocus();
                    }
                }
                m_onUpdatesDisabledUnfocusedWindowId = 0;
            }
        }
    }

    if (enabled && !m_completed) {
        m_completed = true;
        emit completedChanged();
    }
}

void LipstickCompositor::surfaceCommitted()
{
    if (!m_window->isVisible() && !m_fakeRepaintTriggered) {
        startTimer(1000);
        m_fakeRepaintTriggered = true;
    }
}

void LipstickCompositor::timerEvent(QTimerEvent *e)
{
    Q_UNUSED(e)

    m_output->frameStarted();
    m_output->sendFrameCallbacks();
    killTimer(e->timerId());
}
