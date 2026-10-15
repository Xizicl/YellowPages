import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 申诉类型前端枚举
enum AppealOption: String, CaseIterable, Identifiable {
    case falseSpam = "false_spam"
    case wrongName = "wrong_name"
    case whitelistRequest = "whitelist_request"
    case other = "other"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .falseSpam: return "误标为骚扰/营销/诈骗"
        case .wrongName: return "机构/企业名称信息有误"
        case .whitelistRequest: return "官方服务热线白名单认证"
        case .other: return "其他纠错说明"
        }
    }

    var subtitle: String {
        switch self {
        case .falseSpam: return "该号码为正常个人或日常业务通讯，请求解除拦截"
        case .wrongName: return "展示的机构名称有错别字、不准确或已发生变更"
        case .whitelistRequest: return "金融机构、物流调度或政企企事业单位官方客服"
        case .other: return "号码已换号、二手过户或存在其他特殊事实"
        }
    }

    var icon: String {
        switch self {
        case .falseSpam: return "exclamationmark.shield.fill"
        case .wrongName: return "character.cursor.ibeam"
        case .whitelistRequest: return "checkmark.seal.fill"
        case .other: return "ellipsis.bubble.fill"
        }
    }
}

/// 号码误标申诉与纠错面板
struct AppealDisputeSheet: View {
    @ObservedObject var viewModel: MainViewModel
    var onDismiss: () -> Void

    @State private var phoneNumber: String = ""
    @State private var selectedOption: AppealOption = .falseSpam
    @State private var reasonText: String = ""
    @State private var contactPhone: String = ""
    @State private var contactEmail: String = ""
    @State private var proofText: String = ""
    @State private var isSubmittedSuccessfully: Bool = false
    @State private var localErrorMessage: String? = nil

    private var isFormValid: Bool {
        let cleanPhone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanReason = reasonText.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanContactPhone = contactPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanContactEmail = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)

        let isPhoneValid = cleanContactPhone.count >= 5 && cleanContactPhone.allSatisfy { $0.isNumber || $0 == "-" || $0 == "+" }
        let isEmailValid = cleanContactEmail.contains("@") && cleanContactEmail.contains(".")

        return !cleanPhone.isEmpty && !cleanReason.isEmpty && isPhoneValid && isEmailValid
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    // 顶部引导卡片
                    headerInfoCard

