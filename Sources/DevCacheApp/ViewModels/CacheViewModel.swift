import Foundation
import DevCacheCore
import AppKit

@MainActor
final class CacheViewModel: ObservableObject {
    @Published var caches: [CacheInfo] = []
    @Published var selectedCacheIDs: Set<CacheInfo.ID> = []
    @Published var isAnalyzing = false
    @Published var isCleaning = false
    @Published var lastError: String?
    @Published var toastMessage: String?
    @Published var directoryTree: DirectoryNode?
    @Published var isLoadingDirectory = false
    @Published var nodePendingDeletion: DirectoryNode?
    @Published var isDeletingNode = false
    @Published var largeFiles: [LargeFileInfo] = []
    @Published var selectedLargeFilePaths: Set<String> = []
    @Published var isScanningLargeFiles = false
    @Published var largeFileMinimumSizeGB: Double = 1.0
    @Published var largeFilePendingDeletion: LargeFileInfo?

    func analyzeAllCaches(preserveSelection: Bool = false) {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        lastError = nil

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                CacheAnalyzer().analyzeAllCaches()
            }.value

            self.caches = result
            if preserveSelection {
                let validIDs = Set(result.map(\.id))
                self.selectedCacheIDs = self.selectedCacheIDs.intersection(validIDs)
            } else {
                self.selectedCacheIDs = Set(result.filter { $0.isSafeToDelete }.map(\.id))
            }
            self.isAnalyzing = false
            self.inspectFirstSelectedCache()
        }
    }

    func cleanSafeCaches() {
        guard !isCleaning else { return }
        isCleaning = true
        lastError = nil

        let safeCaches = caches.filter { $0.isSafeToDelete }

        Task {
            let results = await Task.detached(priority: .userInitiated) {
                CacheCleaner().cleanSafeCaches(safeCaches)
            }.value

            handleCleanupResults(results)
            self.isCleaning = false
            self.analyzeAllCaches()
        }
    }

    func cleanSelectedCaches() {
        guard !isCleaning else { return }
        isCleaning = true
        lastError = nil

        let cachesToClean = caches.filter { selectedCacheIDs.contains($0.id) }

        Task {
            let results = await Task.detached(priority: .userInitiated) {
                let cleaner = CacheCleaner()
                return cachesToClean.map {
                    cleaner.cleanSpecificPath($0.path, requireConfirmation: false)
                }
            }.value

            handleCleanupResults(results)
            self.isCleaning = false
            self.analyzeAllCaches()
        }
    }

    func scanLargeFiles() {
        guard !isScanningLargeFiles else { return }
        isScanningLargeFiles = true
        lastError = nil

        let minimumSize = UInt64(largeFileMinimumSizeGB * 1_000_000_000)
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                CacheAnalyzer().scanLargeFiles(minimumSize: minimumSize)
            }.value

            self.largeFiles = result
            self.selectedLargeFilePaths = []
            self.isScanningLargeFiles = false
            self.toastMessage = result.isEmpty
                ? "没有找到超过 \(String(format: "%.1f", self.largeFileMinimumSizeGB)) GB 的文件"
                : "找到 \(result.count) 个大文件"
        }
    }

    func requestLargeFileDeletion(_ file: LargeFileInfo) {
        largeFilePendingDeletion = file
    }

    func cancelLargeFileDeletion() {
        largeFilePendingDeletion = nil
    }

    func confirmLargeFileDeletion() {
        guard let file = largeFilePendingDeletion else { return }
        largeFilePendingDeletion = nil
        deleteLargeFiles([file])
    }

    func deleteSelectedLargeFiles() {
        let files = largeFiles.filter { selectedLargeFilePaths.contains($0.path) }
        guard !files.isEmpty else { return }
        deleteLargeFiles(files)
    }

    func clearLargeFileSelection() {
        selectedLargeFilePaths.removeAll()
    }

    func revealLargeFile(_ file: LargeFileInfo) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)])
    }

    func toggleSelection(for cache: CacheInfo) {
        if selectedCacheIDs.contains(cache.id) {
            selectedCacheIDs.remove(cache.id)
        } else {
            selectedCacheIDs.insert(cache.id)
        }
    }

    func requestDeletion(for node: DirectoryNode) {
        nodePendingDeletion = node
    }

    func cancelDeletionRequest() {
        nodePendingDeletion = nil
    }

    func confirmDeletion() {
        guard let node = nodePendingDeletion, !isDeletingNode else { return }
        isDeletingNode = true

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                CacheCleaner().cleanSpecificPath(node.path, requireConfirmation: false)
            }.value

            switch result {
            case .success(let freedSpace):
                self.toastMessage = "已清理 \(CacheFormatter.formatSize(freedSpace))"
            case .failed(let error):
                self.lastError = error.localizedDescription
            case .skipped(let reason):
                self.toastMessage = reason
            }

            self.isDeletingNode = false
            self.nodePendingDeletion = nil
            self.inspectFirstSelectedCache()
            self.analyzeAllCaches(preserveSelection: true)
        }
    }

    func selectAllSafeCaches() {
        selectedCacheIDs = Set(caches.filter { $0.isSafeToDelete }.map(\.id))
    }

    func clearSelection() {
        selectedCacheIDs.removeAll()
        directoryTree = nil
    }

    var totalSize: UInt64 {
        caches.reduce(0) { $0 + $1.size }
    }

    var safeSize: UInt64 {
        caches.filter { $0.isSafeToDelete }.reduce(0) { $0 + $1.size }
    }

    var requiresConfirmationSize: UInt64 {
        totalSize - safeSize
    }

    var safeCaches: [CacheInfo] {
        caches.filter { $0.isSafeToDelete }
    }

    var riskyCaches: [CacheInfo] {
        caches.filter { !$0.isSafeToDelete }
    }

    var firstSelectedCache: CacheInfo? {
        caches.first { selectedCacheIDs.contains($0.id) }
    }

    func revealFirstSelectedInFinder() {
        guard let cache = firstSelectedCache else { return }
        let url = URL(fileURLWithPath: cache.path, isDirectory: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func inspectFirstSelectedCache() {
        guard let cache = firstSelectedCache else {
            directoryTree = nil
            isLoadingDirectory = false
            return
        }

        isLoadingDirectory = true
        let targetURL = URL(fileURLWithPath: cache.path, isDirectory: true)

        Task {
            let node = await Task.detached(priority: .userInitiated) {
                DirectoryInspector.buildTree(at: targetURL)
            }.value

            self.directoryTree = node
            self.isLoadingDirectory = false
        }
    }

    private func handleCleanupResults(_ results: [CacheCleaner.CleanupResult]) {
        let freedSpace = results.compactMap { result -> UInt64? in
            if case let .success(size) = result {
                return size
            }
            return nil
        }.reduce(0, +)

        let failedCount = results.filter {
            if case .failed = $0 { return true }
            return false
        }.count

        let skippedCount = results.filter {
            if case .skipped = $0 { return true }
            return false
        }.count

        var messages: [String] = []
        if freedSpace > 0 {
            messages.append("释放空间 \(CacheFormatter.formatSize(freedSpace))")
        }
        if failedCount > 0 {
            messages.append("失败 \(failedCount) 项")
        }
        if skippedCount > 0 {
            messages.append("跳过 \(skippedCount) 项")
        }

        toastMessage = messages.isEmpty ? "清理完成" : messages.joined(separator: " · ")
    }

    private func deleteLargeFiles(_ files: [LargeFileInfo]) {
        guard !isCleaning else { return }
        isCleaning = true
        Task {
            let results = await Task.detached(priority: .userInitiated) {
                let cleaner = CacheCleaner()
                return files.map {
                    cleaner.cleanSpecificPath($0.path, requireConfirmation: false)
                }
            }.value
            handleCleanupResults(results)
            self.isCleaning = false
            self.selectedLargeFilePaths = []
            self.scanLargeFiles()
        }
    }
}
