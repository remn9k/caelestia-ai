import Quickshell
import Quickshell.Io
import qs.services
import qs.utils

Scope {
    id: root

    readonly property bool hasFullscreen: Hypr.focusedWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false
    readonly property string triggerPath: `${Paths.state}/blob-trigger`

    function openBlob(): void {
        if (root.hasFullscreen)
            return;
        const visibilities = Visibilities.getForActive();
        if (!visibilities)
            return;
        visibilities.launcher = false;
        visibilities.dashboard = false;
        visibilities.session = false;
        visibilities.blob = true;
    }

    FileView {
        path: root.triggerPath
        watchChanges: true
        preload: true
        onFileChanged: root.openBlob()
    }
}