                    if isSubmittedSuccessfully {
                        successFeedbackCard
                    } else {
                        // 申诉表单核心卡片
                        formSectionCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("误标申诉与纠错")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isSubmittedSuccessfully ? "完成" : "取消") {
                        onDismiss()
                    }
                    .foregroundColor(.secondary)
                }
            }
            .onAppear {
                if phoneNumber.isEmpty && !viewModel.appealTargetNumber.isEmpty {
                    phoneNumber = viewModel.appealTargetNumber
                }
            }
        }
    }

    // MARK: - 顶部说明卡片
    private var headerInfoCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "exclamationmark.bubble.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.orange)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("公众纠错与申诉通道")
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                Text("若号码被错误拦截或标签有误，提交核实后将自动解除拦截，并生成墓碑差量日志向全体客户端下发纠错。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - 表单核心卡片
    private var formSectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 1. 申诉号码 (必填)
            VStack(alignment: .leading, spacing: 6) {
                Text("申诉号码 (必填)")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                HStack {
                    Image(systemName: "phone.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))

                    TextField("如 13800138000 或 021-68888888", text: $phoneNumber)
                        .keyboardType(.phonePad)
                        .font(.system(.body, design: .monospaced))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(UIColor.tertiarySystemGroupedBackground))
                .cornerRadius(10)
            }

            // 2. 申诉类别 (垂直列表单选卡片，彻底避免横向截断)
            VStack(alignment: .leading, spacing: 8) {
                Text("申诉类型 (必选)")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                VStack(spacing: 6) {
                    ForEach(AppealOption.allCases) { opt in
                        let isSelected = selectedOption == opt
                        Button(action: {
                            selectedOption = opt
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: opt.icon)
                                    .font(.system(size: 15))
                                    .foregroundColor(isSelected ? .accentColor : .secondary)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(opt.title)
                                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                        .foregroundColor(.primary)
                                    Text(opt.subtitle)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(isSelected ? .accentColor : Color(UIColor.tertiaryLabel))
                                    .font(.system(size: 18))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(isSelected ? Color.accentColor.opacity(0.08) : Color(UIColor.tertiarySystemGroupedBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                            )
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // 3. 申诉事由与真实身份说明 (必填)
            VStack(alignment: .leading, spacing: 6) {
                Text("真实身份与申诉事由 (必填)")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                ZStack(alignment: .topLeading) {
                    if reasonText.isEmpty {
                        Text("请详细说明：例如该号码属于何种正常业务、日常用途或误报背景...")
                            .font(.caption)
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                            .padding(.top, 8)
                            .padding(.leading, 6)
                    }

                    TextEditor(text: $reasonText)
                        .frame(minHeight: 80)
                        .font(.subheadline)
                        .scrollContentBackground(.hidden)
                }
                .padding(8)
                .background(Color(UIColor.tertiarySystemGroupedBackground))
                .cornerRadius(10)
            }

            // 4. 联系人信息 (电话与邮箱均为必填)
            VStack(alignment: .leading, spacing: 10) {
                Text("申诉人联络方式 (电话与邮箱均必填)")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                // 电话
                HStack {
                    Image(systemName: "phone.badge.waveform")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))

                    TextField("联系电话 (必填，如：13900001111)", text: $contactPhone)
                        .keyboardType(.phonePad)
                        .font(.subheadline)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(UIColor.tertiarySystemGroupedBackground))
                .cornerRadius(10)

                // 邮箱
                HStack {
                    Image(systemName: "envelope.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))

                    TextField("电子邮箱 (必填，用于接收审核结论)", text: $contactEmail)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.subheadline)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(UIColor.tertiarySystemGroupedBackground))
                .cornerRadius(10)
            }

            // 5. 资质佐证 (可选)
            VStack(alignment: .leading, spacing: 6) {
                Text("备案或资质摘要 (可选)")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                TextField("如：营业执照名称、电信开户证明或工信部备案号", text: $proofText)
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(UIColor.tertiarySystemGroupedBackground))
                    .cornerRadius(8)
            }

            if let err = localErrorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(8)
                .background(Color.red.opacity(0.08))
                .cornerRadius(6)
            }

            // 提交按钮
            Button(action: {
                handleSubmitAppeal()
            }) {
                HStack(spacing: 6) {
                    if viewModel.isSubmittingAppeal {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 13, weight: .bold))
                    }
                    Text(viewModel.isSubmittingAppeal ? "正在提交..." : "提交纠错申诉")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .disabled(!isFormValid || viewModel.isSubmittingAppeal)
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    // MARK: - 成功反馈卡片
    private var successFeedbackCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 56, height: 56)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.green)
            }

            VStack(spacing: 4) {
                Text("申诉已成功受理")
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(viewModel.appealResultMessage ?? "工作人员核实后将自动解除标记，并下发差量更新纠错。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("完成并返回") {
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private func handleSubmitAppeal() {
        self.localErrorMessage = nil
        let cleanPhone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanReason = reasonText.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanContactPhone = contactPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanContactEmail = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanPhone.isEmpty else {
            self.localErrorMessage = "请填写需申诉的电话号码"
            return
        }

        guard !cleanReason.isEmpty else {
            self.localErrorMessage = "请填写申诉事由"
            return
        }

        guard cleanContactPhone.count >= 5 else {
            self.localErrorMessage = "请填写有效的联系电话"
            return
        }

        guard cleanContactEmail.contains("@") && cleanContactEmail.contains(".") else {
            self.localErrorMessage = "请填写格式正确的电子邮箱"
            return
        }

        let proof = proofText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : proofText

        Task {
            do {
                try await viewModel.submitAppeal(
                    phoneNumber: cleanPhone,
                    appealType: selectedOption.rawValue,
                    reason: cleanReason,
                    contactPhone: cleanContactPhone,
                    contactEmail: cleanContactEmail,
                    proofSnippet: proof
                )
                self.isSubmittedSuccessfully = true
            } catch {
                self.localErrorMessage = error.localizedDescription
            }
        }
    }
}
