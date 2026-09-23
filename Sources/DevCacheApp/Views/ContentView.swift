import SwiftUI
import DevCacheCore
import AppKit

private enum AppSection: Hashable {
    case developerCaches
    case largeFiles
    case settings
}

struct ContentView: View {
    @EnvironmentObject private var viewModel: CacheViewModel
    @State private var selection: AppSection? = .developerCaches

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("清理工具") {
                    Label("开发缓存", systemImage: "hammer.fill")
                        .tag(AppSection.developerCaches)
                    Label("大文件", systemImage: "doc.richtext.fill")
                        .tag(AppSection.largeFiles)
                }

                Section("应用") {
                    Label("AI 设置", systemImage: "slider.horizontal.3")
                        .tag(AppSection.settings)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("DevCache Cleaner")
        } detail: {
            Group {
                switch selection ?? .developerCaches {
                case .developerCaches:
                    DeveloperCachesView()
                case .largeFiles:
                    LargeFilesView()
                case .settings:
                    AISettingsView()
                }
            }
            .frame(minWidth: 980, minHeight: 700)
        }
        .task {
            if viewModel.caches.isEmpty { viewModel.analyzeAllCaches() }
            if viewModel.dockerUsage == nil { viewModel.refreshDocker() }
        }
        .overlay(alignment: .bottom) {
            if let message = viewModel.toastMessage {
                ToastView(message: message)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { viewModel.lastError != nil },
                set: { if !$0 { viewModel.lastError = nil } }
            ),
            presenting: viewModel.lastError
        ) { _ in
            Button("好的", role: .cancel) {}
        } message: { error in
            Text(error)
        }
        .confirmationDialog(
            "确认删除大文件?",
            isPresented: Binding(
                get: { viewModel.largeFilePendingDeletion != nil },
                set: { if !$0 { viewModel.cancelLargeFileDeletion() } }
            ),
            presenting: viewModel.largeFilePendingDeletion
        ) { file in
            Button("移到废纸篓", role: .destructive) {
                viewModel.confirmLargeFileDeletion()
            }
            Button("取消", role: .cancel) {}
        } message: { file in
            Text("\(file.name) · \(CacheFormatter.formatSize(file.size))\n删除后可从废纸篓恢复。")
        }
        .sheet(
            isPresented: $viewModel.isAIAnalysisPresented,
            onDismiss: { viewModel.cancelAIAnalysis() }
        ) {
            AIAnalysisView()
                .environmentObject(viewModel)
        }
    }
}

private struct DeveloperCachesView: View {
    @EnvironmentObject private var viewModel: CacheViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(
                eyebrow: "DEVELOPER CLEANUP",
                title: "开发缓存",
                subtitle: "集中查看 Xcode、Android Studio、Node.js 和 Docker 的开发环境占用。",
                actions: {
                    Button {
                        viewModel.analyzeAllCaches()
                    } label: {
                        Label("刷新开发缓存", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isAnalyzing || viewModel.isCleaning)

                    Button {
                        viewModel.cleanSafeCaches()
                    } label: {
                        Label("清理安全项", systemImage: "checkmark.shield")
                    }
                    .disabled(viewModel.isAnalyzing || viewModel.isCleaning || viewModel.safeCaches.isEmpty)

                    AIAnalyzeButton {
                        viewModel.analyzeSelectedCaches()
                    }
                    .disabled(viewModel.selectedCacheIDs.isEmpty || viewModel.isAnalyzingFile)
                }
            )

            HStack(spacing: 12) {
                SummaryCard(title: "总缓存", value: CacheFormatter.formatSize(viewModel.totalSize), subtitle: "当前发现", icon: "externaldrive.fill")
                SummaryCard(title: "可安全清理", value: CacheFormatter.formatSize(viewModel.safeSize), subtitle: "无需逐项确认", icon: "checkmark.shield.fill", tint: .green)
                SummaryCard(title: "需要确认", value: CacheFormatter.formatSize(viewModel.requiresConfirmationSize), subtitle: "建议先检查", icon: "exclamationmark.triangle.fill", tint: .orange)
            }

            HStack {
                Text("开发缓存明细")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("全选安全项") { viewModel.selectAllSafeCaches() }
                    .disabled(viewModel.caches.isEmpty)
                Button("清空选择") { viewModel.clearSelection() }
                    .disabled(viewModel.selectedCacheIDs.isEmpty)
                Button("清理选中", role: .destructive) { viewModel.cleanSelectedCaches() }
                .disabled(viewModel.selectedCacheIDs.isEmpty || viewModel.isCleaning)
            }

            Text("提示：可多选缓存后进行 AI 分析，也可以双击任意一项直接分析。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if viewModel.isAnalyzing {
                ProgressView("正在分析开发缓存...")
                    .progressViewStyle(.linear)
            }

            Table(viewModel.caches, selection: $viewModel.selectedCacheIDs) {
                TableColumn("类别") { cache in
                    Label(cache.category.rawValue, systemImage: icon(for: cache.category))
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { viewModel.analyzeCache(cache) }
                }
                TableColumn("说明", value: \.description)
                TableColumn("大小") { cache in
                    Text(CacheFormatter.formatSize(cache.size)).fontWeight(.semibold)
                }
                TableColumn("状态") { cache in
                    Label(cache.isSafeToDelete ? "安全" : "需确认", systemImage: cache.isSafeToDelete ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(cache.isSafeToDelete ? .green : .orange)
                }
                TableColumn("路径") { cache in
                    Text(cache.path).font(.caption.monospaced()).lineLimit(1)
                }
            }
            .frame(minHeight: 320)
        }
        .padding(28)
    }

