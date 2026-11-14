/*
 * Copyright (C) 2015 Florent Revest <revestflo@gmail.com>
 *               2014 Aleksi Suomalainen <suomalainen.aleksi@gmail.com>
 *               2012 Timur Kristóf <venemo@fedoraproject.org>
 * All rights reserved.
 *
 * You may use this file under the terms of BSD license as follows:
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of the author nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include <QFont>
#include <QScreen>
#include <QQmlEngine>
#include <QQmlContext>
#include <QTranslator>
#include <QProcess>
#include <MDConfItem>

#include <lipstickqmltypes.h>
#include <homeapplication.h>
#include <notificationmanager.h>
#include <localemanager.h>

#include "applauncherbackground.h"
#include "firstrun.h"
#include "gesturefilterarea.h"
#include "notificationsnoozer.h"
#include "applauncher.h"
#include "watchfacereloader.h"
#include "healthlog.h"
#include "crownbutton.h"
#include "aodbrightness.h"
#include "modes.h"
#include "assistantkey.h"
#include "keyclaims.h"
#include "ongoingregistry.h"
#include "huboffload.h"
#include "offbody.h"
#include "eosquietpolicy.h"

int main(int argc, char **argv)
{
    // Every touch move goes to the home screen's QML as it comes: with Qt
    // Quick's touch compression the panels took the finger on every second
    // frame only (drags at 30 Hz, flings at 60). Qt Quick reads this once,
    // at the first touch event, so setting it here is enough; it is the
    // same as QML_NO_TOUCH_COMPRESSION=1 in the service's environment (and
    // applications started from here inherit it as before).
    if (!qEnvironmentVariableIsSet("QML_NO_TOUCH_COMPRESSION"))
        qputenv("QML_NO_TOUCH_COMPRESSION", "1");

    // Registers the org.nemomobile.lipstick QML types, previously provided
    // by lipstick's QML extension plugin.
    registerLipstickTypes();
    HomeApplication app(argc, argv);

    FirstRun *firstRun = new FirstRun();

    QGuiApplication::setFont(QFont("Noto Sans"));
    Qt::ScreenOrientation nativeOrientation = app.primaryScreen()->nativeOrientation();
    QByteArray v = qgetenv("LAUNCHER_NATIVEORIENTATION");
    if (!v.isEmpty()) {
        switch (v.toInt()) {
        case 1:
            nativeOrientation = Qt::PortraitOrientation;
            break;
        case 2:
            nativeOrientation = Qt::LandscapeOrientation;
            break;
        case 4:
            nativeOrientation = Qt::InvertedPortraitOrientation;
            break;
        case 8:
            nativeOrientation = Qt::InvertedLandscapeOrientation;
            break;
        default:
            nativeOrientation = app.primaryScreen()->nativeOrientation();
        }
    }
    if (nativeOrientation == Qt::PrimaryOrientation)
        nativeOrientation = app.primaryScreen()->primaryOrientation();
    app.engine()->rootContext()->setContextProperty("nativeOrientation", nativeOrientation);
    app.engine()->rootContext()->setContextProperty("firstRun", firstRun);

    // Drops the QML component cache when a watchface is installed at runtime so
    // it shows on the homescreen live, without a launcher restart.
    WatchfaceReloader *watchfaceReloader = new WatchfaceReloader(app.engine());
    app.engine()->rootContext()->setContextProperty("watchfaceReloader", watchfaceReloader);
    // the always-on display layout for the sensor hub (stock display offload)
    HubOffload *hubOffload = new HubOffload(&app);
    app.engine()->rootContext()->setContextProperty("hubOffload", hubOffload);
    // whether the watch is on the wrist (the hub's off-body sensor, on change
    // only): Settings > Display > Always-on when off wrist, Silence when off wrist
    OffBody *offBody = new OffBody(&app);
    app.engine()->rootContext()->setContextProperty("offBody", offBody);

    qmlRegisterType<AppLauncherBackground>("org.asteroid.launcher", 1, 0, "AppLauncherBackground");
    qmlRegisterType<GestureFilterArea>("org.asteroid.launcher", 1, 0, "GestureFilterArea");
    qmlRegisterType<NotificationSnoozer>("org.asteroid.launcher", 1, 0, "NotificationSnoozer");
    qmlRegisterType<AppLauncher>("org.asteroid.launcher", 1, 0, "AppLauncher");
    qmlRegisterType<HealthLog>("org.asteroid.launcher", 1, 0, "HealthLog");

    // The crown button as Wear OS uses it (mce sends power_button_trigger)
    CrownButton *crownButton = new CrownButton();
    // Settings > Display > Always-on brightness, to the panel driver
    new AodBrightness(&app);
    // Bedtime, Theater, Battery saver and Extra dim, as Wear OS (modes.h):
    // what they change, and the user's settings they keep
    ModesEngine *modes = new ModesEngine(&app);
    app.engine()->rootContext()->setContextProperty("modes", modes);
    // Bedtime and Theater make the notification server quiet: no feedback or
    // banner from any poster but an alarm's (lipstick eosquietpolicy.h)
    NotificationManager *notificationManager = NotificationManager::instance();
    // ...and an alarm only with the sound and vibration the modes' Customize
    // pages allow (Theater: vibration only)
    QObject::connect(modes, &ModesEngine::changed, notificationManager,
                     [modes, notificationManager] {
                         notificationManager->setQuiet(modes->quiet());
                         notificationManager->setDnd(modes->doNotDisturb());
                         notificationManager->setAlarmMask(modes->alarmMask());
                     });
    notificationManager->setQuiet(modes->quiet());
    // Do Not Disturb holds the watch's own posters too (heads-up-alerts-17): the same
    // dconf key as the phone's (btsyncd); alarms, calls and the critical battery warning pass
    notificationManager->setDnd(modes->doNotDisturb());
    notificationManager->setAlarmMask(modes->alarmMask());
    // Settings > Vibration > 'Silence when off wrist' (stock: no sound or vibration
    // off the wrist or charging): dconf /org/asteroidos/notifications/silence-off-wrist;
    // never set before, it takes the old 'quiet on the charger' value (eosquietpolicy.h).
    // Follows the hub's off-body sensor (on change) and the charger; nothing polls.
    {
        MDConfItem *silence = new MDConfItem(QStringLiteral("/org/asteroidos/notifications/silence-off-wrist"), &app);
        MDConfItem oldKey(QStringLiteral("/org/asteroidos/notifications/quiet-on-charger"));
        if (!silence->value().isValid())
            silence->set(EosQuiet::silenceDefault(oldKey.value().isValid(), oldKey.value(true).toBool()));
        auto applySilence = [silence, offBody, modes, notificationManager] {
            notificationManager->setSilenced(EosQuiet::silenced(silence->value(false).toBool(),
                                                                offBody->offBody(), modes->charging()));
        };
        QObject::connect(silence, &MDConfItem::valueChanged, &app, applySilence);
        QObject::connect(offBody, &OffBody::changed, &app, applySilence);
        QObject::connect(modes, &ModesEngine::chargingChanged, &app, applySilence);
        applySilence();
    }
    app.engine()->rootContext()->setContextProperty("crownButton", crownButton);
    // The assistant: a hold of the side button (as the stock Pixel Watch 2;
    // mce sends power_button_trigger), and Open()/Ask() on the session bus
    AssistantKey *assistantKey = new AssistantKey(&app);
    app.engine()->rootContext()->setContextProperty("assistantKey", assistantKey);
    // Which key the window in front takes for itself (the alarm presenter:
    // its side button = dismiss, the crown is not its: it goes to the face and
    // the alarm keeps ringing, Q49; an exercise app: its side button), on
    // the session bus: org.asteroidos.launcher.Keys at /org/asteroidos/launcher/keys
    KeyClaims *keyClaims = new KeyClaims(&app);
    app.engine()->rootContext()->setContextProperty("keyClaims", keyClaims);

    // The ongoing activities (a running timer or stopwatch, a call, media, a workout): the face
    // chip, the privacy status icons. Apps publish on the session bus, org.asteroidos.launcher.Ongoing
    // at /org/asteroidos/launcher/ongoing, or with a notification carrying the x-eos-ongoing hints
    // (ongoingregistry.h, W2-launcher-status)
    OngoingRegistry *ongoingRegistry = new OngoingRegistry(&app);
    app.engine()->rootContext()->setContextProperty("ongoingRegistry", ongoingRegistry);

    // Give these to the environment inside the launcher's wayland compositor
    // Fixes a bug where some applications wouldn't launch, eg. terminal or browser
    setenv("EGL_PLATFORM", "wayland", 1);
    setenv("QT_QPA_PLATFORM", "wayland", 1);
    setenv("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1", 1);

    // Load the compositor scene last: it instantiates the home screen (and the
    // overlays), which rely on the context properties and types set up above.
    app.setCompositorPath("qrc:/Launcher/compositor.qml");
    return app.exec();
}
