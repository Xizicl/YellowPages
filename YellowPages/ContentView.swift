import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = MainViewModel()

    var body: some View {
        TabView {
            // Tab 1: 防护中枢 (Dashboard)
            DashboardView(viewModel: viewModel)
                .tabItem {
                    Label("防护中枢", systemImage: "shield.lefthalf.filled")
                }

            // Tab 2: 号码识别 (Number Identification)
            IdentificationView(viewModel: viewModel)
                .tabItem {
                    Label("号码识别", systemImage: "phone.badge.waveform")
                }

            // Tab 3: 标记上报 (Reporting & Community)
            ReportingView(viewModel: viewModel)
                .tabItem {
                    Label("标记上报", systemImage: "megaphone")
                }

            // Tab 4: 偏好设置 (Settings & Profile)
            SettingsView(viewModel: viewModel)
                .tabItem {
                    Label("偏好设置", systemImage: "slider.horizontal.3")
                }
        }
        .tint(.accentColor)
        // 全局挂断来电 / 剪贴板快速处置 Sheet
        .sheet(item: $viewModel.presentedQuickActionPrompt) { prompt in
            IncomingCallQuickActionSheet(
                quickActionCoordinator: viewModel.quickActionCoordinator,
                prompt: prompt,
                onDismiss: {
                    viewModel.presentedQuickActionPrompt = nil
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

#Preview {
    ContentView()
}