    private func icon(for category: CacheCategory) -> String {
        switch category {
        case .xcode: return "hammer.fill"
        case .androidStudio: return "antenna.radiowaves.left.and.right"
        case .nodejs: return "leaf.fill"
        case .system: return "gearshape.fill"
        case .other: return "tray.fill"
        }
    }
}

private struct LargeFilesView: View {
    @EnvironmentObject private var viewModel: CacheViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(
                eyebrow: "STORAGE INSPECTOR",
                title: "大文件扫描",
                subtitle: "扫描可访问位置，按大小找出真正占用空间的文件。",
                actions: {
                    Stepper(value: $viewModel.largeFileMinimumSizeGB, in: 0.1...100, step: 0.1) {
                        Text("大于 \(viewModel.largeFileMinimumSizeGB, specifier: "%.1f") GB")
                            .monospacedDigit()
                    }
                    .frame(width: 170)

                    Button {
                        viewModel.scanLargeFiles()
                    } label: {
                        Label("开始扫描", systemImage: "magnifyingglass")
                    }
                    .disabled(viewModel.isScanningLargeFiles || viewModel.isCleaning)
                }
            )

            HStack {
                Text(viewModel.largeFiles.isEmpty ? "还没有扫描结果" : "找到 \(viewModel.largeFiles.count) 个文件 · \(CacheFormatter.formatSize(viewModel.largeFiles.reduce(0) { $0 + $1.size }))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("在访达中显示") {
                    if let file = selectedFile { viewModel.revealLargeFile(file) }
                }
                .disabled(selectedFile == nil)
                AIAnalyzeButton {
                    viewModel.analyzeSelectedLargeFiles()
                }
                .disabled(selectedFile == nil || viewModel.isAnalyzingFile)
                Button("删除选中", role: .destructive) {
                    viewModel.deleteSelectedLargeFiles()
                }
                .disabled(viewModel.selectedLargeFilePaths.isEmpty || viewModel.isCleaning)
            }

            Text("提示：可按住 Command 多选文件进行 AI 分析，也可以双击文件直接分析。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if viewModel.isScanningLargeFiles {
                ProgressView("正在扫描磁盘，请稍候...")
                    .progressViewStyle(.linear)
            }

            Table(viewModel.largeFiles, selection: $viewModel.selectedLargeFilePaths) {
                TableColumn("文件") { file in
                    Label(file.name, systemImage: fileIcon(file)).lineLimit(1)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { viewModel.analyzeLargeFile(file) }
                }
                TableColumn("大小") { file in
                    Text(CacheFormatter.formatSize(file.size)).fontWeight(.semibold)
                }
                TableColumn("类型") { file in
                    Text(file.fileExtension).foregroundStyle(.secondary)
                }
                TableColumn("最后修改") { file in
                    Text(CacheFormatter.formatDate(file.lastModified))
                }
                TableColumn("路径") { file in
                    Text(file.path).font(.caption.monospaced()).lineLimit(1)
                }
            }
            .frame(minHeight: 420)
        }
        .padding(28)
    }

    private var selectedFile: LargeFileInfo? {
        viewModel.largeFiles.first { viewModel.selectedLargeFilePaths.contains($0.path) }
    }

    private func fileIcon(_ file: LargeFileInfo) -> String {
        switch file.fileExtension.lowercased() {
        case "dmg", "iso", "pkg": return "externaldrive"
        case "zip", "7z", "rar", "tar", "gz": return "archivebox"
        case "mov", "mp4", "mkv", "avi": return "film"
        default: return "doc"
        }
    }
}

private struct AISettingsView: View {
    @EnvironmentObject private var viewModel: CacheViewModel

