pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.components.containers
import qs.components.controls
import qs.config
import qs.services

ColumnLayout {
    id: root

    required property PopoutState popouts
    readonly property bool hovered: aiHover.hovered

    property bool permissionsMenuExpanded: false
    property bool chatMenuExpanded: false
    property bool modelMenuExpanded: false
    property bool thinkingMenuExpanded: false
    readonly property bool menuOpen: root.chatMenuExpanded || root.modelMenuExpanded || root.thinkingMenuExpanded
    readonly property bool voiceOverlayVisible: SpeechToText.recording || SpeechToText.transcribing
    property double highlightedAssistantCreated: 0
    property double lastFocusedAssistantCreated: 0
    property string footerReasoningText: ""
    property bool footerReasoningClosing: false
    property bool footerReasoningExpanded: false
    readonly property bool footerReasoningVisible: root.footerReasoningText.length > 0 || root.footerReasoningClosing
    property bool pendingBottomScroll: false
    property bool followStreamingReasoningBottom: false

    spacing: Appearance.spacing.normal
    width: 470
    implicitWidth: width
    implicitHeight: 760

    HoverHandler {
        id: aiHover
    }

    function scrollToLatest(): void {
        scrollTimer.restart();
    }

    function requestBottomScroll(): void {
        pendingBottomScroll = true;
        chatFlickable.followBottom = true;
        scrollToLatest();
    }

    function closeMenus(): void {
        permissionsMenuExpanded = false;
        chatMenuExpanded = false;
        modelMenuExpanded = false;
        thinkingMenuExpanded = false;
    }

    function followReasoningBottom(): void {
        if (!root.followStreamingReasoningBottom)
            return;
        chatFlickable.followBottom = true;
        chatFlickable.stickToBottom();
        Qt.callLater(() => chatFlickable.stickToBottom());
    }

    onFooterReasoningTextChanged: {
        root.followReasoningBottom();
    }

    onFooterReasoningExpandedChanged: {
        root.followReasoningBottom();
    }

    onFooterReasoningClosingChanged: {
        root.followReasoningBottom();
    }

    function focusInput(): void {
        if (root.popouts.currentName !== "ai")
            return;

        root.forceActiveFocus();
        input.forceActiveFocus();
        Qt.callLater(() => {
            const targetPos = Math.max(0, Math.min(Opencode.draftCursorPosition, input.text.length));
            input.cursorPosition = targetPos;
        });
    }

    function sendMessage(): void {
        const value = input.text.trim();
        if (!Opencode.sendMessage(value))
            return;

        input.text = "";
        Opencode.draftInput = "";
        root.requestBottomScroll();
        root.focusInput();
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

    function formatRecordingTime(seconds: real): string {
        const total = Math.max(0, Math.floor(seconds));
        const mins = Math.floor(total / 60);
        const secs = total % 60;
        return `${mins}:${secs < 10 ? "0" : ""}${secs}`;
    }

    function extractCodeBlocks(text: string): var {
        const blocks = [];
        const regex = /```([^\n`]*)\n?([\s\S]*?)```/g;
        let match = null;

        while ((match = regex.exec(text)) !== null) {
            const code = (match[2] || "").trim();
            if (code.length > 0)
                blocks.push({
                    language: (match[1] || "").trim(),
                    code
                });
        }

        return blocks;
    }

    function removeCodeBlocks(text: string): string {
        return (text || "").replace(/```[^\n`]*\n?[\s\S]*?```/g, "").trim();
    }

    function cleanUserText(text: string): string {
        let value = (text || "")
            .replace(/\s*\[\[[\s\S]*?\]\]\s*/g, "\n")
            .replace(/^\s*\n+/, "")
            .replace(/\n+$/g, "")
            .trim();
        if (value.length >= 2 && value.startsWith("\"") && value.endsWith("\""))
            value = value.slice(1, -1);
        if (value.startsWith(">") || value.startsWith("@"))
            value = value.slice(1).trim();
        value = value.replace(/^\n+/, "");
        return value;
    }

    function cleanAssistantText(text: string): string {
        return (text || "").replace(/^\n+/g, "").replace(/\n+$/g, "").trim();
    }

    function simplifyInlineMath(text: string): string {
        function simplifySnippet(snippet) {
            return (snippet || "")
                .replace(/\\text\s*\{([^}]*)\}/g, "$1")
                .replace(/\\rightarrow/g, "→")
                .replace(/\\to\b/g, "→")
                .replace(/\\Leftarrow/g, "⇐")
                .replace(/\\Rightarrow/g, "⇒")
                .replace(/\\leftrightarrow/g, "↔")
                .replace(/\\cdot/g, "·")
                .replace(/\\times/g, "×")
                .replace(/\\left/g, "")
                .replace(/\\right/g, "")
                .replace(/\s+/g, " ")
                .trim();
        }

        return (text || "").replace(/\$([^$]+)\$/g, function(_, snippet) {
            return simplifySnippet(snippet);
        });
    }

    function formatToolErrorTitle(toolParts: var): string {
        if (toolParts && toolParts.length > 0) {
            const lastTool = toolParts[toolParts.length - 1] || {};
            const baseTitle = (lastTool.title || lastTool.tool || qsTr("Tool")).toString().trim();
            if (baseTitle.length > 0)
                return `${baseTitle}  Failed`;
        }
        return qsTr("Request Failed");
    }

    function toolHasError(tool: var): bool {
        const status = (tool?.status || "").toString().toLowerCase();
        const output = (tool?.output || "").toString().toLowerCase();
        const exitCode = tool?.exitCode;
        return status === "error"
            || status === "failed"
            || (typeof exitCode === "number" && exitCode !== 0)
            || output.includes("rejected permission")
            || output.includes("permission denied")
            || output.includes("failed");
    }

    function stripMarkdown(text: string): string {
        return (text || "")
            .replace(/```[^\n`]*\n?([\s\S]*?)```/g, "$1")
            .replace(/!\[([^\]]*)\]\([^)]+\)/g, "$1")
            .replace(/\[([^\]]+)\]\(([^)]+)\)/g, "$1")
            .replace(/^\s{0,3}#{1,6}\s+/gm, "")
            .replace(/^\s*[-*+]\s+/gm, "")
            .replace(/^\s*\d+\.\s+/gm, "")
            .replace(/[*_~`>]/g, "")
            .replace(/\n{3,}/g, "\n\n")
            .trim();
    }

    function copyText(value: string): void {
        Quickshell.clipboardText = value;
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
            onClicked: {
                onTap();
            }
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
        radius: Appearance.rounding.large
        color: Colours.palette.m3surfaceContainer

        Behavior on opacity {
            Anim {
                duration: Appearance.anim.durations.normal
            }
        }

        Behavior on scale {
            Anim {
                duration: Appearance.anim.durations.normal
                easing.bezierCurve: Appearance.anim.curves.standardDecel
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
            color: selected
                   ? Colours.palette.m3onSecondaryContainer
                   : Colours.palette.m3onSurface
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

    Timer {
        id: scrollTimer

        interval: 16
        onTriggered: {
            chatList.positionViewAtEnd();
            chatFlickable.contentY = Math.max(0, chatList.contentHeight - chatFlickable.height);
            chatFlickable.syncScrollState();
            root.pendingBottomScroll = false;
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Appearance.padding.normal
        Layout.leftMargin: Appearance.padding.small
        Layout.rightMargin: Appearance.padding.large
        spacing: Appearance.spacing.small
        z: 50

        StyledText {
            text: Opencode.currentModelLabel
            font.weight: 500
            font.pointSize: Appearance.font.size.large
            elide: Text.ElideRight
            maximumLineCount: 1
            Layout.maximumWidth: Math.max(100, root.width * 0.4)
        }

        StyledRect {
            implicitWidth: 1
            implicitHeight: 24
            Layout.leftMargin: 2
            Layout.rightMargin: 0
            radius: Appearance.rounding.full
            color: Qt.alpha(Colours.palette.m3outline, 0.45)
        }

        Item {
            Layout.fillWidth: true
        }

        StyledRect {
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

                    FloatingMenu {
                        visible: !Opencode.apiMode && opacity > 0
                        expanded: root.thinkingMenuExpanded
                        z: 1000
                        anchors.top: parent.bottom
                        anchors.right: parent.right
                        anchors.topMargin: Appearance.spacing.small
                        implicitWidth: 190
                        implicitHeight: Math.min(thinkingMenuColumn.implicitHeight, 8 * 42)

                        StyledFlickable {
                            id: thinkingMenuFlick

                            anchors.fill: parent
                            clip: true
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
                    shown: true

                    IconControl {
                        anchors.centerIn: parent
                        iconName: "chat_bubble"
                        active: root.chatMenuExpanded
                        onTap: () => {
                            root.chatMenuExpanded = !root.chatMenuExpanded;
                            root.permissionsMenuExpanded = false;
                            root.modelMenuExpanded = false;
                            root.thinkingMenuExpanded = false;
                        }
                    }

                    FloatingMenu {
                        expanded: root.chatMenuExpanded
                        z: 1000
                        anchors.top: parent.bottom
                        anchors.right: parent.right
                        anchors.topMargin: Appearance.spacing.small
                        implicitWidth: 250
                        implicitHeight: Math.min(chatMenuColumn.implicitHeight, 8 * 46)

                        StyledFlickable {
                            id: chatMenuFlick

                            anchors.fill: parent
                            clip: true
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
                                        x: newChatTap.containsMouse ? 2 : 0

                                        Behavior on x {
                                            Anim {
                                                duration: Appearance.anim.durations.small
                                                easing.bezierCurve: Appearance.anim.curves.standard
                                            }
                                        }

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
                                            x: hovered ? 2 : 0

                                            Behavior on x {
                                                Anim {
                                                    duration: Appearance.anim.durations.small
                                                    easing.bezierCurve: Appearance.anim.curves.standard
                                                }
                                            }

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
                }

                ControlSlot {
                    shown: true

                    IconControl {
                        anchors.centerIn: parent
                        iconName: "deployed_code"
                        active: root.modelMenuExpanded
                        onTap: () => {
                            root.modelMenuExpanded = !root.modelMenuExpanded;
                            root.permissionsMenuExpanded = false;
                            root.chatMenuExpanded = false;
                            root.thinkingMenuExpanded = false;
                        }
                    }

                    FloatingMenu {
                        expanded: root.modelMenuExpanded
                        z: 1000
                        anchors.top: parent.bottom
                        anchors.right: parent.right
                        anchors.topMargin: Appearance.spacing.small
                        implicitWidth: 220
                        implicitHeight: Math.min(modelMenuColumn.implicitHeight, 8 * 46)

                        StyledFlickable {
                            id: modelMenuFlick

                            anchors.fill: parent
                            clip: true
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

                                    Item {
                                        required property var modelData
                                        readonly property bool isProviderHeader: ((modelData && modelData.type) || "") === "provider"
                                        implicitWidth: parent ? parent.width : 220
                                        implicitHeight: isProviderHeader ? 30 : 46

                                        StyledText {
                                            visible: parent.isProviderHeader
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.leftMargin: Appearance.padding.normal + 4
                                            anchors.rightMargin: Appearance.padding.normal
                                            text: modelData && modelData.label ? modelData.label : ""
                                            font.pointSize: Appearance.font.size.small
                                            font.weight: 500
                                            color: Qt.alpha(Colours.palette.m3onSurfaceVariant, 0.75)
                                        }

                                        StyledRect {
                                            visible: !parent.isProviderHeader
                                            anchors.fill: parent
                                            property bool hovered: modelOptionTap.containsMouse
                                            color: modelData.id === Opencode.selectedModel
                                                   ? Colours.palette.m3secondaryContainer
                                                   : hovered
                                                     ? Qt.alpha(Colours.palette.m3secondaryContainer, 0.12)
                                                     : "transparent"

                                            Behavior on color {
                                                CAnim {}
                                            }

                                            MouseArea {
                                                id: modelOptionTap

                                                anchors.fill: parent
                                                hoverEnabled: true
                                                onClicked: {
                                                    Opencode.selectModel(modelData.id);
                                                    root.modelMenuExpanded = false;
                                                }
                                            }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: Appearance.padding.normal + 4
                                                anchors.rightMargin: Appearance.padding.normal
                                                spacing: Appearance.spacing.small
                                                x: parent.hovered ? 2 : 0

                                                Behavior on x {
                                                    Anim {
                                                        duration: Appearance.anim.durations.small
                                                        easing.bezierCurve: Appearance.anim.curves.standard
                                                    }
                                                }

                                                MaterialIcon {
                                                    text: "deployed_code"
                                                    color: modelData.id === Opencode.selectedModel
                                                           ? Colours.palette.m3onSecondaryContainer
                                                           : Colours.palette.m3onSurfaceVariant
                                                }

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: modelData.label
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
                    }
                }
            }
        }
    }

    StyledClippingRect {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: 500
        Layout.minimumHeight: 500
        Layout.leftMargin: Appearance.padding.small
        Layout.rightMargin: Appearance.padding.large
        color: "transparent"
        radius: Appearance.rounding.large

        StyledFlickable {
            id: chatFlickable

            property real scrollTargetY: 0
            readonly property real wheelStep: Math.max(80, height * 0.18)
            property bool followBottom: true

            function maxScrollY(): real {
                return Math.max(0, contentHeight - height);
            }

            function isNearBottom(): bool {
                return maxScrollY() - contentY <= 6;
            }

            function clampScrollTarget(value: real): real {
                return Math.max(0, Math.min(maxScrollY(), value));
            }

            function syncScrollTarget(): void {
                scrollTargetY = clampScrollTarget(contentY);
            }

            function syncScrollbarPosition(): void {
                const maxContentY = maxScrollY();
                const size = contentHeight > height && contentHeight > 0 ? Math.max(0, Math.min(1, height / contentHeight)) : 1;
                const maxPos = 1 - size;
                const pos = maxContentY > 0 && maxPos > 0 ? (contentY / maxContentY) * maxPos : 0;
                chatScrollBar.animating = false;
                chatScrollBar.nonAnimPosition = pos;
            }

            function syncScrollState(): void {
                syncScrollTarget();
                syncScrollbarPosition();
            }

            function stickToBottom(): void {
                const bottom = maxScrollY();
                followBottom = true;
                scrollTargetY = bottom;
                contentY = bottom;
                syncScrollbarPosition();
            }

            function scrollBy(delta: real): void {
                syncScrollTarget();
                const bottom = maxScrollY();
                if (followBottom)
                    scrollTargetY = bottom;
                if (delta < 0 && scrollTargetY <= 0.5) {
                    scrollTargetY = 0;
                    contentY = 0;
                    syncScrollbarPosition();
                    return;
                }
                if (followBottom && delta > 0 && Opencode.busy) {
                    stickToBottom();
                    return;
                }
                if (!followBottom && delta > 0 && Opencode.busy && scrollTargetY >= bottom - 0.5) {
                    stickToBottom();
                    return;
                }
                scrollTargetY = clampScrollTarget(scrollTargetY + delta);
                followBottom = scrollTargetY >= bottom - 6;
                if (!followBottom)
                    root.followStreamingReasoningBottom = false;
                contentY = scrollTargetY;
            }

            anchors.fill: parent
            anchors.leftMargin: Appearance.padding.small
            anchors.rightMargin: Appearance.padding.small
            anchors.topMargin: Appearance.padding.small
            anchors.bottomMargin: Appearance.padding.small
            clip: true
            contentHeight: chatList.contentHeight
            boundsBehavior: Flickable.StopAtBounds

            Behavior on contentY {
                enabled: !chatFlickable.dragging && !chatFlickable.flicking && !chatScrollBar.pressed

                Anim {
                    duration: 260
                    easing.bezierCurve: Appearance.anim.curves.standardDecel
                }
            }

            onDraggingChanged: {
                if (!dragging) {
                    syncScrollState();
                    followBottom = isNearBottom();
                    if (!followBottom)
                        root.followStreamingReasoningBottom = false;
                }
            }

            onFlickingChanged: {
                if (!flicking) {
                    syncScrollState();
                    followBottom = isNearBottom();
                    if (!followBottom)
                        root.followStreamingReasoningBottom = false;
                }
            }

            onMovementEnded: {
                syncScrollState();
                followBottom = isNearBottom();
                if (!followBottom)
                    root.followStreamingReasoningBottom = false;
            }
            onContentYChanged: {
                if (!dragging && !flicking && !chatScrollBar.pressed) {
                    followBottom = isNearBottom();
                    if (!followBottom)
                        root.followStreamingReasoningBottom = false;
                }
            }
            onContentHeightChanged: {
                if (!dragging && !flicking && !chatScrollBar.pressed && followBottom && Opencode.busy) {
                    stickToBottom();
                    return;
                }

                scrollTargetY = clampScrollTarget(scrollTargetY);
                if (!dragging && !flicking && !chatScrollBar.pressed) {
                    contentY = scrollTargetY;
                    syncScrollbarPosition();
                }
            }
            onHeightChanged: {
                if (!dragging && !flicking && !chatScrollBar.pressed && followBottom && Opencode.busy) {
                    stickToBottom();
                    return;
                }

                scrollTargetY = clampScrollTarget(scrollTargetY);
                if (!dragging && !flicking && !chatScrollBar.pressed) {
                    contentY = scrollTargetY;
                    syncScrollbarPosition();
                }
            }
            Component.onCompleted: syncScrollState()

            StyledScrollBar.vertical: StyledScrollBar {
                id: chatScrollBar

                flickable: chatFlickable
                policy: ScrollBar.AsNeeded
                shouldBeActive: chatScrollReveal.running || hovered || flickable.moving
                z: 4
                anchors.right: parent.right
                anchors.rightMargin: 0
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                implicitWidth: Math.max(4, Appearance.padding.small)

                onPressedChanged: {
                    if (!pressed) {
                        chatFlickable.syncScrollState();
                        chatFlickable.followBottom = chatFlickable.isNearBottom();
                        if (!chatFlickable.followBottom)
                            root.followStreamingReasoningBottom = false;
                    }
                }
            }

            Timer {
                id: chatScrollReveal

                interval: 700
            }

            CustomMouseArea {
                id: chatWheelArea

                anchors.fill: parent
                anchors.rightMargin: chatScrollBar.implicitWidth + Appearance.padding.small
                acceptedButtons: Qt.NoButton
                propagateComposedEvents: true
                z: 1

                function onEntered(): void {
                    if (chatFlickable.followBottom)
                        chatFlickable.stickToBottom();
                }

                function onWheel(wheel: WheelEvent): void {
                    const magnitude = Math.max(Math.abs(wheel.angleDelta.y), Math.abs(wheel.pixelDelta.y));
                    const notches = Math.max(1, Math.round(magnitude / 120));
                    chatScrollReveal.restart();
                    if (wheel.angleDelta.y > 0 || wheel.pixelDelta.y > 0)
                        chatFlickable.scrollBy(-chatFlickable.wheelStep * notches);
                    else if (wheel.angleDelta.y < 0 || wheel.pixelDelta.y < 0)
                        chatFlickable.scrollBy(chatFlickable.wheelStep * notches);
                }
            }

            ListView {
                id: chatList

                anchors.fill: parent
                anchors.rightMargin: chatScrollBar.implicitWidth + Appearance.padding.small
                spacing: Appearance.spacing.normal
                model: Opencode.allMessages
                onCountChanged: {
                    if (root.pendingBottomScroll || (Opencode.busy && chatFlickable.followBottom))
                        root.scrollToLatest();
                }
                footerPositioning: ListView.InlineFooter
                footer: Column {
                    width: chatList.width
                    spacing: Appearance.spacing.small

                    Item {
                        width: 1
                        height: Appearance.spacing.large + 2
                        visible: Opencode.busy
                    }

                    Item {
                        width: parent.width
                        height: waitingForReplyLabel.implicitHeight
                        visible: opacity > 0 || height > 0
                        opacity: Opencode.busy && root.footerReasoningText.length === 0 ? 1 : 0
                        implicitHeight: Opencode.busy && root.footerReasoningText.length === 0 ? waitingForReplyLabel.implicitHeight : 0

                        Behavior on opacity {
                            Anim {
                                duration: Appearance.anim.durations.large
                                easing.bezierCurve: Appearance.anim.curves.emphasizedDecel
                            }
                        }

                        Behavior on implicitHeight {
                            Anim {
                                duration: Appearance.anim.durations.large
                                easing.bezierCurve: Appearance.anim.curves.emphasizedDecel
                            }
                        }

                        StyledText {
                            id: waitingForReplyLabel

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("Waiting for reply...")
                            color: Qt.alpha(Colours.palette.m3onSurfaceVariant, 0.65)
                            wrapMode: Text.WordWrap
                            font.pointSize: Appearance.font.size.normal
                        }
                    }

                    StyledClippingRect {
                        width: parent.width
                        visible: root.footerReasoningVisible
                        implicitHeight: root.footerReasoningExpanded
                                        ? footerReasoningBody.implicitHeight + footerReasoningHeader.implicitHeight + Appearance.padding.normal * 2 + Appearance.spacing.small
                                        : footerReasoningClosing
                                          ? footerReasoningHeader.implicitHeight + Appearance.padding.normal * 2
                                          : 0
                        radius: Appearance.rounding.large
                        color: Qt.alpha(Colours.palette.m3surfaceContainerHighest, 0.12)
                        opacity: root.footerReasoningVisible ? 1 : 0
                        scale: footerReasoningClosing ? 0.992 : 1

                        Behavior on implicitHeight {
                            Anim {
                                duration: Appearance.anim.durations.large + 80
                                easing.bezierCurve: Appearance.anim.curves.emphasizedDecel
                            }
                        }

                        Behavior on opacity {
                            Anim {
                                duration: Appearance.anim.durations.large + 80
                                easing.bezierCurve: Appearance.anim.curves.emphasizedDecel
                            }
                        }

                        Behavior on scale {
                            Anim {
                                duration: Appearance.anim.durations.large + 80
                                easing.bezierCurve: Appearance.anim.curves.emphasizedDecel
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Appearance.padding.normal
                            spacing: Appearance.spacing.small

                            RowLayout {
                                id: footerReasoningHeader

                                Layout.fillWidth: true
                                spacing: Appearance.spacing.small

                                MaterialIcon {
                                    text: root.footerReasoningExpanded ? "keyboard_arrow_down" : "keyboard_arrow_right"
                                    color: Qt.alpha(Colours.palette.m3onSurfaceVariant, 0.76)
                                    font.pointSize: Appearance.font.size.small
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: qsTr("Reasoning")
                                    color: Qt.alpha(Colours.palette.m3onSurfaceVariant, 0.72)
                                    font.pointSize: Appearance.font.size.small
                                }
                            }

                            Item {
                                id: footerReasoningBody

                                Layout.fillWidth: true
                                implicitHeight: busyReasoningText.implicitHeight
                                visible: opacity > 0
                                opacity: root.footerReasoningExpanded ? 1 : 0

                                Behavior on opacity {
                                    Anim {
                                        duration: Appearance.anim.durations.normal + 80
                                        easing.bezierCurve: Appearance.anim.curves.emphasizedDecel
                                    }
                                }

                                StyledText {
                                    id: busyReasoningText

                                    anchors.fill: parent
                                    text: root.simplifyInlineMath(root.footerReasoningText)
                                    wrapMode: Text.WordWrap
                                    font.pointSize: Appearance.font.size.small
                                    color: Qt.alpha(Colours.palette.m3onSurfaceVariant, 0.62)
                                }
                            }
                        }
                    }
                }

                add: Transition {
                    ParallelAnimation {
                        NumberAnimation {
                            property: "opacity"
                            from: 0
                            to: 1
                            duration: Appearance.anim.durations.large + 40
                            easing.bezierCurve: Appearance.anim.curves.emphasizedDecel
                        }
                        NumberAnimation {
                            property: "y"
                            from: 18
                            to: 0
                            duration: Appearance.anim.durations.large + 40
                            easing.bezierCurve: Appearance.anim.curves.emphasizedDecel
                        }
                        NumberAnimation {
                            property: "scale"
                            from: 0.975
                            to: 1
                            duration: Appearance.anim.durations.large + 40
                            easing.bezierCurve: Appearance.anim.curves.emphasizedDecel
                        }
                    }
                }

                delegate: Item {
                    id: chatDelegate

                    required property var modelData

                    readonly property string roleName: modelData.role ?? "assistant"
                    readonly property string messageText: modelData.text ?? ""
                    readonly property string displayText: roleName === "user"
                                                           ? root.cleanUserText(messageText)
                                                           : root.cleanAssistantText(messageText)
                    readonly property var messageAttachments: modelData.attachments ?? []
                    readonly property var codeBlocks: root.extractCodeBlocks(messageText)
                    readonly property var toolParts: modelData.tools ?? []
                    readonly property string reasoningText: modelData.reasoningText ?? ""
                    readonly property string assistantBodyText: root.removeCodeBlocks(displayText)
                    readonly property string assistantErrorText: modelData.error ?? ""
                    readonly property string assistantVisibleBodyText: assistantErrorText.length > 0
                                                                       && assistantBodyText === assistantErrorText
                                                                       ? ""
                                                                       : root.simplifyInlineMath(assistantBodyText)
                    readonly property int assistantTextFormat: Text.MarkdownText
                    readonly property bool isLiveAssistant: roleName === "assistant"
                                                            && Opencode.streamingCreated > 0
                                                            && (modelData.created ?? -1) === Opencode.streamingCreated
                    readonly property bool isFreshCompletedAssistant: roleName === "assistant"
                                                                      && !isLiveAssistant
                                                                      && (modelData.created ?? 0) === root.highlightedAssistantCreated
                    property real copyFlash: 0
                    property bool reasoningExpanded: false
                    property int revealCount: assistantVisibleBodyText.length
                    readonly property bool revealInProgress: false
                    property real finalAppearProgress: 1

                    width: chatList.width
                    implicitHeight: roleName === "user"
                                    ? bubble.implicitHeight
                                    : roleName === "system"
                                      ? systemText.implicitHeight
                                      : roleName === "thinking"
                                        ? thinkingColumn.implicitHeight
                                      : assistantColumn.implicitHeight
                    opacity: 1
                    scale: 1

                    NumberAnimation {
                        id: finalAppearAnim

                        target: chatDelegate
                        property: "finalAppearProgress"
                        from: 0
                        to: 1
                        duration: Appearance.anim.durations.extraLarge + 140
                        easing.bezierCurve: Appearance.anim.curves.emphasizedDecel
                    }

                    StyledText {
                        id: bubbleMeasureText

                        visible: false
                        text: roleName === "user" ? displayText : ""
                        wrapMode: Text.NoWrap
                        font.pointSize: Appearance.font.size.normal
                    }

                    StyledRect {
                        id: bubble

                        visible: roleName === "user"
                        anchors.right: parent.right
                        width: Math.min(parent.width * 0.78, Math.max(88, bubbleMeasureText.implicitWidth + Appearance.padding.large * 2))
                        implicitHeight: bubbleColumn.implicitHeight + Appearance.padding.normal * 2
                        radius: Appearance.rounding.normal * 0.9
                        color: Colours.palette.m3primaryContainer

                        ColumnLayout {
                            id: bubbleColumn

                            anchors.fill: parent
                            anchors.margins: Appearance.padding.normal
                            spacing: Appearance.spacing.small

                            StyledText {
                                id: bubbleText

                                Layout.fillWidth: true
                                text: roleName === "user" ? displayText : ""
                                wrapMode: Text.Wrap
                                font.pointSize: Appearance.font.size.normal
                                lineHeight: 1.05
                                color: Colours.palette.m3onPrimaryContainer
                            }

                                Repeater {
                                    model: messageAttachments

                                    StyledRect {
                                        required property var modelData

                                        radius: Appearance.rounding.full
                                        color: Qt.alpha(Colours.palette.m3onPrimaryContainer, 0.12)
                                        implicitWidth: Math.min(bubble.width - Appearance.padding.normal * 2, attachBubbleRow.implicitWidth + Appearance.padding.normal * 2)
                                        implicitHeight: attachBubbleRow.implicitHeight + Appearance.padding.small

                                        RowLayout {
                                            id: attachBubbleRow

                                            anchors.fill: parent
                                            anchors.leftMargin: Appearance.padding.normal
                                            anchors.rightMargin: Appearance.padding.normal
                                            spacing: Appearance.spacing.small

                                            MaterialIcon {
                                                text: "image"
                                                font.pointSize: Appearance.font.size.small
                                            color: Colours.palette.m3onPrimaryContainer
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: (modelData.split("/").pop() || modelData)
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                            font.pointSize: Appearance.font.size.small
                                            color: Colours.palette.m3onPrimaryContainer
                                        }
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        id: systemText

                        visible: roleName === "system"
                        anchors.left: parent.left
                        anchors.right: parent.right
                        text: messageText
                        wrapMode: Text.WordWrap
                        font.pointSize: Appearance.font.size.small
                        color: Qt.alpha(Colours.palette.m3onSurfaceVariant, 0.78)
                    }

                    ColumnLayout {
                        id: thinkingColumn
                        visible: roleName === "thinking"
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: Appearance.spacing.small

                        StyledRect {
                            Layout.fillWidth: true
                            implicitHeight: 34
                            radius: Appearance.rounding.full
                            color: "transparent"

                            MouseArea {
                                anchors.fill: parent
                                onClicked: chatDelegate.reasoningExpanded = !chatDelegate.reasoningExpanded
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Appearance.padding.normal
                                anchors.rightMargin: Appearance.padding.normal
                                spacing: Appearance.spacing.small

                                MaterialIcon {
                                    text: chatDelegate.reasoningExpanded ? "keyboard_arrow_down" : "keyboard_arrow_right"
                                    color: Qt.alpha(Colours.palette.m3onSurfaceVariant, 0.82)
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: qsTr("Reasoning")
                                    color: Qt.alpha(Colours.palette.m3onSurfaceVariant, 0.78)
                                    font.pointSize: Appearance.font.size.small
                                }
                            }
                        }

                        StyledClippingRect {
                            Layout.fillWidth: true
                            implicitHeight: chatDelegate.reasoningExpanded ? thinkingText.implicitHeight + Appearance.padding.normal * 2 : 0
                            opacity: chatDelegate.reasoningExpanded ? 1 : 0
                            radius: Appearance.rounding.large
                            color: Qt.alpha(Colours.palette.m3surfaceContainerHighest, 0.12)

                            Behavior on implicitHeight {
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

                            StyledText {
                                id: thinkingText

                                anchors.fill: parent
                                anchors.margins: Appearance.padding.normal
                                text: root.simplifyInlineMath(messageText)
                                wrapMode: Text.WordWrap
                                font.pointSize: Appearance.font.size.small
                                color: Qt.alpha(Colours.palette.m3onSurfaceVariant, 0.56)
                            }
                        }
                    }

                    ColumnLayout {
                        id: assistantColumn

                        visible: roleName === "assistant"
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: Appearance.spacing.small

                        StyledRect {
                            Layout.fillWidth: true
                            visible: reasoningText.length > 0
                            implicitHeight: 34
                            radius: Appearance.rounding.full
                            color: "transparent"

                            MouseArea {
                                anchors.fill: parent
                                onClicked: chatDelegate.reasoningExpanded = !chatDelegate.reasoningExpanded
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Appearance.padding.normal
                                anchors.rightMargin: Appearance.padding.normal
                                spacing: Appearance.spacing.small

                                MaterialIcon {
                                    text: chatDelegate.reasoningExpanded ? "keyboard_arrow_down" : "keyboard_arrow_right"
                                    color: Qt.alpha(Colours.palette.m3onSurfaceVariant, 0.82)
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: qsTr("Reasoning")
                                    color: Qt.alpha(Colours.palette.m3onSurfaceVariant, 0.78)
                                    font.pointSize: Appearance.font.size.small
                                }
                            }
                        }

                        StyledClippingRect {
                            Layout.fillWidth: true
                            visible: reasoningText.length > 0
                            implicitHeight: chatDelegate.reasoningExpanded ? finalReasoningText.implicitHeight + Appearance.padding.normal * 2 : 0
                            opacity: chatDelegate.reasoningExpanded ? 1 : 0
                            radius: Appearance.rounding.large
                            color: Qt.alpha(Colours.palette.m3surfaceContainerHighest, 0.12)

                            Behavior on implicitHeight {
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

                            StyledText {
                                id: finalReasoningText

                                anchors.fill: parent
                                anchors.margins: Appearance.padding.normal
                                text: root.simplifyInlineMath(reasoningText)
                                wrapMode: Text.WordWrap
                                font.pointSize: Appearance.font.size.small
                                color: Qt.alpha(Colours.palette.m3onSurfaceVariant, 0.56)
                            }
                        }

                        Repeater {
                            model: toolParts

                            StyledRect {
                                required property var modelData
                                property real enterProgress: 0
                                readonly property bool isErrorTool: root.toolHasError(modelData)

                                Layout.fillWidth: true
                                implicitHeight: toolColumn.implicitHeight + Appearance.padding.normal * 2
                                radius: Appearance.rounding.large
                                color: isErrorTool
                                       ? Qt.alpha(Colours.palette.m3error, 0.06)
                                       : Qt.alpha(Colours.palette.m3surfaceContainerHighest, 0.16)
                                opacity: enterProgress
                                scale: 0.96 + enterProgress * 0.04

                                NumberAnimation on enterProgress {
                                    from: 0
                                    to: 1
                                    duration: Appearance.anim.durations.normal
                                    easing.bezierCurve: Appearance.anim.curves.standardDecel
                                }

                                ColumnLayout {
                                    id: toolColumn

                                    anchors.fill: parent
                                    anchors.margins: Appearance.padding.normal
                                    spacing: Appearance.spacing.small

                                    Item {
                                        Layout.fillWidth: true
                                        implicitHeight: toolChip.implicitHeight

                                        StyledRect {
                                            id: toolChip

                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            radius: Appearance.rounding.full
                                            color: isErrorTool
                                                   ? Qt.alpha(Colours.palette.m3error, 0.14)
                                                   : Qt.alpha(Colours.palette.m3secondaryContainer, 0.18)
                                            width: Math.min(
                                                       toolChipIcon.implicitWidth
                                                       + Appearance.spacing.small
                                                       + toolChipText.implicitWidth
                                                       + Appearance.padding.normal * 2,
                                                       parent.width
                                                   )
                                            implicitHeight: Math.max(toolChipIcon.implicitHeight, toolChipText.implicitHeight) + Appearance.padding.small

                                            MaterialIcon {
                                                id: toolChipIcon

                                                anchors.left: parent.left
                                                anchors.leftMargin: Appearance.padding.normal
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: modelData.tool === "bash" ? "terminal" : "data_object"
                                                font.pointSize: Appearance.font.size.small
                                                color: isErrorTool
                                                       ? Colours.palette.m3error
                                                       : Colours.palette.m3onSecondaryContainer
                                            }

                                            StyledText {
                                                id: toolChipText

                                                anchors.left: toolChipIcon.right
                                                anchors.leftMargin: Appearance.spacing.small
                                                anchors.right: parent.right
                                                anchors.rightMargin: Appearance.padding.normal
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: isErrorTool
                                                      ? `${modelData.title || modelData.tool || qsTr("Tool")}  Failed`
                                                      : (modelData.title || modelData.tool || qsTr("Tool"))
                                                font.pointSize: Appearance.font.size.small
                                                color: isErrorTool
                                                       ? Colours.palette.m3error
                                                       : Colours.palette.m3onSecondaryContainer
                                                elide: Text.ElideRight
                                                maximumLineCount: 1
                                            }
                                        }
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        visible: (modelData.command || "").length > 0
                                        text: modelData.command || ""
                                        font.family: "monospace"
                                        font.pointSize: Appearance.font.size.small
                                        wrapMode: Text.WordWrap
                                        color: Qt.alpha(Colours.palette.m3onSurfaceVariant, 0.84)
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        visible: (modelData.output || "").length > 0
                                        text: (modelData.output || "").trim()
                                        font.family: "monospace"
                                        font.pointSize: Appearance.font.size.small
                                        wrapMode: Text.WordWrap
                                        color: isErrorTool
                                               ? Qt.alpha(Colours.palette.m3onSurface, 0.92)
                                               : Qt.alpha(Colours.palette.m3onSurfaceVariant, 0.72)
                                    }
                                }
                            }
                        }

                        StyledClippingRect {
                            Layout.fillWidth: true
                            visible: assistantErrorText.length > 0
                            implicitHeight: errorColumn.implicitHeight + Appearance.padding.normal * 2
                            radius: Appearance.rounding.large
                            color: Qt.alpha(Colours.palette.m3error, 0.06)

                            ColumnLayout {
                                id: errorColumn

                                anchors.fill: parent
                                anchors.margins: Appearance.padding.normal
                                spacing: Appearance.spacing.small

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Appearance.spacing.small

                                    MaterialIcon {
                                        text: "do_not_disturb_on"
                                        color: Colours.palette.m3error
                                        font.pointSize: Appearance.font.size.normal
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: root.formatToolErrorTitle(toolParts)
                                        color: Colours.palette.m3onSurface
                                        font.pointSize: Appearance.font.size.normal
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }

                                    MaterialIcon {
                                        text: "keyboard_arrow_down"
                                        color: Qt.alpha(Colours.palette.m3onSurfaceVariant, 0.72)
                                        font.pointSize: Appearance.font.size.small
                                    }
                                }

                                StyledRect {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: Appearance.padding.normal + 4
                                    implicitHeight: Math.max(errorText.implicitHeight + Appearance.padding.small * 2, 36)
                                    radius: Appearance.rounding.normal
                                    color: Qt.alpha(Colours.palette.m3error, 0.08)

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.leftMargin: -(Appearance.padding.small + 2)
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        width: 2
                                        color: Qt.alpha(Colours.palette.m3error, 0.9)
                                    }

                                    StyledText {
                                        id: errorText

                                        anchors.fill: parent
                                        anchors.leftMargin: 9
                                        anchors.rightMargin: Appearance.padding.normal + 2
                                        anchors.topMargin: Appearance.padding.small + 1
                                        anchors.bottomMargin: Appearance.padding.small + 1
                                        text: assistantErrorText
                                        wrapMode: Text.Wrap
                                        color: Qt.alpha(Colours.palette.m3onSurface, 0.92)
                                        font.pointSize: Appearance.font.size.normal
                                    }
                                }
                            }
                        }

                        StyledRect {
                            Layout.fillWidth: true
                            visible: assistantVisibleBodyText.length > 0
                            implicitHeight: (chatDelegate.isLiveAssistant ? liveAssistantText.implicitHeight : assistantText.implicitHeight) + Appearance.padding.small * 2
                            radius: Appearance.rounding.large
                            color: Qt.alpha(Colours.palette.m3secondaryContainer, copyFlash * 0.24)
                            opacity: finalAppearProgress
                            scale: (assistantCopyTap.pressed ? 0.988 : 1) * (0.975 + finalAppearProgress * 0.025)

                            Behavior on scale {
                                Anim {
                                    duration: Appearance.anim.durations.small
                                    easing.bezierCurve: Appearance.anim.curves.standard
                                }
                            }

                            Behavior on opacity {
                                Anim {
                                    duration: Appearance.anim.durations.extraLarge + 120
                                    easing.bezierCurve: Appearance.anim.curves.emphasizedDecel
                                }
                            }

                            StyledText {
                                id: liveAssistantText

                                visible: chatDelegate.isLiveAssistant
                                anchors.fill: parent
                                anchors.margins: Appearance.padding.small
                                text: roleName === "assistant" ? assistantVisibleBodyText : ""
                                wrapMode: Text.Wrap
                                textFormat: Text.MarkdownText
                                font.pointSize: Appearance.font.size.normal
                                color: Colours.palette.m3onSurface
                            }

                            TextEdit {
                                id: assistantText

                                visible: !chatDelegate.isLiveAssistant
                                anchors.fill: parent
                                anchors.margins: Appearance.padding.small
                                text: roleName === "assistant"
                                      ? (chatDelegate.revealInProgress
                                         ? assistantVisibleBodyText.slice(0, revealCount)
                                         : assistantVisibleBodyText)
                                      : ""
                                readOnly: true
                                wrapMode: TextEdit.Wrap
                                selectByMouse: true
                                activeFocusOnPress: true
                                textFormat: chatDelegate.assistantTextFormat
                                font.pointSize: Appearance.font.size.normal
                                color: Colours.palette.m3onSurface
                                selectionColor: Qt.alpha(Colours.palette.m3secondaryContainer, 0.82)
                                selectedTextColor: Colours.palette.m3onSecondaryContainer

                                onActiveFocusChanged: {
                                    if (!activeFocus)
                                        chatFlickable.interactive = true;
                                }

                                Component.onCompleted: {
                                    cursorPosition = 0;
                                }
                            }

                            MouseArea {
                                id: assistantCopyTap

                                anchors.fill: parent
                                acceptedButtons: Qt.RightButton | Qt.MiddleButton
                                propagateComposedEvents: true

                                onClicked: mouse => {
                                    root.copyText(mouse.button === Qt.MiddleButton
                                                  ? root.stripMarkdown(messageText)
                                                  : messageText);

                                    copyFlash = 1;
                                    copyFlashAnim.restart();
                                }
                            }
                        }

                        Repeater {
                            model: codeBlocks

                            StyledRect {
                                required property var modelData
                                property real enterProgress: 0

                                Layout.fillWidth: true
                                implicitHeight: codeColumn.implicitHeight + Appearance.padding.normal * 2
                                radius: Appearance.rounding.large
                                color: Qt.alpha(Colours.palette.m3surfaceContainerHighest, 0.2)
                                opacity: enterProgress
                                scale: 0.96 + enterProgress * 0.04

                                NumberAnimation on enterProgress {
                                    from: 0
                                    to: 1
                                    duration: Appearance.anim.durations.normal
                                    easing.bezierCurve: Appearance.anim.curves.standardDecel
                                }

                                ColumnLayout {
                                    id: codeColumn

                                    anchors.fill: parent
                                    anchors.margins: Appearance.padding.normal
                                    spacing: Appearance.spacing.small

                                    Item {
                                        Layout.fillWidth: true
                                        implicitHeight: Math.max(codeCopyButton.implicitHeight, (modelData.language || "").length > 0 ? codeLanguageChip.implicitHeight : 0)

                                        StyledRect {
                                            id: codeLanguageChip

                                            visible: (modelData.language || "").length > 0
                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            radius: Appearance.rounding.full
                                            color: Qt.alpha(Colours.palette.m3secondaryContainer, 0.14)
                                            width: Math.min(
                                                       codeLanguageLabel.implicitWidth + Appearance.padding.normal * 2,
                                                       Math.max(0, parent.width - codeCopyButton.implicitWidth - Appearance.spacing.small)
                                                   )
                                            implicitHeight: codeLanguageLabel.implicitHeight + Appearance.padding.small

                                            StyledText {
                                                id: codeLanguageLabel

                                                anchors.left: parent.left
                                                anchors.leftMargin: Appearance.padding.normal
                                                anchors.right: parent.right
                                                anchors.rightMargin: Appearance.padding.normal
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: modelData.language || ""
                                                font.pointSize: Appearance.font.size.small
                                                color: Qt.alpha(Colours.palette.m3onSurfaceVariant, 0.82)
                                                elide: Text.ElideRight
                                                maximumLineCount: 1
                                            }
                                        }

                                        StyledRect {
                                            id: codeCopyButton

                                            property bool hovered: codeCopyTap.containsMouse
                                            property bool pressed: codeCopyTap.pressed

                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            radius: Appearance.rounding.full
                                            color: pressed
                                                   ? Qt.alpha(Colours.palette.m3secondaryContainer, 0.34)
                                                   : hovered
                                                     ? Qt.alpha(Colours.palette.m3secondaryContainer, 0.26)
                                                     : Qt.alpha(Colours.palette.m3secondaryContainer, 0.16)
                                            implicitWidth: codeCopyRow.implicitWidth + Appearance.padding.normal * 2
                                            implicitHeight: codeCopyRow.implicitHeight + Appearance.padding.small
                                            scale: pressed ? 0.97 : hovered ? 1.02 : 1

                                            Behavior on color {
                                                CAnim {}
                                            }

                                            Behavior on scale {
                                                Anim {
                                                    duration: Appearance.anim.durations.small
                                                    easing.bezierCurve: Appearance.anim.curves.standard
                                                }
                                            }

                                            MouseArea {
                                                id: codeCopyTap

                                                anchors.fill: parent
                                                hoverEnabled: true
                                                onClicked: root.copyText(modelData.code)
                                            }

                                            RowLayout {
                                                id: codeCopyRow

                                                anchors.centerIn: parent
                                                spacing: Appearance.spacing.small
                                                x: codeCopyButton.pressed ? 0 : codeCopyButton.hovered ? 1 : 0

                                                Behavior on x {
                                                    Anim {
                                                        duration: Appearance.anim.durations.small
                                                        easing.bezierCurve: Appearance.anim.curves.standard
                                                    }
                                                }

                                                MaterialIcon {
                                                    text: "content_copy"
                                                    font.pointSize: Appearance.font.size.small
                                                    color: Colours.palette.m3onSecondaryContainer
                                                }

                                                StyledText {
                                                    text: qsTr("Copy")
                                                    font.pointSize: Appearance.font.size.small
                                                    color: Colours.palette.m3onSecondaryContainer
                                                }
                                            }
                                        }
                                    }

                                    StyledClippingRect {
                                        Layout.fillWidth: true
                                        implicitHeight: Math.min(codeText.contentHeight + Appearance.padding.normal * 2, 220)
                                        radius: Appearance.rounding.large
                                        color: Qt.alpha(Colours.palette.m3surface, 0.16)

                                        Flickable {
                                            anchors.fill: parent
                                            anchors.margins: Appearance.padding.small
                                            contentWidth: codeText.paintedWidth
                                            contentHeight: codeText.paintedHeight
                                            clip: true

                                            StyledScrollBar.horizontal: StyledScrollBar {
                                                flickable: parent
                                            }

                                            StyledText {
                                                id: codeText

                                                text: modelData.code
                                                wrapMode: Text.NoWrap
                                                font.family: "monospace"
                                                font.pointSize: Appearance.font.size.small
                                                color: Colours.palette.m3onSurface
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    NumberAnimation {
                        id: copyFlashAnim

                        target: chatDelegate
                        property: "copyFlash"
                        from: 1
                        to: 0
                        duration: Appearance.anim.durations.large
                        easing.bezierCurve: Appearance.anim.curves.standardDecel
                    }

                    onAssistantVisibleBodyTextChanged: revealCount = assistantVisibleBodyText.length

                    onIsFreshCompletedAssistantChanged: {
                        if (isFreshCompletedAssistant) {
                            finalAppearProgress = 0;
                            finalAppearAnim.restart();
                        }
                    }

                    Component.onCompleted: {
                        revealCount = assistantVisibleBodyText.length;
                        if (isFreshCompletedAssistant) {
                            finalAppearProgress = 0;
                            finalAppearAnim.restart();
                        }
                    }
                }
            }
        }

        MaterialIcon {
            anchors.centerIn: parent
            visible: !Opencode.busy && Opencode.allMessages.length === 0
            text: "wand_stars"
            font.pointSize: 48
            color: Qt.alpha(Colours.palette.m3onSurfaceVariant, 0.26)
        }

        MouseArea {
            anchors.fill: parent
            visible: root.menuOpen
            z: 900
            onClicked: root.closeMenus()
        }

    }

        RowLayout {
            Layout.fillWidth: true
            visible: Opencode.attachments.length > 0
            Layout.leftMargin: Appearance.padding.small
            Layout.rightMargin: Appearance.padding.large
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
            Layout.leftMargin: Appearance.padding.small
            Layout.rightMargin: Appearance.padding.large
            Layout.bottomMargin: Appearance.padding.normal
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
            implicitHeight: Math.max(48, Math.min(input.contentHeight + Appearance.padding.normal * 2 + 6, 86))
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

                MaterialIcon {
                    id: transcribeIcon

                    text: "progress_activity"
                    fill: 1
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
                    opacity: 0.78

                    SequentialAnimation on opacity {
                        running: SpeechToText.transcribing
                        loops: Animation.Infinite
                        alwaysRunToEnd: true

                        Anim {
                            from: 0.52
                            to: 0.9
                            duration: Appearance.anim.durations.large
                            easing.bezierCurve: Appearance.anim.curves.standard
                        }
                        Anim {
                            from: 0.9
                            to: 0.52
                            duration: Appearance.anim.durations.large
                            easing.bezierCurve: Appearance.anim.curves.standardDecel
                        }
                    }
                }
            }

            StyledText {
                anchors.left: parent.left
                anchors.leftMargin: Appearance.padding.large + 6
                anchors.verticalCenter: parent.verticalCenter
                visible: input.text.length === 0 && !SpeechToText.recording && !SpeechToText.transcribing
                text: SpeechToText.recording
                      ? qsTr("Listening...")
                      : SpeechToText.transcribing
                        ? qsTr("Transcribing...")
                        : Opencode.busy
                          ? qsTr("Waiting for reply...")
                          : qsTr("Ask something...")
                color: Qt.alpha(Colours.palette.m3onSurfaceVariant, 0.72)
                font.pointSize: Appearance.font.size.normal
            }
        }

        IconControl {
            id: micButton

            iconName: SpeechToText.recording ? "stop_circle" : "mic"
            active: SpeechToText.recording
            implicitWidth: 42
            implicitHeight: 42
            inactiveColor: Colours.palette.m3secondaryContainer
            iconPointSize: Appearance.font.size.large - 1
            onTap: () => {
                SpeechToText.activeTarget = "popout";
                SpeechToText.toggle();
            }

            SequentialAnimation on opacity {
                running: SpeechToText.recording
                loops: Animation.Infinite
                alwaysRunToEnd: true

                Anim {
                    from: 1
                    to: 0.48
                    duration: Appearance.anim.durations.extraLarge
                    easing.bezierCurve: Appearance.anim.curves.standardAccel
                }
                Anim {
                    from: 0.48
                    to: 1
                    duration: Appearance.anim.durations.extraLarge
                    easing.bezierCurve: Appearance.anim.curves.standardDecel
                }
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
            onClicked: {
                Opencode.cancelRequest();
            }
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

        Behavior on opacity {
            Anim {
                duration: Appearance.anim.durations.small
            }
        }

        SequentialAnimation on opacity {
            running: false
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

        SequentialAnimation on scale {
            running: input.text.trim().length > 0 && !Opencode.busy && !sendTap.pressed
            loops: Animation.Infinite
            alwaysRunToEnd: true

            Anim {
                from: 1
                to: 1.03
                duration: Appearance.anim.durations.extraLarge
                easing.bezierCurve: Appearance.anim.curves.standard
            }
            Anim {
                from: 1.03
                to: 1
                duration: Appearance.anim.durations.extraLarge
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
                    SpeechToText.activeTarget = "popout";
                    SpeechToText.stop(true);
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

        Behavior on opacity {
            Anim {
                duration: Appearance.anim.durations.small
            }
        }
    }

    Connections {
        function onCurrentNameChanged(): void {
            if (root.popouts.currentName === "ai") {
                Qt.callLater(() => {
                    root.focusInput();
                    root.requestBottomScroll();
                });
                Opencode.reloadSessions();
            } else {
                Opencode.draftCursorPosition = input.cursorPosition;
                root.closeMenus();
            }
        }

        target: root.popouts
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

        function onStreamingReasoningChanged(): void {
            if (Opencode.streamingReasoning.length > 0) {
                if (!root.followStreamingReasoningBottom)
                    root.followStreamingReasoningBottom = chatFlickable.followBottom || chatFlickable.isNearBottom();
                root.footerReasoningText = Opencode.streamingReasoning;
                root.footerReasoningClosing = false;
                root.footerReasoningExpanded = true;
                footerReasoningClearTimer.stop();
                if (Opencode.busy && root.followStreamingReasoningBottom) {
                    root.followReasoningBottom();
                }
            }
        }

        function onBusyChanged(): void {
            if (!Opencode.busy && root.footerReasoningText.length > 0) {
                root.footerReasoningExpanded = false;
                root.footerReasoningClosing = true;
                root.followReasoningBottom();
                footerReasoningClearTimer.restart();
            }
            if (!Opencode.busy && Opencode.streamingReasoning.length === 0)
                root.followStreamingReasoningBottom = false;
        }

        function onMessagesChanged(): void {
            if (root.pendingBottomScroll || Opencode.busy || chatFlickable.followBottom)
                root.scrollToLatest();
        }

        function onSystemMessagesChanged(): void {
            if (root.pendingBottomScroll || Opencode.busy || chatFlickable.followBottom)
                root.scrollToLatest();
        }

        function onCurrentSessionIdChanged(): void {
            root.requestBottomScroll();
        }

        function onLatestCompletedAssistantCreatedChanged(): void {
            if (Opencode.latestCompletedAssistantCreated <= 0
                || Opencode.latestCompletedAssistantCreated === root.lastFocusedAssistantCreated
                || Opencode.latestCompletedAssistantSessionId !== Opencode.currentSessionId)
                return;

            root.highlightedAssistantCreated = Opencode.latestCompletedAssistantCreated;
            root.lastFocusedAssistantCreated = Opencode.latestCompletedAssistantCreated;
            root.requestBottomScroll();
            if (root.footerReasoningText.length > 0) {
                root.footerReasoningExpanded = false;
                root.footerReasoningClosing = true;
                root.followReasoningBottom();
                footerReasoningClearTimer.restart();
            }
            assistantHighlightReset.restart();
        }

        target: Opencode
    }

    Timer {
        id: assistantHighlightReset

        interval: Appearance.anim.durations.large + 180
        onTriggered: {
            if (root.highlightedAssistantCreated === root.lastFocusedAssistantCreated)
                root.highlightedAssistantCreated = 0;
        }
    }

    Timer {
        id: footerReasoningClearTimer

        interval: Appearance.anim.durations.large + 120
        onTriggered: {
            root.footerReasoningText = "";
            root.footerReasoningClosing = false;
            root.footerReasoningExpanded = false;
            root.followStreamingReasoningBottom = false;
        }
    }

    Connections {
        function onTranscriptNonceChanged(): void {
            if (SpeechToText.activeTarget !== "popout")
                return;
            root.appendTranscript(SpeechToText.lastTranscript);
            if (SpeechToText.consumeSubmitAfterTranscribe())
                Qt.callLater(() => root.sendMessage());
            SpeechToText.activeTarget = "";
        }

        target: SpeechToText
    }

    Component.onCompleted: {
        root.scrollToLatest();
        if (root.popouts.currentName === "ai") {
            Qt.callLater(() => {
                root.focusInput();
                chatFlickable.syncScrollState();
            });
        }
    }
}
