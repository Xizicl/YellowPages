import SwiftUI
import Contacts
#if canImport(UIKit)
import UIKit
#endif

/// 陌生号码来电处置面板（原生零权限新建联系人、加入黑名单与标记举报）
struct IncomingCallQuickActionSheet: View {
    @ObservedObject var quickActionCoordinator: QuickActionCoordinator
    let prompt: DetectedCallPrompt
    var onDismiss: () -> Void

    // 原生系统新建联系人状态（零权限跳转）
    @State private var contactName: String = ""
    @State private var contactToPresent: CNMutableContact? = nil
    @State private var isShowingNativeContactSheet: Bool = false

    // 标记与举报状态
    @State private var selectedCategory: NumberCategory = .harassment
    @State private var customTag: String = ""
    @State private var alsoBlockNumber: Bool = true
    @State private var isSubmittingReport: Bool = false

    // 内部反馈
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 头部卡片：展示来电特征与识别号码
                    incomingCallHeaderCard

                    // 操作区块 1：系统原生新建联系人 (零权限跳转)
                    saveToContactsCard

                    // 操作区块 2：快速标记与上报
                    tagAndReportCard

                    // 操作区块 3：高危阻断与一键加入黑名单
                    blockAndInterceptCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("陌生来电处置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("忽略") {
                        quickActionCoordinator.dismissCurrentPrompt()
                        onDismiss()
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
            }
            .onAppear {
                // 默认提供友好的建议名称
                if contactName.isEmpty {
                    contactName = "新联系人 (\(prompt.formattedNumber))"
                }
            }
            .sheet(isPresented: $isShowingNativeContactSheet) {
                if let contact = contactToPresent {
                    NativeNewContactSheet(contact: contact) {
                        isShowingNativeContactSheet = false
                        onDismiss()
                    }
                    .ignoresSafeArea()
                }
            }
        }
    }

    // MARK: - 头部来电卡片
    private var incomingCallHeaderCard: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 56, height: 56)
                Image(systemName: "phone.down.circle.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.orange)
            }

            VStack(spacing: 4) {
                Text(prompt.formattedNumber)
                    .font(.system(.title2, design: .monospaced).weight(.bold))
                    .foregroundColor(.primary)

                HStack(spacing: 6) {
                    Text("检测到挂断通话 / 剪贴板复制号码")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("未在通讯录")
                        .font(.caption2.bold())
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(Capsule())
                }
            }

            if let err = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.08))
                .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    // MARK: - 操作 1：系统原生新建联系人 (零权限跳转)
    private var saveToContactsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("在系统通讯录中新建", systemImage: "person.crop.circle.badge.plus")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }

            Text("直接调起 iOS 系统原生新建联系人面板，用户自行确认或取消。App 零隐私权限索取，安全合规。")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Image(systemName: "person.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))

                TextField("预填姓名（如：快递员、张经理）", text: $contactName)
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(UIColor.tertiarySystemGroupedBackground))
            .cornerRadius(10)

            Button(action: {
                handleSaveContact()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.square.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("调起系统新建联系人")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    // MARK: - 操作 2：标记与上报
    private var tagAndReportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("标记类型并向社区举报", systemImage: "flag.badge.ellipsis")
                .font(.headline)
                .foregroundColor(.primary)

            Text("选定类型并一键提交，帮助自己和他人识别骚扰风险。")
                .font(.caption)
                .foregroundColor(.secondary)

            // 分类快速点选 (8 核心网格 + 1 自定义底栏)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(NumberCategory.allCases.filter { $0 != .custom }, id: \.self) { cat in
                    categoryQuickButton(cat: cat)
                }
            }

            categoryQuickButton(cat: .custom)

            // 自定义标签
            HStack {
                Image(systemName: "tag.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                TextField("自定义备注标签（可选，如：装修推销）", text: $customTag)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(UIColor.tertiarySystemGroupedBackground))
            .cornerRadius(8)

            // 附带加入黑名单开关
            Toggle(isOn: $alsoBlockNumber) {
                HStack(spacing: 6) {
                    Image(systemName: "shield.slash")
                        .font(.caption)
                        .foregroundColor(alsoBlockNumber ? .red : .secondary)
                    Text("同时加入本地黑名单（拦截来电）")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.primary)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: .red))
            .padding(.vertical, 2)

            Button(action: {
                handleTagAndReport()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text(isSubmittingReport ? "提交中..." : "提交标记举报")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(.accentColor)
            .disabled(isSubmittingReport)
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    // MARK: - 操作 3：直接加入拦截黑名单
    private var blockAndInterceptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("立即彻底拦截并挂断", systemImage: "nosign")
                    .font(.headline)
                    .foregroundColor(.red)
                Spacer()
            }

            Text("写入本地 CallKit 阻止列表并立即热重载扩展。后续此号码来电将由 iOS 系统直接静默拦截。")
                .font(.caption)
                .foregroundColor(.secondary)

            Button(action: {
                handleBlockDirectly()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.shield.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("加入拦截黑名单 (静默挂断)")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    // MARK: - 操作逻辑调用

    private func handleSaveContact() {
        self.errorMessage = nil
        if let contact = quickActionCoordinator.prepareNewContact(name: contactName) {
            self.contactToPresent = contact
            self.isShowingNativeContactSheet = true
        }
    }

    private func handleTagAndReport() {
        self.isSubmittingReport = true
        self.errorMessage = nil

        let trimmedTag = customTag.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmedTag.isEmpty ? nil : trimmedTag

        Task {
            do {
                try await quickActionCoordinator.actionMarkAndReport(
                    category: selectedCategory,
                    label: label,
                    snippet: "通过陌生来电快捷面板上报"
                )

                if alsoBlockNumber {
                    try? await quickActionCoordinator.actionAddToBlacklist(
                        label: label ?? selectedCategory.displayName,
                        category: selectedCategory
                    )
                }

                self.isSubmittingReport = false
                onDismiss()
            } catch {
                self.isSubmittingReport = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func handleBlockDirectly() {
        self.errorMessage = nil

        Task {
            do {
                try await quickActionCoordinator.actionAddToBlacklist(
                    label: "用户来电快捷拉黑",
                    category: .harassment
                )
                onDismiss()
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func categoryQuickButton(cat: NumberCategory) -> some View {
        let isSelected = selectedCategory == cat
        return Button(action: {
            selectedCategory = cat
        }) {
            HStack(spacing: 5) {
                Image(systemName: cat.systemImageName)
                    .font(.system(size: 11))
                Text(cat.displayName)
                    .font(.system(size: 11, weight: isSelected ? .bold : .regular))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundColor(isSelected ? .white : (cat.isRisk ? .red : .primary))
            .background(isSelected ? (cat.isRisk ? Color.red : Color.accentColor) : Color(UIColor.tertiarySystemGroupedBackground))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
