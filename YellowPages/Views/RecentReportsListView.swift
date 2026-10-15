import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 模块 4：近期上报与本地记录列表
struct RecentReportsListView: View {
    @ObservedObject var viewModel: MainViewModel

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 模块头部与操作按钮
            HStack {
                Label("本地标记与上报记录", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: {
                    viewModel.retryPendingUploads()
                }) {
                    Label("同步队列", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // 搜索过滤与分类筛选栏
            VStack(spacing: 8) {
                // 搜索框
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundColor(.secondary)
                        .font(.caption)

                    TextField("搜索号码或机构标签", text: $viewModel.reportHistoryQuery)
                        .font(.caption)

                    if !viewModel.reportHistoryQuery.isEmpty {
                        Button(action: {
                            viewModel.reportHistoryQuery = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(8)

                // 分类筛选横向滚轴
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        filterChip(
                            title: "全部",
                            isSelected: viewModel.reportCategoryFilter == nil,
                            action: { viewModel.reportCategoryFilter = nil }
                        )

                        ForEach(NumberCategory.allCases, id: \.self) { cat in
                            filterChip(
                                title: cat.displayName,
                                isSelected: viewModel.reportCategoryFilter == cat,
                                action: { viewModel.reportCategoryFilter = cat }
                            )
                        }
                    }
                }
            }

            // 记录列表或空状态
            let items = viewModel.filteredRecentReports
            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text(viewModel.reportHistoryQuery.isEmpty ? "暂无本地标记记录" : "无匹配记录")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(spacing: 8) {
                    ForEach(items) { record in
                        recordRow(record)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(isSelected ? .bold : .regular))
                .foregroundColor(isSelected ? .white : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor : Color(UIColor.tertiarySystemGroupedBackground))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func recordRow(_ record: ReportRecord) -> some View {
        HStack(alignment: .center, spacing: 10) {
            // 分类图标
            ZStack {
                Circle()
                    .fill(categoryColor(for: record.category).opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: record.category.systemImageName)
                    .font(.system(size: 15))
                    .foregroundColor(categoryColor(for: record.category))
            }

            // 号码与标签
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(record.rawPhoneNumber)
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        .foregroundColor(.primary)

                    if let label = record.customLabel, !label.isEmpty {
                        Text(label)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .cornerRadius(4)
                    }
                }

                HStack(spacing: 8) {
                    Text(record.category.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text(dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(record.reportedAt / 1000))))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundColor(Color(UIColor.tertiaryLabel))

                    if let snippet = record.contentSnippet, !snippet.isEmpty {
                        Text(snippet)
                            .font(.caption2)
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // 状态指示徽标
            VStack(alignment: .trailing, spacing: 4) {
                statusBadge(for: record.status)

                Button(action: {
                    viewModel.deleteReportRecord(id: record.id)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(10)
    }

    private func statusBadge(for status: ReportStatus) -> some View {
        switch status {
        case .pending:
            return Text("待同步")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.12))
                .clipShape(Capsule())
        case .uploading:
            return Text("同步中")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.blue)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.12))
                .clipShape(Capsule())
        case .uploaded:
            return Text("已同步")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.green)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.12))
                .clipShape(Capsule())
        case .failed:
            return Text("重试中")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.red)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.12))
                .clipShape(Capsule())
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
}
