/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls

/* The long press menu of a live update (the face chip's and the stream chips'), as stock
 * CP3A draws it (W2-launcher-status review fix; status-indicators-12, notif-stream-20, -21).
 * Stock: ini.java:160-230 builds the state (jfm: header jfg, display style jfk, mute jfl,
 * confirmation jfi), hdw.java:1170-1262 lays it out as a scaling list whose content padding
 * is 5.2 % of the width at the sides, 10 % of the height at the top and 36.46 % at the
 * bottom (hdw.java:1190-1196), with these items in this order:
 *   title_and_subtitle        the app name (outline, titleMedium) and the entry's channel
 *                             name (onBackground, titleMedium), 12 % of the width at each
 *                             side, centred (hwy.java:214-290)
 *   4 dp spacer
 *   display_style_picker_title  "Show on watch face" (titleSmall, onSurface, 14 dp at the
 *                             sides) - only for a local live update (jfk.a)
 *   icon_and_text_picker, icon_only_picker   two radio rows "Icon and text" / "Icon only"
 *                             (bej.java:658-699), the chosen style selected
 *   4 dp spacer
 *   mute_button_title         "%1 live updates" (titleSmall, 14 dp at the sides)
 *   mute_button               "Turn off", a Button in errorContainer / onErrorContainer
 *                             with the mute icon (kok.java:81-99, euv A and C)
 *   mute_button_description   "Ongoing notifications from %1 won't appear on your watch face"
 *                             (bodySmall, 14 dp at the sides, 4 dp above)
 * Choosing a style applies at once (styleChosen); the button asks muteRequested (the caller
 * opens the confirmation dialog, jfi: "Turn off %1 live updates?").
 * A full-screen Dialog: opaque black, a swipe right dismisses it. Nothing runs while it is
 * closed. */
