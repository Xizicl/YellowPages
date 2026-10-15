import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 模块 2：号码反查与智能识别器
struct NumberLookupCardView: View {
    @ObservedObject var viewModel: MainViewModel
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 14) {
            // 模块标题
            HStack {
                Label("智能号码识别与反查", systemImage: "magnifyingglass.circle.fill")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                if viewModel.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            // 搜索输入栏
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 15))

                TextField("请输入需查询的电话号码（如 95338 或手机号）", text: $viewModel.searchInput)
                    .keyboardType(.phonePad)
                    .font(.system(.body, design: .monospaced))
                    .focused($isInputFocused)
                    .onChange(of: viewModel.searchInput) { _, _ in
                        viewModel.onSearchInputChanged()
                    }

                if !viewModel.searchInput.isEmpty {
                    Button(action: {
                        viewModel.searchInput = ""
                        viewModel.onSearchInputChanged()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 15))
                    }
                }

                if isInputFocused {
                    Button("完成") {
                        isInputFocused = false
                    }
                    .font(.caption.bold())
                    .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(10)

            // 搜索错误提示
            if let error = viewModel.searchError {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }

            // 查询结果卡片
            if let result = viewModel.searchResult {
                VStack(alignment: .leading, spacing: 12) {
                    // 头部：号码与来源归属
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.phoneNumber)
                                .font(.system(.title3, design: .monospaced).weight(.bold))
                                .foregroundColor(.primary)

                            if (result.carrierDescription?.isEmpty == false) || (result.locationDescription?.isEmpty == false) {
                                HStack(spacing: 8) {
                                    if let carrier = result.carrierDescription, !carrier.isEmpty {
                                        Text(carrier)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    if let loc = result.locationDescription, !loc.isEmpty {
                                        Text(loc)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }

                        Spacer()

                        // 拦截/识别/未收录标识
                        if result.isFound {
                            Text(result.action.displayName)
                                .font(.caption2.weight(.bold))
                                .foregroundColor(result.action == .block ? .white : .accentColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(result.action == .block ? Color.red : Color.accentColor.opacity(0.12))
                                .clipShape(Capsule())
                        } else {
                            Text("未收录")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(UIColor.tertiarySystemGroupedBackground))
                                .clipShape(Capsule())
                        }
                    }

                    Divider()

                    // 中部：识别标签与业务分类
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(categoryColor(for: result.category).opacity(0.12))
                                .frame(width: 44, height: 44)
                            Image(systemName: result.category.systemImageName)
                                .font(.system(size: 20))
                                .foregroundColor(categoryColor(for: result.category))
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(result.displayLabel)
                                .font(.system(.body, design: .rounded).weight(.semibold))
                                .foregroundColor(.primary)

                            if result.isFound {
                                HStack(spacing: 5) {
                                    Text(result.category.displayName)
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(categoryColor(for: result.category))
                                    Text("·")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(result.category.groupName)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text("尚未被官方或社区标记收录")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()
                    }

                    // 底部指标：已收录展示置信度条，未收录明确提示暂无数据
                    if result.isFound {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("置信度")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(Int(result.confidence * 100))%")
                                    .font(.caption2.bold())
                                    .monospacedDigit()
                                    .foregroundColor(confidenceColor(result.confidence))
                            }

                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color(UIColor.systemGray5))
                                        .frame(height: 6)
                                    Capsule()
                                        .fill(confidenceColor(result.confidence))
                                        .frame(width: max(4, proxy.size.width * CGFloat(result.confidence)), height: 6)
                                }
                            }
                            .frame(height: 6)
                        }
                    } else {
                        HStack {
                            Text("社区评级")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("暂无数据 (未收录)")
                                .font(.caption2)
                                .foregroundColor(Color(UIColor.tertiaryLabel))
                        }
                    }

                    // 来源标注与快捷操作 (已收录 -> 修正或举报；未收录 -> 标记此号码)
                    HStack {
                        Label(result.sourceDescription, systemImage: result.isFound ? "internaldrive.fill" : "questionmark.circle")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        Spacer()

                        if result.isFound {
                            Button(action: {
                                viewModel.presentAppeal(for: result.phoneNumber)
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "exclamationmark.bubble")
                                        .font(.system(size: 10))
                                    Text("误标申诉")
                                        .font(.caption.bold())
                                }
                                .foregroundColor(.orange)
                            }
                            .buttonStyle(.plain)

                            Text("·")
                                .foregroundColor(.secondary)

                            Button(action: {
                                viewModel.presentCorrection(for: result)
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "pencil.line")
                                        .font(.system(size: 10))
                                    Text("修正或举报")
                                        .font(.caption.bold())
                                }
                                .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                        } else {
                            // 未收录陌生号码：鲜明展示“标记此号码”
                            Button(action: {
                                viewModel.presentCorrection(for: result)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "tag.fill")
                                        .font(.system(size: 11))
                                    Text("标记此号码")
                                        .font(.caption.bold())
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.accentColor)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(14)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)
            } else if viewModel.searchInput.isEmpty {
                // 默认占位提示（无多余图示，纯 HIG 规范）
                HStack {
                    Text("支持反查官方机构、快递服务及已收录的骚扰推销号码。")
                        .font(.caption)
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .sheet(isPresented: $viewModel.isShowingAppealSheet) {
            AppealDisputeSheet(viewModel: viewModel) {
                viewModel.isShowingAppealSheet = false
            }
        }
        .sheet(isPresented: $viewModel.isShowingCorrectionSheet) {
            if let target = viewModel.correctionTargetResult {
                InPlaceCorrectionSheet(viewModel: viewModel, result: target) {
                    viewModel.isShowingCorrectionSheet = false
                }
            }
        }
    }

    private func categoryColor(for category: NumberCategory) -> Color {
        switch category {
        case .delivery:
            return .blue
        case .official:
            return .indigo
        case .enterprise:
            return .teal
        case .realEstate:
            return .orange
        case .financeLoan:
            return .yellow
        case .marketing:
            return .purple
        case .harassment, .fraud:
            return .red
        case .custom:
            return .secondary
        }
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 0.8 {
            return .green
        } else if confidence >= 0.5 {
            return .orange
        } else {
            return .secondary
        }
    }
}
