/*
 *    SPDX-FileCopyrightText: 2021 Mikel Johnson <mikel5764@gmail.com>
 *    SPDX-FileCopyrightText: 2021 Noah Davis <noahadvs@gmail.com>
 *
 *    SPDX-License-Identifier: GPL-2.0-or-later
 */

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.ksvg as KSvg
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

PlasmaExtras.PlasmoidHeading {
    id: root

    readonly property alias tabBar: tabBar
    property real preferredTabBarWidth: 0
    readonly property alias leaveButtons: leaveButtons

    contentWidth: tabBar.implicitWidth + spacing
    contentHeight: leaveButtons.implicitHeight

    leftPadding: kickoff.backgroundMetrics.leftPadding
    rightPadding: kickoff.backgroundMetrics.rightPadding
    topPadding: Kirigami.Units.smallSpacing * 2
    bottomPadding: Kirigami.Units.smallSpacing * 2

    topInset: 0
    leftInset: 0
    rightInset: 0
    bottomInset: 0

    spacing: kickoff.backgroundMetrics.spacing
    position: PC3.ToolBar.Footer

    PC3.TabBar {
        id: tabBar

        // Increase tabWidth to make "Applications" wider; adjust multiplier as needed
        property real tabWidth: Math.max(applicationsTab.implicitWidth, placesTab.implicitWidth) * 1

        focus: true

        width: root.preferredTabBarWidth > 0 ? root.preferredTabBarWidth : undefined
        implicitWidth: contentWidth + leftPadding + rightPadding
        implicitHeight: contentHeight + topPadding + bottomPadding

        leftPadding: mirrored ? root.spacing : 0
        rightPadding: !mirrored ? root.spacing : 0

        anchors {
            top: parent.top
            left: parent.left
            bottom: parent.bottom
        }

        position: PC3.TabBar.Footer

        contentItem: ListView {
            id: tabBarListView
            focus: true
            model: tabBar.contentModel
            currentIndex: tabBar.currentIndex

            spacing: tabBar.spacing
            orientation: ListView.Horizontal
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.AutoFlickIfNeeded
            snapMode: ListView.SnapToItem

            highlightMoveDuration: Kirigami.Units.longDuration
            highlightRangeMode: ListView.ApplyRange
            preferredHighlightBegin: tabBar.tabWidth
            preferredHighlightEnd: width - tabBar.tabWidth
            highlight: KSvg.FrameSvgItem {
                anchors.top: tabBarListView.contentItem.top
                anchors.bottom: tabBarListView.contentItem.bottom
                anchors.topMargin: -root.topPadding
                anchors.bottomMargin: -root.bottomPadding
                imagePath: "widgets/tabbar"
                prefix: tabBar.position === PC3.TabBar.Header ? "north-active-tab" : "south-active-tab"
            }
            keyNavigationEnabled: false
        }

        PC3.TabButton {
            id: applicationsTab
            focus: true
            width: tabBar.tabWidth
            anchors.top: tabBarListView.contentItem.top
            anchors.bottom: tabBarListView.contentItem.bottom
            anchors.topMargin: -root.topPadding
            anchors.bottomMargin: -root.bottomPadding
            icon.width: Kirigami.Units.iconSizes.smallMedium
            icon.height: Kirigami.Units.iconSizes.smallMedium
            icon.name: "applications-all-symbolic"
            text: i18n("Applications")
            Keys.onBacktabPressed: event => {
                (kickoff.lastCentralPane || nextItemInFocusChain(false))
                    .forceActiveFocus(Qt.BacktabFocusReason)
            }
        }
        PC3.TabButton {
            id: placesTab
            width: tabBar.tabWidth
            anchors.top: tabBarListView.contentItem.top
            anchors.bottom: tabBarListView.contentItem.bottom
            anchors.topMargin: -root.topPadding
            anchors.bottomMargin: -root.bottomPadding
            icon.width: Kirigami.Units.iconSizes.smallMedium
            icon.height: Kirigami.Units.iconSizes.smallMedium
            icon.name: "compass"
            text: i18n("Places")
            visible: false // Make it invisible
            enabled: false // Disable interaction
        }

        Connections {
            target: kickoff
            function onExpandedChanged() {
                if (kickoff.expanded) {
                    tabBar.currentIndex = 0 // Always stay on Applications
                }
            }
        }

        Keys.onPressed: event => {
            const Key_Next = Qt.application.layoutDirection === Qt.RightToLeft ? Qt.Key_Left : Qt.Key_Right
            const Key_Prev = Qt.application.layoutDirection === Qt.RightToLeft ? Qt.Key_Right : Qt.Key_Left
            if (event.key === Key_Next) {
                leaveButtons.nextItemInFocusChain().forceActiveFocus(Qt.TabFocusReason)
                event.accepted = true
            } else if (event.key === Key_Prev) {
                // No action needed since we only want Applications active
                event.accepted = true
            }
        }
        Keys.onUpPressed: event => {
            kickoff.firstCentralPane.forceActiveFocus(Qt.BacktabFocusReason);
        }
    }

    LeaveButtons {
        id: leaveButtons

        anchors {
            top: parent.top
            right: parent.right
            bottom: parent.bottom
        }

        maximumWidth: root.availableWidth - tabBar.width - root.spacing

        Keys.onUpPressed: event => {
            kickoff.lastCentralPane.forceActiveFocus(Qt.BacktabFocusReason);
        }
    }

    Behavior on height {
        enabled: kickoff.expanded
        NumberAnimation {
            duration: Kirigami.Units.longDuration
            easing.type: Easing.InQuad
        }
    }

    Item {
        id: mouseItem
        parent: root
        anchors.left: parent.left
        height: root.height
        width: tabBar.width
        z: 1
        WheelHandler {
            id: tabScrollHandler
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: {
                // Disable wheel switching since Places is non-functional
            }
        }
    }

    Shortcut {
        sequences: ["Ctrl+Tab", "Ctrl+Shift+Tab", StandardKey.NextChild, StandardKey.PreviousChild]
        onActivated: {
            // Do nothing since we only want Applications
        }
    }
}
