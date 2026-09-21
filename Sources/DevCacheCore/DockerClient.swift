import Foundation

public struct DockerUsage: Sendable {
    public let imageCount: Int
    public let imageSize: UInt64
    public let containerCount: Int
    public let containerSize: UInt64
    public let volumeCount: Int
    public let volumeSize: UInt64
    public let buildCacheSize: UInt64
    public let buildCacheReclaimable: UInt64

    public init(
        imageCount: Int = 0,
        imageSize: UInt64 = 0,
        containerCount: Int = 0,
        containerSize: UInt64 = 0,
        volumeCount: Int = 0,
        volumeSize: UInt64 = 0,
        buildCacheSize: UInt64 = 0,
        buildCacheReclaimable: UInt64 = 0
    ) {
        self.imageCount = imageCount
        self.imageSize = imageSize
        self.containerCount = containerCount
        self.containerSize = containerSize
        self.volumeCount = volumeCount
        self.volumeSize = volumeSize
        self.buildCacheSize = buildCacheSize
        self.buildCacheReclaimable = buildCacheReclaimable
    }
}

public struct DockerService: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let image: String
    public let status: String
    public let ports: String

    public init(id: String, name: String, image: String, status: String, ports: String) {
        self.id = id
        self.name = name
        self.image = image
        self.status = status
        self.ports = ports
    }
}

public enum DockerClientError: LocalizedError {
    case commandFailed(String)
    case unavailable

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let message): return message
        case .unavailable: return "Docker Desktop 未运行或 Docker 命令不可用"
        }
    }
}

/// Read-only Docker inspection plus the narrowly scoped build-cache cleanup.
/// It never removes containers, images, volumes, or networks.
public final class DockerClient: Sendable {
    public init() {}

    public func inspect() throws -> (usage: DockerUsage, services: [DockerService]) {
        let usage = try readUsage()
        let services = try readServices()
        return (usage, services)
    }

    @discardableResult
    public func pruneBuildCache() throws -> UInt64 {
        let output = try run(["builder", "prune", "--force"])
        guard let match = output.range(of: #"Total reclaimed space:\s*([0-9.]+)\s*([KMGT]?B)"#, options: .regularExpression) else {
            return 0
        }

        let line = String(output[match])
        let parts = line.replacingOccurrences(of: "Total reclaimed space:", with: "")
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ")
        guard parts.count == 2, let value = Double(parts[0]) else { return 0 }
        return Self.parseBytes(value: value, unit: String(parts[1]))
    }

    private func readUsage() throws -> DockerUsage {
        let output = try run(["system", "df", "--format", "{{.Type}}\t{{.TotalCount}}\t{{.Active}}\t{{.Size}}\t{{.Reclaimable}}"])
        var usage = DockerUsage()

        for line in output.split(whereSeparator: \.isNewline) {
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard columns.count >= 5 else { continue }
            let count = Int(columns[1]) ?? 0
            let size = Self.parseBytes(from: columns[3])
            let reclaimable = Self.parseBytes(from: columns[4])

            switch columns[0] {
            case "Images":
                usage = DockerUsage(imageCount: count, imageSize: size,
                                    containerCount: usage.containerCount, containerSize: usage.containerSize,
                                    volumeCount: usage.volumeCount, volumeSize: usage.volumeSize,
                                    buildCacheSize: usage.buildCacheSize, buildCacheReclaimable: usage.buildCacheReclaimable)
            case "Containers":
                usage = DockerUsage(imageCount: usage.imageCount, imageSize: usage.imageSize,
                                    containerCount: count, containerSize: size,
                                    volumeCount: usage.volumeCount, volumeSize: usage.volumeSize,
                                    buildCacheSize: usage.buildCacheSize, buildCacheReclaimable: usage.buildCacheReclaimable)
            case "Local Volumes":
                usage = DockerUsage(imageCount: usage.imageCount, imageSize: usage.imageSize,
                                    containerCount: usage.containerCount, containerSize: usage.containerSize,
                                    volumeCount: count, volumeSize: size,
                                    buildCacheSize: usage.buildCacheSize, buildCacheReclaimable: usage.buildCacheReclaimable)
            case "Build Cache":
                usage = DockerUsage(imageCount: usage.imageCount, imageSize: usage.imageSize,
                                    containerCount: usage.containerCount, containerSize: usage.containerSize,
                                    volumeCount: usage.volumeCount, volumeSize: usage.volumeSize,
                                    buildCacheSize: size, buildCacheReclaimable: reclaimable)
            default:
                continue
            }
        }
        return usage
    }

    private func readServices() throws -> [DockerService] {
        let output = try run(["ps", "--format", "{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"])
        return output.split(whereSeparator: \.isNewline).compactMap { line in
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard columns.count >= 5 else { return nil }
            return DockerService(id: columns[0], name: columns[1], image: columns[2], status: columns[3], ports: columns[4])
        }
    }

    private func run(_ arguments: [String]) throws -> String {
        guard let executable = [
            "/Applications/Docker.app/Contents/Resources/bin/docker",
            "/opt/homebrew/bin/docker",
            "/usr/local/bin/docker"
        ].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw DockerClientError.unavailable
        }

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw DockerClientError.commandFailed(error.isEmpty ? output : error.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }

    private static func parseBytes(from text: String) -> UInt64 {
        let cleaned = text.replacingOccurrences(of: #"\s*\(.*\)$"#, with: "", options: .regularExpression)
        guard let match = cleaned.range(of: #"([0-9.]+)\s*([KMGT]?B)"#, options: .regularExpression) else { return 0 }
        let valueText = String(cleaned[match]).replacingOccurrences(of: #"[^0-9.]"#, with: "", options: .regularExpression)
        let unit = cleaned[match].replacingOccurrences(of: #"[0-9.\s]"#, with: "", options: .regularExpression)
        return parseBytes(value: Double(valueText) ?? 0, unit: unit)
    }

    private static func parseBytes(value: Double, unit: String) -> UInt64 {
        let multiplier: Double
        switch unit.uppercased() {
        case "KB": multiplier = 1_000
        case "MB": multiplier = 1_000_000
        case "GB": multiplier = 1_000_000_000
        case "TB": multiplier = 1_000_000_000_000
        default: multiplier = 1
        }
        return UInt64(max(0, value * multiplier))
    }
}
