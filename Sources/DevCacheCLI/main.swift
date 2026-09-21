import ArgumentParser
import Foundation
import DevCacheCore

struct DevCacheCleanerCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "devcache",
        abstract: "开发者缓存清理工具 - 智能分析和清理开发环境产生的缓存文件",
        version: "1.0.0"
    )

    @Flag(name: .shortAndLong, help: "只分析，不执行清理")
    var analyze = false

    @Flag(name: .shortAndLong, help: "自动清理所有安全的缓存文件")
    var clean = false

    @Flag(name: .shortAndLong, help: "显示详细信息")
    var verbose = false

    @Option(name: .shortAndLong, help: "只分析指定类型的缓存 (xcode/android/nodejs)")
    var type: String?

    func run() throws {
        let analyzer = CacheAnalyzer()
        let cleaner = CacheCleaner()

        print("🔍 DevCache Cleaner v1.0.0")
        print("分析开发工具缓存文件...\n")

        // 分析所有缓存
        var allCaches = analyzer.analyzeAllCaches()

        // 根据类型过滤
        if let filterType = type {
            switch filterType.lowercased() {
            case "xcode":
                allCaches = allCaches.filter { $0.category == .xcode }
            case "android":
                allCaches = allCaches.filter { $0.category == .androidStudio }
            case "nodejs", "node":
                allCaches = allCaches.filter { $0.category == .nodejs }
            default:
                print("❌ 未知的类型: \(filterType)")
                print("支持的类型: xcode, android, nodejs")
                return
            }
        }

        if allCaches.isEmpty {
            print("✨ 没有找到缓存文件，你的系统很干净！")
            return
        }

        // 显示分析结果
        displayCacheAnalysis(allCaches)

        // 如果只是分析模式，直接返回
        if analyze {
            return
        }

        // 如果是清理模式
        if clean {
            performCleanup(caches: allCaches, cleaner: cleaner)
        } else {
            // 交互模式
            performInteractiveCleanup(caches: allCaches, cleaner: cleaner)
        }
    }

    private func displayCacheAnalysis(_ caches: [CacheInfo]) {
        let totalSize = caches.reduce(0) { $0 + $1.size }
        let safeToDeleteSize = caches.filter { $0.isSafeToDelete }.reduce(0) { $0 + $1.size }

        print("📊 缓存分析结果:")
        print("总缓存大小: \(CacheFormatter.formatSize(totalSize))")
        print("可安全清理: \(CacheFormatter.formatSize(safeToDeleteSize))")
        print("需确认清理: \(CacheFormatter.formatSize(totalSize - safeToDeleteSize))")
        print()

        // 按类别分组显示
        let groupedCaches = Dictionary(grouping: caches) { $0.category }

        for category in CacheCategory.allCases {
            guard let categoryCache = groupedCaches[category], !categoryCache.isEmpty else { continue }

            let categorySize = categoryCache.reduce(0) { $0 + $1.size }

            print("📂 \(category.rawValue) (总计: \(CacheFormatter.formatSize(categorySize)))")

            for cache in categoryCache {
                let safetyIcon = cache.isSafeToDelete ? "✅" : "⚠️"
                let sizeStr = CacheFormatter.formatSize(cache.size)

                if verbose {
                    print("  \(safetyIcon) \(sizeStr.padding(toLength: 10, withPad: " ", startingAt: 0)) \(cache.description)")
                    print("      路径: \(cache.path)")
                    print("      修改时间: \(CacheFormatter.formatDate(cache.lastModified))")
                } else {
                    print("  \(safetyIcon) \(sizeStr.padding(toLength: 10, withPad: " ", startingAt: 0)) \(cache.description)")
                }
            }
            print()
        }
    }

    private func performCleanup(caches: [CacheInfo], cleaner: CacheCleaner) {
        print("🧹 开始自动清理安全的缓存文件...")

        let results = cleaner.cleanSafeCaches(caches)
        let report = cleaner.generateCleanupReport(results)

        print(report)

        // 显示需要手动处理的文件
        let unsafeCaches = caches.filter { !$0.isSafeToDelete }
        if !unsafeCaches.isEmpty {
            print("\n⚠️  以下文件需要手动确认后清理:")
            for cache in unsafeCaches {
                print("  📁 \(CacheFormatter.formatSize(cache.size).padding(toLength: 10, withPad: " ", startingAt: 0)) \(cache.description)")
                print("      路径: \(cache.path)")
            }
            print("\n💡 使用 --verbose 查看详细信息，或手动删除这些文件")
        }
    }

    private func performInteractiveCleanup(caches: [CacheInfo], cleaner: CacheCleaner) {
        print("🤔 选择操作:")
        print("1. 清理所有安全的缓存文件")
        print("2. 选择性清理")
        print("3. 退出")
        print("\n请输入选择 (1-3): ", terminator: "")

        guard let input = readLine(), let choice = Int(input) else {
            print("❌ 无效输入")
            return
        }

        switch choice {
        case 1:
            performCleanup(caches: caches, cleaner: cleaner)
        case 2:
            performSelectiveCleanup(caches: caches, cleaner: cleaner)
        case 3:
            print("👋 退出程序")
        default:
            print("❌ 无效选择")
        }
    }

    private func performSelectiveCleanup(caches: [CacheInfo], cleaner: CacheCleaner) {
        print("\n🎯 选择性清理模式:")

        for (index, cache) in caches.enumerated() {
            let safetyIcon = cache.isSafeToDelete ? "✅" : "⚠️"
            print("\n\(index + 1). \(safetyIcon) \(cache.description)")
            print("   大小: \(CacheFormatter.formatSize(cache.size))")
            print("   路径: \(cache.path)")
            print("   是否清理? (y/N): ", terminator: "")

            let input = readLine()?.lowercased()
            if input == "y" || input == "yes" {
                let result = cleaner.cleanSpecificPath(
                    cache.path,
                    requireConfirmation: !cache.isSafeToDelete
                ) {
                    print("⚠️  确认删除: \(cache.path)")
                    print("按 y 确认, 按其他键取消:")
                    let confirmInput = readLine()?.lowercased()
                    return confirmInput == "y" || confirmInput == "yes"
                }

                switch result {
                case .success(let freedSpace):
                    print("✅ 成功清理，释放空间: \(CacheFormatter.formatSize(freedSpace))")
                case .failed(let error):
                    print("❌ 清理失败: \(error.localizedDescription)")
                case .skipped(let reason):
                    print("⏭️  跳过: \(reason)")
                }
            }
        }

        print("\n🎉 选择性清理完成！")
    }
}

DevCacheCleanerCommand.main()
