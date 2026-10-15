import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 模块 3：陌生号码标记与举报表单
struct ReportFormCardView: View {
    @ObservedObject var viewModel: MainViewModel
    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case phone
        case label
        case snippet
    }

    // 电话模式 8 核心分类（4 行 × 2 列严格对称双列网格）
    private let callGridCategories: [CallCategory] = [
        .delivery, .official,
        .enterprise, .realEstate,
        .financeLoan, .marketing,
        .harassment, .fraud
    ]

    // 短信模式 6 一级动作（3 行 × 2 列严格对称双列网格）
    private let smsGridActions: [SMSPrimaryAction] = [
        .junk, .allow,
        .promotion, .transaction,
        .none, .custom
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 模块头部
            headerSection

            // 上报通道分段控制器（保留来电与短信，移除多余动作切换）
            channelPickerSection

            // 号码输入框
            phoneInputSection

            // 分类选择网格（电话 4x2+1 独立底栏；短信 3x2+二级细分抽屉）
            if viewModel.reportType == .call {
                callCategorySection
            } else {
                smsCategorySection
            }

            // 自定义标签与内容补充
            supplementarySection

            // 手机端真实生效呈现即时预览 (Live Preview)
            livePreviewSection

            // 状态反馈提示条
            if let notice = viewModel.reportSubmissionNotice {
                statusNoticeSection(notice: notice)
            }

            // 提交按钮
            submitButton
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .onChange(of: viewModel.reportType) { _, newType in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                handleChannelChange(to: newType)
            }
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        }
    }

    // MARK: - 头部区域
    private var headerSection: some View {
        HStack {
            Label("号码标记与举报", systemImage: "exclamationmark.bubble.fill")
                .font(.headline)
                .foregroundColor(.primary)
            Spacer()
            if viewModel.isSubmittingReport {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    // MARK: - 通道切换分段选择器（仅来电 / 短信）
    private var channelPickerSection: some View {
        Picker("上报通道", selection: $viewModel.reportType) {
            Text("来电").tag(ReportType.call)
            Text("短信").tag(ReportType.sms)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - 号码输入框
    private var phoneInputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(viewModel.reportType == .call ? "目标电话号码" : "发件人号码")
                .font(.caption2.weight(.medium))
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Image(systemName: viewModel.reportType == .call ? "phone.fill" : "message.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
                    .frame(width: 20)

                TextField(
                    viewModel.reportType == .call ? "请输入来电号码（如 95338 或手机号）" : "请输入发件人号码（支持 1069 等短号）",
                    text: $viewModel.reportRawPhone
                )
                .keyboardType(.phonePad)
                .font(.system(.body, design: .monospaced))
                .focused($focusedField, equals: .phone)

                if !viewModel.reportRawPhone.isEmpty {
                    Button(action: {
                        viewModel.reportRawPhone = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Color(UIColor.tertiarySystemGroupedBackground))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(focusedField == .phone ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
        }
    }

    // MARK: - 来电分类体系模块 (4 行 × 2 列严格对称双列网格 + 1 底栏独立卡片)
    private var callCategorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("来电分类")
                .font(.caption2.weight(.medium))
                .foregroundColor(.secondary)

            // 4 行 × 2 列双列等高网格
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 8
            ) {
                ForEach(callGridCategories, id: \.self) { cat in
                    callCategoryTile(cat: cat)
                }
            }

            // 第 9 个【自定义标记】作为底栏独立的等宽优雅卡片平铺
            callCustomCategoryCard
        }
    }

    // MARK: - 来电分类单项卡片
    private func callCategoryTile(cat: CallCategory) -> some View {
        let isSelected = viewModel.selectedCallCategory == cat
        let tint = callCategoryColor(for: cat)

        return Button(action: {
            callCategoryTapped(cat)
        }) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? tint : Color(UIColor.secondarySystemGroupedBackground))
                        .frame(width: 28, height: 28)
                    Image(systemName: cat.systemImageName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isSelected ? .white : tint)
                }

                Text(cat.displayName)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? tint : .primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(tint)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.10) : Color(UIColor.tertiarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? tint.opacity(0.55) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 第 9 个【自定义标记】底栏独立等宽卡片
    private var callCustomCategoryCard: some View {
        let isSelected = viewModel.selectedCallCategory == .custom
        let tint = Color.accentColor

        return Button(action: {
            callCategoryTapped(.custom)
        }) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? tint : Color(UIColor.secondarySystemGroupedBackground))
                        .frame(width: 28, height: 28)
                    Image(systemName: "tag.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isSelected ? .white : tint)
                }

                Text("自定义标记")
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? tint : .primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(tint)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text("输入专属名称")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.10) : Color(UIColor.tertiarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? tint.opacity(0.55) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 短信分类体系模块 (3 行 × 2 列严格对称双列网格 + 二级细分抽屉)
    private var smsCategorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("短信分类")
                .font(.caption2.weight(.medium))
                .foregroundColor(.secondary)

            // 3 行 × 2 列双列等高网格
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 8
            ) {
                ForEach(smsGridActions) { action in
                    smsPrimaryActionTile(action: action)
                }
            }

            // 二级细分平滑展开抽屉
            if viewModel.selectedSMSPrimaryAction.hasSubActions {
                smsSubActionsDrawer
            }
        }
    }

    // MARK: - 短信一级分类单项卡片
    private func smsPrimaryActionTile(action: SMSPrimaryAction) -> some View {
        let isSelected = viewModel.selectedSMSPrimaryAction == action
        let tint = smsActionColor(for: action)
        let hasSub = action.hasSubActions

        return Button(action: {
            smsPrimaryActionTapped(action)
        }) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? tint : Color(UIColor.secondarySystemGroupedBackground))
                        .frame(width: 28, height: 28)
                    Image(systemName: action.systemImageName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isSelected ? .white : tint)
                }

                Text(smsActionTitle(for: action))
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? tint : .primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if hasSub {
                    Image(systemName: isSelected ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(isSelected ? tint : Color(UIColor.tertiaryLabel))
                } else if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(tint)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.10) : Color(UIColor.tertiarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? tint.opacity(0.55) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 短信二级细分平滑展开抽屉 (等高紧凑网格，清爽透气)
    private var smsSubActionsDrawer: some View {
        let isPromotion = viewModel.selectedSMSPrimaryAction == .promotion
        let tint = isPromotion ? Color.orange : Color.accentColor

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(isPromotion ? "推广细分类型" : "交易细分类型")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
                if let sub = viewModel.selectedSMSSubCategory {
                    Text(smsSubCategoryTitle(for: sub))
                        .font(.caption2.weight(.medium))
                        .foregroundColor(tint)
                }
            }
            .padding(.horizontal, 2)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6)
                ],
                spacing: 6
            ) {
                ForEach(viewModel.selectedSMSPrimaryAction.subCategories) { sub in
                    smsSubCategoryTile(sub: sub, tint: tint)
                }
            }
        }
        .padding(10)
        .background(Color(UIColor.tertiarySystemGroupedBackground))
        .cornerRadius(12)
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
    }

    // MARK: - 短信二级细分药丸单元格
    private func smsSubCategoryTile(sub: SMSCategory, tint: Color) -> some View {
        let isSelected = viewModel.selectedSMSSubCategory == sub

        return Button(action: {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                viewModel.selectedSMSSubCategory = sub
            }
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        }) {
            HStack(spacing: 5) {
                Image(systemName: sub.systemImageName)
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? tint : .secondary)

                Text(smsSubCategoryTitle(for: sub))
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? tint : .primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.12) : Color(UIColor.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? tint.opacity(0.55) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 补充说明与自定义标签输入
    private var supplementarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(supplementaryTitle)
                .font(.caption2.weight(.medium))
                .foregroundColor(.secondary)
                .animation(.easeInOut(duration: 0.2), value: isCustomSelected)

            VStack(spacing: 8) {
                // 自定义或补充标签
                HStack(spacing: 8) {
                    Image(systemName: "tag.fill")
                        .foregroundColor(isCustomSelected ? .accentColor : .secondary)
                        .font(.system(size: 13))
                        .frame(width: 20)

                    TextField(customLabelPlaceholder, text: $viewModel.reportCustomLabel)
                        .font(.system(size: 13))
                        .focused($focusedField, equals: .label)

                    if !viewModel.reportCustomLabel.isEmpty {
                        Button(action: { viewModel.reportCustomLabel = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Color(UIColor.tertiaryLabel))
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(Color(UIColor.tertiarySystemGroupedBackground))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(
                            focusedField == .label ? Color.accentColor.opacity(0.5) : (isCustomSelected ? Color.accentColor.opacity(0.35) : Color.clear),
                            lineWidth: 1.5
                        )
                )

                // 摘要或关键词补充
                HStack(spacing: 8) {
                    Image(systemName: viewModel.reportType == .call ? "quote.bubble" : "text.bubble.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                        .frame(width: 20)

                    TextField(contentSnippetPlaceholder, text: $viewModel.reportContentSnippet)
                        .font(.system(size: 13))
                        .focused($focusedField, equals: .snippet)

                    if !viewModel.reportContentSnippet.isEmpty {
                        Button(action: { viewModel.reportContentSnippet = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Color(UIColor.tertiaryLabel))
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(Color(UIColor.tertiarySystemGroupedBackground))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(focusedField == .snippet ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
                )
            }
        }
    }

    // MARK: - 状态提示横幅
    private func statusNoticeSection(notice: String) -> some View {
        let isError = notice.contains("失败")
        return HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundColor(isError ? .red : .green)
                .font(.system(size: 14))
            Text(notice)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isError ? Color.red.opacity(0.08) : Color.green.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isError ? Color.red.opacity(0.3) : Color.green.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - 提交按钮
    private var submitButton: some View {
        Button(action: {
            focusedField = nil
            viewModel.submitReport()
        }) {
            HStack(spacing: 6) {
                if viewModel.isSubmittingReport {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                }
                Text(viewModel.reportType == .call ? "登记来电标记并上报" : "登记短信特征并上报")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(.accentColor)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .disabled(viewModel.reportRawPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSubmittingReport)
    }

    // MARK: - 手机端真实生效呈现即时预览 (Live Preview)
    private var livePreviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.accentColor)
                Text("iOS 27 原生呈现真实即时预览")
                    .font(.caption.bold())
                    .foregroundColor(.primary)
                Spacer()
                Text(viewModel.reportType == .call ? "CallKit 原生来电界面" : "Messages 会话原生分组")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }

            if viewModel.reportType == .call {
                callScreenLivePreview
            } else {
                smsMessageLivePreview
            }
        }
        .padding(12)
        .background(Color(UIColor.tertiarySystemGroupedBackground))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // 逼真的 iOS 27 来电全屏/海报原生即时预览卡片 (基于 iPhone 16 Pro 物理比例)
    private var callScreenLivePreview: some View {
        let isBlocked = viewModel.reportActionSuggested == .block || viewModel.selectedCallCategory == .harassment || viewModel.selectedCallCategory == .fraud
        let displayPhone = viewModel.reportRawPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "138 0000 8000" : viewModel.reportRawPhone

        return VStack(spacing: 0) {
            // 1. 顶部灵动岛 (Dynamic Island)
            HStack {
                Spacer()
                Capsule()
                    .fill(Color.black)
                    .frame(width: 88, height: 24)
                    .overlay(
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.black.opacity(0.8))
                                .frame(width: 8, height: 8)
                                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
                            Spacer()
                            Circle()
                                .fill(Color(red: 0.1, green: 0.2, blue: 0.35))
                                .frame(width: 7, height: 7)
                        }
                        .padding(.horizontal, 6)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
                Spacer()
            }
            .padding(.top, 10)
            .padding(.bottom, 12)

            // 2. 来电归属地与号码主体（原生 Contact Poster 顶部信息层）
            VStack(spacing: 4) {
                Text("中国大陆 · 移动转售 / 固话")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))

                Text(displayPhone)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                if isBlocked {
                    // 拦截类真实底色行为反馈
                    HStack(spacing: 6) {
                        Image(systemName: "shield.slash.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("系统直接静默拒接挂断（屏幕不亮屏、不震动）")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(Color(red: 1.0, green: 0.35, blue: 0.35))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.red.opacity(0.22))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.red.opacity(0.35), lineWidth: 0.8)
                    )
                    .padding(.top, 4)
                } else {
                    // 识别类 CallKit 原生加粗标识标签
                    VStack(spacing: 2) {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.cyan)
                            Text("YellowPages: [\(previewCallCategoryName)] \(previewCallLabel)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        Text("iOS 原生 CallKit 实时识别标识")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.55))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                    )
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)

            Spacer(minLength: 16)

            // 3. 底部 Contact Poster 风格原生双圆形拨号接听键
            HStack(spacing: 52) {
                // 红色拒绝/挂断键
                VStack(spacing: 4) {
                    Circle()
                        .fill(Color(red: 0.95, green: 0.26, blue: 0.21))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "phone.down.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        )
                        .shadow(color: Color.red.opacity(0.3), radius: 6, x: 0, y: 3)
                    Text("拒绝")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }

                // 绿色接听键
                VStack(spacing: 4) {
                    Circle()
                        .fill(Color(red: 0.20, green: 0.78, blue: 0.35))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "phone.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        )
                        .shadow(color: Color.green.opacity(0.3), radius: 6, x: 0, y: 3)
                    Text("接听")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.09, blue: 0.13),
                        Color(red: 0.12, green: 0.14, blue: 0.18),
                        Color(red: 0.05, green: 0.06, blue: 0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // 毛玻璃质感光斑
                RadialGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.18), Color.clear]),
                    center: .top,
                    startRadius: 10,
                    endRadius: 140
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
    }

    // 逼真的 iOS 27 Messages 原生分组与会话气泡卡片
    private var smsMessageLivePreview: some View {
        let isBlocked = viewModel.reportActionSuggested == .block || viewModel.selectedSMSPrimaryAction == .junk
        let displayPhone = viewModel.reportRawPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "1069 0000 1234" : viewModel.reportRawPhone

        return VStack(alignment: .leading, spacing: 10) {
            // 1. 真实 iOS Messages 会话单行（原生系统气泡与头像）
            HStack(alignment: .top, spacing: 10) {
                // 发件人拟真头像
                ZStack {
                    Circle()
                        .fill(previewSmsAvatarColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: previewSmsAvatarIcon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(previewSmsAvatarColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(displayPhone)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Spacer()
                        Text("刚刚")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(.secondary)
                    }

                    // 短信气泡预览
                    Text(previewSmsSnippetText)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .lineSpacing(2)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                }
            }

            Divider()
                .opacity(0.6)

            // 2. iOS 27 Messages 真实分组路径与系统动作
            HStack(spacing: 6) {
                Image(systemName: previewSmsDestinationIcon)
                    .font(.system(size: 11, weight: .bold))
                Text(previewSmsDestinationPathText)
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if isBlocked {
                    Text("原生静默过滤")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.15))
                        .foregroundColor(.red)
                        .cornerRadius(4)
                }
            }
            .foregroundColor(previewSmsDestinationColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(previewSmsDestinationColor.opacity(0.08))
            .cornerRadius(8)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var previewSmsDestinationPathText: String {
        if viewModel.reportActionSuggested == .block || viewModel.selectedSMSPrimaryAction == .junk {
            return "🚫 移入「垃圾信息」文件夹（系统不弹窗并静默拦截）"
        }
        switch viewModel.selectedSMSPrimaryAction {
        case .allow:
            return "✅ 保留「所有信息」主收件箱（高优先级横幅通知）"
        case .promotion:
            let subTitle = viewModel.selectedSMSSubCategory.map { smsSubCategoryTitle(for: $0) } ?? "优惠营销"
            return "📁 归入「推广信息」->「\(subTitle)」"
        case .transaction:
            let subTitle = viewModel.selectedSMSSubCategory.map { smsSubCategoryTitle(for: $0) } ?? "订单物流"
            return "📁 归入「交易信息」->「\(subTitle)」"
        case .none:
            return "📥 归入「所有信息」（默认收件箱）"
        case .custom:
            return "⚙️ 触发「自定义过滤规则」动态流转"
        case .junk:
            return "🚫 移入「垃圾信息」文件夹（系统不弹窗并静默拦截）"
        }
    }

    private var previewCallCategoryName: String {
        if viewModel.selectedCallCategory == .custom {
            return "自定义标记"
        }
        return viewModel.selectedCallCategory.displayName
    }

    private var previewCallLabel: String {
        let custom = viewModel.reportCustomLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            return custom
        }
        switch viewModel.selectedCallCategory {
        case .delivery: return "顺丰速运派件员"
        case .official: return "政务便民热线"
        case .enterprise: return "招商银行客服"
        case .realEstate: return "置业推销顾问"
        case .financeLoan: return "贷款授信中心"
        case .marketing: return "营销推广热线"
        case .harassment: return "高频恶意骚扰"
        case .fraud: return "高危诈骗电话"
        case .custom: return "自定义专属标记"
        }
    }

    private var previewSmsAvatarColor: Color {
        if viewModel.reportActionSuggested == .block || viewModel.selectedSMSPrimaryAction == .junk {
            return .red
        }
        if viewModel.selectedSMSPrimaryAction == .allow {
            return .green
        }
        if viewModel.selectedSMSPrimaryAction == .promotion {
            return .orange
        }
        return .accentColor
    }

    private var previewSmsAvatarIcon: String {
        if viewModel.reportActionSuggested == .block || viewModel.selectedSMSPrimaryAction == .junk {
            return "shield.slash.fill"
        }
        if viewModel.selectedSMSPrimaryAction == .allow {
            return "checkmark.shield.fill"
        }
        if viewModel.selectedSMSPrimaryAction == .promotion {
            return "megaphone.fill"
        }
        return "shippingbox.fill"
    }

    private var previewSmsSnippetText: String {
        let snippet = viewModel.reportContentSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
        if !snippet.isEmpty {
            return snippet
        }
        switch viewModel.selectedSMSPrimaryAction {
        case .junk: return "【高利分期】恭喜您获得20万免息额度，点击立即领取..."
        case .allow: return "【系统验证】您的动态验证码是 892301，5分钟内有效。"
        case .promotion: return "【特惠活动】年中大促全场满300减50，退订回T..."
        case .transaction: return "【顺丰速运】您的包裹已送达丰巢快递柜，取件码 5821。"
        case .none: return "收到一条普通短信通知。"
        case .custom: return "【自定义规则】符合用户设定的关键词规则。"
        }
    }

    private var previewSmsDestinationIcon: String {
        if viewModel.reportActionSuggested == .block || viewModel.selectedSMSPrimaryAction == .junk {
            return "xmark.bin.fill"
        }
        if viewModel.selectedSMSPrimaryAction == .allow {
            return "checkmark.seal.fill"
        }
        return "folder.fill"
    }

    private var previewSmsDestinationColor: Color {
        if viewModel.reportActionSuggested == .block || viewModel.selectedSMSPrimaryAction == .junk {
            return .red
        }
        if viewModel.selectedSMSPrimaryAction == .allow {
            return .green
        }
        if viewModel.selectedSMSPrimaryAction == .promotion {
            return .orange
        }
        return .accentColor
    }

    private var previewSmsDestinationText: String {
        if viewModel.reportActionSuggested == .block || viewModel.selectedSMSPrimaryAction == .junk {
            return "🚫 将自动移入：垃圾信息文件夹（系统彻底静默）"
        }
        switch viewModel.selectedSMSPrimaryAction {
        case .allow:
            return "✅ 将自动保留：主收件箱（高优先级横幅弹窗通知）"
        case .promotion:
            let subTitle = viewModel.selectedSMSSubCategory.map { smsSubCategoryTitle(for: $0) } ?? "优惠营销"
            let code = viewModel.selectedSMSSubCategory?.subActionCode ?? 20001
            return "📁 将自动归入：推广信息 -> \(subTitle) (\(code))"
        case .transaction:
            let subTitle = viewModel.selectedSMSSubCategory.map { smsSubCategoryTitle(for: $0) } ?? "订单物流"
            let code = viewModel.selectedSMSSubCategory?.subActionCode ?? 10002
            return "📁 将自动归入：交易信息 -> \(subTitle) (\(code))"
        case .none:
            return "📥 将自动归入：主收件箱（默认放行）"
        case .custom:
            return "⚙️ 将自动触发：用户自定义专属过滤规则"
        case .junk:
            return "🚫 将自动移入：垃圾信息文件夹（系统彻底静默）"
        }
    }

    // MARK: - 逻辑交互与事件处理
    private func callCategoryTapped(_ cat: CallCategory) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            viewModel.selectedCallCategory = cat
            viewModel.reportCategory = cat
            if cat == .harassment || cat == .fraud {
                viewModel.reportActionSuggested = .block
            } else {
                viewModel.reportActionSuggested = .identify
            }
            if cat == .custom {
                focusedField = .label
            }
        }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func smsPrimaryActionTapped(_ action: SMSPrimaryAction) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            viewModel.selectedSMSPrimaryAction = action
            switch action {
            case .junk:
                viewModel.selectedSMSSubCategory = nil
                viewModel.reportActionSuggested = .block
            case .allow:
                viewModel.selectedSMSSubCategory = nil
                viewModel.reportActionSuggested = .identify
            case .none:
                viewModel.selectedSMSSubCategory = nil
                viewModel.reportActionSuggested = .identify
            case .promotion:
                if viewModel.selectedSMSSubCategory == nil || !action.subCategories.contains(viewModel.selectedSMSSubCategory!) {
                    viewModel.selectedSMSSubCategory = .offers
                }
                viewModel.reportActionSuggested = .block
            case .transaction:
                if viewModel.selectedSMSSubCategory == nil || !action.subCategories.contains(viewModel.selectedSMSSubCategory!) {
                    viewModel.selectedSMSSubCategory = .orders
                }
                viewModel.reportActionSuggested = .identify
            case .custom:
                viewModel.selectedSMSSubCategory = nil
                viewModel.reportActionSuggested = .identify
                focusedField = .label
            }
        }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func handleChannelChange(to newType: ReportType) {
        if newType == .sms {
            viewModel.selectedSMSPrimaryAction = .junk
            viewModel.selectedSMSSubCategory = nil
            viewModel.reportActionSuggested = .block
        } else {
            if viewModel.selectedCallCategory == .harassment || viewModel.selectedCallCategory == .fraud {
                viewModel.reportActionSuggested = .block
            } else {
                viewModel.reportActionSuggested = .identify
            }
        }
    }

    // MARK: - 语义色彩与文本工具
    private func callCategoryColor(for cat: CallCategory) -> Color {
        switch cat {
        case .harassment, .fraud:
            return .red
        case .realEstate, .financeLoan, .marketing:
            return .orange
        case .delivery, .official, .enterprise, .custom:
            return .accentColor
        }
    }

    private func smsActionColor(for action: SMSPrimaryAction) -> Color {
        switch action {
        case .junk:
            return .red
        case .promotion:
            return .orange
        case .allow, .transaction, .none, .custom:
            return .accentColor
        }
    }

    private func smsActionTitle(for action: SMSPrimaryAction) -> String {
        switch action {
        case .junk: return "垃圾拦截"
        case .allow: return "验证码"
        case .promotion: return "商业推广"
        case .transaction: return "交易服务"
        case .none: return "默认放行"
        case .custom: return "自定义规则"
        }
    }

    private func smsSubCategoryTitle(for sub: SMSCategory) -> String {
        switch sub {
        case .offers: return "优惠促销"
        case .coupons: return "折扣卡券"
        case .promotionOthers: return "其他推广"
        case .orders: return "订单物流"
        case .finance: return "银行金融"
        case .publicServices: return "公共政务"
        case .reminders: return "行程预订"
        case .health: return "医疗健康"
        case .weather: return "气象预警"
        case .carrier: return "运营商"
        case .rewards: return "积分奖励"
        case .transactionOthers: return "其他交易"
        default: return sub.displayName
        }
    }

    private var isCustomSelected: Bool {
        if viewModel.reportType == .call {
            return viewModel.selectedCallCategory == .custom
        } else {
            return viewModel.selectedSMSPrimaryAction == .custom
        }
    }

    private var supplementaryTitle: String {
        if isCustomSelected {
            return viewModel.reportType == .call ? "自定义标签名称 (必填)" : "自定义规则名称 (必填)"
        } else {
            return "补充说明 (可选)"
        }
    }

    private var customLabelPlaceholder: String {
        if isCustomSelected {
            return viewModel.reportType == .call ? "输入专属名称（如：房东专线、专属快递）" : "输入规则名称（如：某业务通知规则）"
        } else {
            return viewModel.reportType == .call ? "机构或标识名称（如：顺丰速运、招商银行）" : "发件机构或服务名称（如：某电商平台、某政务通知）"
        }
    }

    private var contentSnippetPlaceholder: String {
        if isCustomSelected {
            return viewModel.reportType == .call ? "通话特征或说明备注" : "短信关键词（如：退订、免息、加群）"
        } else {
            return viewModel.reportType == .call ? "通话摘要或场景说明" : "短信关键文本（供过滤规则沉淀）"
        }
    }
}
