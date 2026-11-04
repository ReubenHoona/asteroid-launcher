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

#ifndef LIPSTICKCOMPOSITOR_H
#define LIPSTICKCOMPOSITOR_H

#include <QQuickWindow>
#include <QWaylandSurface>
#include <QWaylandQuickCompositor>
#include <QWaylandQuickOutput>
#include <QWaylandXdgShell>
#include <QWaylandQtWindowManager>
#include <QQmlComponent>
#include <QWaylandClient>
#include <QPointer>
#include <QTimer>
#include <MDConfItem>
#include <qmcedisplay.h>

#include <timed-qt6/interface>
#include <timed-qt6/exception>
#include <timed-qt6/event-declarations.h>

class LipstickCompositorWindow;
class AsteroidGesturesManager;

class LipstickCompositor : public QWaylandQuickCompositor
{
    Q_OBJECT

    Q_PROPERTY(int windowCount READ windowCount NOTIFY windowCountChanged)
    Q_PROPERTY(int ghostWindowCount READ ghostWindowCount NOTIFY ghostWindowCountChanged)
    Q_PROPERTY(bool homeActive READ homeActive WRITE setHomeActive NOTIFY homeActiveChanged)
    Q_PROPERTY(bool debug READ debug CONSTANT)
    Q_PROPERTY(QWaylandSurface* fullscreenSurface READ fullscreenSurface WRITE setFullscreenSurface NOTIFY fullscreenSurfaceChanged)
    Q_PROPERTY(bool directRenderingActive READ directRenderingActive NOTIFY directRenderingActiveChanged)
    Q_PROPERTY(int topmostWindowId READ topmostWindowId WRITE setTopmostWindowId NOTIFY topmostWindowIdChanged)
    Q_PROPERTY(Qt::ScreenOrientation topmostWindowOrientation READ topmostWindowOrientation WRITE setTopmostWindowOrientation NOTIFY topmostWindowOrientationChanged)
    Q_PROPERTY(Qt::ScreenOrientation screenOrientation READ screenOrientation WRITE setScreenOrientation NOTIFY screenOrientationChanged)
    Q_PROPERTY(QObject* clipboard READ clipboard CONSTANT)
    Q_PROPERTY(QVariant orientationLock READ orientationLock NOTIFY orientationLockChanged)
    Q_PROPERTY(bool displayDimmed READ displayDimmed NOTIFY displayDimmedChanged)
    Q_PROPERTY(bool completed READ completed NOTIFY completedChanged)
    Q_PROPERTY(QQuickWindow *quickWindow READ quickWindow CONSTANT)
    Q_PROPERTY(bool ambientSupported READ ambientSupported CONSTANT)
    Q_PROPERTY(bool ambientEnabled READ ambientEnabled WRITE setAmbientEnabled NOTIFY ambientEnabledChanged)
    Q_PROPERTY(bool displayAmbient READ displayAmbient NOTIFY displayAmbientChanged)
    // eos: the sensor hub draws the always-on display (the AP does not)
    Q_PROPERTY(bool displayOffloaded READ displayOffloaded NOTIFY displayOffloadedChanged)
    // eos: a mode keeps the always-on screen off (MainScreen binds the modes
    // engine's alwaysOnBlocked): the hub does not draw it either
    Q_PROPERTY(bool offloadBlocked READ offloadBlocked WRITE setOffloadBlocked NOTIFY offloadBlockedChanged)

public:
    LipstickCompositor();
    ~LipstickCompositor();

    static LipstickCompositor *instance();

    bool openUrl(QWaylandClient *client, const QUrl &url);
    void retainedSelectionReceived(QMimeData *mimeData) Q_DECL_OVERRIDE;

    int windowCount() const;
    int ghostWindowCount() const;

    bool homeActive() const;
    void setHomeActive(bool);

    QWaylandSurface *fullscreenSurface() const { return m_fullscreenSurface; }
    void setFullscreenSurface(QWaylandSurface *surface);
    bool directRenderingActive() const { return m_directRenderingActive; }

