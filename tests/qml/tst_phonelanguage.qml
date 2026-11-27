// Copyright (C) 2026 eos
// SPDX-License-Identifier: BSD-3-Clause
//
// R5 C-04: the watch follows the phone's language and region (src/qml/system/PhoneLanguage.qml, phonelanguage.js),
// as stock's PhoneSettingLocaleListener.maybeUpdateWatchLocale: the phone's tag (asteroid-btsyncd's
// settings/phone-locale, invented tags) applied with its region when the image has the language, the setup
// language otherwise with Settings' "Language not supported." dialog once per language after setup, at the next
// display on. A stand-in LanguageModel records what is applied (nothing reaches localed or lipstick here).
// MODE=st (the staged tree).
import QtQuick
import QtTest
import LauncherTest
import "st/qml/system/phonelanguage.js" as PL

Item {
    id: testRoot
    width: 384
    height: 384

    // the image's languages (a part of image 72's supported-languages) and what was applied
    QtObject {
        id: models
        property var codes: ["de_DE.utf8", "en_GB.utf8", "es.utf8", "fr.utf8", "nl_BE.utf8", "nl_NL.utf8", "pt.utf8",
                             "pt_BR.utf8", "pt_PT.utf8", "zh_Hans.utf8", "zh_Hant.utf8"]
        property var applied: []
        function rowCount() { return codes.length }
        function locale(i) { return codes[i] }
        function setSystemLocale(code, mode) { applied = applied.concat([code + "/" + mode]) }
    }
    property int launches: 0

    Loader { id: loader; active: false; source: Qt.resolvedUrl("st/qml/system/PhoneLanguage.qml") }

    TestCase {
        name: "PhoneLanguage"
        when: windowShown

        property var f: null

        function init() {
            Backend.reset()
            Backend.confSet("/org/asteroidos/launcher/firstRunDone", true)
            models.applied = []
            testRoot.launches = 0
        }
        function make() {
            loader.active = true
            f = loader.item
            f.languageModel = models
            f.launchSettings = function () { testRoot.launches++ }
            wait(20)
            return f
        }
        function cleanup() {
            loader.active = false
            f = null
            wait(0)
        }
        function phone(tag) {
            Backend.confSet("/org/asteroidos/settings/phone-locale", tag)
            wait(20)
        }

        function test_01_tags() {
            var c = models.codes
            var t = function (tag) { var r = PL.target(tag, c, "en_GB.utf8"); return r ? r.code + (r.supported ? "" : "!") : null }
            // the language the image has, with the phone's region: its formats
            compare(t("de-AT"), "de_AT.utf8")
            compare(t("de-DE"), "de_DE.utf8")
            compare(t("en-US"), "en_US.utf8")
            compare(t("en_AU"), "en_AU.utf8")
            compare(t("nl-BE"), "nl_BE.utf8")
            compare(t("fr-CA"), "fr_CA.utf8")
            compare(t("pt-BR"), "pt_BR.utf8")
            compare(t("es-419"), "es_419.utf8")
            // scripts: the region wins (QLocale writes zh_TW in Traditional), else the shipped script entry
            compare(t("zh-Hant-TW"), "zh_TW.utf8")
            compare(t("zh-Hans"), "zh_Hans.utf8")
            compare(t("de"), "de.utf8")
            // extensions are left out
            compare(t("de-AT-u-mu-celsius"), "de_AT.utf8")
            // a language the image does not have: the fallback, marked unsupported
            compare(t("sw-KE"), "en_GB.utf8!")
            compare(t("haw-US"), "en_GB.utf8!")
            // not a tag
            compare(t(""), null)
            compare(t("1x"), null)
            compare(t("-AT"), null)
            compare(PL.languageOf("zh_Hant.utf8"), "zh")
            compare(PL.localeName("de_AT.utf8"), "de_AT")
        }

        function test_02_applies_the_phone_language() {
            make()
            compare(models.applied.length, 0, "no phone language yet: nothing")
            phone("fr-CA")
            compare(models.applied, ["fr_CA.utf8/1"], "the phone's language and region, without a reboot")
            compare(f.applied, "fr_CA.utf8")
            compare(String(Backend.confGet("/org/asteroidos/settings/phone-locale-last-request")), "fr")
            compare(testRoot.launches, 0, "no dialog for a language the watch has")
            phone("de-AT")
            compare(models.applied, ["fr_CA.utf8/1", "de_AT.utf8/1"])
        }

        function test_03_the_current_language_is_left_alone() {
            // the phone's tag for the language the watch has now (as QLocale names it): nothing to apply, also at
            // the launcher's start
            Backend.confSet("/org/asteroidos/settings/phone-locale", "de-AT")
            loader.active = true
            f = loader.item
            f.languageModel = models
            f.currentLocale = function () { return "de_AT" }
            f.follow()
            compare(models.applied.length, 0, "already de_AT")
            // zh-Hans is the zh_Hans entry, which QLocale names zh_CN
            f.currentLocale = function () { return "zh_CN" }
            phone("zh-Hans")
            compare(models.applied.length, 0, "zh_Hans is zh_CN")
            phone("zh-Hant-HK")
            compare(models.applied, ["zh_HK.utf8/1"])
        }

        function test_04_a_language_the_watch_lacks() {
            Backend.confSet("/org/asteroidos/settings/setup-locale", "de_DE.utf8")
            make()
            f.displayOn = false
            phone("sw-KE")
            // the setup language (stock: setup_locale), and the dialog waits for the display
            compare(models.applied, ["de_DE.utf8/1"])
            verify(f.alertPending)
            compare(testRoot.launches, 0)
            f.displayOn = true
            compare(testRoot.launches, 1, "Settings opens on the dialog")
            var req = String(Backend.confGet("/org/asteroidos/settings/ui/open"))
            verify(req.indexOf("language_not_supported@") === 0, req)
            verify(!f.alertPending)
            // once per language (stock last_lang_req)
            phone("sw-TZ")
            f.displayOn = false
            f.displayOn = true
            compare(testRoot.launches, 1, "not again for the same language")
            // another language the watch lacks: again
            phone("haw-US")
            compare(testRoot.launches, 2)
            // something that must not be covered: it waits
            phone("de-AT")
            f.blocked = true
            phone("sw-KE")
            verify(f.alertPending)
            f.displayOn = false
            f.displayOn = true
            compare(testRoot.launches, 2)
            f.blocked = false
            compare(testRoot.launches, 3)
        }

        function test_05_no_dialog_during_setup() {
            Backend.confSet("/org/asteroidos/launcher/firstRunDone", false)
            make()
            phone("sw-KE")
            // the image's default without a setup language (unless it is the language now)
            verify(models.applied.length === 0 ? Qt.locale().name === "en_GB" : models.applied[0] === "en_GB.utf8/1",
                   JSON.stringify(models.applied))
            verify(!f.alertPending, "stock: not before setup has run")
            compare(testRoot.launches, 0)
            compare(String(Backend.confGet("/org/asteroidos/settings/phone-locale-last-request")), "sw")
        }

        function test_06_a_tag_that_is_not_one() {
            make()
            phone("not a tag")
            compare(models.applied.length, 0)
            compare(testRoot.launches, 0)
        }
    }
}
