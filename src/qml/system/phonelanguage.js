/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */
.pragma library

/*
 * The watch's language and region from the phone's (R5 C-04, DECISIONS Q60), as stock's
 * PhoneSettingLocaleListener.maybeUpdateWatchLocale (com.google.wear.services phonesettings):
 * - the phone's first language tag ("de-AT": asteroid-btsyncd keeps it at /org/asteroidos/settings/phone-locale);
 * - a language the watch has (any shipped language with the same language part, stock: a supported locale
 *   whose getLanguage() is the same) is applied with the phone's region: its formats, units and first day of
 *   the week are the phone's; the text is the language's catalogue (the nearest one when the region has
 *   none of its own: de-AT reads de_DE's, AsteroidApp::installTranslators and the launcher's LocaleManager);
 * - a language the watch does not have: the setup language (stock: Settings.Global setup_locale, else en-US;
 *   here /org/asteroidos/settings/setup-locale, else the image's en_GB), and once per language after setup the
 *   "Language not supported." dialog (stock UnsupportedLanguageDialog, last_lang_req).
 */

// "de-AT" -> { language: "de", script: "", region: "AT" }; null for what is not a language tag
function parseTag(tag) {
    var s = String(tag === undefined || tag === null ? "" : tag).trim().replace(/_/g, "-")
    var parts = s.split("-")
    if (!/^[A-Za-z]{2,3}$/.test(parts[0]))
        return null
    var r = { language: parts[0].toLowerCase(), script: "", region: "" }
    for (var i = 1; i < parts.length; i++) {
        var p = parts[i]
        if (r.script === "" && r.region === "" && /^[A-Za-z]{4}$/.test(p))
            r.script = p.charAt(0).toUpperCase() + p.substring(1).toLowerCase()
        else if (r.region === "" && (/^[A-Za-z]{2}$/.test(p) || /^[0-9]{3}$/.test(p)))
            r.region = p.toUpperCase()
        else
            break   // variants and extensions ("-u-..."): not used
    }
    return r
}

// "de_DE.utf8" -> "de"
function languageOf(code) {
    return String(code || "").split(/[_.@]/)[0].toLowerCase()
}

// "de_AT.utf8" -> "de_AT" (what QLocale takes)
function localeName(code) {
    return String(code || "").split(/[.@]/)[0]
}

/* The locale the watch applies for the phone's tag: { code: the LANG ("de_AT.utf8"), supported: the watch has the
 * language, language: its language part }; null for a tag that is not one. shipped: the LocaleCodes of the
 * image's languages (LanguageModel); fallback: the LANG for a language the watch lacks. */
function target(tag, shipped, fallback) {
    var t = parseTag(tag)
    if (!t)
        return null
    var list = shipped || []
    var has = false
    for (var i = 0; i < list.length; i++) {
        if (languageOf(list[i]) === t.language)
            has = true
    }
    if (!has)
        return { code: fallback, supported: false, language: t.language }
    // the region when the phone names one (zh-Hant-TW: zh_TW, which QLocale writes in Traditional), else the script
    var want = t.language + (t.region !== "" ? "_" + t.region : t.script !== "" ? "_" + t.script : "")
    for (var j = 0; j < list.length; j++) {
        if (localeName(list[j]).toLowerCase() === want.toLowerCase())
            return { code: list[j], supported: true, language: t.language }
    }
    return { code: want + ".utf8", supported: true, language: t.language }
}
