/*
 * NotificationPreviewPresenter (lipstick/src/notifications/notificationpreviewpresenter.cpp): the
 * queue of notification previews and the display wake mce gives a critical one.
 *
 * The real class (and the real feedback player and LipstickNotification) against the fake
 * NotificationManager, stubs of the compositor and qmce, and a fake mce on a private system bus.
 * Checks which notifications preview (lock, urgency, hidden / restored / empty, the topmost window's
 * mode), the queue, notification_begin_req for a critical one, and our change: the
 * notification_end_req that releases it asks mce for no linger when the display is off (the user
 * turned it off with the power key), the usual 1 s otherwise.
 */

#include <QSignalSpy>
#include <QtTest>

#include <NgfClient>
#include <qmcedisplay.h>
#include <qmcetklock.h>

#include "fakenotificationmanager.h"
#include "fakeservice.h"
#include "lipstickcompositor.h"
#include "mce.h"
#include "notificationmanager.h"
#include "notificationpreviewpresenter.h"

class Ut_NotificationPreviewPresenter : public QObject
{
    Q_OBJECT

private:
    FakeServiceHost *host = nullptr;
    FakeService *mce = nullptr;
    FakeObject *mceObj = nullptr;
    LipstickCompositor compositor;
    LipstickCompositorWindow window;
    NotificationManager *manager = nullptr;

    uint post(int urgency, const QVariantHash &extra = QVariantHash(),
              const QString &preview = QStringLiteral("Preview"))
    {
        QVariantHash h = extra;
        h.insert(NotificationManager::HINT_URGENCY, urgency);
        h.insert(NotificationManager::HINT_PREVIEW_BODY, preview);
        h.insert(NotificationManager::HINT_FEEDBACK, QStringLiteral("chat"));
        return manager->Notify(QStringLiteral("app"), 0, QString(), QStringLiteral("Message"), QStringLiteral("Hello"),
                               QStringList(), h, -1);
    }

    QStringList mceCalls(const QString &member) const
    {
        return mceRequests(mceObj).filter(member);
    }

private slots:
    void initTestCase()
    {
        QVERIFY(TestBus::start());
        host = new FakeServiceHost;
        mce = new FakeService(*host, QStringLiteral("com.nokia.mce"), QStringLiteral("fake-mce"));
        mceObj = new FakeObject(mceIntrospection());
        mce->add(QStringLiteral("/com/nokia/mce/request"), mceObj);
        QVERIFY(mce->registerName());
        LipstickCompositor::s_instance = &compositor;
        manager = NotificationManager::instance();
    }

    void cleanupTestCase()
    {
        delete mce;
        delete host;
        TestBus::stop();
    }

    void init()
    {
        mceObj->clear();
        Ngf::ClientLog::reset();
        FakeNotificationManagerLog::markedDisplayed.clear();
        QMceDisplay::s_state = QMceDisplay::DisplayOn;
        QMceTkLock::s_locked = false;
        compositor.m_windows.clear();
        window.m_properties.clear();
    }

    void cleanup()
    {
        manager->CloseNotifications(manager->notificationIds());
    }

    void showsCriticalAndWakesDisplay()
    {
        NotificationPreviewPresenter presenter;
        QSignalSpy changed(&presenter, &NotificationPreviewPresenter::notificationChanged);
        QSignalSpy presented(&presenter, &NotificationPreviewPresenter::notificationPresented);
        const uint id = post(2);
        QCOMPARE(presenter.notification(), manager->notification(id));
        QCOMPARE(changed.count(), 1);
        QCOMPARE(presented.count(), 1);
        QCOMPARE(presented.first().first().toUInt(), id);
        QCOMPARE(Ngf::ClientLog::played.size(), 1); // the feedback player got it
        QTRY_COMPARE(mceCalls(QStringLiteral("notification_begin_req")),
                     QStringList { QStringLiteral("notification_begin_req %1 6000 2000").arg(id) });
    }

    void releasesDisplayWake_data()
    {
        QTest::addColumn<int>("display");
        QTest::addColumn<int>("linger");
        QTest::newRow("display on") << int(QMceDisplay::DisplayOn) << 1000;
        QTest::newRow("display dimmed") << int(QMceDisplay::DisplayDim) << 1000;
        QTest::newRow("display off") << int(QMceDisplay::DisplayOff) << 0;
    }

    void releasesDisplayWake()
    {
        QFETCH(int, display);
        QFETCH(int, linger);
        NotificationPreviewPresenter presenter;
        const uint id = post(1, hints({ { NotificationManager::HINT_DISPLAY_ON, true } })); // critical by hint
        QCOMPARE(presenter.notification(), manager->notification(id));

        QMceDisplay::s_state = QMceDisplay::State(display);
        presenter.showNextNotification(); // the preview ended
        QCOMPARE(presenter.notification(), static_cast<LipstickNotification *>(nullptr));
        QCOMPARE(FakeNotificationManagerLog::markedDisplayed, QList<uint> { id });
        QTRY_COMPARE(mceCalls(QStringLiteral("notification_end_req")),
                     QStringList { QStringLiteral("notification_end_req %1 %2").arg(id).arg(linger) });
    }

    void normalNotificationLeavesDisplayAlone()
    {
        NotificationPreviewPresenter presenter;
        const uint id = post(1);
        QCOMPARE(presenter.notification(), manager->notification(id));
        presenter.showNextNotification();
        QCOMPARE(FakeNotificationManagerLog::markedDisplayed, QList<uint> { id });
        QTest::qWait(50);
        QVERIFY(mceObj->calls().isEmpty());
    }

