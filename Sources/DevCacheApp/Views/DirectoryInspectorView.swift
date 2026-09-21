import SwiftUI
import DevCacheCore

struct DirectoryInspectorView: View {
    let root: DirectoryNode?
    let isLoading: Bool
    let isDeleting: Bool
    let basePath: String?
    let onDeleteRequest: (DirectoryNode) -> Void

    @State private var expandedIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("文件结构", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                Spacer()
                if let path = basePath {
                    Text(path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            content
                .frame(minHeight: 160, maxHeight: 320)
        }
        .padding(16)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onChange(of: root?.id) { _ in
            expandedIDs = []
            if let root {
                expandedIDs.insert(root.id)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            HStack {
                ProgressView()
                Text("正在读取目录...")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if isDeleting {
            HStack {
                ProgressView()
                Text("正在删除...")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let root {
            ScrollView {
                DirectoryTreeNodeView(
                    node: root,
                    expandedIDs: $expandedIDs,
                    isDeleting: isDeleting,
                    onDeleteRequest: onDeleteRequest
                )
                .padding(.leading, 4)
            }
        } else {
            Text("选择一个缓存条目以浏览内部文件结构")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DirectoryTreeNodeView: View {
    let node: DirectoryNode
    @Binding var expandedIDs: Set<String>
    let isDeleting: Bool
    let onDeleteRequest: (DirectoryNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            nodeRow

            if let children = node.nonEmptyChildren, isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(children) { child in
                        DirectoryTreeNodeView(
                            node: child,
                            expandedIDs: $expandedIDs,
                            isDeleting: isDeleting,
                            onDeleteRequest: onDeleteRequest
                        )
                        .padding(.leading, 14)
                    }
                }
            }
        }
    }

    private var nodeRow: some View {
        let hasChildren = node.nonEmptyChildren != nil

        return HStack(spacing: 8) {
            if hasChildren {
                Button {
                    toggleExpanded()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear
                    .frame(width: 14, height: 1)
            }

            Image(systemName: node.isDirectory ? "folder" : "doc")
                .foregroundStyle(node.isDirectory ? Color.accentColor : Color.secondary)
            Text(node.name)
                .font(node.isDirectory ? .body.weight(.medium) : .body)
                .lineLimit(1)
            Spacer()
            Text(CacheFormatter.formatSize(node.size))
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                onDeleteRequest(node)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .help("移动到废纸篓")
            .disabled(isDeleting)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            if hasChildren {
                toggleExpanded()
            }
        }
    }

    private var isExpanded: Bool {
        expandedIDs.contains(node.id)
    }

    private func toggleExpanded() {
        if isExpanded {
            expandedIDs.remove(node.id)
        } else {
            expandedIDs.insert(node.id)
        }
    }
}

#Preview {
        DirectoryInspectorView(
            root: DirectoryNode(
                path: "/tmp",
                name: "tmp",
                size: 1024,
                isDirectory: true,
                children: [
                    DirectoryNode(path: "/tmp/a", name: "a", size: 512, isDirectory: true, children: []),
                    DirectoryNode(path: "/tmp/b.txt", name: "b.txt", size: 256, isDirectory: false, children: [])
                ]
            ),
            isLoading: false,
            isDeleting: false,
            basePath: "/tmp",
            onDeleteRequest: { _ in }
        )
    .padding()
    .frame(width: 400)
}
