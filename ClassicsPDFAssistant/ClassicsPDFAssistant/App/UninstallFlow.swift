import AppKit
import Foundation

/// The in-app half of "clean uninstall": clears this app's own saved
/// settings and temporary working files, then hands off to the user to
/// drag the app to the Trash themselves — a running app deleting its own
/// bundle is fragile, so this deliberately stops short of that. For a
/// fully automated removal (settings + temp files + the .app itself), see
/// scripts/Uninstall.command, bundled alongside the app in the .dmg (see
/// scripts/build_dmg.sh and README.md "제거하기").
///
/// Never touches user documents: nothing this removes lives anywhere near
/// wherever the user chose to save an exported PDF.
enum UninstallFlow {
    static func run() {
        let confirmAlert = NSAlert()
        confirmAlert.messageText = "Classics PDF Assistant 제거"
        confirmAlert.informativeText = "저장된 설정과 임시 작업 파일을 삭제합니다. 내보낸 PDF 등 사용자 문서는 전혀 건드리지 않습니다. 이후 앱 자체는 Finder에서 직접 휴지통으로 옮겨야 합니다."
        confirmAlert.alertStyle = .warning
        confirmAlert.addButton(withTitle: "제거")
        confirmAlert.addButton(withTitle: "취소")
        guard confirmAlert.runModal() == .alertFirstButtonReturn else { return }

        clearSavedSettings()
        removeTemporaryWorkingFiles()

        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])

        let doneAlert = NSAlert()
        doneAlert.messageText = "설정과 임시 파일을 삭제했습니다"
        doneAlert.informativeText = "Finder에서 Classics PDF Assistant가 선택되어 있습니다 — 휴지통으로 드래그한 뒤 휴지통을 비우면 제거가 끝납니다."
        doneAlert.addButton(withTitle: "지금 종료")
        doneAlert.runModal()

        NSApplication.shared.terminate(nil)
    }

    private static func clearSavedSettings() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
    }

    private static func removeTemporaryWorkingFiles() {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClassicsPDFAssistant", isDirectory: true)
        try? FileManager.default.removeItem(at: tempRoot)
    }
}
