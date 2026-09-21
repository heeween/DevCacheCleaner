import SwiftUI
import DevCacheCore

struct ContentView: View {
    @EnvironmentObject private var viewModel: CacheViewModel

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                header
                summaryCards
                actionButtons
                dockerSection
                largeFilesSection
                cacheTable
                directoryInspectorSection
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(minWidth: 900, minHeight: 600)
        }
        .navigationTitle("DevCache Cleaner")
        .toolbar { toolbarButtons }
        .task { viewModel.analyzeAllCaches() }
        .task { viewModel.refreshDocker() }
        .onChange(of: viewModel.selectedCacheIDs) { _ in
            viewModel.inspectFirstSelectedCache()
        }
        .overlay(alignment: .bottom) {
            if let message = viewModel.toastMessage {
                ToastView(message: message)
                    .padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation {
                                viewModel.toastMessage = nil
                            }
                        }
                    }
            }
        }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { viewModel.lastError != nil },
                set: { value in
                    if !value { viewModel.lastError = nil }
                }
            ),
            presenting: viewModel.lastError
        ) { _ in
            Button("好的", role: .cancel) {}
        } message: { error in
            Text(error)
        }
        .confirmationDialog(
            "确认删除?",
            isPresented: Binding(
                get: { viewModel.nodePendingDeletion != nil },
                set: { value in
                    if !value { viewModel.cancelDeletionRequest() }
                }
            ),
            presenting: viewModel.nodePendingDeletion
        ) { node in
            Button("删除", role: .destructive) {
                viewModel.confirmDeletion()
            }
            .disabled(viewModel.isDeletingNode)

            Button("取消", role: .cancel) {
                viewModel.cancelDeletionRequest()
            }
        } message: { node in
            VStack(alignment: .leading, spacing: 4) {
                Text("此操作会将 \(node.name) 移动到废纸篓")
                Text(node.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text("大小约 \(CacheFormatter.formatSize(node.size))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(
            "确认删除大文件?",
            isPresented: Binding(
                get: { viewModel.largeFilePendingDeletion != nil },
                set: { value in
                    if !value { viewModel.cancelLargeFileDeletion() }
                }
            ),
            presenting: viewModel.largeFilePendingDeletion
        ) { file in
            Button("移到废纸篓", role: .destructive) {
                viewModel.confirmLargeFileDeletion()
            }
            Button("取消", role: .cancel) {
                viewModel.cancelLargeFileDeletion()
            }
        } message: { file in
            VStack(alignment: .leading, spacing: 4) {
                Text(file.name)
                Text(file.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text("大小 \(CacheFormatter.formatSize(file.size)) · 删除后可从废纸篓恢复")
                    .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(
            "清理 Docker 构建缓存?",
            isPresented: $viewModel.dockerCleanupPending
        ) {
            Button("清理构建缓存", role: .destructive) {
                viewModel.confirmDockerCacheCleanup()
            }
            Button("取消", role: .cancel) {
                viewModel.cancelDockerCacheCleanup()
            }
        } message: {
            Text("只会删除 Docker 构建缓存，不会停止服务，也不会删除镜像、Volume 或容器。")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DevCache Cleaner")
                .font(.largeTitle.weight(.semibold))
            Text("专为开发者打造的缓存清理工具")
                .foregroundStyle(.secondary)
        }
    }

    private var summaryCards: some View {
        HStack(spacing: 16) {
            SummaryCard(
                title: "总缓存",
                value: CacheFormatter.formatSize(viewModel.totalSize),
                subtitle: "当前分析到的总空间占用",
                icon: "externaldrive.fill"
            )
            SummaryCard(
                title: "安全清理",
                value: CacheFormatter.formatSize(viewModel.safeSize),
                subtitle: "一键即可安全删除的文件",
                icon: "checkmark.shield.fill",
                tint: .green
            )
            SummaryCard(
                title: "需确认",
                value: CacheFormatter.formatSize(viewModel.requiresConfirmationSize),
                subtitle: "建议手动检查后再处理",
                icon: "exclamationmark.triangle.fill",
                tint: .orange
            )
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.analyzeAllCaches()
            } label: {
                Label("分析缓存", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isAnalyzing)

            Button {
                viewModel.cleanSafeCaches()
            } label: {
                Label("清理安全项目", systemImage: "sparkles")
            }
            .disabled(viewModel.isAnalyzing || viewModel.isCleaning || viewModel.isDeletingNode || viewModel.safeCaches.isEmpty)

            Button {
                viewModel.cleanSelectedCaches()
            } label: {
                Label("清理选中", systemImage: "trash")
            }
            .disabled(viewModel.isAnalyzing || viewModel.isCleaning || viewModel.isDeletingNode || viewModel.selectedCacheIDs.isEmpty)

            if viewModel.firstSelectedCache != nil {
                Button {
                    viewModel.revealFirstSelectedInFinder()
                } label: {
                    Label("打开文件夹", systemImage: "folder")
                }
            }

            Spacer()

            if viewModel.isAnalyzing {
                ProgressView("正在分析...")
                    .progressViewStyle(.linear)
                    .frame(width: 160)
            } else if viewModel.isCleaning {
                ProgressView("正在清理...")
                    .progressViewStyle(.linear)
                    .frame(width: 160)
            }
        }
    }

    private var dockerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Docker", systemImage: "shippingbox.fill")
                    .font(.headline)
                if viewModel.dockerUsage != nil {
                    Text("运行中 · \(viewModel.dockerServices.count) 个服务")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("未连接")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    viewModel.refreshDocker()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isLoadingDocker || viewModel.isCleaningDocker)
            }

            if viewModel.isLoadingDocker {
                ProgressView("正在读取 Docker 状态...")
                    .progressViewStyle(.linear)
            } else if let usage = viewModel.dockerUsage {
                HStack(spacing: 12) {
                    DockerMetric(title: "镜像", value: CacheFormatter.formatSize(usage.imageSize), detail: "\(usage.imageCount) 个")
                    DockerMetric(title: "容器", value: CacheFormatter.formatSize(usage.containerSize), detail: "\(usage.containerCount) 个")
                    DockerMetric(title: "Volume", value: CacheFormatter.formatSize(usage.volumeSize), detail: "\(usage.volumeCount) 个")
                    DockerMetric(title: "构建缓存", value: CacheFormatter.formatSize(usage.buildCacheSize), detail: "可回收 \(CacheFormatter.formatSize(usage.buildCacheReclaimable))")
                }

                if viewModel.dockerServices.isEmpty {
                    Text("当前没有运行中的 Docker 服务")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("运行中的服务")
                            .font(.subheadline.weight(.medium))
                        ForEach(viewModel.dockerServices) { service in
                            HStack {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 7))
                                    .foregroundStyle(.green)
                                Text(service.name)
                                    .fontWeight(.medium)
                                Text(service.image)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(service.status)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                HStack {
                    Text("清理构建缓存可释放约 \(CacheFormatter.formatSize(usage.buildCacheReclaimable))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        viewModel.requestDockerCacheCleanup()
                    } label: {
                        Label("清理 Docker 缓存", systemImage: "trash")
                    }
                    .disabled(viewModel.isCleaningDocker || usage.buildCacheReclaimable == 0)
                }
            } else {
                Text("Docker Desktop 未运行，或当前无法连接 Docker 引擎")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var cacheTable: some View {
        Table(viewModel.caches, selection: $viewModel.selectedCacheIDs) {
            TableColumn("类别") { cache in
                Label(cache.category.rawValue, systemImage: icon(for: cache.category))
                    .labelStyle(.titleAndIcon)
            }
            TableColumn("描述", value: \.description)
            TableColumn("大小") { cache in
                Text(CacheFormatter.formatSize(cache.size))
            }
            TableColumn("安全性") { cache in
                if cache.isSafeToDelete {
                    Label("安全", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("需确认", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            TableColumn("最后修改") { cache in
                Text(CacheFormatter.formatDate(cache.lastModified))
            }
            TableColumn("路径") { cache in
                Text(cache.path)
                    .font(.caption.monospaced())
            }
            TableColumn("提示") { cache in
                if let tip = cache.tip, !tip.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.blue)
                        Text(tip)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("")
                }
            }
        }
        .frame(minHeight: 360)
        .background(.background, ignoresSafeAreaEdges: .bottom)
    }

    private var largeFilesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("大文件扫描", systemImage: "doc.richtext.fill")
                        .font(.headline)
                    Text("扫描整个磁盘中可访问的文件，只显示超过阈值的项目")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Stepper(value: $viewModel.largeFileMinimumSizeGB, in: 0.1...100, step: 0.1) {
                    Text("大于 \(viewModel.largeFileMinimumSizeGB, specifier: "%.1f") GB")
                        .monospacedDigit()
                }
                .frame(width: 170)
                Button {
                    viewModel.scanLargeFiles()
                } label: {
                    Label("扫描大文件", systemImage: "magnifyingglass")
                }
                .disabled(viewModel.isScanningLargeFiles || viewModel.isCleaning)
            }

            if viewModel.isScanningLargeFiles {
                ProgressView("正在扫描磁盘，请稍候...")
                    .progressViewStyle(.linear)
            } else if !viewModel.largeFiles.isEmpty {
                HStack {
                    Text("共 \(viewModel.largeFiles.count) 个文件 · \(CacheFormatter.formatSize(viewModel.largeFiles.reduce(0) { $0 + $1.size }))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("清空选择") { viewModel.clearLargeFileSelection() }
                        .disabled(viewModel.selectedLargeFilePaths.isEmpty)
                    Button("删除选中", role: .destructive) {
                        viewModel.deleteSelectedLargeFiles()
                    }
                    .disabled(viewModel.selectedLargeFilePaths.isEmpty || viewModel.isCleaning)
                }

                Table(viewModel.largeFiles, selection: $viewModel.selectedLargeFilePaths) {
                    TableColumn("文件") { file in
                        Label(file.name, systemImage: icon(for: file))
                            .lineLimit(1)
                    }
                    TableColumn("大小") { file in
                        Text(CacheFormatter.formatSize(file.size))
                            .fontWeight(.semibold)
                    }
                    TableColumn("类型") { file in
                        Text(file.fileExtension)
                            .foregroundStyle(.secondary)
                    }
                    TableColumn("最后修改") { file in
                        Text(CacheFormatter.formatDate(file.lastModified))
                    }
                    TableColumn("路径") { file in
                        Text(file.path)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                    }
                    TableColumn("") { file in
                        HStack(spacing: 8) {
                            Button {
                                viewModel.revealLargeFile(file)
                            } label: {
                                Image(systemName: "folder")
                            }
                            .buttonStyle(.borderless)
                            .help("在访达中显示")

                            Button {
                                viewModel.requestLargeFileDeletion(file)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                            .help("移到废纸篓")
                        }
                    }
                }
                .frame(minHeight: 220, maxHeight: 320)
            } else {
                Text("点击“扫描大文件”开始查找")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            }
        }
        .padding(16)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func icon(for file: LargeFileInfo) -> String {
        switch file.fileExtension.lowercased() {
        case "dmg", "iso", "pkg": return "externaldrive"
        case "zip", "7z", "rar", "tar", "gz": return "archivebox"
        case "mov", "mp4", "mkv", "avi": return "film"
        default: return "doc"
        }
    }

    private var directoryInspectorSection: some View {
        DirectoryInspectorView(
            root: viewModel.directoryTree,
            isLoading: viewModel.isLoadingDirectory,
            isDeleting: viewModel.isDeletingNode,
            basePath: viewModel.firstSelectedCache?.path,
            onDeleteRequest: viewModel.requestDeletion(for:)
        )
    }

    @ToolbarContentBuilder
    private var toolbarButtons: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button("仅选安全") {
                viewModel.selectAllSafeCaches()
            }
            .disabled(viewModel.caches.isEmpty)

            Button("清空选择") {
                viewModel.clearSelection()
            }
            .disabled(viewModel.selectedCacheIDs.isEmpty)
        }
    }

    private func icon(for category: CacheCategory) -> String {
        switch category {
        case .xcode:
            return "hammer.fill"
        case .androidStudio:
            return "antenna.radiowaves.left.and.right"
        case .nodejs:
            return "leaf.fill"
        case .system:
            return "gearshape.fill"
        case .other:
            return "tray.fill"
        }
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
                .font(.title2.bold())
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct DockerMetric: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.background.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
