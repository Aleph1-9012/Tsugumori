import Quickshell
import Quickshell.Io

Scope {
    id: root

    signal menuRequested()
    signal playerRequested()
    signal playerShowRequested()
    signal playerHideRequested()
    signal frontRequested()

    IpcHandler {
        target: "tsugumoriShell"

        function toggleMenu(): void {
            root.menuRequested()
        }

        function togglePlayer(): void {
            root.playerRequested()
        }

        function showPlayer(): void {
            root.playerShowRequested()
        }

        function hidePlayer(): void {
            root.playerHideRequested()
        }

        function toggleFront(): void {
            root.frontRequested()
        }
    }
}