    int topmostWindowId() const { return m_topmostWindowId; }
    void setTopmostWindowId(int id);
    int privateTopmostWindowProcessId() const { return m_topmostWindowProcessId; }

    Qt::ScreenOrientation topmostWindowOrientation() const { return m_topmostWindowOrientation; }
    void setTopmostWindowOrientation(Qt::ScreenOrientation topmostWindowOrientation);

    Qt::ScreenOrientation screenOrientation() const { return m_screenOrientation; }
    void setScreenOrientation(Qt::ScreenOrientation screenOrientation);


    QVariant orientationLock() const { return m_orientationLock->value("dynamic"); }

    bool displayDimmed() const { return m_currentDisplayState == QMceDisplay::DisplayDim; }

    QObject *clipboard() const;

    bool debug() const;

    Q_INVOKABLE QObject *windowForId(int) const;
    Q_INVOKABLE void closeClientForWindowId(int);
    Q_INVOKABLE void clearKeyboardFocus();
    Q_INVOKABLE void setDisplayOff();
    Q_INVOKABLE QVariant settingsValue(const QString &key, const QVariant &defaultValue = QVariant()) const
        { return (key == "orientationLock") ? m_orientationLock->value(defaultValue) : MDConfItem("/lipstick/" + key).value(defaultValue); }


    QWaylandSurface *surfaceForId(int) const;

    bool completed();

    bool ambientSupported() const;
    void setAmbientEnabled(bool enabled);
    bool ambientEnabled() const { return m_ambientModeEnabled; }
    Q_INVOKABLE void setAmbientUpdatesEnabled(bool enabled);

    bool displayAmbient() const { return (m_currentDisplayState == QMceDisplay::DisplayOff) && ambientEnabled(); }
    Q_INVOKABLE void setUpdatesEnabled(bool enabled, bool inAmbientMode = false);

    /*
     * eos display offload (eos-display-offload daemon, the stock display
     * offload HAL): the layout the hub draws while the AP sleeps, as the
     * hub's render-channel messages in a file (eoslayout), or none.
     */
    bool displayOffloaded() const { return m_displayOffloaded; }
    // validUntil: when the layout's background expires (lipstick wakes the AP
    // then); moveAfter: when the burn-in protection may move the face (the
    // layout is then dropped at a display off and the AP sends the moved one)
    Q_INVOKABLE bool setOffloadLayout(const QString &path, qint64 validUntil = 0,
                                      qint64 moveAfter = 0);
    // whether an ambient update is wanted: not while the hub draws a current
    // layout (eosoffloadpolicy.h)
    Q_INVOKABLE bool offloadAmbientUpdateWanted() const;
    Q_INVOKABLE void clearOffloadLayout();
    bool offloadBlocked() const { return m_offloadBlocked; }
    void setOffloadBlocked(bool blocked);
    // the daemon's status line ("ok state=... layout=0|1 ..."), empty without a daemon
    Q_INVOKABLE QString offloadStatus() { return QString::fromLocal8Bit(offloadRequest("status")); }
    LipstickCompositorWindow *createView(QWaylandSurface *surf);

    QQuickWindow *quickWindow() { return m_window; }

protected:
    void timerEvent(QTimerEvent *e) Q_DECL_OVERRIDE;

signals:
    void windowAdded(QObject *window);
    void windowRemoved(QObject *window);
    void windowRaised(QObject *window);
    void windowLowered(QObject *window);
    void windowHidden(QObject *window);

    void windowCountChanged();
    void ghostWindowCountChanged();

    void availableWinIdsChanged();

    void homeActiveChanged();
    void fullscreenSurfaceChanged();
    void directRenderingActiveChanged();
    void topmostWindowIdChanged();
    void privateTopmostWindowProcessIdChanged(int pid);
    void topmostWindowOrientationChanged();
    void screenOrientationChanged();
    void orientationLockChanged();
    void displayDimmedChanged();

