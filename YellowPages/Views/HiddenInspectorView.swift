import SwiftUI
import SQLite3
#if canImport(UIKit)
import UIKit
#endif

/// 隐藏工程详情页面（HiddenInspectorView）- 极客硬核、全透明底层运行状态观测
struct HiddenInspectorView: View {
    @ObservedObject var viewModel: MainViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var copiedItem: String? = nil

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (Build \(b))"
    }

    private var processID: Int32 {
        ProcessInfo.processInfo.processIdentifier
    }

    private var physicalMemoryMB: String {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / 4)
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            let mb = Double(info.resident_size) / (1024.0 * 1024.0)
            return String(format: "%.2f MB", mb)
        }
        return "-- MB"
    }

    private var sqliteVersion: String {
        if let ver = sqlite3_libversion() {
            return String(cString: ver)
        }
        return "Unknown"
    }

    var body: some View {
        NavigationStack {
            List {
                // Section 1: 运行时与设备硬件环境
                runtimeSection

                // Section 2: 底层存储与 SQLite 单一事实源
                storageSection

                // Section 3: CallKit 扩展与 App Group 沙盒
                extensionSandboxSection

                // Section 4: 网络服务端通信与同步契约
                networkContractSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("工程调试与运行时观测")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                    .font(.subheadline.bold())
                }
            }
        }
    }

    // MARK: - Section 1: 运行时与设备硬件
    private var runtimeSection: some View {
        Section {
            kvRow(label: "应用构建版本", value: appVersion)
            kvRow(label: "iOS 系统版本", value: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
            kvRow(label: "硬件机型标识", value: UIDevice.current.model)
            kvRow(label: "进程 PID", value: "\(processID)")
            kvRow(label: "常驻内存占用 (RSS)", value: physicalMemoryMB)
        } header: {
            Text("运行时与硬件宿主 (Runtime & Host)")
        }
    }

    // MARK: - Section 2: 底层 SQLite
    private var storageSection: some View {
        Section {
            kvRow(label: "SQLite 引擎版本", value: sqliteVersion)
            kvRow(label: "WAL 并发模式", value: "PRAGMA journal_mode = WAL (Active)")
            kvRow(label: "事务同步等级", value: "PRAGMA synchronous = NORMAL")
            kvRow(label: "数据库物理体积", value: viewModel.databaseFileSizeText)
            kvRow(label: "主表已收录总条数", value: "\(viewModel.identificationCount + viewModel.blockingCount) 记录")
            kvRow(label: "阻断拦截条数", value: "\(viewModel.blockingCount) 记录")
            kvRow(label: "识别标记条数", value: "\(viewModel.identificationCount) 记录")

            VStack(alignment: .leading, spacing: 6) {
                Text("数据库文件绝对路径")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                HStack {
                    Text(AppGroupConstants.databaseURL.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .truncationMode(.middle)

                    Spacer()

                    copyButton(text: AppGroupConstants.databaseURL.path, key: "db_path")
                }
            }
            .padding(.vertical, 2)
        } header: {
            Text("底层离线数据库存储")
        }
    }

    // MARK: - Section 3: CallKit 沙盒
    private var extensionSandboxSection: some View {
        Section {
            kvRow(label: "App Group Identifier", value: AppGroupConstants.groupIdentifier)
            kvRow(label: "Extension Bundle ID", value: AppGroupConstants.extensionBundleIdentifier)
            kvRow(label: "CallKit 扩展状态", value: viewModel.callKitStatus.isEnabled ? "ENABLED" : "DISABLED")

            VStack(alignment: .leading, spacing: 6) {
                Text("共享 App Group 容器路径")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                HStack {
                    Text(AppGroupConstants.sharedContainerURL.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .truncationMode(.middle)

                    Spacer()

                    copyButton(text: AppGroupConstants.sharedContainerURL.path, key: "group_path")
                }
            }
            .padding(.vertical, 2)
        } header: {
            Text("系统扩展与沙盒共享 (CallKit & Sandbox)")
        }
    }

    // MARK: - Section 4: 网络通信契约
    private var networkContractSection: some View {
        Section {
            kvRow(label: "生效 Server Endpoint", value: viewModel.serverAddressInput)
            kvRow(label: "离线库本地版本", value: "v\(viewModel.localDatabaseVersion)")

            switch viewModel.serverConnectionStatus {
            case .connected(let ms):
                kvRow(label: "连接链路延迟", value: "\(ms) ms")
            case .failed(let reason):
                kvRow(label: "连接异常状态", value: reason)
            case .testing:
                kvRow(label: "连接探测", value: "Testing...")
            case .idle:
                kvRow(label: "连接状态", value: "未测试")
            }

            kvRow(label: "匿名设备加盐哈希", value: viewModel.deviceFingerprint)
        } header: {
            Text("通信契约与同步游标 (Network Contract)")
        }
    }

    // MARK: - 通用行与拷贝
    private func kvRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    private func copyButton(text: String, key: String) -> some View {
        Button(action: {
            UIPasteboard.general.string = text
            copiedItem = key
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if copiedItem == key {
                    copiedItem = nil
                }
            }
        }) {
            Text(copiedItem == key ? "已复制" : "复制")
                .font(.caption2.bold())
                .foregroundColor(.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Capsule())
        }
        .buttonStyle(.borderless)
    }
}
