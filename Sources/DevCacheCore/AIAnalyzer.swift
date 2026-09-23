import Foundation

public struct AIModelConfiguration: Codable, Equatable, Sendable {
    public var baseURL: String
    public var model: String
    public var apiKey: String

    public init(
        baseURL: String = "https://openrouter.ai/api/v1",
        model: String = "openrouter/free",
        apiKey: String = ""
    ) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
    }

    public var isReady: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct AIFileAnalysis: Codable, Sendable {
    public let canDelete: Bool
    public let confidence: Int
    public let riskLevel: String
    public let recommendation: String
    public let explanation: String
    public let deletionCommand: String

    public init(
        canDelete: Bool,
        confidence: Int,
        riskLevel: String,
        recommendation: String,
        explanation: String,
        deletionCommand: String
    ) {
        self.canDelete = canDelete
        self.confidence = confidence
        self.riskLevel = riskLevel
        self.recommendation = recommendation
        self.explanation = explanation
        self.deletionCommand = deletionCommand
    }
}

public struct AIAnalysisTarget: Identifiable, Sendable {
    public let path: String
    public let name: String
    public let size: UInt64
    public let lastModified: Date
    public let kind: String

    public init(path: String, size: UInt64, lastModified: Date, kind: String) {
        self.path = path
        self.name = URL(fileURLWithPath: path).lastPathComponent
        self.size = size
        self.lastModified = lastModified
        self.kind = kind
    }

    public init(file: LargeFileInfo) {
        self.init(path: file.path, size: file.size, lastModified: file.lastModified, kind: "文件")
    }

    public init(cache: CacheInfo) {
        self.init(path: cache.path, size: cache.size, lastModified: cache.lastModified, kind: "开发缓存目录（\(cache.category.rawValue)）")
    }

    public var id: String { path }

    public var fileExtension: String {
        let ext = URL(fileURLWithPath: path).pathExtension
        return ext.isEmpty ? "无扩展名" : ext.uppercased()
    }
}

public enum AIAnalyzerError: LocalizedError {
    case invalidBaseURL
    case missingAPIKey
    case requestFailed(String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL: return "AI 服务地址无效"
        case .missingAPIKey: return "请先在设置中填写 API Key"
        case .requestFailed(let message): return message
        case .invalidResponse: return "AI 返回内容无法解析"
        }
    }
}

public final class AIAnalyzer: Sendable {
    public init() {}

    public func analyze(file: LargeFileInfo, configuration: AIModelConfiguration) async throws -> AIFileAnalysis {
        try await analyze(target: AIAnalysisTarget(file: file), configuration: configuration)
    }

    public func analyze(cache: CacheInfo, configuration: AIModelConfiguration) async throws -> AIFileAnalysis {
        try await analyze(target: AIAnalysisTarget(cache: cache), configuration: configuration)
    }

    public func analyze(target: AIAnalysisTarget, configuration: AIModelConfiguration) async throws -> AIFileAnalysis {
        guard configuration.isReady else { throw AIAnalyzerError.missingAPIKey }
        guard let baseURL = URL(string: configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw AIAnalyzerError.invalidBaseURL
        }

        let endpoint = baseURL.appendingPathComponent("chat/completions")
        let prompt = """
        你是 macOS 磁盘清理安全顾问。请分析下面的文件或开发缓存目录是否适合删除。
        不要因为体积大就直接建议删除；要考虑它可能是系统文件、用户数据、项目源文件、开发工具缓存、构建产物或容器数据。
        所有 recommendation、explanation、riskLevel 字符串必须使用简体中文；riskLevel 只能是“低”“中”“高”。
        只返回合法 JSON，不要 Markdown、代码围栏或额外说明，字段必须为：
        canDelete（布尔值）、confidence（0 到 100 的整数）、riskLevel（字符串）、recommendation（中文字符串）、explanation（中文字符串）、deletionCommand（字符串）。
        如果建议删除，deletionCommand 必须使用下面的确切路径生成将项目移入 macOS 废纸篓的命令：
        osascript -e 'tell application "Finder" to delete POSIX file "确切路径"'
        如果不建议删除，deletionCommand 返回空字符串。不要生成 rm -rf，不要执行命令。

        名称：\(target.name)
        路径：\(target.path)
        类型：\(target.kind)
        扩展名：\(target.fileExtension)
        大小：\(CacheFormatter.formatSize(target.size))
        最后修改：\(CacheFormatter.formatDate(target.lastModified))
        """

        let body = ChatRequest(
            model: configuration.model,
            temperature: 0.1,
            messages: [
                ChatMessage(role: "system", content: "你是一名谨慎的 macOS 存储清理助手。必须用简体中文解释结果，必须只返回可解析的 JSON。"),
                ChatMessage(role: "user", content: prompt)
            ]
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIAnalyzerError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "AI 请求失败"
            throw AIAnalyzerError.requestFailed("AI 请求失败（\(httpResponse.statusCode)）：\(message)")
        }

        let completion = try JSONDecoder().decode(ChatResponse.self, from: data)
        let content = completion.choices.first?.message.content ?? ""
        let json = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jsonData = json.data(using: .utf8) else { throw AIAnalyzerError.invalidResponse }
        return try JSONDecoder().decode(AIFileAnalysis.self, from: jsonData)
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let temperature: Double
    let messages: [ChatMessage]
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        let message: ChatMessage
    }
    let choices: [Choice]
}