    var body: some View {
        Form {
            Section {
                PageHeader(
                    eyebrow: "MODEL CONNECTION",
                    title: "AI 设置",
                    subtitle: "配置一个 OpenAI-compatible Chat Completions 接口，用于分析大文件和开发缓存。",
                    actions: {}
                )
            }

            Section("连接信息") {
                TextField("Base URL", text: $viewModel.aiConfiguration.baseURL)
                TextField("模型名称", text: $viewModel.aiConfiguration.model)
                SecureField("API Key", text: $viewModel.aiConfiguration.apiKey)
                Text("默认使用 OpenRouter 免费模型路由，也支持其他 OpenAI 兼容服务。API Key 仅保存在本机设置中。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Image(systemName: viewModel.aiConfiguration.isReady ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(viewModel.aiConfiguration.isReady ? .green : .secondary)
                    Text(viewModel.aiConfiguration.isReady ? "配置完整，可以进行 AI 分析" : "请填写 Base URL、模型和 API Key")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("保存配置") { viewModel.saveAIConfiguration() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .formStyle(.grouped)
        .padding(28)
    }
}

private struct AIAnalysisView: View {
    @EnvironmentObject private var viewModel: CacheViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI 分析结果")
                        .font(.title2.weight(.semibold))
                    Text("已选择 \(viewModel.aiAnalysisItems.count) 个项目，分析结果仅基于文件元数据。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if viewModel.isAnalyzingFile {
                    Button("取消分析") { viewModel.cancelAIAnalysis() }
                        .buttonStyle(.bordered)
                }
                Button("关闭") { viewModel.isAIAnalysisPresented = false }
            }

            if viewModel.isAnalyzingFile {
                ProgressView("正在分析 \(viewModel.aiAnalysisItems.filter { $0.analysis != nil || $0.errorMessage != nil }.count)/\(viewModel.aiAnalysisItems.count)...")
                    .progressViewStyle(.linear)
                Text("仅发送文件名、路径、大小和修改时间，不上传文件内容。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("分析完成后，请逐项确认 AI 建议，再决定是否移到废纸篓。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.aiAnalysisItems) { item in
                        AIAnalysisResultCard(item: item)
                    }
                }
            }

            HStack {
                Spacer()
                Button("完成") { viewModel.isAIAnalysisPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 760, idealWidth: 820, minHeight: 520, alignment: .topLeading)
    }
}

private struct AIAnalysisResultCard: View {
    @EnvironmentObject private var viewModel: CacheViewModel
    let item: AIAnalysisItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.target.name)
                        .font(.headline)
                    Text(item.target.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(CacheFormatter.formatSize(item.target.size))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let analysis = item.analysis {
                HStack(spacing: 8) {
                    AnalysisBadge(title: analysis.canDelete ? "建议删除" : "不建议删除", color: analysis.canDelete ? .green : .orange)
                    AnalysisBadge(title: "风险：\(analysis.riskLevel)", color: analysis.canDelete ? .green : .orange)
                    AnalysisBadge(title: "置信度 \(analysis.confidence)%", color: .blue)
                }

                Text(analysis.recommendation)
                    .font(.headline)
                Text(analysis.explanation)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !analysis.deletionCommand.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("建议命令")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Button {
                                viewModel.copyDeletionCommand(analysis.deletionCommand)
                            } label: {
                                Label("复制命令", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                        }
                        Text(analysis.deletionCommand)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.black.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text("命令仅供参考，执行前请再次确认路径和文件用途。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            } else if let errorMessage = item.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                ProgressView("等待分析...")
                    .controlSize(.small)
            }
        }
        .padding(14)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct AIAnalyzeButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .symbolRenderingMode(.multicolor)
                    .foregroundStyle(.yellow, .mint, .white)
                Text("AI 分析")
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(
                LinearGradient(
                    colors: [.teal, .blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .blue.opacity(0.25), radius: 7, y: 3)
        }
        .buttonStyle(.plain)
        .help("分析选中的文件或开发缓存")
    }
}

private struct PageHeader<Actions: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Text(eyebrow)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
                Text(title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 560, alignment: .leading)
            }
            Spacer(minLength: 20)
            HStack(spacing: 10) {
                actions()
            }
            .padding(.top, 18)
        }
        .padding(.bottom, 4)
    }
}

private struct SummaryCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(tint)
            Text(value)
                .font(.title2.bold().monospacedDigit())
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct AnalysisBadge: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial)
            .clipShape(Capsule())
            .shadow(radius: 8)
    }
}

#Preview {
    ContentView()
        .environmentObject(CacheViewModel())
}
