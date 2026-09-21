import Foundation

public final class CacheCleaner {
    private let fileManager = FileManager.default

    public enum CleanupResult {
        case success(freedSpace: UInt64)
        case failed(error: Error)
        case skipped(reason: String)
    }

    public init() {}

    public func cleanSafeCaches(_ caches: [CacheInfo]) -> [CleanupResult] {
        let safeCaches = caches.filter { $0.isSafeToDelete }
        return safeCaches.map { cleanCache($0) }
    }

    public func cleanCache(_ cache: CacheInfo) -> CleanupResult {
        guard cache.isSafeToDelete else {
            return .skipped(reason: "需要用户确认才能删除")
        }

        return cleanPath(cache.path, expectedSize: cache.size)
    }

    public func cleanSpecificPath(
        _ path: String,
        requireConfirmation: Bool = true,
        confirmationHandler: (() -> Bool)? = nil
    ) -> CleanupResult {
        guard fileManager.fileExists(atPath: path) else {
            return .skipped(reason: "路径不存在")
        }

        if requireConfirmation && !(confirmationHandler?() ?? false) {
            return .skipped(reason: "需要确认")
        }

        let size = directorySizeIfPossible(at: URL(fileURLWithPath: path))
        return cleanPath(path, expectedSize: size)
    }

    public func generateCleanupReport(_ results: [CleanupResult]) -> String {
        var report = "\n=== 清理报告 ===\n"

        var totalFreed: UInt64 = 0
        var successCount = 0
        var failedCount = 0
        var skippedCount = 0

        for result in results {
            switch result {
            case .success(let freedSpace):
                totalFreed += freedSpace
                successCount += 1
            case .failed:
                failedCount += 1
            case .skipped:
                skippedCount += 1
            }
        }

        report += "✅ 成功清理: \(successCount) 项\n"
        report += "❌ 清理失败: \(failedCount) 项\n"
        report += "⏭️  跳过清理: \(skippedCount) 项\n"
        report += "💾 释放空间: \(formatSize(totalFreed))\n"

        return report
    }

    // MARK: - Private

    private func cleanPath(_ path: String, expectedSize: UInt64) -> CleanupResult {
        let cacheURL = URL(fileURLWithPath: path)

        guard fileManager.fileExists(atPath: path) else {
            return .skipped(reason: "文件不存在")
        }

        do {
            var targetURL: NSURL?
            try fileManager.trashItem(at: cacheURL, resultingItemURL: &targetURL)

            return .success(freedSpace: expectedSize)
        } catch {
            return .failed(error: error)
        }
    }

    private func directorySizeIfPossible(at url: URL) -> UInt64 {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return 0
        }

        guard isDirectory.boolValue else {
            return fileSize(at: url)
        }

        return getDirectorySize(at: url)
    }

    private func fileSize(at url: URL) -> UInt64 {
        do {
            let attrs = try fileManager.attributesOfItem(atPath: url.path)
            if let number = attrs[.size] as? NSNumber {
                return number.uint64Value
            }
            return 0
        } catch {
            return 0
        }
    }

    private func getDirectorySize(at url: URL) -> UInt64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var totalSize: UInt64 = 0

        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                if let fileSize = resourceValues.fileSize, resourceValues.isDirectory != true {
                    totalSize += UInt64(fileSize)
                }
            } catch {
                continue
            }
        }

        return totalSize
    }

    private func formatSize(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
