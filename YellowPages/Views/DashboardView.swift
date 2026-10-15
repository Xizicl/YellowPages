import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Tab 1: Dashboard 防护中枢 / 仪表盘
struct DashboardView: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 1. 系统扩展状态总览卡片 (含设置引导与同步中枢)
                    SystemStatusCardView(viewModel: viewModel)

                    // 2. 离线规则库看板与分类构成矩阵
                    databaseBreakdownCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("防护中枢")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                viewModel.refreshAll()
            }
        }
    }

    // MARK: - 离线规则库分类构成矩阵
    private var databaseBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("离线规则库构成", systemImage: "chart.bar.xaxis")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Text("共 \(viewModel.identificationCount + viewModel.blockingCount) 条")
                    .font(.caption.bold())
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }

            // 8 个核心分类规则构成矩阵（3 显示类 + 5 拦截类，完美 8 项工整网格）
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(viewModel.categoryBreakdown.filter { $0.0 != .custom }, id: \.0) { cat, count in
                    categoryTile(cat: cat, count: count)
                }
            }

            // 用户自主标记规则
            if let customTuple = viewModel.categoryBreakdown.first(where: { $0.0 == .custom }), customTuple.1 > 0 {
                categoryTile(cat: customTuple.0, count: customTuple.1)
            }

            Divider()

            HStack {
                Image(systemName: "lock.shield")
                    .font(.caption)
                    .foregroundColor(.green)
                Text("所有号码规则均保存在本地离线号码库中，支持无网离线识别与拦截。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private func categoryTile(cat: NumberCategory, count: Int) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(cat.isRisk ? Color.red.opacity(0.12) : Color.accentColor.opacity(0.12))
                    .frame(width: 30, height: 30)
                Image(systemName: cat.systemImageName)
                    .font(.system(size: 13))
                    .foregroundColor(cat.isRisk ? .red : .accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(cat.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.primary)
                Text("\(count) 条")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(8)
        .background(Color(UIColor.tertiarySystemGroupedBackground))
        .cornerRadius(8)
    }
}
