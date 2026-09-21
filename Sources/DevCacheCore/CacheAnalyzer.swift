import Foundation

public struct CacheInfo: Identifiable {
    public let path: String
    public let size: UInt64
    public let lastModified: Date
    public let isSafeToDelete: Bool
    public let category: CacheCategory
    public let description: String
    public let tip: String?

    public init(
        path: String,
        size: UInt64,
        lastModified: Date,
        isSafeToDelete: Bool,
        category: CacheCategory,
        description: String,
        tip: String? = nil
    ) {
        self.path = path
        self.size = size
        self.lastModified = lastModified
        self.isSafeToDelete = isSafeToDelete
        self.category = category
        self.description = description
        self.tip = tip
    }

    public var id: String { path }
}

public struct LargeFileInfo: Identifiable, Sendable {
    public let path: String
    public let size: UInt64
    public let lastModified: Date

    public init(path: String, size: UInt64, lastModified: Date) {
        self.path = path
        self.size = size
        self.lastModified = lastModified
    }

    public var id: String { path }
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
    public var fileExtension: String {
        let ext = URL(fileURLWithPath: path).pathExtension
        return ext.isEmpty ? "无扩展名" : ext.uppercased()
    }
}

public enum CacheCategory: String, CaseIterable {
    case xcode = "Xcode"
    case androidStudio = "Android Studio"
    case nodejs = "Node.js"
    case system = "System"
    case other = "Other"
}

public final class CacheAnalyzer {
    private let fileManager = FileManager.default
    private let homeDirectory: URL

    public init() {
        homeDirectory = fileManager.homeDirectoryForCurrentUser
    }

    public func analyzeAllCaches() -> [CacheInfo] {
        var allCaches: [CacheInfo] = []

        allCaches.append(contentsOf: analyzeXcodeCaches())
        allCaches.append(contentsOf: analyzeAndroidStudioCaches())
        allCaches.append(contentsOf: analyzeNodeJSCaches())

        return allCaches.sorted { $0.size > $1.size }
    }

    /// Finds large regular files in locations the app can access. The scan is deliberately
    /// read-only; deletion is handled separately by CacheCleaner and moves items to Trash.
    public func scanLargeFiles(
        minimumSize: UInt64 = 1_000_000_000,
        maxResults: Int = .max,
        roots: [URL]? = nil
    ) -> [LargeFileInfo] {
        let scanRoots = roots ?? [URL(fileURLWithPath: "/")]
        let excludedPrefixes = [
            "/System", "/private/var/db", "/private/var/folders",
            "/Library/Apple", "/Applications", "/usr", "/bin", "/sbin",
            "/dev", "/proc", "/Volumes/com.apple.TimeMachine"
        ]
        var results: [LargeFileInfo] = []
        var seenPaths = Set<String>()

        for root in scanRoots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [
                    .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
                    .fileSizeKey, .contentModificationDateKey
                ],
                options: []
            ) else { continue }

            for case let url as URL in enumerator {
                let path = url.path
                if excludedPrefixes.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
                    enumerator.skipDescendants()
                    continue
                }