    void displayAmbientEntered();
    void displayAmbientLeft();
    // Display entered/left ambient mode.
    void displayAmbientChanged();
    // Update the screen in ambient mode.
    void displayAmbientUpdate();

    void displayOn();
    void displayOff();
    void displayAboutToBeOn();
    void displayAboutToBeOff();

    void ambientEnabledChanged();
    void displayOffloadedChanged();
    void offloadBlockedChanged();

    void completedChanged();


private slots:
    void onHasContentChanged();
    void surfaceTitleChanged();
    void surfaceSetFullScreen(QWaylandOutput *output);
    void surfaceDamaged(const QRegion &);
    void windowSwapped();
    void windowDestroyed();
    void reactOnDisplayStateChanges(QMceDisplay::State state);
    void onDisplayStateChanged();
    void homeApplicationAboutToDestroy();
    void clipboardDataChanged();
    void onVisibleChanged(bool visible);
    void onSurfaceDying();
    void initialize();

    void onToplevelCreated(QWaylandXdgToplevel * topLevel, QWaylandXdgSurface * shellSurface);

private:
    friend class LipstickCompositorWindow;
    friend class NotificationPreviewPresenter;
    friend class NotificationFeedbackPlayer;

    void surfaceMapped(QWaylandSurface *surface);
    void surfaceUnmapped(QWaylandSurface *surface);
    void surfaceUnmapped(LipstickCompositorWindow *item);

    void windowAdded(int);
    void windowRemoved(int);
    void windowDestroyed(LipstickCompositorWindow *item);
    void surfaceCommitted();
    void onSurfaceCreated(QWaylandSurface *surface);

    QQmlComponent *shaderEffectComponent();

    void scheduleAmbientUpdate();
    QByteArray offloadRequest(const QByteArray &request, int timeoutSec = 2);
    void offloadSuspend(const char *why);
    void offloadResume(const char *why);
    void offloadRelease(const char *why);

    static LipstickCompositor *m_instance;

    int m_totalWindowCount;
    QHash<int, LipstickCompositorWindow *> m_mappedSurfaces;
    QHash<int, LipstickCompositorWindow *> m_windows;

    int m_nextWindowId;

    bool m_homeActive;

    QQmlComponent *m_shaderEffect;
    QWaylandSurface *m_fullscreenSurface;
    bool m_directRenderingActive;
    int m_topmostWindowId;
    int m_topmostWindowProcessId;
    Qt::ScreenOrientation m_topmostWindowOrientation;
    Qt::ScreenOrientation m_screenOrientation;
    QMceDisplay *m_displayState;
    QPointer<QMimeData> m_retainedSelection;
    MDConfItem *m_orientationLock;
    QMceDisplay::State m_currentDisplayState;
    bool m_updatesEnabled;
    bool m_completed;
    int m_onUpdatesDisabledUnfocusedWindowId;
    bool m_fakeRepaintTriggered;
    QQuickWindow *m_window;
    QWaylandOutput *m_output;
    QWaylandXdgShell *m_xdgShell;
    QWaylandQtWindowManager *m_wm;
    AsteroidGesturesManager *m_gesturesManager;

    Maemo::Timed::Interface *m_timedDbus;
    bool m_ambientModeEnabled;
    bool m_displayOffloaded = false;
    qint64 m_offloadValidUntil = 0;
    qint64 m_offloadMoveAfter = 0;
    // what the display offload daemon holds, as far as this compositor knows
    // (unknown: an earlier launcher may have left it a layout)
    enum { OffloadLayoutUnknown, OffloadLayoutNone, OffloadLayoutSet } m_offloadLayout = OffloadLayoutUnknown;
    // the daemon was told the display is ready (suspend) and not since that
    // it is not (resume)
    bool m_offloadDisplayReady = false;
    bool m_offloadBlocked = false;
};

#endif // LIPSTICKCOMPOSITOR_H