    void queuesWhileOneIsShown()
    {
        NotificationPreviewPresenter presenter;
        const uint a = post(1);
        const uint b = post(1);
        post(1, QVariantHash(), QString()); // nothing to preview: not queued
        QCOMPARE(presenter.notification(), manager->notification(a));
        manager->Notify(QStringLiteral("app"), b, QString(), QStringLiteral("Message"), QStringLiteral("Again"),
                        QStringList(), hints({ { NotificationManager::HINT_PREVIEW_BODY, QStringLiteral("Again") } }), -1);
        presenter.updateNotification(b); // an update of a queued one: still once in the queue
        QCOMPARE(presenter.notificationQueue.size(), 1);
        presenter.showNextNotification();
        QCOMPARE(presenter.notification(), manager->notification(b));
        presenter.showNextNotification();
        QCOMPARE(presenter.notification(), static_cast<LipstickNotification *>(nullptr));
    }

    void lockedScreenPreviewsOnlyCritical()
    {
        QMceTkLock::s_locked = true;
        NotificationPreviewPresenter presenter;
        QSignalSpy presented(&presenter, &NotificationPreviewPresenter::notificationPresented);
        const uint normal = post(1);
        QCOMPARE(presenter.notification(), static_cast<LipstickNotification *>(nullptr));
        QCOMPARE(presented.count(), 1); // presented (its feedback plays) without a preview
        QCOMPARE(FakeNotificationManagerLog::markedDisplayed, QList<uint> { normal });

        const uint critical = post(2);
        QCOMPARE(presenter.notification(), manager->notification(critical));
    }

    void skipsQueuedWhenLockedWithDisplayOff()
    {
        NotificationPreviewPresenter presenter;
        QSignalSpy presented(&presenter, &NotificationPreviewPresenter::notificationPresented);
        const uint a = post(1);
        const uint b = post(1);
        QCOMPARE(presenter.notification(), manager->notification(a));
        QMceTkLock::s_locked = true;
        QMceDisplay::s_state = QMceDisplay::DisplayOff;
        presenter.showNextNotification();
        QCOMPARE(presenter.notification(), static_cast<LipstickNotification *>(nullptr));
        QCOMPARE(presented.count(), 2);
        QCOMPARE(presented.last().first().toUInt(), b);
    }

    void notPreviewed_data()
    {
        QTest::addColumn<QString>("hint");
        QTest::newRow("hidden") << QString::fromLatin1(NotificationManager::HINT_HIDDEN);
        QTest::newRow("restored") << QString::fromLatin1(NotificationManager::HINT_RESTORED);
    }

    void notPreviewed()
    {
        QFETCH(QString, hint);
        NotificationPreviewPresenter presenter;
        QVariantHash h;
        h.insert(hint, true);
        const uint id = post(2, h);
        QCOMPARE(presenter.notification(), static_cast<LipstickNotification *>(nullptr));
        QCOMPARE(FakeNotificationManagerLog::markedDisplayed, QList<uint> { id });
    }

    void removingTheShownOne()
    {
        NotificationPreviewPresenter presenter;
        const uint id = post(1);
        QSignalSpy changed(&presenter, &NotificationPreviewPresenter::notificationChanged);
        manager->CloseNotification(id);
        QCOMPARE(presenter.notification(), static_cast<LipstickNotification *>(nullptr));
        QCOMPARE(changed.count(), 1);
    }

    void updatedToHiddenStaysWhileShown()
    {
        NotificationPreviewPresenter presenter;
        const uint id = post(1);
        manager->Notify(QStringLiteral("app"), id, QString(), QStringLiteral("Message"), QStringLiteral("Hello"),
                        QStringList(), hints({ { NotificationManager::HINT_HIDDEN, true } }), -1);
        presenter.updateNotification(id);
        QCOMPARE(presenter.notification(), manager->notification(id)); // does not suddenly disappear
        QVERIFY(FakeNotificationManagerLog::markedDisplayed.isEmpty());
    }

    void previewModeOfTopmostWindow_data()
    {
        QTest::addColumn<int>("mode");
        QTest::addColumn<int>("urgency");
        QTest::addColumn<bool>("shown");
        QTest::newRow("apps disabled, normal") << 1 << 1 << false;
        QTest::newRow("apps disabled, critical") << 1 << 2 << true;
        QTest::newRow("system disabled, normal") << 2 << 1 << true;
        QTest::newRow("system disabled, critical") << 2 << 2 << false;
        QTest::newRow("all disabled") << 3 << 2 << false;
    }

    void previewModeOfTopmostWindow()
    {
        QFETCH(int, mode);
        QFETCH(int, urgency);
        QFETCH(bool, shown);
        window.m_properties.insert(QStringLiteral("NOTIFICATION_PREVIEWS_DISABLED"), uint(mode));
        compositor.m_windows.insert(3, &window);
        compositor.m_topmostWindowId = 3;
        NotificationPreviewPresenter presenter;
        post(urgency);
        QCOMPARE(presenter.notification() != nullptr, shown);
        compositor.m_topmostWindowId = 0;
    }
};

QTEST_GUILESS_MAIN(Ut_NotificationPreviewPresenter)
#include "tst_notificationpreviewpresenter.moc"