                do {
                    let values = try url.resourceValues(forKeys: [
                        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
                        .fileSizeKey, .contentModificationDateKey
                    ])
                    guard values.isSymbolicLink != true,
                          values.isDirectory != true,
                          values.isRegularFile == true,
                          let size = values.fileSize,
                          size >= minimumSize,
                          seenPaths.insert(path).inserted else { continue }

                    results.append(LargeFileInfo(
                        path: path,
                        size: UInt64(size),
                        lastModified: values.contentModificationDate ?? Date.distantPast
                    ))
                } catch {
                    continue
                }
            }
        }

        return Array(results.sorted { $0.size > $1.size }.prefix(maxResults))
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
                if let fileSize = resourceValues.fileSize, !resourceValues.isDirectory! {
                    totalSize += UInt64(fileSize)
                }
            } catch {
                continue
            }
        }

        return totalSize
    }

    private func getLastModifiedDate(at url: URL) -> Date {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            return attributes[.modificationDate] as? Date ?? Date.distantPast
        } catch {
            return Date.distantPast
        }
    }

    private func formatSize(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

extension CacheAnalyzer {
    func analyzeXcodeCaches() -> [CacheInfo] {
        var caches: [CacheInfo] = []

        let xcodeBasePath = homeDirectory.appendingPathComponent("Library/Developer/Xcode")

        let cachePaths = [
            ("DerivedData", "构建缓存和索引文件", true),
            ("iOS DeviceSupport", "设备支持文件", true),
            ("Archives", "应用打包文件", true),
        ]

        for (folder, desc, safe) in cachePaths {
            let path = xcodeBasePath.appendingPathComponent(folder)

            if fileManager.fileExists(atPath: path.path) {
                let size = getDirectorySize(at: path)
                if size > 0 {
                    caches.append(CacheInfo(
                        path: path.path,
                        size: size,
                        lastModified: getLastModifiedDate(at: path),
                        isSafeToDelete: safe,
                        category: .xcode,
                        description: desc
                    ))
                }
            }
        }

        // Core Simulator
        let simulatorPath = homeDirectory.appendingPathComponent("Library/Developer/CoreSimulator/Devices")
        if fileManager.fileExists(atPath: simulatorPath.path) {
            let size = getDirectorySize(at: simulatorPath)
            if size > 0 {
                caches.append(CacheInfo(
                    path: simulatorPath.path,
                    size: size,
                    lastModified: getLastModifiedDate(at: simulatorPath),
                    isSafeToDelete: false,
                    category: .xcode,
                    description: "模拟器数据 (包含应用数据)"
                ))
            }
        }

        return caches
    }

    func analyzeAndroidStudioCaches() -> [CacheInfo] {
        var caches: [CacheInfo] = []

        // Gradle缓存
        let gradlePath = homeDirectory.appendingPathComponent(".gradle/caches")
        if fileManager.fileExists(atPath: gradlePath.path) {
            let size = getDirectorySize(at: gradlePath)
            if size > 0 {
                caches.append(CacheInfo(
                    path: gradlePath.path,
                    size: size,
                    lastModified: getLastModifiedDate(at: gradlePath),
                    isSafeToDelete: true,
                    category: .androidStudio,
                    description: "Gradle构建缓存",
                    tip: "删除gradle缓存后再安卓目录下执行./gradlew --refresh-dependencies"
                ))
            }
        }

        // Android构建缓存
        let androidBuildCachePath = homeDirectory.appendingPathComponent(".android/build-cache")
        if fileManager.fileExists(atPath: androidBuildCachePath.path) {
            let size = getDirectorySize(at: androidBuildCachePath)
            if size > 0 {
                caches.append(CacheInfo(
                    path: androidBuildCachePath.path,
                    size: size,
                    lastModified: getLastModifiedDate(at: androidBuildCachePath),
                    isSafeToDelete: true,
                    category: .androidStudio,
                    description: "Android构建缓存"
                ))
            }
        }

        // AVD缓存
        let avdPath = homeDirectory.appendingPathComponent(".android/avd")
        if fileManager.fileExists(atPath: avdPath.path) {
            do {
                let avds = try fileManager.contentsOfDirectory(atPath: avdPath.path)
                for avd in avds where avd.hasSuffix(".avd") {
                    let cachePath = avdPath.appendingPathComponent(avd).appendingPathComponent("cache")
                    if fileManager.fileExists(atPath: cachePath.path) {
                        let size = getDirectorySize(at: cachePath)
                        if size > 0 {
                            caches.append(CacheInfo(
                                path: cachePath.path,
                                size: size,
                                lastModified: getLastModifiedDate(at: cachePath),
                                isSafeToDelete: true,
                                category: .androidStudio,
                                description: "AVD模拟器缓存: \(avd)"
                            ))
                        }
                    }
                }
            } catch {
                print("警告: 无法访问AVD目录")
            }
        }

        return caches
    }

    func analyzeNodeJSCaches() -> [CacheInfo] {
        var caches: [CacheInfo] = []

        // npm缓存
        let npmCachePath = homeDirectory.appendingPathComponent(".npm/_cacache")
        if fileManager.fileExists(atPath: npmCachePath.path) {
            let size = getDirectorySize(at: npmCachePath)
            if size > 0 {
                caches.append(CacheInfo(
                    path: npmCachePath.path,
                    size: size,
                    lastModified: getLastModifiedDate(at: npmCachePath),
                    isSafeToDelete: true,
                    category: .nodejs,
                    description: "npm包缓存"
                ))
            }
        }

        // Yarn缓存
        let yarnCachePath = homeDirectory.appendingPathComponent(".yarn/cache")
        if fileManager.fileExists(atPath: yarnCachePath.path) {
            let size = getDirectorySize(at: yarnCachePath)
            if size > 0 {
                caches.append(CacheInfo(
                    path: yarnCachePath.path,
                    size: size,
                    lastModified: getLastModifiedDate(at: yarnCachePath),
                    isSafeToDelete: true,
                    category: .nodejs,
                    description: "Yarn包缓存"
                ))
            }
        }

        // pnpm存储
        let pnpmStorePath = homeDirectory.appendingPathComponent(".pnpm-store")
        if fileManager.fileExists(atPath: pnpmStorePath.path) {
            let size = getDirectorySize(at: pnpmStorePath)
            if size > 0 {
                caches.append(CacheInfo(
                    path: pnpmStorePath.path,
                    size: size,
                    lastModified: getLastModifiedDate(at: pnpmStorePath),
                    isSafeToDelete: true,
                    category: .nodejs,
                    description: "pnpm包存储"
                ))
            }
        }

        return caches
    }
}
