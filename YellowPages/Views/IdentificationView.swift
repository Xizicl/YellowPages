import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Tab 2: Number Identification 号码识别与反查终端 (纯净专业单号反查面板)
struct IdentificationView: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 号码反查卡片主模块
                    NumberLookupCardView(viewModel: viewModel)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("号码识别")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}