Dialog {
    id: menu
    objectName: "liveMenu"

    // the desktop file id of the app, its name, the entry's channel name (none of ours has one)
    property string app: ""
    property string who: ""
    property string subtitle: ""
    // the phone app that keeps the settings (the confirmation dialog names it)
    property string companion: ""
    // the app's chip shows the icon only (the stored choice)
    property bool iconOnly: false
    // a local live update: the style picker and the mute section show (stock jtp.h, .d, .e)
    readonly property bool local: app !== ""

    signal styleChosen(bool iconOnly)
    signal muteRequested()

    readonly property alias list: list
    readonly property var rows: {
        var r = [{ id: "header" }, { id: "gap" }]
        if (local)
            r = r.concat([{ id: "styleTitle" }, { id: "iconAndText" }, { id: "iconOnly" }, { id: "gap" },
                          { id: "muteTitle" }, { id: "mute" }, { id: "muteDescription" }])
        return r
    }

    // stock paddings (hdw.java:1190-1196 and the header's f7)
    readonly property real sideMargin: 0.052 * (width > 0 ? width : 384)
    readonly property real topMargin: 0.10 * (height > 0 ? height : 384)
    readonly property real bottomMargin: 0.3646 * (height > 0 ? height : 384)
    readonly property real headerSide: 0.12 * (width > 0 ? width : 384)
    readonly property real labelSide: Theme.dp(14)
    readonly property real gapHeight: Theme.dp(4)

    //% "Show on watch face"
    readonly property string styleLabel: qsTrId("id-live-menu-show-on-watch")
    //% "Icon and text"
    readonly property string iconAndTextLabel: qsTrId("id-live-menu-icon-and-text")
    //% "Icon only"
    readonly property string iconOnlyLabel: qsTrId("id-live-menu-icon-only")
    //% "%1 live updates"
    readonly property string muteTitle: qsTrId("id-live-menu-mute-title").arg(who)
    //% "Turn off"
    readonly property string muteButtonText: qsTrId("id-live-menu-turn-off")
    //% "Ongoing notifications from %1 won’t appear on your watch face"
    readonly property string muteDescription: qsTrId("id-live-menu-mute-description").arg(who)

    ScalingList {
        id: list
        objectName: "liveMenuList"
        anchors.fill: parent
        sideMargin: menu.sideMargin
        topMargin: menu.topMargin
        bottomMargin: menu.bottomMargin
        spacing: 0
        model: menu.rows
        itemDelegate: Loader {
            id: row
            property var modelData
            readonly property string kind: modelData ? modelData.id : ""
            sourceComponent: kind === "header" ? headerItem
                : kind === "gap" ? gapItem
                : kind === "styleTitle" ? styleTitleItem
                : kind === "iconAndText" ? iconAndTextItem
                : kind === "iconOnly" ? iconOnlyItem
                : kind === "muteTitle" ? muteTitleItem
                : kind === "mute" ? muteItem
                : kind === "muteDescription" ? muteDescriptionItem
                : null
        }
    }

    Component {
        id: headerItem
        Item {
            objectName: "liveMenuHeader"
            height: col.height
            Column {
                id: col
                x: menu.headerSide - menu.sideMargin
                width: parent.width - 2 * x
                Label {
                    objectName: "liveMenuTitle"
                    width: parent.width
                    text: menu.who
                    role: "titleMedium"
                    color: Theme.color.outline
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    Accessible.role: Accessible.Heading
                }
                Label {
                    objectName: "liveMenuSubtitle"
                    width: parent.width
                    visible: text !== ""
                    height: visible ? implicitHeight : 0
                    text: menu.subtitle
                    role: "titleMedium"
                    color: Theme.color.onBackground
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
            }
        }
    }

    Component {
        id: gapItem
        Item { height: menu.gapHeight }
    }

    Component {
        id: styleTitleItem
        Label {
            objectName: "liveMenuStyleTitle"
            leftPadding: menu.labelSide
            rightPadding: menu.labelSide
            text: menu.styleLabel
            role: "titleSmall"
            color: Theme.color.onSurface
            horizontalAlignment: Text.AlignLeft
            wrapMode: Text.Wrap
        }
    }

    Component {
        id: iconAndTextItem
        RadioButton {
            id: r
            objectName: "liveMenuIconAndText"
            text: menu.iconAndTextLabel
            onClicked: menu.styleChosen(false)
            Binding { target: r; property: "checked"; value: !menu.iconOnly }
        }
    }

    Component {
        id: iconOnlyItem
        RadioButton {
            id: r
            objectName: "liveMenuIconOnly"
            text: menu.iconOnlyLabel
            onClicked: menu.styleChosen(true)
            Binding { target: r; property: "checked"; value: menu.iconOnly }
        }
    }

    Component {
        id: muteTitleItem
        Label {
            objectName: "liveMenuMuteTitle"
            leftPadding: menu.labelSide
            rightPadding: menu.labelSide
            text: menu.muteTitle
            role: "titleSmall"
            color: Theme.color.onSurface
            horizontalAlignment: Text.AlignLeft
            wrapMode: Text.Wrap
        }
    }

    Component {
        id: muteItem
        Button {
            objectName: "liveMenuMute"
            variant: "tonal"
            // the mute icon of stock (mute_live_update_icon, Material keep_off) is not in our
            // icon set: the notifications-off glyph stands in until W2-meta-icons-fonts has it
            iconName: "ms-notifications_off"
            text: menu.muteButtonText
            containerColor: Theme.color.errorContainer
            contentColor: Theme.color.onErrorContainer
            iconColor: Theme.color.onErrorContainer
            onClicked: menu.muteRequested()
        }
    }

    Component {
        id: muteDescriptionItem
        Label {
            objectName: "liveMenuMuteDescription"
            leftPadding: menu.labelSide
            rightPadding: menu.labelSide
            topPadding: Theme.dp(4)
            text: menu.muteDescription
            role: "bodySmall"
            color: Theme.color.onSurface
            horizontalAlignment: Text.AlignLeft
            wrapMode: Text.Wrap
        }
    }
}
