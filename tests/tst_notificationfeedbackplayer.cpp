/*
 * NotificationFeedbackPlayer (lipstick/src/notifications/notificationfeedbackplayer.cpp): plays a
 * notification's feedback (ngf events: ringtone, vibration, LED) and stops it.
 *
 * The real class with the real LipstickNotification, against the fake NotificationManager
 * (tests/fakes) and stubs of ngf and the compositor (tests/stubs). Checks which notifications play
 * (hidden, restored, suppressed, priority, the topmost window's NOTIFICATION_PREVIEWS_DISABLED mode),
 * the LED properties, that a new presentation stops the previous feedback, and our addition: an
 * update that sets x-nemo-feedback-suppressed (a ringing call silenced on the phone or with the
 * power key) stops the feedback, alone or in a batch update, and an update never starts any.
 */

#include <QSignalSpy>
#include <QtTest>

#include <NgfClient>

#include "fakenotificationmanager.h"
#include "lipstickcompositor.h"
#include "notificationfeedbackplayer.h"
#include "notificationmanager.h"

class Ut_NotificationFeedbackPlayer : public QObject
{
    Q_OBJECT

private:
    LipstickCompositor compositor;
    LipstickCompositorWindow window;
    NotificationManager *manager = nullptr;

    uint post(const QVariantHash &h, const QString &summary = QStringLiteral("Message"),
              const QString &body = QStringLiteral("Hello"), uint replacesId = 0)
    {
        return manager->Notify(QStringLiteral("app"), replacesId, QString(), summary, body, QStringList(), h, -1);
    }

    static QStringList playedEvents()
    {
        QStringList out;
        for (const auto &p : Ngf::ClientLog::played)
            out << p.first;
        return out;
    }

private slots:
    void initTestCase()
    {
        LipstickCompositor::s_instance = &compositor;
        manager = NotificationManager::instance();
    }

    void init()
    {
        Ngf::ClientLog::reset();
        compositor.m_windows.clear();
        compositor.m_topmostWindowId = 0;
        window.m_properties.clear();
    }

    void cleanup()
    {
        manager->CloseNotifications(manager->notificationIds());
    }

    void connectsToNgfOnStart()
    {
        NotificationFeedbackPlayer player;
        QCOMPARE(Ngf::ClientLog::connects, 0);
        QTRY_COMPARE(Ngf::ClientLog::connects, 1);
    }

    void playsEachFeedbackOfANotification()
    {
        NotificationFeedbackPlayer player;
        const uint id = post(hints({ { NotificationManager::HINT_FEEDBACK, QStringLiteral("chat_exists,,vibra") } }));
        player.addNotification(id);
        QCOMPARE(playedEvents(), QStringList({ QStringLiteral("chat_exists"), QStringLiteral("vibra") }));
        QVERIFY(Ngf::ClientLog::played.first().second.isEmpty());
        QCOMPARE(player.idToEventId.size(), 2);

        // presented again: the earlier feedback stops first
        const QList<quint32> first = Ngf::ClientLog::playedIds;
        player.addNotification(id);
        QList<quint32> stopped = Ngf::ClientLog::stopped;
        std::sort(stopped.begin(), stopped.end());
        QCOMPARE(stopped, first);
        QCOMPARE(Ngf::ClientLog::played.size(), 4);
        QCOMPARE(player.idToEventId.size(), 2);
    }

    void noFeedbackHintPlaysNothing()
    {
        NotificationFeedbackPlayer player;
        player.addNotification(post(QVariantHash()));
        player.addNotification(4242); // unknown id
        QVERIFY(Ngf::ClientLog::played.isEmpty());
    }

