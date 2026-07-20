import Foundation

@MainActor
final class VaultManager: ObservableObject {
    @Published var vaultURL: URL?
    @Published var errorMessage: String?
    @Published var lastSavedFilename: String?

    private let bookmarkKey = "vaultBookmark"
    private let transcriptsFolderName = "Meta Transcripts"

    init() {
        restoreAccess()
    }

    func setVaultFolder(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Couldn't access the selected folder"
            return
        }
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            vaultURL = url
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't save folder access: \(error.localizedDescription)"
        }
    }

    private func restoreAccess() {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Couldn't restore folder access — pick the vault folder again"
                return
            }
            vaultURL = url
            if isStale, let refreshed = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
            }
        } catch {
            errorMessage = "Couldn't resolve saved folder: \(error.localizedDescription)"
        }
    }

    func saveTranscript(_ text: String) {
        guard let vaultURL else {
            errorMessage = "No vault folder selected"
            return
        }

        let folderURL = vaultURL.appendingPathComponent(transcriptsFolderName, isDirectory: true)

        let filenameFormatter = DateFormatter()
        filenameFormatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let filename = "\(filenameFormatter.string(from: Date())).md"
        let fileURL = folderURL.appendingPathComponent(filename)

        let heading = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
        let content = "# Meta transcript — \(heading)\n\n\(text)\n"

        var writeError: Error?
        var coordinatorError: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: fileURL, options: [], error: &coordinatorError) { url in
            do {
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                writeError = error
            }
        }

        if let coordinatorError {
            errorMessage = "File coordination failed: \(coordinatorError.localizedDescription)"
        } else if let writeError {
            errorMessage = "Couldn't write transcript: \(writeError.localizedDescription)"
        } else {
            errorMessage = nil
            lastSavedFilename = filename
            print("Saved transcript to \(fileURL.path)")
        }
    }
}
