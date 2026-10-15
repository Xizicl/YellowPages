import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 模块 1：系统扩展状态与数据版本总览
struct SystemStatusCardView: View {
    @ObservedObject var viewModel: MainViewModel
    @State private var showSettingsGuide = false

    /// 智能相对时间格式化（自适应当天/今年/跨年，杜绝小屏幕截断）
    private func formatSyncDate(_ date: Date) -> (primary: String, secondary: String?) {
        let calendar = Calendar.current
        let now = Date()

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timeStr = timeFormatter.string(from: date)

        if calendar.isDateInToday(date) {
            return ("今天", timeStr)
        } else if calendar.isDateInYesterday(date) {
            return ("昨天", timeStr)
        } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            let mdFormatter = DateFormatter()
            mdFormatter.dateFormat = "MM-dd"
            return (mdFormatter.string(from: date), timeStr)
        } else {
            let ymdFormatter = DateFormatter()
            ymdFormatter.dateFormat = "yy-MM-dd"
            return (ymdFormatter.string(from: date), timeStr)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            // 顶层状态横幅：CallKit 启用指示
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(callKitStatusColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: callKitStatusIcon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(callKitStatusColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("来电阻止与身份识别")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text(callKitStatusText)
                            .font(.caption2.bold())
                            .foregroundColor(callKitStatusColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(callKitStatusColor.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Text(callKitStatusSubtext)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !viewModel.callKitStatus.isEnabled {
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            showSettingsGuide.toggle()
                        }
                    }) {
                        Text(showSettingsGuide ? "收起" : "指引")
                            .font(.caption.bold())
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // 折叠式原生设置指引
            if showSettingsGuide && !viewModel.callKitStatus.isEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("请按以下路径在 iOS 系统中启用扩展：")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        guideStepPill(number: "1", title: "系统设置")
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                        guideStepPill(number: "2", title: "电话")
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                        guideStepPill(number: "3", title: "通话阻止与身份识别")
                    }

                    HStack {
                        Spacer()
                        Button(action: {
                            openSystemSettings()
                        }) {
                            Label("前往系统「设置」", systemImage: "arrow.up.right.square")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.accentColor)
                    }
                    .padding(.top, 4)
                }
                .padding(12)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(10)
            }

            // 系统三大核心防护能力矩阵指示条（深度融合通信安全中枢）
            VStack(spacing: 8) {
                // 1. 来电阻止与身份识别
                capabilityRow(
                    icon: "phone.badge.checkmark",
                    iconColor: viewModel.callKitStatus.isEnabled ? .green : .orange,
                    title: "来电识别与拦截",
                    subtitle: "通话时离线静默识别权威机构或高危拦截",
                    statusText: viewModel.callKitStatus.isEnabled ? "已启用" : "未开启",
                    statusColor: viewModel.callKitStatus.isEnabled ? .green : .orange
                )

                // 2. 骚扰来电快捷报告
                capabilityRow(
                    icon: "phone.down.waves.left.and.right",
                    iconColor: .blue,
                    title: "最近通话骚扰报告",
                    subtitle: "通话记录陌生号码左滑或详情页直接上报",
                    statusText: "系统支持",
                    statusColor: .blue
                )

                // 3. 垃圾短信快捷报告
                capabilityRow(
                    icon: "message.badge.filled.fill",
                    iconColor: .indigo,
                    title: "垃圾短信快捷报告",
                    subtitle: "信息列表陌生短信左滑或底部一键提交举报",
                    statusText: "系统支持",
                    statusColor: .indigo
                )
            }
            .padding(10)
            .background(Color(UIColor.secondarySystemGroupedBackground).opacity(0.7))
            .cornerRadius(10)

            // 快捷跳转系统设置引导
            Button(action: {
                openSystemSettings()
            }) {
                HStack {
                    Label("前往 iOS「设置」管理电话与信息权限", systemImage: "gearshape.arrow.triangle.2.circlepath")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.accentColor)
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }

            Divider()

            // 离线库核心指标三栏展示
            HStack(spacing: 0) {
                statColumn(
                    title: "当前版本",
                    value: viewModel.formattedDatabaseVersion,
                    hint: "离线规则库"
                )

                Divider()
                    .frame(height: 36)

                statColumn(
                    title: "已加载规则",
                    value: "\(viewModel.identificationCount + viewModel.blockingCount)",
                    hint: "号码记录"
                )

                Divider()
                    .frame(height: 36)

                syncDateColumn
            }

            // 同步进度或结果指示条
            if case .syncing(_, let msg) = viewModel.syncPhase {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(8)
            } else if case .success(let msg) = viewModel.syncPhase {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(8)
            } else if case .failure(let msg) = viewModel.syncPhase {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(8)
            }

            // 操作按钮组
            HStack(spacing: 10) {
                Button(action: {
                    viewModel.performSync(forceFull: false)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13, weight: .semibold))
                        Text("增量更新")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .disabled(isSyncingActive)

                Menu {
                    Button(action: {
                        viewModel.performSync(forceFull: true)
                    }) {
                        Label("全量同步覆盖并重载", systemImage: "arrow.clockwise.icloud")
                    }

                    Button(action: {
                        viewModel.reloadCallKitExtension()
                    }) {
                        Label("立即重载 CallKit 系统扩展", systemImage: "phone.arrow.right")
                    }

                    Button(action: {
                        viewModel.refreshAll()
                    }) {
                        Label("探测系统启用状态", systemImage: "waveform.path.ecg")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                }
                .buttonStyle(.bordered)
                .disabled(isSyncingActive)
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    // MARK: - 辅助子视图与计算属性

    private var isSyncingActive: Bool {
        if case .syncing = viewModel.syncPhase { return true }
        if case .checking = viewModel.syncPhase { return true }
        return false
    }

    private var callKitStatusColor: Color {
        switch viewModel.callKitStatus {
        case .enabled:
            return .green
        case .disabled:
            return .orange
        case .unknown:
            return .secondary
        case .error:
            return .red
        }
    }

    private var callKitStatusIcon: String {
        switch viewModel.callKitStatus {
        case .enabled:
            return "checkmark.shield.fill"
        case .disabled:
            return "exclamationmark.shield.fill"
        case .unknown:
            return "shield.fill"
        case .error:
            return "xmark.shield.fill"
        }
    }

    private var callKitStatusText: String {
        switch viewModel.callKitStatus {
        case .enabled:
            return "已在系统启用"
        case .disabled:
            return "未启用"
        case .unknown:
            return "状态未知"
        case .error:
            return "系统异常"
        }
    }

    private var callKitStatusSubtext: String {
        switch viewModel.callKitStatus {
        case .enabled:
            return "离线号码库可直接在系统通话中静默识别"
        case .disabled:
            return "需在 iOS 设置中允许此应用识别通话"
        case .unknown:
            return "点击可刷新检测 CallKit 扩展"
        case .error(let msg):
            return msg
        }
    }

    private func statColumn(title: String, value: String, hint: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(hint)
                .font(.system(size: 10))
                .foregroundColor(Color(UIColor.tertiaryLabel))
        }
        .frame(maxWidth: .infinity)
    }

    /// 最后同步专属分栏：两行等宽紧凑排版，无论 SE 还是 16 Pro 均零截断、零折叠抖动
    private var syncDateColumn: some View {
        VStack(spacing: 2) {
            Text("最后同步")
                .font(.caption2)
                .foregroundColor(.secondary)

            if let date = viewModel.lastSyncDate {
                let parsed = formatSyncDate(date)
                HStack(spacing: 3) {
                    Text(parsed.primary)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                    if let sec = parsed.secondary {
                        Text(sec)
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    }
                }
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

                Text("离线规则库")
                    .font(.system(size: 10))
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            } else {
                Text("未同步")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text("暂无快照")
                    .font(.system(size: 10))
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func guideStepPill(number: String, title: String) -> some View {
        HStack(spacing: 4) {
            Text(number)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 14, height: 14)
                .background(Color.accentColor)
                .clipShape(Circle())
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundColor(.primary)
        }
    }

    private func capabilityRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        statusText: String,
        statusColor: Color
    ) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(statusText)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(statusColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(statusColor.opacity(0.12))
                .clipShape(Capsule())
        }
    }

    private func openSystemSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}