    void ledPropertiesWithoutBodyAndSummary()
    {
        NotificationFeedbackPlayer player;
        player.addNotification(post(hints({ { NotificationManager::HINT_FEEDBACK, QStringLiteral("sms") } }),
                                    QString(), QString()));
        QCOMPARE(Ngf::ClientLog::played.size(), 1);
        const QMap<QString, QVariant> props = Ngf::ClientLog::played.first().second;
        QCOMPARE(props.value(QStringLiteral("media.leds")).toBool(), false);
        QCOMPARE(props.value(QStringLiteral("media.audio")).toBool(), true);
        QCOMPARE(props.value(QStringLiteral("media.vibra")).toBool(), true);
        QCOMPARE(props.value(QStringLiteral("media.backlight")).toBool(), true);

        Ngf::ClientLog::reset();
        player.addNotification(post(hints({ { NotificationManager::HINT_FEEDBACK, QStringLiteral("sms") },
                                            { NotificationManager::HINT_LED_DISABLED_WITHOUT_BODY_AND_SUMMARY, false } }),
                                    QString(), QString()));
        QCOMPARE(Ngf::ClientLog::played.size(), 1);
        QVERIFY(Ngf::ClientLog::played.first().second.isEmpty());
    }

    void notPlayed_data()
    {
        QTest::addColumn<QString>("hint");
        QTest::newRow("suppressed") << QString::fromLatin1(NotificationManager::HINT_FEEDBACK_SUPPRESSED);
        QTest::newRow("hidden") << QString::fromLatin1(NotificationManager::HINT_HIDDEN);
        QTest::newRow("restored") << QString::fromLatin1(NotificationManager::HINT_RESTORED);
    }

    void notPlayed()
    {
        QFETCH(QString, hint);
        NotificationFeedbackPlayer player;
        QVariantHash h = hints({ { NotificationManager::HINT_FEEDBACK, QStringLiteral("ringtone") } });
        h.insert(hint, true);
        player.addNotification(post(h));
        QVERIFY(Ngf::ClientLog::played.isEmpty());
    }

    void enabledByModeAndPriority_data()
    {
        QTest::addColumn<int>("mode"); // the topmost window's NOTIFICATION_PREVIEWS_DISABLED, -1: no window
        QTest::addColumn<int>("urgency");
        QTest::addColumn<bool>("displayOn");
        QTest::addColumn<int>("priority");
        QTest::addColumn<int>("minimumPriority");
        QTest::addColumn<bool>("enabled");
        QTest::newRow("no window") << -1 << 1 << false << 0 << 0 << true;
        QTest::newRow("all enabled") << 0 << 1 << false << 0 << 0 << true;
        QTest::newRow("low priority") << 0 << 1 << false << 5 << 10 << false;
        QTest::newRow("critical, low priority") << 0 << 2 << false << 5 << 10 << true;
        QTest::newRow("apps disabled, normal") << 1 << 1 << false << 0 << 0 << false;
        QTest::newRow("apps disabled, critical") << 1 << 2 << false << 0 << 0 << true;
        QTest::newRow("apps disabled, display-on") << 1 << 1 << true << 0 << 0 << true;
        QTest::newRow("system disabled, normal") << 2 << 1 << false << 0 << 0 << true;
        QTest::newRow("system disabled, critical") << 2 << 2 << false << 0 << 0 << false;
        QTest::newRow("all disabled") << 3 << 2 << false << 0 << 0 << false;
    }

    void enabledByModeAndPriority()
    {
        QFETCH(int, mode);
        QFETCH(int, urgency);
        QFETCH(bool, displayOn);
        QFETCH(int, priority);
        QFETCH(int, minimumPriority);
        QFETCH(bool, enabled);
        if (mode >= 0) {
            window.m_properties.insert(QStringLiteral("NOTIFICATION_PREVIEWS_DISABLED"), uint(mode));
            compositor.m_windows.insert(7, &window);
            compositor.m_topmostWindowId = 7;
        }
        NotificationFeedbackPlayer player;
        QSignalSpy prioritySpy(&player, &NotificationFeedbackPlayer::minimumPriorityChanged);
        player.setMinimumPriority(minimumPriority);
        QCOMPARE(player.minimumPriority(), minimumPriority);
        QCOMPARE(prioritySpy.count(), 1);
        const uint id = post(hints({ { NotificationManager::HINT_URGENCY, urgency },
                                     { NotificationManager::HINT_DISPLAY_ON, displayOn },
                                     { NotificationManager::HINT_PRIORITY, priority },
                                     { NotificationManager::HINT_FEEDBACK, QStringLiteral("chat") } }));
        QCOMPARE(player.isEnabled(manager->notification(id)), enabled);
        player.addNotification(id);
        QCOMPARE(Ngf::ClientLog::played.size(), enabled ? 1 : 0);
    }

