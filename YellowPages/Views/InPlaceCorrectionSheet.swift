import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Tab 2 就地号码修正与举报半屏面板
/// 遵守 Single Focus 原则：就地唤起、就地纠错、就地刷新，绝不生硬跨 Tab 打断用户反查流程
struct InPlaceCorrectionSheet: View {
    @ObservedObject var viewModel: MainViewModel
    let result: LookupDisplayResult
    var onDismiss: () -> Void

    @State private var selectedCategory: NumberCategory = .harassment
    @State private var correctedLabel: String = ""
    @State private var snippetText: String = ""
    @State private var alsoBlockNumber: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var isSuccess: Bool = false
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 当前号码特征卡片
                    targetHeaderCard

                    if isSuccess {
                        successFeedbackCard
                    } else {
                        // 纠错表单
                        formCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(result.isFound ? "就地修正或举报" : "为此号码添加标记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isSuccess ? "完成" : "取消") {
                        onDismiss()
                    }
                    .foregroundColor(.secondary)
                }
            }
            .onAppear {
                self.selectedCategory = result.category
                self.correctedLabel = (result.displayLabel == "未标记号码" || result.displayLabel == "未收录号码") ? "" : result.displayLabel
                self.alsoBlockNumber = result.isBlocking
            }
        }
    }

    // MARK: - 当前号码卡片
    private var targetHeaderCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "pencil.and.list.clipboard")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(result.phoneNumber)
                    .font(.system(.headline, design: .monospaced).weight(.bold))
                    .foregroundColor(.primary)

                HStack(spacing: 6) {
                    Text("当前状态:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(result.displayLabel)
                        .font(.caption2.bold())
                        .foregroundColor(.primary)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - 纠错表单
    private var formCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 正确分类点选 (8 项工整网格排版：3 显示类 + 5 拦截类)
            VStack(alignment: .leading, spacing: 8) {
                Text("修正为分类 (必选)")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    ForEach(NumberCategory.allCases.filter { $0 != .custom }, id: \.self) { cat in
                        categoryCorrectionButton(cat: cat)
                    }
                }

                categoryCorrectionButton(cat: .custom)
            }

            // 修正标签名称
            VStack(alignment: .leading, spacing: 6) {
                Text("修正或建议的新名称标签")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                HStack {
                    Image(systemName: "tag.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))

                    TextField("如：顺丰快递员、招行信用卡客服", text: $correctedLabel)
                        .font(.subheadline)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(UIColor.tertiarySystemGroupedBackground))
                .cornerRadius(10)
            }

            // 简短说明或内容摘要
            VStack(alignment: .leading, spacing: 6) {
                Text("通话或短信内容特征 (可选)")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                TextField("如：声称贷款办理、推销商铺等", text: $snippetText)
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(UIColor.tertiarySystemGroupedBackground))
                    .cornerRadius(8)
            }

            // 是否加入拦截黑名单
            Toggle(isOn: $alsoBlockNumber) {
                HStack(spacing: 6) {
                    Image(systemName: "nosign")
                        .foregroundColor(alsoBlockNumber ? .red : .secondary)
                        .font(.caption)
                    Text("同时加入本地黑名单 (CallKit 直接拦截挂断)")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.primary)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: .red))
            .padding(.vertical, 2)

            if let err = errorMessage {
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

            Button(action: {
                handleSubmitCorrection()
            }) {
                HStack(spacing: 6) {
                    if isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                    }
                    Text(isSubmitting ? "正在提交..." : (result.isFound ? "就地提交修正与举报" : "保存并提交标记"))
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .disabled(isSubmitting)
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    // MARK: - 成功反馈
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
                Text("修正与举报已提交")
                    .font(.headline)
                    .foregroundColor(.primary)

                Text("数据已提交至本地离线队列与云端聚合管道，本地反查已即时更新。")
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

    private func handleSubmitCorrection() {
        self.errorMessage = nil
        self.isSubmitting = true

        let labelToSubmit = correctedLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? selectedCategory.displayName : correctedLabel
        let snippet = snippetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : snippetText

        Task {
            do {
                // 1. 上报纠错流水
                try await viewModel.reportService.submitReport(
                    rawPhoneNumber: result.phoneNumber,
                    type: .call,
                    category: selectedCategory,
                    customLabel: labelToSubmit,
                    contentSnippet: snippet,
                    actionSuggested: alsoBlockNumber ? .block : .identify
                )

                // 2. 如果勾选拦截黑名单，直接加入本地库并重载
                if alsoBlockNumber, let num = ReportService.normalizeToE164(raw: result.phoneNumber) {
                    try? viewModel.store.addBlacklistNumber(phone: num, label: labelToSubmit, category: selectedCategory)
                    try? await viewModel.callDirectoryManager.reloadExtension()
                }

                // 3. 就地重新触发一次反查，使用户直接看到最新的纠错效果！
                viewModel.onSearchInputChanged()

                self.isSubmitting = false
                self.isSuccess = true
            } catch {
                self.isSubmitting = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func categoryCorrectionButton(cat: NumberCategory) -> some View {
        let isSelected = selectedCategory == cat
        return Button(action: {
            selectedCategory = cat
            if cat.isRisk {
                alsoBlockNumber = true
            }
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
