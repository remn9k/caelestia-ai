pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool recording: false
    property bool transcribing: false
    property bool submitAfterTranscribe: false
    property real elapsed: 0
    property real level: 0
    property int historySize: 28
    property var levelHistory: []
    property string lastTranscript: ""
    property string lastError: ""
    property string transcriptNonce: ""
    property string activeTarget: ""

    readonly property string bridgePath: `${Quickshell.env("HOME")}/.config/quickshell/caelestia/scripts/whisper-bridge.sh`

    function runBridge(proc: Process, args: var): void {
        proc.command = ["bash", root.bridgePath, ...args];
        proc.running = true;
    }

    function resetLevels(): void {
        level = 0;
        const next = [];
        for (let i = 0; i < historySize; i += 1)
            next.push(0);
        levelHistory = next;
    }

    function pushLevel(value: real): void {
        const safe = Math.max(0, Math.min(1, Number(value)));
        level = safe;
        const next = levelHistory.slice();
        if (next.length === 0) {
            for (let i = 0; i < historySize; i += 1)
                next.push(0);
        }
        next.push(safe);
        while (next.length > historySize)
            next.shift();
        levelHistory = next;
    }

    function start(): void {
        if (recording || transcribing)
            return;
        lastError = "";
        elapsed = 0;
        resetLevels();
        runBridge(startProc, ["start"]);
    }

    function stop(autoSubmit = false): void {
        if (!recording || transcribing)
            return;
        submitAfterTranscribe = autoSubmit;
        recording = false;
        transcribing = true;
        resetLevels();
        runBridge(stopProc, ["stop"]);
    }

    function toggle(): void {
        if (transcribing)
            return;
        if (recording)
            stop();
        else
            start();
    }

    function consumeSubmitAfterTranscribe(): bool {
        const value = submitAfterTranscribe;
        submitAfterTranscribe = false;
        return value;
    }

    function parsePayload(text: string): var {
        const payload = text.trim();
        if (payload.length === 0)
            return { ok: false, state: "error", error: "No response from whisper bridge", text: "" };
        return JSON.parse(payload);
    }

    Process {
        id: startProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = root.parsePayload(text);
                    root.recording = data.ok === true && data.state === "recording";
                    root.transcribing = false;
                    root.pushLevel(data.level ?? 0);
                    if (data.error)
                        root.lastError = data.error;
                } catch (e) {
                    root.lastError = e.toString();
                    root.recording = false;
                    root.resetLevels();
                }
            }
        }

        onExited: function(exitCode) {
            if (exitCode !== 0) {
                root.recording = false;
                root.resetLevels();
            }
        }
    }

    Process {
        id: statusProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = root.parsePayload(text);
                    if (root.recording && data.state === "recording")
                        root.pushLevel(data.level ?? 0);
                    else
                        root.resetLevels();
                } catch (e) {
                    root.resetLevels();
                }
            }
        }

        onExited: function(exitCode) {
            if (exitCode !== 0 && !root.recording)
                root.resetLevels();
        }
    }

    Process {
        id: stopProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = root.parsePayload(text);
                    root.recording = false;
                    root.transcribing = false;
                    root.elapsed = 0;
                    root.resetLevels();
                    if (data.error)
                        root.lastError = data.error;
                    if ((data.text ?? "").length > 0) {
                        root.lastTranscript = data.text;
                        root.transcriptNonce = `${Date.now()}`;
                    }
                } catch (e) {
                    root.lastError = e.toString();
                    root.recording = false;
                    root.transcribing = false;
                    root.resetLevels();
                }
            }
        }

        onExited: function(exitCode) {
            if (exitCode !== 0) {
                root.recording = false;
                root.transcribing = false;
                root.elapsed = 0;
                root.resetLevels();
            }
        }
    }

    Timer {
        interval: 120
        running: root.recording
        repeat: true
        onTriggered: {
            if (!statusProc.running)
                root.runBridge(statusProc, ["status"]);
        }
    }

    Connections {
        function onSecondsChanged(): void {
            if (root.recording)
                root.elapsed += 1;
        }

        target: Time
    }

    Component.onCompleted: resetLevels()
}
