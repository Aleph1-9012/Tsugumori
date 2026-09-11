import Quickshell
import Quickshell.Io

Scope {
    id: root

    signal menuRequested()
    signal playerRequested()
    signal playerShowRequested()
    signal playerHideRequested()
    signal frontRequested()
    signal notesShowRequested()
    signal notesHideRequested()
    signal notesToggleRequested()
    signal clipboardShowRequested()
    signal clipboardHideRequested()
    signal clipboardToggleRequested()

    IpcHandler {
        target: "tsugumoriShell"

        function showClipboard(): void {
            root.clipboardShowRequested()
        }

        function hideClipboard(): void {
            root.clipboardHideRequested()
        }

        function toggleClipboard(): void {
            root.clipboardToggleRequested()
        }

        function showNotes(): void {
            root.notesShowRequested()
        }

        function hideNotes(): void {
            root.notesHideRequested()
        }

        function toggleNotes(): void {
            root.notesToggleRequested()
        }

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
