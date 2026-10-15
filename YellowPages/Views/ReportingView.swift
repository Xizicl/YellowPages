import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Tab 3: Reporting & Community 标记上报与社区协同
struct ReportingView: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 主动标记举报卡片
                    ReportFormCardView(viewModel: viewModel)

                    // 历史提交流水与本地队列管理
                    RecentReportsListView(viewModel: viewModel)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("标记上报")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                viewModel.refreshRecentReports()
            }
            .onAppear {
                viewModel.refreshRecentReports()
            }
        }
    }
}
