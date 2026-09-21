import Foundation

struct DirectoryNode: Identifiable, Sendable {
    let path: String
    let name: String
    let size: UInt64
    let isDirectory: Bool
    var children: [DirectoryNode]

    var id: String { path }
}

extension DirectoryNode {
    var nonEmptyChildren: [DirectoryNode]? {
        children.isEmpty ? nil : children
    }
}


enum DirectoryInspector {
    static func buildTree(at url: URL, maxDepth: Int = 3, maxChildren: Int = 50) -> DirectoryNode? {
        buildNode(at: url, depth: 0, maxDepth: maxDepth, maxChildren: maxChildren)
    }

    private static func buildNode(at url: URL, depth: Int, maxDepth: Int, maxChildren: Int) -> DirectoryNode? {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return nil
        }

        let name = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        let size = isDirectory.boolValue ? directorySize(at: url) : fileSize(at: url)

        var children: [DirectoryNode] = []
        if isDirectory.boolValue, depth < maxDepth {
            do {
                let contents = try fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                    options: [.skipsHiddenFiles]
                )

                for childURL in contents {
                    if let node = buildNode(at: childURL, depth: depth + 1, maxDepth: maxDepth, maxChildren: maxChildren) {
                        children.append(node)
                    }
                }

                children.sort { $0.size > $1.size }
                if children.count > maxChildren {
                    children = Array(children.prefix(maxChildren))
                }
            } catch {
                // 忽略无法读取的目录
            }
        }

        return DirectoryNode(
            path: url.path,
            name: name,
            size: size,
            isDirectory: isDirectory.boolValue,
            children: children
        )
    }

    private static func directorySize(at url: URL) -> UInt64 {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            do {
                let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                if values.isDirectory == true {
                    continue
                }
                if let size = values.fileSize {
                    total += UInt64(size)
                }
            } catch {
                continue
            }
        }
        return total
    }

    private static func fileSize(at url: URL) -> UInt64 {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            if let number = attrs[.size] as? NSNumber {
                return number.uint64Value
            }
            return 0
        } catch {
            return 0
        }
    }
}
