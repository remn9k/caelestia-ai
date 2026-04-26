pragma ComponentBehavior: Bound

import QtQuick
import qs.components
import qs.config

Item {
    id: root

    required property DrawerVisibilities visibilities
    readonly property bool holdGeometry: shouldBeActive || shownProgress > 0.001
    readonly property real menuSpillHeight: holdGeometry ? 360 : 0

    readonly property bool shouldBeActive: root.visibilities.blob
    readonly property alias contentItem: content
    readonly property bool hovered: hover.hovered
    property real shownProgress: 0

    visible: holdGeometry
    opacity: shownProgress
    scale: 0.8 + shownProgress * 0.2
    width: implicitWidth
    height: implicitHeight
    implicitWidth: holdGeometry ? content.implicitWidth : 0
    implicitHeight: holdGeometry ? content.implicitHeight + menuSpillHeight : 0

    onShouldBeActiveChanged: {
        if (shouldBeActive) {
            hideAnim.stop();
            showAnim.start();
        } else {
            showAnim.stop();
            hideAnim.start();
        }
    }

    ParallelAnimation {
        id: showAnim

        NumberAnimation {
            target: root
            property: "shownProgress"
            from: root.shownProgress
            to: 1
            duration: 500
            easing.bezierCurve: Appearance.anim.curves.emphasizedDecel
        }
    }

    ParallelAnimation {
        id: hideAnim

        NumberAnimation {
            target: root
            property: "shownProgress"
            from: root.shownProgress
            to: 0
            duration: 300
            easing.bezierCurve: Appearance.anim.curves.emphasizedAccel
        }
    }

    HoverHandler {
        id: hover
    }

    Content {
        id: content

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: menuSpillHeight / 2
        visibilities: root.visibilities
    }

    Component.onCompleted: {
        shownProgress = shouldBeActive ? 1 : 0;
    }
}