    // ours: silencing a ringing call updates its notification with feedback suppressed
    void updateSuppressingFeedbackStopsIt()
    {
        NotificationFeedbackPlayer player;
        const QVariantHash ringing = hints({ { NotificationManager::HINT_FEEDBACK, QStringLiteral("ringtone,vibra") } });
        const uint id = post(ringing);
        player.addNotification(id);
        QCOMPARE(Ngf::ClientLog::played.size(), 2);

        QVariantHash silenced = ringing;
        silenced.insert(NotificationManager::HINT_FEEDBACK_SUPPRESSED, true);
        post(silenced, QStringLiteral("Message"), QStringLiteral("Hello"), id); // emits notificationModified
        QList<quint32> stopped = Ngf::ClientLog::stopped;
        std::sort(stopped.begin(), stopped.end());
        QCOMPARE(stopped, Ngf::ClientLog::playedIds);
        QVERIFY(player.idToEventId.isEmpty());
        QCOMPARE(Ngf::ClientLog::played.size(), 2); // and starts nothing
    }

    void updateWithoutSuppressionKeepsFeedback()
    {
        NotificationFeedbackPlayer player;
        const QVariantHash ringing = hints({ { NotificationManager::HINT_FEEDBACK, QStringLiteral("ringtone") } });
        const uint id = post(ringing);
        player.addNotification(id);
        post(ringing, QStringLiteral("Call"), QStringLiteral("00:01"), id);
        QVERIFY(Ngf::ClientLog::stopped.isEmpty());
        QCOMPARE(Ngf::ClientLog::played.size(), 1); // an update never starts feedback
        QCOMPARE(player.idToEventId.size(), 1);
    }

    void batchUpdateStopsOnlySuppressed()
    {
        NotificationFeedbackPlayer player;
        const uint call = post(hints({ { NotificationManager::HINT_FEEDBACK, QStringLiteral("ringtone") } }));
        const uint chat = post(hints({ { NotificationManager::HINT_FEEDBACK, QStringLiteral("chat") } }));
        player.addNotification(call);
        player.addNotification(chat);
        const quint32 callEvent = Ngf::ClientLog::playedIds.at(0);

        manager->notification(call)->setHints(hints({ { NotificationManager::HINT_FEEDBACK, QStringLiteral("ringtone") },
                                                      { NotificationManager::HINT_FEEDBACK_SUPPRESSED, true } }));
        emit manager->notificationsModified({ call, chat, 999 });
        QCOMPARE(Ngf::ClientLog::stopped, QList<quint32>({ callEvent }));
        QCOMPARE(player.idToEventId.size(), 1);

        emit manager->notificationModified(999); // unknown: nothing
        QCOMPARE(Ngf::ClientLog::stopped.size(), 1);
    }

    void removeStopsFeedback()
    {
        NotificationFeedbackPlayer player;
        const uint id = post(hints({ { NotificationManager::HINT_FEEDBACK, QStringLiteral("ringtone") } }));
        player.addNotification(id);
        manager->CloseNotification(id);
        QCOMPARE(Ngf::ClientLog::stopped, Ngf::ClientLog::playedIds);
        QVERIFY(player.idToEventId.isEmpty());
    }
};

QTEST_GUILESS_MAIN(Ut_NotificationFeedbackPlayer)
#include "tst_notificationfeedbackplayer.moc"
