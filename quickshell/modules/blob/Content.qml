pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.config
import qs.services

ColumnLayout {
    id: root

    required property DrawerVisibilities visibilities
    readonly property color pickerBackground: Qt.alpha(Colours.palette.m3background, 0xdd / 255)
    readonly property color pickerBorder: Qt.alpha(Colours.palette.m3primary, 0x77 / 255)
    readonly property real pickerRadius: 24

    property bool chatMenuExpanded: false
    property bool modelMenuExpanded: false
    property bool thinkingMenuExpanded: false
    readonly property bool menuOpen: chatMenuExpanded || modelMenuExpanded || thinkingMenuExpanded
    readonly property bool voiceOverlayVisible: SpeechToText.recording || SpeechToText.transcribing

    spacing: Appearance.spacing.normal
    width: 760
    implicitWidth: width
    implicitHeight: shellRect.implicitHeight
    focus: root.visibilities.blob

    function closeMenus(): void {
        chatMenuExpanded = false;
        modelMenuExpanded = false;
        thinkingMenuExpanded = false;
    }

    function focusInput(): void {
        if (!root.visibilities.blob)
            return;

        root.forceActiveFocus();
        shellRect.forceActiveFocus();
        input.forceActiveFocus();
        Qt.callLater(() => {
            const targetPos = Math.max(0, Math.min(Opencode.draftCursorPosition, input.text.length));
            input.cursorPosition = targetPos;
        });
    }

    function appendTranscript(text: string): void {
        const cleaned = (text || "").trim();
        if (cleaned.length === 0)
            return;

        const prefix = input.text.length > 0 && !input.text.endsWith(" ") && !input.text.endsWith("\n") ? " " : "";
        input.text += `${prefix}${cleaned}`;
        Opencode.draftInput = input.text;
        input.cursorPosition = input.text.length;
        Opencode.draftCursorPosition = input.cursorPosition;
        transcriptPulse.restart();
        root.focusInput();
    }

    function sendMessage(): void {
        const value = input.text.trim();
        if (!Opencode.sendMessage(value))
            return;

        input.text = "";
        Opencode.draftInput = "";
        Opencode.draftCursorPosition = 0;
        root.visibilities.blob = false;
    }

    function formatRecordingTime(seconds: real): string {
        const total = Math.max(0, Math.floor(seconds));
        const mins = Math.floor(total / 60);
        const secs = total % 60;
        return `${mins}:${secs < 10 ? "0" : ""}${secs}`;
    }

    Keys.onEscapePressed: {
        root.closeMenus();
        root.visibilities.blob = false;
    }

    Shortcut {
        enabled: root.visibilities.blob
        sequence: "Esc"
        onActivated: {
            root.closeMenus();
            root.visibilities.blob = false;
        }
    }

    component IconControl: StyledRect {
        required property string iconName
        required property bool active
        required property var onTap
        property color activeColor: Colours.palette.m3secondaryContainer
        property color inactiveColor: Qt.alpha(Colours.tPalette.m3surfaceContainerHighest, 0.2)
        property int iconPointSize: Appearance.font.size.normal + 1
        readonly property bool hovered: iconTap.containsMouse

        implicitWidth: 34
        implicitHeight: 34
        radius: Appearance.rounding.full
        color: active
               ? Qt.lighter(activeColor, hovered ? 1.04 : 1)
               : hovered
                 ? Qt.alpha(Colours.tPalette.m3surfaceContainerHighest, 0.3)
                 : inactiveColor
        scale: iconTap.pressed ? 0.965 : hovered ? 1.03 : 1

        MaterialIcon {
            anchors.centerIn: parent
            text: iconName
            color: active ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
            font.pointSize: iconPointSize
        }

        MouseArea {
            id: iconTap

            anchors.fill: parent
            hoverEnabled: true
            onClicked: onTap()
        }

        Behavior on color {
            CAnim {}
        }

        Behavior on scale {
            Anim {
                duration: Appearance.anim.durations.small
                easing.bezierCurve: Appearance.anim.curves.standard
            }
        }
    }

    component FloatingMenu: StyledClippingRect {
        property bool expanded: false

        visible: opacity > 0
        opacity: expanded ? 1 : 0
        scale: expanded ? 1 : 0.96
        antialiasing: true
        radius: root.pickerRadius
        color: Colours.palette.m3surfaceContainer
        border.width: 2
        border.color: root.pickerBorder

        Behavior on opacity {
            Anim {
                duration: Appearance.anim.durations.large
                easing.bezierCurve: expanded
                                     ? Appearance.anim.curves.emphasizedDecel
                                     : Appearance.anim.curves.standard
            }
        }

        Behavior on scale {
            Anim {
                duration: Appearance.anim.durations.large
                easing.bezierCurve: expanded
                                     ? Appearance.anim.curves.emphasizedDecel
                                     : Appearance.anim.curves.standardDecel
            }
        }
    }

    component MenuOption: StyledRect {
        required property string label
        required property bool selected
        required property var onSelected
        property bool hovered: optionTap.containsMouse

        Layout.fillWidth: true
        implicitHeight: 42
        color: selected
               ? Colours.palette.m3secondaryContainer
               : hovered
                 ? Qt.alpha(Colours.palette.m3secondaryContainer, 0.12)
                 : "transparent"

        Behavior on color {
            CAnim {}
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Appearance.padding.normal + 4
            anchors.right: parent.right
            anchors.rightMargin: Appearance.padding.normal
            text: label
            elide: Text.ElideRight
            color: selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
            x: hovered ? 2 : 0

            Behavior on x {
                Anim {
                    duration: Appearance.anim.durations.small
                    easing.bezierCurve: Appearance.anim.curves.standard
                }
            }
        }

        MouseArea {
            id: optionTap

            anchors.fill: parent
            hoverEnabled: true
            onClicked: onSelected()
        }
    }

    component ControlSlot: Item {
        required property bool shown

        implicitWidth: shown ? 34 : 0
        implicitHeight: 34
        opacity: shown ? 1 : 0
        scale: shown ? 1 : 0.92
        visible: opacity > 0

        Behavior on implicitWidth {
            Anim {
                duration: Appearance.anim.durations.normal
                easing.bezierCurve: Appearance.anim.curves.standardDecel
            }
        }

        Behavior on opacity {
            Anim {
                duration: Appearance.anim.durations.small
            }
        }

        Behavior on scale {
            Anim {
                duration: Appearance.anim.durations.normal
                easing.bezierCurve: Appearance.anim.curves.standardDecel
            }
        }
    }

    StyledClippingRect {
        id: shellRect

        Layout.fillWidth: true
        implicitWidth: root.width
        implicitHeight: Math.max(shellLayout.implicitHeight + Appearance.padding.large * 2, 252)
        antialiasing: true
        radius: root.pickerRadius
        color: root.pickerBackground
        border.width: 2
        border.color: root.pickerBorder
        z: 10

        ColumnLayout {
            id: shellLayout

            anchors.fill: parent
            anchors.topMargin: Appearance.padding.large
            anchors.bottomMargin: Appearance.padding.large
            anchors.leftMargin: Appearance.padding.large + 10
            anchors.rightMargin: Appearance.padding.large + 10
            spacing: Appearance.spacing.normal

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.small
                z: 30

                StyledText {
                    text: Opencode.currentModelLabel
                    font.weight: 500
                    font.pointSize: Appearance.font.size.large
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    Layout.maximumWidth: Math.max(120, root.width * 0.42)
                }

                StyledRect {
                    implicitWidth: 1
                    implicitHeight: 24
                    Layout.leftMargin: 4
                    radius: Appearance.rounding.full
                    color: Qt.alpha(Colours.palette.m3outline, 0.45)
                }

                Item {
                    Layout.fillWidth: true
                }

                StyledRect {
                    id: topControlsContainer

                    radius: Appearance.rounding.full
                    color: Qt.alpha(Colours.tPalette.m3surfaceContainerHighest, 0.14)
                    implicitWidth: topControls.implicitWidth + Appearance.padding.small * 2
                    implicitHeight: topControls.implicitHeight + Appearance.padding.small * 2

                    Behavior on implicitWidth {
                        Anim {
                            duration: Appearance.anim.durations.normal
                            easing.bezierCurve: Appearance.anim.curves.emphasizedDecel
                        }
                    }

                    Behavior on implicitHeight {
                        Anim {
                            duration: Appearance.anim.durations.normal
                            easing.bezierCurve: Appearance.anim.curves.emphasizedDecel
                        }
                    }

                    RowLayout {
                        id: topControls

                        anchors.centerIn: parent
                        spacing: Appearance.spacing.small

                        ControlSlot {
                            id: modeButtonWrap
                            shown: !Opencode.apiMode

                            scale: 1

                            IconControl {
                                anchors.fill: parent
                                iconName: Opencode.selectedMode === "build" ? "build" : "event_note"
                                active: false
                                onTap: () => {
                                    modePulse.restart();
                                    Opencode.selectedMode = Opencode.selectedMode === "build" ? "plan" : "build";
                                }
                            }

                            SequentialAnimation {
                                id: modePulse

                                NumberAnimation {
                                    target: modeButtonWrap
                                    property: "scale"
                                    to: 0.8
                                    duration: Appearance.anim.durations.small
                                    easing.bezierCurve: Appearance.anim.curves.standard
                                }

                                NumberAnimation {
                                    target: modeButtonWrap
                                    property: "scale"
                                    to: 1
                                    duration: Appearance.anim.durations.normal
                                    easing.bezierCurve: Appearance.anim.curves.standardDecel
                                }
                            }
                        }

                        ControlSlot {
                            id: thinkingButtonWrap
                            shown: !Opencode.apiMode || Opencode.apiReasoningAvailable

                            IconControl {
                                anchors.centerIn: parent
                                iconName: "psychology"
                                active: Opencode.apiMode ? Opencode.apiReasoningEnabled : (Opencode.currentThinkingOptions.length > 1 && root.thinkingMenuExpanded)
                                onTap: () => {
                                    if (Opencode.apiMode) {
                                        Opencode.setApiReasoningEnabled(!Opencode.apiReasoningEnabled);
                                        return;
                                    }
                                    if (Opencode.currentThinkingOptions.length <= 1)
                                        return;
                                    root.thinkingMenuExpanded = !root.thinkingMenuExpanded;
                                    root.chatMenuExpanded = false;
                                    root.modelMenuExpanded = false;
                                }
                            }

                        }

                        ControlSlot {
                            shown: !Opencode.apiMode

                            IconControl {
                                anchors.fill: parent
                                iconName: "shield"
                                active: !Opencode.autoAcceptPermissions
                                onTap: () => {
                                    Opencode.autoAcceptPermissions = !Opencode.autoAcceptPermissions;
                                }
                            }
                        }

                        ControlSlot {
                            id: chatButtonWrap
                            shown: true

                            IconControl {
                                anchors.centerIn: parent
                                iconName: "chat_bubble"
                                active: root.chatMenuExpanded
                                onTap: () => {
                                    root.chatMenuExpanded = !root.chatMenuExpanded;
                                    root.modelMenuExpanded = false;
                                    root.thinkingMenuExpanded = false;
                                }
                            }

                        }

                        ControlSlot {
                            id: modelButtonWrap
                            shown: true

                            IconControl {
                                anchors.centerIn: parent
                                iconName: "deployed_code"
                                active: root.modelMenuExpanded
                                onTap: () => {
                                    root.modelMenuExpanded = !root.modelMenuExpanded;
                                    root.chatMenuExpanded = false;
                                    root.thinkingMenuExpanded = false;
                                }
                            }

                        }
                    }
                }
            }

            StyledRect {
                Layout.fillWidth: true
                implicitHeight: 1
                radius: Appearance.rounding.full
                color: Qt.alpha(Colours.palette.m3outline, 0.18)
            }

            RowLayout {
                Layout.fillWidth: true
                visible: Opencode.attachments.length > 0
                spacing: Appearance.spacing.small

                Repeater {
                    model: Opencode.attachments

                    StyledRect {
                        required property var modelData

                        radius: Appearance.rounding.full
                        color: Qt.alpha(Colours.tPalette.m3surfaceContainerHighest, 0.22)
                        implicitWidth: attachRow.implicitWidth + Appearance.padding.normal * 2
                        implicitHeight: attachRow.implicitHeight + Appearance.padding.small * 2

                        RowLayout {
                            id: attachRow

                            anchors.centerIn: parent
                            spacing: Appearance.spacing.small

                            MaterialIcon {
                                text: "image"
                                font.pointSize: Appearance.font.size.small
                            }

                            StyledText {
                                text: (modelData.split("/").pop() || modelData)
                                font.pointSize: Appearance.font.size.small
                                elide: Text.ElideRight
                            }

                            IconControl {
                                iconName: "close"
                                active: false
                                implicitWidth: 24
                                implicitHeight: 24
                                iconPointSize: Appearance.font.size.small
                                onTap: () => {
                                    const next = [];
                                    for (const attachment of Opencode.attachments) {
                                        if (attachment !== modelData)
                                            next.push(attachment);
                                    }
                                    Opencode.attachments = next;
                                }
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.small

                IconControl {
                    iconName: "add"
                    active: false
                    implicitWidth: 42
                    implicitHeight: 42
                    iconPointSize: Appearance.font.size.large
                    onTap: () => Opencode.pickAttachment()
                }

                StyledRect {
                    id: inputShell

                    property real recordingPulse: 0

                    Layout.fillWidth: true
                    implicitHeight: Math.max(56, Math.min(input.contentHeight + Appearance.padding.normal * 2 + 8, 120))
                    radius: input.lineCount > 1 ? Appearance.rounding.large : Appearance.rounding.full
                    color: Qt.alpha(
                               Colours.tPalette.m3surfaceContainerHigh,
                               0.28 + recordingPulse * 0.12
                           )
                    scale: 1

                    SequentialAnimation {
                        id: transcriptPulse

                        NumberAnimation {
                            target: inputShell
                            property: "scale"
                            from: 1
                            to: 1.02
                            duration: Appearance.anim.durations.small
                            easing.bezierCurve: Appearance.anim.curves.standard
                        }
                        NumberAnimation {
                            target: inputShell
                            property: "scale"
                            from: 1.02
                            to: 1
                            duration: Appearance.anim.durations.normal
                            easing.bezierCurve: Appearance.anim.curves.standardDecel
                        }
                    }

                    Behavior on scale {
                        Anim {
                            duration: Appearance.anim.durations.normal
                            easing.bezierCurve: Appearance.anim.curves.standardDecel
                        }
                    }

                    Behavior on color {
                        CAnim {}
                    }

                    SequentialAnimation on recordingPulse {
                        running: SpeechToText.recording
                        loops: Animation.Infinite
                        alwaysRunToEnd: true

                        Anim {
                            from: 0
                            to: 1
                            duration: Appearance.anim.durations.extraLarge
                            easing.bezierCurve: Appearance.anim.curves.standard
                        }
                        Anim {
                            from: 1
                            to: 0
                            duration: Appearance.anim.durations.extraLarge
                            easing.bezierCurve: Appearance.anim.curves.standardDecel
                        }
                    }

                    StateLayer {
                        color: Colours.palette.m3onSurface

                        function onClicked(): void {
                            root.focusInput();
                        }
                    }

                    Flickable {
                        id: inputFlick

                        anchors.fill: parent
                        anchors.leftMargin: Appearance.padding.large + 4
                        anchors.rightMargin: Appearance.padding.large
                        anchors.topMargin: Appearance.padding.small
                        anchors.bottomMargin: Appearance.padding.small
                        clip: true
                        contentWidth: width
                        contentHeight: Math.max(height, input.y + input.contentHeight)
                        interactive: input.y + input.contentHeight > height
                        opacity: root.voiceOverlayVisible ? 0 : 1

                        Behavior on opacity {
                            Anim {
                                duration: Appearance.anim.durations.small
                                easing.bezierCurve: Appearance.anim.curves.standard
                            }
                        }

                        function ensureCursorVisible(): void {
                            const cursorY = input.y + input.cursorRectangle.y;
                            const targetY = Math.max(0, Math.min(cursorY - (height - input.cursorRectangle.height) / 2, contentHeight - height));
                            contentY = targetY;
                        }

                        TextEdit {
                            id: input

                            width: inputFlick.width
                            height: contentHeight
                            y: contentHeight < inputFlick.height ? Math.floor((inputFlick.height - contentHeight) / 2) : 0
                            wrapMode: TextEdit.Wrap
                            font.pointSize: Appearance.font.size.normal
                            color: Colours.palette.m3onSurface
                            activeFocusOnPress: true
                            readOnly: false
                            selectByMouse: true
                            textFormat: TextEdit.PlainText
                            cursorVisible: true
                            selectionColor: Qt.alpha(Colours.palette.m3secondaryContainer, 0.82)
                            selectedTextColor: Colours.palette.m3onSecondaryContainer
                            text: Opencode.draftInput

                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Escape) {
                                    event.accepted = true;
                                    root.closeMenus();
                                    root.visibilities.blob = false;
                                    return;
                                }
                                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                                    event.accepted = true;
                                    root.sendMessage();
                                }
                            }

                            onTextChanged: {
                                if (text !== Opencode.draftInput)
                                    Opencode.draftInput = text;
                            }
                            onCursorPositionChanged: {
                                if (cursorPosition !== Opencode.draftCursorPosition)
                                    Opencode.draftCursorPosition = cursorPosition;
                            }
                            onCursorRectangleChanged: inputFlick.ensureCursorVisible()
                            onContentHeightChanged: inputFlick.ensureCursorVisible()

                            Component.onCompleted: root.focusInput()
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Appearance.padding.large + 6
                        anchors.rightMargin: Appearance.padding.large
                        visible: SpeechToText.recording
                        spacing: 0
                        opacity: SpeechToText.recording ? 1 : 0

                        Behavior on opacity {
                            Anim {
                                duration: Appearance.anim.durations.small
                                easing.bezierCurve: Appearance.anim.curves.standard
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        StyledText {
                            text: root.formatRecordingTime(SpeechToText.elapsed)
                            color: Qt.alpha(Colours.palette.m3onSurface, 0.86)
                            font.pointSize: Appearance.font.size.normal
                            font.weight: 400
                        }

                        Item {
                            Layout.fillWidth: true
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Appearance.padding.large + 6
                        anchors.rightMargin: Appearance.padding.large
                        visible: SpeechToText.transcribing
                        spacing: Appearance.spacing.small
                        opacity: SpeechToText.transcribing ? 1 : 0

                        Behavior on opacity {
                            Anim {
                                duration: Appearance.anim.durations.small
                                easing.bezierCurve: Appearance.anim.curves.standard
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        MaterialIcon {
                            text: "progress_activity"
                            color: Qt.alpha(Colours.palette.m3secondary, 0.92)
                            font.pointSize: Appearance.font.size.normal + 1
                            rotation: 0

                            RotationAnimation on rotation {
                                running: SpeechToText.transcribing
                                loops: Animation.Infinite
                                from: 0
                                to: 360
                                duration: 1000
                            }
                        }

                        StyledText {
                            text: qsTr("Rendering your voice...")
                            color: Qt.alpha(Colours.palette.m3onSurface, 0.82)
                            font.pointSize: Appearance.font.size.normal
                        }

                        Item {
                            Layout.fillWidth: true
                        }
                    }

                    StyledText {
                        anchors.left: parent.left
                        anchors.leftMargin: Appearance.padding.large + 6
                        anchors.verticalCenter: parent.verticalCenter
                        visible: input.text.length === 0 && !SpeechToText.recording && !SpeechToText.transcribing
                        text: Opencode.busy ? qsTr("Queue your next question...") : qsTr("Ask something...")
                        color: Qt.alpha(Colours.palette.m3onSurfaceVariant, 0.72)
                        font.pointSize: Appearance.font.size.normal
                    }
                }

                IconControl {
                    iconName: SpeechToText.recording ? "stop_circle" : "mic"
                    active: SpeechToText.recording
                    implicitWidth: 42
                    implicitHeight: 42
                    inactiveColor: Colours.palette.m3secondaryContainer
                    iconPointSize: Appearance.font.size.large - 1
                    onTap: () => {
                        SpeechToText.activeTarget = "blob";
                        SpeechToText.toggle();
                    }
                }

                StopButton {
                    visible: Opencode.busy
                    opacity: visible ? 1 : 0
                }

                SendButton {
                    visible: !Opencode.busy
                    opacity: visible ? 1 : 0
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            visible: root.menuOpen
            z: 5
            onClicked: root.closeMenus()
        }

    }

    FloatingMenu {
        parent: shellRect
        expanded: root.thinkingMenuExpanded
        z: 1000
        x: Math.max(Appearance.padding.large, topControlsContainer.x + topControlsContainer.width - width)
        y: topControlsContainer.y + topControlsContainer.height + Appearance.spacing.normal + 16
        implicitWidth: 190
        implicitHeight: Math.min(thinkingMenuColumn.implicitHeight, 8 * 42)

        StyledFlickable {
            id: thinkingMenuFlick

            anchors.fill: parent
            clip: true
            contentWidth: parent.width
            contentHeight: thinkingMenuColumn.implicitHeight

            StyledScrollBar.vertical: StyledScrollBar {
                flickable: thinkingMenuFlick
            }

            ColumnLayout {
                id: thinkingMenuColumn
                width: parent.width
                spacing: 0

                Repeater {
                    model: Opencode.currentThinkingOptions

                    MenuOption {
                        required property var modelData
                        label: modelData === "default"
                               ? qsTr("Default")
                               : modelData.charAt(0).toUpperCase() + modelData.slice(1)
                        selected: modelData === Opencode.currentThinkingLevel
                        onSelected: () => {
                            Opencode.setThinkingLevel(modelData);
                            root.thinkingMenuExpanded = false;
                        }
                    }
                }
            }
        }
    }

    FloatingMenu {
        parent: shellRect
        expanded: root.chatMenuExpanded
        z: 1000
        x: Math.max(Appearance.padding.large, topControlsContainer.x + topControlsContainer.width - width)
        y: topControlsContainer.y + topControlsContainer.height + Appearance.spacing.normal + 16
        implicitWidth: 250
        implicitHeight: Math.min(chatMenuColumn.implicitHeight, 8 * 46)

        StyledFlickable {
            id: chatMenuFlick

            anchors.fill: parent
            clip: true
            contentWidth: parent.width
            contentHeight: chatMenuColumn.implicitHeight

            StyledScrollBar.vertical: StyledScrollBar {
                flickable: chatMenuFlick
            }

            ColumnLayout {
                id: chatMenuColumn
                width: parent.width
                spacing: 0

                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: 46
                    color: Qt.alpha(Colours.palette.m3secondaryContainer, newChatTap.containsMouse ? 0.18 : 0.1)

                    Behavior on color {
                        CAnim {}
                    }

                    MouseArea {
                        id: newChatTap

                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            Opencode.newChat();
                            root.chatMenuExpanded = false;
                            root.focusInput();
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Appearance.padding.normal + 4
                        anchors.rightMargin: Appearance.padding.normal
                        spacing: Appearance.spacing.small

                        MaterialIcon {
                            text: "add_comment"
                            color: Colours.palette.m3onSurface
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: qsTr("New Chat")
                            color: Colours.palette.m3onSurface
                        }
                    }
                }

                Repeater {
                    model: Opencode.sessions

                    StyledRect {
                        required property var modelData
                        property bool hovered: chatOptionTap.containsMouse

                        Layout.fillWidth: true
                        implicitHeight: 46
                        color: modelData.id === Opencode.currentSessionId
                               ? Colours.palette.m3secondaryContainer
                               : hovered
                                 ? Qt.alpha(Colours.palette.m3secondaryContainer, 0.12)
                                 : "transparent"

                        Behavior on color {
                            CAnim {}
                        }

                        MouseArea {
                            id: chatOptionTap

                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                Opencode.loadSession(modelData.id);
                                root.chatMenuExpanded = false;
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Appearance.padding.normal + 4
                            anchors.rightMargin: Appearance.padding.normal
                            spacing: Appearance.spacing.small

                            MaterialIcon {
                                text: "chat_bubble"
                                color: modelData && modelData.id === Opencode.currentSessionId
                                       ? Colours.palette.m3onSecondaryContainer
                                       : Colours.palette.m3onSurfaceVariant
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: modelData ? modelData.title : ""
                                elide: Text.ElideRight
                                color: modelData && modelData.id === Opencode.currentSessionId
                                       ? Colours.palette.m3onSecondaryContainer
                                       : Colours.palette.m3onSurface
                            }
                        }
                    }
                }
            }
        }
    }

    FloatingMenu {
        parent: shellRect
        expanded: root.modelMenuExpanded
        z: 1000
        x: Math.max(Appearance.padding.large, topControlsContainer.x + topControlsContainer.width - width)
        y: topControlsContainer.y + topControlsContainer.height + Appearance.spacing.normal + 16
        implicitWidth: 240
        implicitHeight: Math.min(modelMenuColumn.implicitHeight, 8 * 46)

        StyledFlickable {
            id: modelMenuFlick

            anchors.fill: parent
            clip: true
            contentWidth: parent.width
            contentHeight: modelMenuColumn.implicitHeight

            StyledScrollBar.vertical: StyledScrollBar {
                flickable: modelMenuFlick
            }

            ColumnLayout {
                id: modelMenuColumn
                width: parent.width
                spacing: 0

                Repeater {
                    model: Opencode.modelMenuItems

                    delegate: StyledRect {
                        required property var modelData

                        Layout.fillWidth: true
                        implicitHeight: modelData.type === "provider" ? 34 : 46
                        color: modelData.type === "provider"
                               ? "transparent"
                               : modelOptionTap.containsMouse
                                 ? Qt.alpha(Colours.palette.m3secondaryContainer, 0.12)
                                 : modelData.id === Opencode.selectedModel
                                   ? Colours.palette.m3secondaryContainer
                                   : "transparent"

                        Behavior on color {
                            CAnim {}
                        }

                        StyledText {
                            visible: modelData.type === "provider"
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: Appearance.padding.normal + 4
                            anchors.right: parent.right
                            anchors.rightMargin: Appearance.padding.normal
                            text: modelData.label || ""
                            elide: Text.ElideRight
                            font.pointSize: Appearance.font.size.small
                            font.weight: 500
                            color: Qt.alpha(Colours.palette.m3onSurfaceVariant, 0.75)
                        }

                        MouseArea {
                            id: modelOptionTap

                            anchors.fill: parent
                            enabled: modelData.type === "model"
                            hoverEnabled: enabled
                            onClicked: {
                                Opencode.selectModel(modelData.id);
                                root.modelMenuExpanded = false;
                            }
                        }

                        RowLayout {
                            visible: modelData.type === "model"
                            anchors.fill: parent
                            anchors.leftMargin: Appearance.padding.normal + 4
                            anchors.rightMargin: Appearance.padding.normal
                            spacing: Appearance.spacing.small

                            MaterialIcon {
                                text: "deployed_code"
                                color: modelData.id === Opencode.selectedModel
                                       ? Colours.palette.m3onSecondaryContainer
                                       : Colours.palette.m3onSurfaceVariant
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.label || ""
                                elide: Text.ElideRight
                                color: modelData.id === Opencode.selectedModel
                                       ? Colours.palette.m3onSecondaryContainer
                                       : Colours.palette.m3onSurface
                            }
                        }
                    }
                }
            }
        }
    }

    component StopButton: StyledRect {
        property real pulseOpacity: 1
        property real pulseScale: 1

        Layout.preferredWidth: 42
        Layout.preferredHeight: 42
        implicitWidth: 42
        implicitHeight: 42
        radius: Appearance.rounding.full
        color: stopTap.containsMouse
               ? Qt.darker(Colours.palette.m3primary, 1.05)
               : Qt.darker(Colours.palette.m3primary, 1.16)
        scale: (stopTap.pressed ? 0.972 : stopTap.containsMouse ? 1.02 : 1) * pulseScale
        opacity: pulseOpacity

        StyledRect {
            anchors.centerIn: parent
            implicitWidth: 13
            implicitHeight: 13
            radius: Appearance.rounding.small / 2
            color: Colours.palette.m3onTertiaryContainer
        }

        MouseArea {
            id: stopTap

            anchors.fill: parent
            hoverEnabled: true
            onClicked: Opencode.cancelRequest()
        }

        Behavior on color {
            CAnim {}
        }

        Behavior on scale {
            Anim {
                duration: Appearance.anim.durations.small
                easing.bezierCurve: Appearance.anim.curves.standard
            }
        }

        SequentialAnimation on pulseOpacity {
            running: Opencode.busy && !stopTap.pressed
            loops: Animation.Infinite
            alwaysRunToEnd: true

            Anim {
                from: 1
                to: 0.72
                duration: 620
                easing.bezierCurve: Appearance.anim.curves.standard
            }
            Anim {
                from: 0.72
                to: 1
                duration: 780
                easing.bezierCurve: Appearance.anim.curves.standardDecel
            }
        }

        SequentialAnimation on pulseScale {
            running: Opencode.busy && !stopTap.pressed
            loops: Animation.Infinite
            alwaysRunToEnd: true

            Anim {
                from: 1
                to: 0.985
                duration: 620
                easing.bezierCurve: Appearance.anim.curves.standard
            }
            Anim {
                from: 0.985
                to: 1
                duration: 780
                easing.bezierCurve: Appearance.anim.curves.standardDecel
            }
        }
    }

    component SendButton: StyledRect {
        Layout.preferredWidth: 42
        Layout.preferredHeight: 42
        implicitWidth: 42
        implicitHeight: 42
        radius: Appearance.rounding.full
        color: Colours.palette.m3primary
        opacity: input.text.trim().length === 0 ? 0.5 : 0.92
        scale: sendTap.pressed ? 0.97 : 1

        SequentialAnimation on opacity {
            running: input.text.trim().length > 0 && !sendTap.pressed
            loops: Animation.Infinite

            Anim {
                from: 0.92
                to: 1
                duration: 900
                easing.bezierCurve: Appearance.anim.curves.standard
            }
            Anim {
                from: 1
                to: 0.92
                duration: 900
                easing.bezierCurve: Appearance.anim.curves.standardDecel
            }
        }

        MaterialIcon {
            anchors.centerIn: parent
            animate: true
            text: "arrow_upward"
            color: Colours.palette.m3onPrimary
            font.pointSize: Appearance.font.size.large
        }

        MouseArea {
            id: sendTap

            anchors.fill: parent
            onClicked: {
                if (SpeechToText.recording) {
                    SpeechToText.activeTarget = "blob";
                    SpeechToText.stop(true);
                    root.visibilities.blob = false;
                    return;
                }
                if (input.text.trim().length > 0)
                    root.sendMessage();
            }
        }

        Behavior on scale {
            Anim {
                duration: Appearance.anim.durations.small
                easing.bezierCurve: Appearance.anim.curves.standard
            }
        }
    }

    Connections {
        function onBlobChanged(): void {
            if (root.visibilities.blob) {
                Qt.callLater(() => root.focusInput());
                Opencode.reloadSessions();
            } else {
                Opencode.draftCursorPosition = input.cursorPosition;
                root.closeMenus();
            }
        }

        target: root.visibilities
    }

    Connections {
        function onDraftInputChanged(): void {
            if (input.text !== Opencode.draftInput)
                input.text = Opencode.draftInput;
        }

        function onDraftCursorPositionChanged(): void {
            if (!input.activeFocus)
                input.cursorPosition = Math.max(0, Math.min(Opencode.draftCursorPosition, input.text.length));
        }

        target: Opencode
    }

    Connections {
        function onTranscriptNonceChanged(): void {
            if (SpeechToText.activeTarget !== "blob")
                return;

            if (SpeechToText.consumeSubmitAfterTranscribe()) {
                root.appendTranscript(SpeechToText.lastTranscript);
                Qt.callLater(() => root.sendMessage());
            } else {
                root.appendTranscript(SpeechToText.lastTranscript);
            }

            SpeechToText.activeTarget = "";
        }

        target: SpeechToText
    }

    Component.onCompleted: {
        if (root.visibilities.blob)
            Qt.callLater(() => root.focusInput());
    }
}
