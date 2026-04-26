pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

Singleton {
    id: root

    property var sessions: []
    property var models: []
    property var opencodeModels: []
    property var apiModels: []
    property var opencodeSessions: []
    property var apiSessions: []
    property var messages: []
    property var systemMessages: []
    property var attachments: []
    property var thinkingLevels: ({})
    property var apiReasoningEnabledByModel: ({})
    property string currentSessionId: ""
    property string currentTitle: qsTr("New chat")
    property string currentDirectory: ""
    property bool draftSession: false
    property string selectedModel: ""
    property string selectedMode: "build"
    property string draftInput: ""
    property int draftCursorPosition: 0
    property string lastError: ""
    property bool busy: false
    property bool autoAcceptPermissions: true
    property string streamingText: ""
    property string streamingReasoning: ""
    property double streamingCreated: 0
    property bool pendingTelegramForward: false
    property double lastTelegramForwardedCreated: 0
    property string pendingCopyNonce: ""
    property double latestCompletedAssistantCreated: 0
    property string latestCompletedAssistantSessionId: ""
    property string logPath: `${Quickshell.env("HOME")}/.local/state/caelestia/opencode-bridge.log`
    property string statePath: `${Paths.state}/opencode-ui.json`
    property string apiStatePath: `${Paths.state}/google-api-chats.json`
    property bool awaitingAssistantRefresh: false
    property bool suppressNextRefresh: false
    property string pendingUserText: ""
    property var pendingUserAttachments: []
    property var streamingToolParts: []
    property string lastStreamTextSnapshot: ""
    property double lastStreamCreatedSnapshot: 0
    property bool stateReady: false
    property int modelRetryCount: 0
    property int sessionRetryCount: 0
    property int exportRetryCount: 0

    property var sessionCache: ({})
    property var apiSessionCache: ({})
    property string currentBackend: "opencode"
    property string opencodeCurrentSessionId: ""
    property string apiCurrentSessionId: ""
    property string opencodeSelectedModel: ""
    property string apiSelectedModel: ""
    property string opencodeCurrentTitle: qsTr("New chat")
    property string apiCurrentTitle: qsTr("New chat")
    property string opencodeCurrentDirectory: ""
    property string apiCurrentDirectory: ""
    property bool opencodeDraftSession: false
    property bool apiDraftSession: false
    property bool suppressSelectedModelRouting: false
    readonly property bool apiMode: (root.selectedModel || "").startsWith("api/")
    readonly property bool apiReasoningAvailable: root.apiMode && !!(root.currentModelData?.reasoning ?? false)
    readonly property bool apiReasoningEnabled: {
        const key = root.selectedModel || "__default__";
        if (!root.apiReasoningAvailable)
            return false;
        const saved = root.apiReasoningEnabledByModel[key];
        return typeof saved === "boolean" ? saved : true;
    }

    readonly property var allMessages: {
        const combined = [];
        for (const message of messages)
            combined.push(message);
        for (const message of systemMessages)
            combined.push(message);
        if ((busy || awaitingAssistantRefresh) && pendingUserText.length > 0) {
            combined.push({
                role: "user",
                text: pendingUserText,
                attachments: pendingUserAttachments,
                created: streamingCreated - 2
            });
        }
        if ((busy || awaitingAssistantRefresh) && streamingCreated > 0 && root.currentBackend !== "api") {
            if (streamingReasoning.length > 0 && streamingText.length > 0) {
                combined.push({
                    role: "thinking",
                    text: streamingReasoning,
                    created: streamingCreated - 1
                });
            }
            if (streamingText.length > 0) {
                combined.push({
                    role: "assistant",
                    text: streamingText,
                    tools: streamingToolParts,
                    created: streamingCreated
                });
            }
        }
        combined.sort((a, b) => (a.created ?? 0) - (b.created ?? 0));
        return combined;
    }
    readonly property string currentModelLabel: {
        const current = models.find(model => model.id === root.selectedModel);
        return current ? current.label : "Model";
    }
    function providerLabel(provider: string): string {
        if (provider === "api")
            return "API";
        if (provider === "opencode")
            return "OpenCode Zen";
        if (provider === "openai")
            return "OpenAI";
        const value = provider || "other";
        return value.charAt(0).toUpperCase() + value.slice(1);
    }
    readonly property var modelMenuItems: {
        const items = [];
        const providerOrder = [];
        const grouped = ({});

        for (const model of models) {
            const provider = model.provider || "other";
            if (!grouped[provider]) {
                grouped[provider] = [];
                providerOrder.push(provider);
            }
            grouped[provider].push(model);
        }

        for (const provider of providerOrder) {
            items.push({
                type: "provider",
                provider,
                label: root.providerLabel(provider)
            });

            for (const model of grouped[provider]) {
                const item = {
                    type: "model"
                };
                for (const key in model)
                    item[key] = model[key];
                items.push(item);
            }
        }

        return items;
    }
    readonly property var currentModelData: models.find(model => model.id === root.selectedModel) ?? null
    readonly property var currentThinkingOptions: {
        const current = root.currentModelData;
        if (!current || !current.reasoning)
            return [];
        const variants = ["default"];
        for (const variant of (current.variants ?? []))
            variants.push(variant);
        return variants;
    }
    readonly property string bridgePath: `${Quickshell.env("HOME")}/.config/quickshell/caelestia/scripts/opencode-bridge.sh`
    readonly property string apiBridgePath: `${Quickshell.env("HOME")}/.config/quickshell/caelestia/scripts/google-api-bridge.py`
    readonly property string workingDir: `${Quickshell.env("HOME")}/opencode`
    readonly property string desktopStatePath: `${Quickshell.env("HOME")}/.config/ai.opencode.desktop/opencode.global.dat.json`
    readonly property string opencodeConfigPath: `${Quickshell.env("HOME")}/.config/opencode/opencode.json`
    readonly property string apiConfigPath: `${Quickshell.env("HOME")}/.config/caelestia-ai/api-config.json`
    readonly property string systemPrompt: systemPromptFile.loaded ? systemPromptFile.text() : ""
    readonly property string specialPrompt: specialPromptFile.loaded ? specialPromptFile.text() : ""
    readonly property string specialPrompt2: specialPrompt2File.loaded ? specialPrompt2File.text() : ""
    readonly property string specialPrompt3: specialPrompt3File.loaded ? specialPrompt3File.text() : ""
    readonly property string botPrompt: botPromptFile.loaded ? botPromptFile.text() : ""
    readonly property string currentThinkingLevel: {
        const key = root.selectedModel || "__default__";
        const available = root.currentThinkingOptions;
        const saved = root.thinkingLevels[key];
        if (saved && available.includes(saved))
            return saved;
        return available.length > 0 ? available[0] : "default";
    }

    function runBridge(proc: Process, args: var): void {
        proc.command = [
            "env",
            `OPENCODE_DESKTOP_STATE_PATH=${root.desktopStatePath}`,
            `OPENCODE_CONFIG_PATH=${root.opencodeConfigPath}`,
            "bash",
            root.bridgePath,
            ...args
        ];
        proc.running = true;
    }

    function runApiBridge(proc: Process, args: var): void {
        proc.command = [
            "env",
            `CAELESTIA_API_CONFIG_PATH=${root.apiConfigPath}`,
            `CAELESTIA_API_CHAT_STORE=${root.apiStatePath}`,
            root.apiBridgePath,
            ...args
        ];
        proc.running = true;
    }

    function backendForModel(modelId: string): string {
        return (modelId || "").startsWith("api/") ? "api" : "opencode";
    }

    function refreshMergedModels(): void {
        const next = [];
        for (const model of root.apiModels)
            next.push(model);
        for (const model of root.opencodeModels)
            next.push(model);
        root.models = next;
        if ((!root.selectedModel || root.selectedModel.length === 0) && root.models.length > 0)
            root.selectedModel = root.models[0].id;
        if (root.selectedModel.length > 0 && !root.models.find(model => model.id === root.selectedModel) && root.models.length > 0)
            root.selectedModel = root.models[0].id;
        if (root.selectedModel.length > 0)
            root.currentBackend = root.backendForModel(root.selectedModel);
        root.syncSessionsForBackend(root.currentBackend);
    }

    function syncSessionsForBackend(backend: string): void {
        root.sessions = backend === "api" ? root.apiSessions : root.opencodeSessions;
    }

    function selectModel(modelId: string): void {
        if (!modelId || modelId.length === 0)
            return;

        const nextBackend = root.backendForModel(modelId);
        const wasBackend = root.currentBackend;

        if (nextBackend === "api")
            root.apiSelectedModel = modelId;
        else
            root.opencodeSelectedModel = modelId;

        root.suppressSelectedModelRouting = true;
        root.selectedModel = modelId;
        root.suppressSelectedModelRouting = false;

        if (nextBackend !== wasBackend)
            root.switchBackend(nextBackend, false);
        root.queueStateSave();
    }

    function switchBackend(backend: string, forceNewChat: bool): void {
        if (backend !== "api" && backend !== "opencode")
            return;

        root.currentBackend = backend;
        root.syncSessionsForBackend(backend);
        root.streamingText = "";
        root.streamingReasoning = "";
        root.streamingToolParts = [];
        root.streamingCreated = 0;
        root.awaitingAssistantRefresh = false;
        root.suppressNextRefresh = false;
        root.pendingUserText = "";
        root.pendingUserAttachments = [];

        if (backend === "api") {
            root.currentSessionId = root.apiCurrentSessionId;
            root.currentTitle = root.apiCurrentTitle;
            root.currentDirectory = root.apiCurrentDirectory;
            root.draftSession = root.apiDraftSession;
            if (root.apiSelectedModel.length > 0 && root.selectedModel !== root.apiSelectedModel) {
                root.suppressSelectedModelRouting = true;
                root.selectedModel = root.apiSelectedModel;
                root.suppressSelectedModelRouting = false;
            }
            if (forceNewChat)
                root.newChat();
            else if (root.apiCurrentSessionId && root.apiCurrentSessionId.length > 0)
                root.loadSession(root.apiCurrentSessionId);
            else if (root.apiSessions.length > 0)
                root.loadSession(root.apiSessions[0].id);
            else
                root.newChat();
        } else {
            root.currentSessionId = root.opencodeCurrentSessionId;
            root.currentTitle = root.opencodeCurrentTitle;
            root.currentDirectory = root.opencodeCurrentDirectory;
            root.draftSession = root.opencodeDraftSession;
            if (root.opencodeSelectedModel.length > 0 && root.selectedModel !== root.opencodeSelectedModel) {
                root.suppressSelectedModelRouting = true;
                root.selectedModel = root.opencodeSelectedModel;
                root.suppressSelectedModelRouting = false;
            }
            if (root.opencodeCurrentSessionId.length > 0)
                root.loadSession(root.opencodeCurrentSessionId);
            else if (root.opencodeSessions.length > 0)
                root.loadSession(root.opencodeSessions[0].id);
            else
                root.newChat();
        }
    }

    function reload(): void {
        reloadModels();
        reloadSessions();
    }

    function reloadModels(): void {
        runBridge(modelsProc, ["list-models"]);
        runApiBridge(apiModelsProc, ["list-models"]);
    }

    function reloadSessions(): void {
        runBridge(sessionsProc, ["list-sessions"]);
        runApiBridge(apiSessionsProc, ["list-sessions"]);
    }

    function loadSession(sessionId: string): void {
        if (!sessionId || sessionId.length === 0)
            return;

        currentSessionId = sessionId;
        draftSession = false;
        lastError = "";
        if (root.currentBackend === "api")
            root.apiCurrentSessionId = sessionId;
        else
            root.opencodeCurrentSessionId = sessionId;

        const cache = root.currentBackend === "api" ? root.apiSessionCache : root.sessionCache;
        const cached = cache[sessionId];
        if (cached) {
            currentTitle = cached.title ?? currentTitle;
            currentDirectory = cached.directory ?? currentDirectory;
            messages = cached.messages ?? messages;
            if (root.currentBackend === "api" && !(root.awaitingAssistantRefresh && sessionId === root.currentSessionId)) {
                root.apiCurrentTitle = currentTitle;
                root.apiCurrentDirectory = currentDirectory;
                root.apiDraftSession = false;
                root.queueStateSave();
                return;
            }
        }
        exportRetryCount = 0;
        if (root.currentBackend === "api")
            runApiBridge(apiExportProc, ["export-session", sessionId]);
        else
            runBridge(exportProc, ["export-session", sessionId]);
    }

    function newChat(): void {
        currentSessionId = "";
        currentTitle = qsTr("New chat");
        currentDirectory = "";
        draftSession = true;
        messages = [];
        systemMessages = [];
        lastError = "";
        streamingText = "";
        streamingReasoning = "";
        streamingToolParts = [];
        streamingCreated = 0;
        busy = false;
        if (root.currentBackend === "api") {
            root.apiCurrentSessionId = "";
            root.apiCurrentTitle = root.currentTitle;
            root.apiCurrentDirectory = root.currentDirectory;
            root.apiDraftSession = true;
        } else {
            root.opencodeCurrentSessionId = "";
            root.opencodeCurrentTitle = root.currentTitle;
            root.opencodeCurrentDirectory = root.currentDirectory;
            root.opencodeDraftSession = true;
        }
        queueStateSave();
    }

    function sendMessage(message: string): bool {
        let prompt = message.trim();
        let visiblePrompt = prompt;
        let effectiveModel = selectedModel;
        const targetBackend = root.backendForModel(effectiveModel);
        const hasSystemPrompt = root.systemPrompt.trim().length > 0;
        if (busy || prompt.length === 0)
            return false;
        if (targetBackend === "opencode" && attachments.length > 0 && !(currentModelData?.attachments ?? false)) {
            const fallbackModel = models.find(model => model.attachments);
            if (!fallbackModel) {
                lastError = qsTr("No available model supports image attachments");
                pushSystemMessage(lastError);
                return false;
            }
            effectiveModel = fallbackModel.id;
            root.selectModel(fallbackModel.id);
        }

        if (root.currentBackend !== targetBackend)
            root.switchBackend(targetBackend, targetBackend === "api");

        lastError = "";
        busy = true;
        awaitingAssistantRefresh = false;
        suppressNextRefresh = false;
        streamingText = "";
        streamingReasoning = "";
        streamingToolParts = [];
        streamingCreated = Date.now();
        const useSpecialPrompt = prompt.startsWith(">");
        const useSpecialPrompt2 = prompt.startsWith("@");
        const useSpecialPrompt3 = prompt.startsWith("$");
        const useBotPrompt = prompt.startsWith("<");
        if (useSpecialPrompt || useSpecialPrompt2 || useSpecialPrompt3 || useBotPrompt) {
            prompt = prompt.slice(1).trim();
            visiblePrompt = prompt;
        }

        pendingUserText = visiblePrompt;
        draftInput = "";
        draftCursorPosition = 0;
        pendingUserAttachments = attachments.slice();
        pendingTelegramForward = useBotPrompt;
        if (targetBackend !== "api" && selectedMode === "plan")
            prompt = `Plan mode only. Do not make changes or run tools. Give a concise implementation plan.\n\n${prompt}`;
        if (useBotPrompt && root.botPrompt.trim().length > 0)
            prompt = `[[${root.botPrompt.trim()}]]\n\n${prompt}`;
        else if (useSpecialPrompt3 && root.specialPrompt3.trim().length > 0)
            prompt = `[[${root.specialPrompt3.trim()}]]\n\n${prompt}`;
        else if (useSpecialPrompt2 && root.specialPrompt2.trim().length > 0)
            prompt = `[[${root.specialPrompt2.trim()}]]\n\n${prompt}`;
        else if (useSpecialPrompt && root.specialPrompt.trim().length > 0)
            prompt = `[[${root.specialPrompt.trim()}]]\n\n${prompt}`;
        else if (hasSystemPrompt)
            prompt = `[[${root.systemPrompt.trim()}]]\n\n${prompt}`;

        const args = ["run", "--dir", currentDirectory || workingDir, "--message", prompt];
        draftSession = false;
        if (currentSessionId.length > 0)
            args.push("--session", currentSessionId);
        if (effectiveModel.length > 0)
            args.push("--model", effectiveModel);
        if (targetBackend !== "api")
            args.push("--agent", "build");
        if (targetBackend === "api" && root.apiReasoningEnabled)
            args.push("--thinking");
        if (targetBackend !== "api" && currentThinkingLevel.length > 0 && currentThinkingLevel !== "default")
            args.push("--thinking", "--variant", currentThinkingLevel);
        for (const path of attachments)
            args.push("--file", path);

        if (targetBackend === "api")
            runApiBridge(apiSendProc, args);
        else
            runBridge(sendProc, args);
        attachments = [];
        queueStateSave();
        return true;
    }

    function cancelRequest(): void {
        if (!busy)
            return;

        sendProc.running = false;
        apiSendProc.running = false;
        busy = false;
        suppressNextRefresh = true;
        awaitingAssistantRefresh = false;
        streamingText = "";
        streamingReasoning = "";
        streamingToolParts = [];
        streamingCreated = 0;
        pendingUserText = "";
        pendingUserAttachments = [];
        pushSystemMessage(qsTr("Request cancelled"));
    }

    function pickAttachment(): void {
        pickerProc.command = [
            "zenity",
            "--file-selection",
            "--title=Attach image",
            "--file-filter=Images | *.png *.jpg *.jpeg *.webp *.gif"
        ];
        pickerProc.running = true;
    }

    function setThinkingLevel(level: string): void {
        if (!root.currentThinkingOptions.includes(level))
            return;
        const next = {};
        for (const key in thinkingLevels)
            next[key] = thinkingLevels[key];
        next[selectedModel || "__default__"] = level;
        thinkingLevels = next;
        queueStateSave();
    }

    function setApiReasoningEnabled(enabled: bool): void {
        const key = selectedModel || "__default__";
        const next = {};
        for (const existingKey in apiReasoningEnabledByModel)
            next[existingKey] = apiReasoningEnabledByModel[existingKey];
        next[key] = enabled;
        apiReasoningEnabledByModel = next;
        queueStateSave();
    }

    function queueStateSave(): void {
        if (!stateReady)
            return;
        stateSaveTimer.restart();
    }

    function saveState(): void {
        if (!stateReady)
            return;

        saveStateProc.command = [
            "python",
            "-c",
            "import os,sys; os.makedirs(os.path.dirname(sys.argv[1]), exist_ok=True); open(sys.argv[1], 'w', encoding='utf-8').write(sys.argv[2])",
            statePath,
            JSON.stringify({
            selectedModel,
            selectedMode,
            currentBackend,
            currentSessionId,
            currentTitle,
            currentDirectory,
            opencodeCurrentSessionId,
            apiCurrentSessionId,
            opencodeSelectedModel,
            apiSelectedModel,
            draftInput,
            draftCursorPosition,
            autoAcceptPermissions,
            thinkingLevels,
            apiReasoningEnabledByModel
        }, null, 2)
        ];
        saveStateProc.running = true;
    }

    function restoreState(data: var): void {
        if (!data)
            return;

        if (typeof data.selectedModel === "string")
            selectedModel = data.selectedModel;
        if (typeof data.selectedMode === "string" && data.selectedMode.length > 0)
            selectedMode = data.selectedMode;
        if (typeof data.currentBackend === "string" && data.currentBackend.length > 0)
            currentBackend = data.currentBackend;
        if (typeof data.currentSessionId === "string")
            currentSessionId = data.currentSessionId;
        if (typeof data.currentTitle === "string" && data.currentTitle.length > 0)
            currentTitle = data.currentTitle;
        if (typeof data.currentDirectory === "string")
            currentDirectory = data.currentDirectory;
        if (typeof data.opencodeCurrentSessionId === "string")
            opencodeCurrentSessionId = data.opencodeCurrentSessionId;
        if (typeof data.apiCurrentSessionId === "string")
            apiCurrentSessionId = data.apiCurrentSessionId;
        if (typeof data.opencodeSelectedModel === "string")
            opencodeSelectedModel = data.opencodeSelectedModel;
        if (typeof data.apiSelectedModel === "string")
            apiSelectedModel = data.apiSelectedModel;
        if (typeof data.draftInput === "string")
            draftInput = data.draftInput;
        if (typeof data.draftCursorPosition === "number")
            draftCursorPosition = data.draftCursorPosition;
        if (typeof data.autoAcceptPermissions === "boolean")
            autoAcceptPermissions = data.autoAcceptPermissions;
        if (data.thinkingLevels && typeof data.thinkingLevels === "object")
            thinkingLevels = data.thinkingLevels;
        if (data.apiReasoningEnabledByModel && typeof data.apiReasoningEnabledByModel === "object")
            apiReasoningEnabledByModel = data.apiReasoningEnabledByModel;
    }

    function pushSystemMessage(text: string): void {
        const next = [];
        for (const message of systemMessages)
            next.push(message);
        next.push({
            role: "system",
            text,
            created: Date.now()
        });
        systemMessages = next;
    }

    function applyExport(data: var): void {
        const previousLatestAssistant = messages
            .filter(message => (message.role ?? "") === "assistant" && (message.text ?? "").trim().length > 0)
            .sort((a, b) => (a.created ?? 0) - (b.created ?? 0))
            .slice(-1)[0] ?? null;
        currentSessionId = data.session?.id ?? root.currentSessionId;
        currentTitle = data.session?.title ?? qsTr("New chat");
        currentDirectory = data.session?.directory ?? "";
        if (root.currentBackend === "api") {
            root.apiCurrentSessionId = currentSessionId;
            root.apiCurrentTitle = currentTitle;
            root.apiCurrentDirectory = currentDirectory;
            root.apiDraftSession = false;
        } else {
            root.opencodeCurrentSessionId = currentSessionId;
            root.opencodeCurrentTitle = currentTitle;
            root.opencodeCurrentDirectory = currentDirectory;
            root.opencodeDraftSession = false;
        }
        const nextMessages = [];
        for (const message of (data.messages ?? [])) {
            const next = {};
            for (const key in message)
                next[key] = message[key];
            if ((next.role ?? "") === "user")
                next.text = sanitizeVisibleUserText(next.text ?? "");
            nextMessages.push(next);
        }
        const latestAssistant = nextMessages
            .filter(message => (message.role ?? "") === "assistant" && (message.text ?? "").trim().length > 0)
            .sort((a, b) => (a.created ?? 0) - (b.created ?? 0))
            .slice(-1)[0] ?? null;
        messages = nextMessages;
        const nextCache = {};
        const sourceCache = root.currentBackend === "api" ? root.apiSessionCache : root.sessionCache;
        for (const key in sourceCache)
            nextCache[key] = sourceCache[key];
        nextCache[currentSessionId] = {
            title: currentTitle,
            directory: currentDirectory,
            messages
        };
        if (root.currentBackend === "api")
            apiSessionCache = nextCache;
        else
            sessionCache = nextCache;
        pendingUserText = "";
        pendingUserAttachments = [];

        if ((root.awaitingAssistantRefresh || root.busy) && latestAssistant && (latestAssistant.created ?? 0) !== (previousLatestAssistant?.created ?? 0)) {
            root.latestCompletedAssistantCreated = latestAssistant.created ?? 0;
            root.latestCompletedAssistantSessionId = currentSessionId;
        }

        if (root.pendingTelegramForward) {
            const assistants = nextMessages
                .filter(message => (message.role ?? "") === "assistant" && (message.text ?? "").trim().length > 0)
                .sort((a, b) => (a.created ?? 0) - (b.created ?? 0));
            const latestAssistant = assistants.length > 0 ? assistants[assistants.length - 1] : null;
            if (latestAssistant && (latestAssistant.created ?? 0) > root.lastTelegramForwardedCreated) {
                root.lastTelegramForwardedCreated = latestAssistant.created ?? Date.now();
                telegramProc.command = [
                    "bash",
                    `${Quickshell.env("HOME")}/.config/quickshell/caelestia/scripts/telegram-forward.sh`,
                    latestAssistant.text ?? ""
                ];
                telegramProc.running = true;
            }
            root.pendingTelegramForward = false;
        }
    }

    function parsePayload(text: string): var {
        const payload = text.trim();
        if (payload.length === 0) {
            return {
                ok: false,
                error: qsTr("No response from opencode bridge")
            };
        }
        return JSON.parse(payload);
    }

    function sanitizeVisibleUserText(text: string): string {
        let value = (text || "").replace(/\r\n/g, "\n").replace(/^\uFEFF/, "").trim();
        value = value.replace(/\s*\[\[[\s\S]*?\]\]\s*/g, "\n");
        value = value.replace(/^\n+/, "").replace(/\n{3,}/g, "\n\n").trim();
        const planPrefix = "Plan mode only. Do not make changes or run tools. Give a concise implementation plan.";
        const prefixes = [planPrefix, root.botPrompt, root.specialPrompt3, root.specialPrompt2, root.specialPrompt, root.systemPrompt]
            .map(prefix => (prefix || "").replace(/\r\n/g, "\n").replace(/^\uFEFF/, "").trim())
            .filter(prefix => prefix.length > 0);

        let changed = true;
        let hadInjectedPrefix = false;
        while (changed) {
            changed = false;

            for (const prefix of prefixes) {
                if (value === prefix) {
                    value = "";
                    changed = true;
                    hadInjectedPrefix = true;
                    continue;
                }

                const doubleNewlinePrefix = `${prefix}\n\n`;
                const singleNewlinePrefix = `${prefix}\n`;
                if (value.startsWith(doubleNewlinePrefix)) {
                    value = value.slice(doubleNewlinePrefix.length).trim();
                    changed = true;
                    hadInjectedPrefix = true;
                } else if (value.startsWith(singleNewlinePrefix)) {
                    value = value.slice(singleNewlinePrefix.length).trim();
                    changed = true;
                    hadInjectedPrefix = true;
                } else if (value.startsWith(prefix)) {
                    value = value.slice(prefix.length).trim();
                    changed = true;
                    hadInjectedPrefix = true;
                }
            }

            if (value.startsWith(">") || value.startsWith("@") || value.startsWith("$")) {
                value = value.slice(1).trim();
                changed = true;
                hadInjectedPrefix = true;
            }
            if (value.startsWith("<")) {
                value = value.slice(1).trim();
                changed = true;
                hadInjectedPrefix = true;
            }
        }

        if (hadInjectedPrefix && value.includes("\n")) {
            const parts = value
                .split(/\n{2,}/)
                .map(part => part.trim())
                .filter(part => part.length > 0);
            if (parts.length > 0)
                value = parts[parts.length - 1];
        }

        return value;
    }

    Process {
        id: modelsProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = root.parsePayload(text);
                    root.opencodeModels = data.models ?? [];
                    root.modelRetryCount = 0;
                    root.refreshMergedModels();
                    root.queueStateSave();
                } catch (e) {
                    if (text.trim().length === 0 && root.modelRetryCount < 2) {
                        root.modelRetryCount += 1;
                        retryModelsTimer.restart();
                        return;
                    }
                    root.lastError = e.toString();
                    root.pushSystemMessage(root.lastError);
                }
            }
        }
    }

    Process {
        id: apiModelsProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = root.parsePayload(text);
                    root.apiModels = data.models ?? [];
                    root.refreshMergedModels();
                    root.queueStateSave();
                } catch (e) {
                    root.lastError = e.toString();
                    root.pushSystemMessage(root.lastError);
                }
            }
        }
    }

    Process {
        id: sessionsProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = root.parsePayload(text);
                    root.opencodeSessions = data.sessions ?? [];
                    if (root.currentBackend === "opencode")
                        root.sessions = root.opencodeSessions;
                    root.sessionRetryCount = 0;

                    if (root.opencodeCurrentSessionId.length > 0) {
                        const current = root.opencodeSessions.find(session => session.id === root.opencodeCurrentSessionId);
                        if (current) {
                            root.opencodeCurrentTitle = current.title;
                            if (root.currentBackend === "opencode") {
                                root.currentTitle = current.title;
                                if (root.messages.length === 0 && !root.busy && !root.awaitingAssistantRefresh)
                                    root.loadSession(root.opencodeCurrentSessionId);
                            }
                            return;
                        }
                    }

                    if (root.currentBackend === "opencode" && !root.draftSession && (!root.opencodeCurrentSessionId || root.opencodeCurrentSessionId.length === 0) && root.opencodeSessions.length > 0) {
                        root.loadSession(root.opencodeSessions[0].id);
                        return;
                    }
                } catch (e) {
                    if (text.trim().length === 0 && root.sessionRetryCount < 2) {
                        root.sessionRetryCount += 1;
                        retrySessionsTimer.restart();
                        return;
                    }
                    root.lastError = e.toString();
                    root.pushSystemMessage(root.lastError);
                }
            }
        }
    }

    Process {
        id: apiSessionsProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = root.parsePayload(text);
                    root.apiSessions = data.sessions ?? [];
                    if (root.currentBackend === "api")
                        root.sessions = root.apiSessions;
                    if (root.apiCurrentSessionId.length > 0) {
                        const current = root.apiSessions.find(session => session.id === root.apiCurrentSessionId);
                        if (current) {
                            root.apiCurrentTitle = current.title;
                            if (root.currentBackend === "api") {
                                root.currentTitle = current.title;
                                if (root.messages.length === 0 && !root.busy && !root.awaitingAssistantRefresh)
                                    root.loadSession(root.apiCurrentSessionId);
                            }
                            return;
                        }
                    }
                    if (root.currentBackend === "api" && !root.draftSession && (!root.apiCurrentSessionId || root.apiCurrentSessionId.length === 0) && root.apiSessions.length > 0)
                        root.loadSession(root.apiSessions[0].id);
                } catch (e) {
                    root.lastError = e.toString();
                    root.pushSystemMessage(root.lastError);
                }
            }
        }
    }

    Process {
        id: exportProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = root.parsePayload(text);
                    if (data.ok === false) {
                        if ((data.error ?? "").includes("No response from opencode bridge") && root.exportRetryCount < 2) {
                            root.exportRetryCount += 1;
                            retryExportTimer.restart();
                            return;
                        }
                        root.lastError = data.error ?? qsTr("Failed to load chat");
                        root.pushSystemMessage(root.lastError);
                        return;
                    }
                    root.applyExport(data);
                    root.exportRetryCount = 0;
                    root.lastStreamTextSnapshot = root.streamingText;
                    root.lastStreamCreatedSnapshot = root.streamingCreated;
                    root.streamingText = "";
                    root.streamingReasoning = "";
                    root.streamingToolParts = [];
                    root.streamingCreated = 0;
                    root.awaitingAssistantRefresh = false;
                    root.suppressNextRefresh = false;
                    root.queueStateSave();
                } catch (e) {
                    if (text.trim().length === 0 && root.exportRetryCount < 2) {
                        root.exportRetryCount += 1;
                        retryExportTimer.restart();
                        return;
                    }
                    root.lastError = e.toString();
                    root.pushSystemMessage(root.lastError);
                }
            }
        }
    }

    Process {
        id: apiExportProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = root.parsePayload(text);
                    if (data.ok === false) {
                        root.lastError = data.error ?? qsTr("Failed to load chat");
                        root.pushSystemMessage(root.lastError);
                        return;
                    }
                    root.applyExport(data);
                    root.lastStreamTextSnapshot = root.streamingText;
                    root.lastStreamCreatedSnapshot = root.streamingCreated;
                    root.streamingText = "";
                    root.streamingReasoning = "";
                    root.streamingToolParts = [];
                    root.streamingCreated = 0;
                    root.awaitingAssistantRefresh = false;
                    root.suppressNextRefresh = false;
                    root.queueStateSave();
                } catch (e) {
                    root.lastError = e.toString();
                    root.pushSystemMessage(root.lastError);
                }
            }
        }
    }

    Process {
        id: sendProc

        stdout: SplitParser {
            onRead: data => {
                try {
                    const event = root.parsePayload(data);
                    if (event.type === "reasoning") {
                        if (event.part?.text && event.part.text.length > 0)
                            root.streamingReasoning += event.part.text;
                        return;
                    }
                    if (event.type === "tool_use") {
                        const state = event.part?.state ?? {};
                        const input = state.input ?? {};
                        const metadata = state.metadata ?? {};
                        root.streamingToolParts = root.streamingToolParts.concat([{
                            tool: event.part?.tool ?? "",
                            title: state.title ?? input.description ?? event.part?.tool ?? qsTr("Tool"),
                            command: input.command ?? "",
                            description: input.description ?? "",
                            output: state.output ?? metadata.output ?? "",
                            status: state.status ?? "",
                            exitCode: metadata.exit ?? null
                        }]);
                        return;
                    }
                    if (event.type === "text") {
                        if (event.part?.text)
                            root.streamingText += event.part.text;
                        return;
                    }
                    if (event.type === "error") {
                        root.lastError = event.error?.data?.message ?? event.error?.message ?? event.error?.name ?? qsTr("Failed to send message");
                        root.pushSystemMessage(root.lastError);
                        return;
                    }
                    if (event.sessionID)
                        root.currentSessionId = event.sessionID;
                    if (event.sessionID)
                        root.draftSession = false;
                } catch (e) {
                    // Ignore non-JSON bridge log lines; only surface real JSON failures above.
                }
            }
        }

        onExited: {
            root.busy = false;
            const nextSessionId = root.currentSessionId;
            if (root.suppressNextRefresh) {
                root.suppressNextRefresh = false;
                root.awaitingAssistantRefresh = false;
            } else {
                root.awaitingAssistantRefresh = true;
                if (nextSessionId && nextSessionId.length > 0)
                    refreshTimer.restart();
            }
            root.reloadSessions();
            root.queueStateSave();
        }
    }

    Process {
        id: apiSendProc

        stdout: SplitParser {
            onRead: data => {
                try {
                    const event = root.parsePayload(data);
                    if (event.type === "reasoning") {
                        if (event.part?.text && event.part.text.length > 0)
                            root.streamingReasoning += event.part.text;
                        return;
                    }
                    if (event.type === "text") {
                        if (event.part?.text)
                            root.streamingText += event.part.text;
                        return;
                    }
                    if (event.type === "error") {
                        root.lastError = event.error?.message ?? qsTr("Failed to send message");
                        root.pushSystemMessage(root.lastError);
                        return;
                    }
                    if (event.sessionID) {
                        root.currentSessionId = event.sessionID;
                        root.apiCurrentSessionId = event.sessionID;
                    }
                } catch (e) {
                }
            }
        }

        onExited: {
            root.busy = false;
            const nextSessionId = root.currentSessionId;
            if (root.suppressNextRefresh) {
                root.suppressNextRefresh = false;
                root.awaitingAssistantRefresh = false;
            } else {
                root.awaitingAssistantRefresh = true;
                if (nextSessionId && nextSessionId.length > 0)
                    apiRefreshTimer.restart();
            }
            runApiBridge(apiSessionsProc, ["list-sessions"]);
            root.queueStateSave();
        }
    }

    Timer {
        id: retryModelsTimer

        interval: 220
        onTriggered: root.reloadModels()
    }

    Timer {
        id: retrySessionsTimer

        interval: 220
        onTriggered: root.reloadSessions()
    }

    Timer {
        id: refreshTimer

        interval: 180
        onTriggered: {
            if (root.currentSessionId && root.currentSessionId.length > 0)
                root.loadSession(root.currentSessionId);
        }
    }

    Timer {
        id: apiRefreshTimer

        interval: 180
        onTriggered: {
            if (root.currentSessionId && root.currentSessionId.length > 0)
                root.loadSession(root.currentSessionId);
        }
    }

    Timer {
        id: retryExportTimer

        interval: 220
        onTriggered: {
            if (root.currentSessionId && root.currentSessionId.length > 0)
                root.loadSession(root.currentSessionId);
        }
    }

    Timer {
        id: stateSaveTimer

        interval: 180
        onTriggered: root.saveState()
    }

    Process {
        id: saveStateProc
    }

    Process {
        id: pickerProc

        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim();
                if (path.length === 0)
                    return;

                const next = [];
                for (const attachment of root.attachments)
                    next.push(attachment);
                next.push(path);
                root.attachments = next;
            }
        }
    }

    Process {
        id: telegramProc
    }

    FileView {
        id: systemPromptFile

        path: `${root.workingDir}/prompts/sys.md`
    }

    FileView {
        id: specialPromptFile

        path: `${root.workingDir}/prompts/special.md`
    }

    FileView {
        id: specialPrompt2File

        path: `${root.workingDir}/prompts/special2.md`
    }

    FileView {
        id: botPromptFile

        path: `${root.workingDir}/prompts/bot.md`
    }

    FileView {
        id: specialPrompt3File

        path: `${root.workingDir}/prompts/special3.md`
    }

    FileView {
        id: stateStorage

        path: root.statePath
        onLoaded: {
            try {
                root.restoreState(JSON.parse(text()));
            } catch (e) {
                root.lastError = e.toString();
            }
            root.stateReady = true;
            root.queueStateSave();
        }
        onLoadFailed: err => {
            root.stateReady = true;
            root.queueStateSave();
        }
    }

    FileView {
        id: desktopStateFile

        path: root.desktopStatePath
        onFileChanged: root.reloadModels()
    }

    FileView {
        id: opencodeConfigFile

        path: root.opencodeConfigPath
        onFileChanged: root.reloadModels()
    }

    FileView {
        id: apiConfigFile

        path: root.apiConfigPath
        onFileChanged: root.reloadModels()
    }

    Connections {
        target: root

        function onSelectedModelChanged(): void {
            if (!root.suppressSelectedModelRouting) {
                if (root.backendForModel(root.selectedModel) === "api")
                    root.apiSelectedModel = root.selectedModel;
                else
                    root.opencodeSelectedModel = root.selectedModel;
            }
            root.queueStateSave();
        }
        function onSelectedModeChanged(): void { root.queueStateSave(); }
        function onCurrentSessionIdChanged(): void {
            if (root.currentBackend === "api")
                root.apiCurrentSessionId = root.currentSessionId;
            else
                root.opencodeCurrentSessionId = root.currentSessionId;
            root.queueStateSave();
        }
        function onCurrentTitleChanged(): void { root.queueStateSave(); }
        function onCurrentDirectoryChanged(): void { root.queueStateSave(); }
        function onDraftInputChanged(): void { root.queueStateSave(); }
        function onDraftCursorPositionChanged(): void { root.queueStateSave(); }
        function onAutoAcceptPermissionsChanged(): void { root.queueStateSave(); }
        function onThinkingLevelsChanged(): void { root.queueStateSave(); }
        function onApiReasoningEnabledByModelChanged(): void { root.queueStateSave(); }
    }

    Component.onCompleted: {
        if (stateReady)
            queueStateSave();
        reload();
    }
}
