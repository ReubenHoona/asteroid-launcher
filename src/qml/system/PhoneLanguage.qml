/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import "phonelanguage.js" as PL
import "../desktop.js" as Desktop

/*
 * The watch follows the phone's language and region (R5 C-04, DECISIONS Q60), as stock's
 * PhoneSettingLocaleListener.maybeUpdateWatchLocale (com.google.wear.services phonesettings): asteroid-btsyncd
 * keeps the phone's language tag at /org/asteroidos/settings/phone-locale (written when it changes, from the
 * phone status <lc>); this applies it the way Settings > Language and setup do (LanguageModel.setSystemLocale:
 * systemd-localed's SetLocale for the next start, lipstick's selectLocale now; the apps follow localed's
 * announcement, AsteroidApp's LocaleFollower):
 * - the phone's language with its region when the watch has the language (phonelanguage.js target());
 * - else the setup language (/org/asteroidos/settings/setup-locale, the image's en_GB without one), and after
 *   setup, once per language (stock's last_lang_req: /org/asteroidos/settings/phone-locale-last-request),
 *   Settings' "Language not supported." dialog (stock UnsupportedLanguageDialog, with Open on phone). Stock
 *   wakes the screen for it (a 1 s wake lock); here it waits for the next time the display is on.
 * Settings > System > Language then says the watch's language is the phone's (pref_locale_open_companion).
 * Battery: dconf notifications only (the phone's language changing, setup); nothing is polled or timed, no wakeup.
 */
QtObject {
    id: follower

    /*! The display is on (fully, not always-on): the dialog waits for it */
    property bool displayOn: true
    /*! Something covers the screen that must not be covered (a call, an alarm, setup's own screens) */
    property bool blocked: false
    /*! The image's languages and how one is applied: an org.asteroid.settings LanguageModel (rowCount(),
        locale(i), setSystemLocale(code, mode)), made when first needed; a test sets a stand-in */
    property var languageModel: null
    /*! Starts Settings for the dialog (a test replaces it) */
    property var launchSettings: function () {
        if (Desktop.desktop && Desktop.desktop.launchByName)
            Desktop.desktop.launchByName("asteroid-settings", null)
    }
    /*! The watch's language now, as QLocale names it (a test replaces it) */
    property var currentLocale: function () { return Qt.locale().name }
    /*! The image's default language, for a language the watch lacks when setup chose none */
    property string imageDefault: "en_GB.utf8"
    /*! The dialog is waiting for the display */
    property bool alertPending: false
    /*! What was applied last ("" before the first time): tests */
    property string applied: ""

    readonly property bool setupDone: firstRunDone.value === true || firstRunDone.value === "true"

    property ConfigurationValue _phoneLocale: ConfigurationValue {
        key: "/org/asteroidos/settings/phone-locale"
        defaultValue: ""
        onValueChanged: Qt.callLater(follower.follow)
    }
    property ConfigurationValue _setupLocale: ConfigurationValue {
        key: "/org/asteroidos/settings/setup-locale"
        defaultValue: ""
    }
    property ConfigurationValue _lastRequest: ConfigurationValue {
        key: "/org/asteroidos/settings/phone-locale-last-request"
        defaultValue: ""
    }
    property ConfigurationValue _firstRunDone: ConfigurationValue {
        id: firstRunDone
        key: "/org/asteroidos/launcher/firstRunDone"
        defaultValue: false
    }
    property ConfigurationValue _settingsOpen: ConfigurationValue {
        id: settingsOpen
        key: "/org/asteroidos/settings/ui/open"
        defaultValue: ""
    }

    function _model() {
        if (!languageModel)
            languageModel = Qt.createQmlObject("import org.asteroid.settings; LanguageModel { }", follower, "PhoneLanguageModel")
        return languageModel
    }
    function shippedCodes() {
        var m = _model()
        var out = []
        for (var i = 0; m && i < m.rowCount(); i++)
            out.push(String(m.locale(i)))
        return out
    }

    /*! Applies the phone's language (at start and when the tag changes) */
    function follow() {
        var tag = String(_phoneLocale.value === undefined || _phoneLocale.value === null ? "" : _phoneLocale.value)
        if (tag === "")
            return
        var fallback = String(_setupLocale.value || "") !== "" ? String(_setupLocale.value) : imageDefault
        var t = PL.target(tag, shippedCodes(), fallback)
        if (!t)
            return
        // the watch's language now, as QLocale names it (de_AT.utf8 and de_AT are the same; zh_Hans is zh_CN)
        if (Qt.locale(PL.localeName(t.code)).name !== currentLocale()) {
            applied = t.code
            // LanguageModel.UpdateWithoutReboot
            _model().setSystemLocale(t.code, 1)
        }
        if (String(_lastRequest.value || "") === t.language)
            return
        if (!t.supported && setupDone)
            alertPending = true
        _lastRequest.value = t.language
        showAlert()
    }

    /*! The "Language not supported." dialog of Settings, once the display is on */
    function showAlert() {
        if (!alertPending || !displayOn || blocked)
            return
        alertPending = false
        var v = "language_not_supported@" + Date.now()
        Desktop.ownSettingsRequest = v
        settingsOpen.value = v
        launchSettings()
    }
    onDisplayOnChanged: showAlert()
    onBlockedChanged: showAlert()

    Component.onCompleted: Qt.callLater(follow)
}
