/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef MEDIAMUTE_H
#define MEDIAMUTE_H

#include <QObject>
#include <QSet>
#include <QString>
#include <QStringList>
#include <functional>

class QDBusConnection;
class QDBusMessage;
class QDBusObjectPath;
class QDBusServiceWatcher;

/*
 * Media sounds off in a mode (ModesCore::mediaMuted, C-11): while it is
 * wanted, the PulseAudio playback streams whose media.role is a media one
 * (ModesCore::isMediaRole: music, video, game) are muted, those that start
 * meanwhile too; when it is not wanted any more the streams muted here are
 * unmuted (a stream that was muted already, by its app or the user, is
 * left as it is). Stock mutes the media usages the same way while a mode
 * does not allow media (ZenModeHelper.applyRestrictions): the playback goes
 * on, silently.
 *
 * Through PulseAudio's D-Bus protocol (module-dbus-protocol; the server's
 * address is $PULSE_DBUS_SERVER, else the session bus lookup
 * org.pulseaudio.Server, as the volume control finds it): the core's
 * PlaybackStreams, its NewPlaybackStream and PlaybackStreamRemoved signals
 * (asked for with ListenForSignal only while muting is wanted), each
 * stream's PropertyList and Mute. Every call is asynchronous.
 *
 * The streams muted here are listed in $XDG_RUNTIME_DIR/eos-media-mute
 * (their object paths; a tmpfs, gone at a reboot): a launcher that starts
 * again (a crash, an update) knows them, unmutes them when no mode wants
 * them muted any more and does not take them for streams their app muted.
 *
 * Power: no timer and no polling. Nothing runs unless a mode or its
 * Customize switch changes, a stream starts or ends while muting is wanted,
 * or PulseAudio (re)starts (its lookup name appearing on the session bus).
 */
class MediaMute : public QObject
{
    Q_OBJECT

public:
    explicit MediaMute(QObject *parent = nullptr);
    ~MediaMute() override;

    // true: mute the media streams, now and those that start; false: unmute the ones muted here
    void setWanted(bool wanted);
    bool wanted() const { return mWanted; }
    // the streams muted here (object paths), for the tests and the log
    QStringList mutedStreams() const;
    // connected to PulseAudio's D-Bus server
    bool connected() const;

signals:
    // PulseAudio confirmed the change of a stream muted or unmuted here
    void streamMuted(const QString &path);
    void streamUnmuted(const QString &path);

private slots:
    void newStream(const QDBusObjectPath &path);
    void streamRemoved(const QDBusObjectPath &path);
    void serverAppeared();

private:
    void connectServer();
    void connectTo(const QString &address);
    void listen(bool on);
    void scan();
    void check(const QString &path);
    void release(const QString &path);
    void apply();
    void setMute(const QString &path, bool mute);
    void save();
    void call(const QDBusMessage &message, const std::function<void(const QDBusMessage &)> &done);

    bool mWanted = false;
    // setWanted was called once (the first call acts even when it does not change mWanted)
    bool mStarted = false;
    // the next connection is the first of this process: the list of the last run still holds
    bool mFirstConnection = true;
    QString mStatePath;
    // an address lookup on the session bus is on its way
    bool mLookup = false;
    // the peer connection's name ("" none) and a serial for a new one after PulseAudio restarted
    QString mName;
    int mSerial = 0;
    bool mListening = false;
    // the streams muted here, and those being looked at
    QSet<QString> mMuted;
    QSet<QString> mChecking;
    // the part of mMuted that came from the list of an earlier launcher and was not looked at yet
    QSet<QString> mLastRun;
    QDBusServiceWatcher *mWatcher = nullptr;
};

#endif // MEDIAMUTE_H
