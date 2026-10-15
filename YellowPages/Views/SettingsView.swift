import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Tab 4: 核心配置与设备凭证 (严格践行奥卡姆剃刀：只保留有实质工程意义的 3 个核心板块)
struct SettingsView: View {
    @ObservedObject var viewModel: MainViewModel
    @State private var showResetAlert = false
    @State private var showCopiedFeedback = false
    @State private var isShowingHiddenInspector = false
    @State private var sharingURL: URL? = nil
    @State private var isShowingShareSheet = false

    // 连续点击 5 次彩蛋计数与计时器
    @State private var versionTapCount: Int = 0
    @State private var lastTapTimestamp: TimeInterval = 0

    private var appVersionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (Build \(b))"
    }

    var body: some View {
        NavigationStack {
            List {
                // 板块 1: 后端同步服务接入 (真正干活的联调实体)
                serverEndpointSection

                // 板块 2: 匿名设备凭证 (用户认可的唯一无感通行证)
                deviceIdentitySection

                // 板块 3: 本地存储管理与快照备份
                storageManagementSection

                // 板块 4: 号码误标申诉与纠错中心
                disputeAppealSection

                // 板块 5: 关于与版本号（内嵌连续 5 次点击彩蛋触发器）
                aboutVersionSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("偏好设置")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $isShowingHiddenInspector) {
                HiddenInspectorView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.isShowingAppealSheet) {
                AppealDisputeSheet(viewModel: viewModel) {
                    viewModel.isShowingAppealSheet = false
                }
            }
            .sheet(isPresented: $isShowingShareSheet) {
                if let url = sharingURL {
                    #if canImport(UIKit)
                    ActivityView(activityItems: [url])
                    #endif
                }
            }
            .alert("确认重置本地规则库？", isPresented: $showResetAlert) {
                Button("取消", role: .cancel) { }
                Button("清空并重置", role: .destructive) {
                    viewModel.resetLocalDatabase()
                }
            } message: {
                Text("此操作将清空本地缓存的全部离线号码规则，并重置 CallKit 扩展。您可以通过重新同步快速恢复。")
            }
        }
    }

    // MARK: - 板块 5: 关于与版本号 (包含彩蛋触发)
    private var aboutVersionSection: some View {
        Section {
            Button(action: {
                handleVersionTap()
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("YellowPages")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                        Text("全本地离线匹配 · CallKit 电话身份识别与骚扰阻止")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(appVersionString)
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } header: {
            Text("关于与版本")
        }
    }

    /// 连击 5 次彩蛋触发算法（2 秒窗口内累计）
    private func handleVersionTap() {
        let now = Date().timeIntervalSince1970
        if now - lastTapTimestamp > 2.0 {
            versionTapCount = 1
        } else {
            versionTapCount += 1
        }
        lastTapTimestamp = now

        #if canImport(UIKit)
        if versionTapCount >= 5 {
            versionTapCount = 0
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            isShowingHiddenInspector = true
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        #endif
    }

    // MARK: - 板块 1: 后端同步服务配置 (Server Endpoint)
    private var serverEndpointSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("后端 API 基础地址", systemImage: "server.rack")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Spacer()

                    serverStatusBadge
                }

                Text("指定离线号码同步、在线反查及社区举报提交的 RESTful 服务端。")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // 地址输入框与操作按键
                HStack(spacing: 8) {
                    TextField("http://127.0.0.1:8080", text: $viewModel.serverAddressInput)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.subheadline, design: .monospaced))

                    if !viewModel.serverAddressInput.isEmpty {
                        Button(action: {
                            viewModel.serverAddressInput = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                    }

                    Button("应用保存") {
                        viewModel.saveServerAddress()
                    }
                    .font(.caption.bold())
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(UIColor.tertiarySystemGroupedBackground))
                .cornerRadius(8)

                // 快捷预设与连通性测试
                HStack {
                    Button(action: {
                        viewModel.testServerConnectivity()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "network")
                                .font(.caption)
                            Text("连通性检测")
                                .font(.caption.weight(.medium))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    Menu("快捷预设") {
                        Button("本地开发 (127.0.0.1:8080)") {
                            viewModel.applyServerPreset("http://127.0.0.1:8080")
                        }

                        Button("局域网 Mac (192.168.1.100:8080)") {
                            viewModel.applyServerPreset("http://192.168.1.100:8080")
                        }

                        Button("官方示范服务 (api.yellowpages.local)") {
                            viewModel.applyServerPreset("https://api.yellowpages.local")
                        }

                        Divider()

                        Button("恢复默认设置", role: .destructive) {
                            viewModel.resetServerAddressToDefault()
                        }
                    }
                    .font(.caption.bold())
                    .foregroundColor(.accentColor)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("后端同步服务 (API Endpoint)")
        }
    }

    private var serverStatusBadge: some View {
        Group {
            switch viewModel.serverConnectionStatus {
            case .idle:
                Text("未测试")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            case .testing:
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("探测中...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            case .connected(let ms):
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("已连接 (\(ms)ms)")
                        .font(.caption2.bold())
                        .monospacedDigit()
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.1))
                .clipShape(Capsule())
            case .failed(let reason):
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                    Text(reason)
                        .font(.caption2.bold())
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.1))
                .clipShape(Capsule())
            }
        }
    }

    // MARK: - 板块 2: 匿名设备凭证 (Device Identity)
    private var deviceIdentitySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("匿名设备凭证", systemImage: "key.viewfinder")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Text("社区信用: \(viewModel.deviceCreditLevelName)")
                        .font(.caption2.bold())
                        .foregroundColor(creditColor(for: viewModel.deviceCreditLevel))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(creditColor(for: viewModel.deviceCreditLevel).opacity(0.12))
                        .clipShape(Capsule())
                }

                Text("基于本地硬件安全芯片加盐哈希生成匿名凭证，杜绝手机号或密码注册，仅用于标记防刷与上报信誉评级。")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Text(viewModel.deviceFingerprint)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button(action: {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = viewModel.deviceFingerprint
                        showCopiedFeedback = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showCopiedFeedback = false
                        }
                        #endif
                    }) {
                        Text(showCopiedFeedback ? "已复制" : "复制")
                            .font(.caption.bold())
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(8)
                .background(Color(UIColor.tertiarySystemGroupedBackground))
                .cornerRadius(8)
            }
            .padding(.vertical, 4)
        } header: {
            Text("设备身份与隐私凭证")
        }
    }

    // MARK: - 板块 3: 本地存储、快照备份与导出 (Storage & Backups)
    private var storageManagementSection: some View {
        Section {
            HStack {
                Text("本地 SQLite 数据库体积")
                    .font(.subheadline)
                Spacer()
                Text(viewModel.databaseFileSizeText)
                    .font(.caption.bold())
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("已载入规则记录")
                    .font(.subheadline)
                Spacer()
                Text("\(viewModel.identificationCount + viewModel.blockingCount) 条")
                    .font(.caption.bold())
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }

            // 快照备份操作按钮
            Button(action: {
                viewModel.createNewBackup()
            }) {
                HStack {
                    Label("立即创建数据库快照备份", systemImage: "arrow.down.doc.fill")
                        .font(.subheadline)
                    Spacer()
                    Text("保留最近 5 次")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // 备份成功或失败提示条
            if let notice = viewModel.backupNotice {
                Text(notice)
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }

            // 备份列表展示
            if viewModel.backupList.isEmpty {
                Text("暂无本地历史备份。执行全量同步或点击上方按钮可生成快照。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(viewModel.backupList) { item in
                    HStack(spacing: 10) {
                        Image(systemName: "internaldrive.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.fileName)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .lineLimit(1)
                            Text("\(formattedBackupDate(item.createdAt)) · \(item.recordCount) 条记录 · \(item.fileSizeText)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button(action: {
                            sharingURL = item.fileURL
                            isShowingShareSheet = true
                        }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14))
                                .foregroundColor(.accentColor)
                                .padding(6)
                                .background(Color.accentColor.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.borderless)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            viewModel.deleteBackupItem(item)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }

            Button(role: .destructive, action: {
                showResetAlert = true
            }) {
                Text("清空并重置本地号码规则库")
                    .font(.subheadline)
            }
        } header: {
            Text("存储管理与快照备份")
        } footer: {
            Text("备份文件保存在 App Group 共享目录中，支持通过隔空投送、文件 App 或微信导出分享。")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func formattedBackupDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    // MARK: - 板块 4: 号码误标申诉与纠错中心
    private var disputeAppealSection: some View {
        Section(header: Text("服务与纠错")) {
            Button(action: {
                viewModel.presentAppeal(for: "")
            }) {
                HStack {
                    Label("号码误标与纠错申诉中心", systemImage: "exclamationmark.bubble")
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                }
            }
        }
    }

    private func creditColor(for level: String) -> Color {
        switch level {
        case "excellent":
            return .green
        case "good":
            return .blue
        case "fair":
            return .orange
        case "poor":
            return .red
        default:
            return .green
        }
    }
}

#if canImport(UIKit)
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
