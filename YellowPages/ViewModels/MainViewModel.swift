import Foundation
import Combine
import SwiftUI

/// 服务端连接检测状态
public enum ServerConnectionStatus: Equatable, Sendable {
    case idle
    case testing
    case connected(latencyMs: Int)
    case failed(reason: String)
}

/// 统一的号码匹配结果展示模型（融合本地库与在线查询）
public struct LookupDisplayResult: Equatable, Sendable {
    public let phoneNumber: String
    public let displayLabel: String
    public let category: NumberCategory
    public let action: EntryAction
    public let confidence: Double
    public let isBlocking: Bool
    public let isFound: Bool
    public let sourceDescription: String
    public let locationDescription: String?
    public let carrierDescription: String?
    public let riskLevel: String?
    public let reportCount: Int?

    public init(
        phoneNumber: String,
        displayLabel: String,
        category: NumberCategory,
        action: EntryAction,
        confidence: Double,
        isBlocking: Bool,
        isFound: Bool = true,
        sourceDescription: String,
        locationDescription: String? = nil,
        carrierDescription: String? = nil,
        riskLevel: String? = nil,
        reportCount: Int? = nil
    ) {
        self.phoneNumber = phoneNumber
        self.displayLabel = displayLabel
        self.category = category
        self.action = action
        self.confidence = confidence
        self.isBlocking = isBlocking
        self.isFound = isFound
        self.sourceDescription = sourceDescription
        self.locationDescription = locationDescription
        self.carrierDescription = carrierDescription
        self.riskLevel = riskLevel
        self.reportCount = reportCount
    }
}

/// 同步阶段状态
public enum SyncPhase: Equatable, Sendable {
    case idle
    case checking
    case syncing(progress: Double?, message: String)
    case success(message: String)
    case failure(message: String)
}

/// 主界面单一事实源 (SSOT) 协调器
@MainActor
public final class MainViewModel: ObservableObject {
    // MARK: - 依赖服务
    public let callDirectoryManager: CallDirectoryManager
    public let syncService: SyncService
    public let reportService: ReportService
    public let store: DirectoryStore
    public let quickActionCoordinator: QuickActionCoordinator

    // MARK: - 快捷处置与来电弹窗
    @Published public var presentedQuickActionPrompt: DetectedCallPrompt? = nil
    private var cancellables = Set<AnyCancellable>()

    // MARK: - 模块 1：系统扩展与数据状态
    @Published public private(set) var callKitStatus: CallDirectoryStatus = .unknown
    @Published public private(set) var localDatabaseVersion: Int64 = 0
    @Published public private(set) var identificationCount: Int = 0
    @Published public private(set) var blockingCount: Int = 0
    @Published public private(set) var lastSyncDate: Date? = nil
    @Published public private(set) var syncPhase: SyncPhase = .idle

    /// 以时间戳为基准的友好版本号显示，避免初始显示为 --
    public var formattedDatabaseVersion: String {
        guard localDatabaseVersion > 0 else {
            return "未同步"
        }
        let s = String(localDatabaseVersion)
        if s.count == 12 {
            let y = s.prefix(4)
            let m = s.dropFirst(4).prefix(2)
            let d = s.dropFirst(6).prefix(2)
            let h = s.dropFirst(8).prefix(2)
            let min = s.dropFirst(10).prefix(2)
            return "\(y).\(m).\(d) \(h):\(min)"
        }
        return "v\(localDatabaseVersion)"
    }

    // MARK: - 模块 2：号码反查与识别
    @Published public var searchInput: String = ""
    @Published public private(set) var isSearching: Bool = false
    @Published public private(set) var searchResult: LookupDisplayResult? = nil
    @Published public private(set) var searchError: String? = nil
    private var searchTask: Task<Void, Never>? = nil

    // MARK: - 模块 3：标记与举报表单
    @Published public var reportRawPhone: String = ""
    @Published public var reportType: ReportType = .call
    @Published public var reportCategory: NumberCategory = .delivery
    @Published public var selectedCallCategory: CallCategory = .delivery
    @Published public var selectedSMSPrimaryAction: SMSPrimaryAction = .junk
    @Published public var selectedSMSSubCategory: SMSCategory? = nil
    @Published public var selectedSMSCategory: SMSCategory = .junk
    @Published public var reportCustomLabel: String = ""
    @Published public var reportActionSuggested: EntryAction = .identify
    @Published public var reportContentSnippet: String = ""
    @Published public private(set) var isSubmittingReport: Bool = false
    @Published public private(set) var reportSubmissionNotice: String? = nil

    // MARK: - 模块 4：近期上报记录与过滤
    @Published public private(set) var recentReports: [ReportRecord] = []
    @Published public var reportHistoryQuery: String = ""
    @Published public var reportCategoryFilter: NumberCategory? = nil

    // MARK: - 模块 5：核心设置与状态 (Settings & Identity)
    @Published public var serverAddressInput: String = AppGroupConstants.serverBaseURL.absoluteString
    @Published public private(set) var serverConnectionStatus: ServerConnectionStatus = .idle
    @Published public private(set) var deviceFingerprint: String = ""
    @Published public private(set) var databaseFileSizeText: String = "--"
    @Published public private(set) var categoryBreakdown: [(NumberCategory, Int)] = []
    @Published public private(set) var deviceCreditLevel: String = "excellent"
    @Published public private(set) var deviceCreditLevelName: String = "良好"
    @Published public private(set) var deviceReputationScore: Double = 100.0

    // MARK: - 模块 6：号码误标申诉与就地纠错
    @Published public var isShowingAppealSheet: Bool = false
    @Published public var appealTargetNumber: String = ""
    @Published public private(set) var isSubmittingAppeal: Bool = false
    @Published public private(set) var appealResultMessage: String? = nil

    @Published public var isShowingCorrectionSheet: Bool = false
    @Published public var correctionTargetResult: LookupDisplayResult? = nil

    // MARK: - 模块 7：本地快照备份与导出
    @Published public private(set) var backupList: [DatabaseBackupItem] = []
    @Published public private(set) var backupNotice: String? = nil

    public func refreshBackups() {
        self.backupList = store.listBackups()
    }

    public func createNewBackup() {
        do {
            let item = try store.createBackup(maxKeep: 5)
            refreshBackups()
            backupNotice = "成功创建备份: \(item.fileName) (\(item.recordCount)条)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.backupNotice = nil
            }
        } catch {
            backupNotice = "备份失败: \(error.localizedDescription)"
        }
    }

    public func deleteBackupItem(_ item: DatabaseBackupItem) {
        try? store.deleteBackup(fileName: item.fileName)
        refreshBackups()
    }

    public func presentCorrection(for result: LookupDisplayResult) {
        self.correctionTargetResult = result
        self.isShowingCorrectionSheet = true
    }

    public func presentAppeal(for phoneNumber: String = "") {
        self.appealTargetNumber = phoneNumber
        self.appealResultMessage = nil
        self.isShowingAppealSheet = true
    }

    public func submitAppeal(
        phoneNumber: String,
        appealType: String,
        reason: String,
        contactPhone: String,
        contactEmail: String,
        proofSnippet: String? = nil
    ) async throws {
        self.isSubmittingAppeal = true
        defer { self.isSubmittingAppeal = false }

        let resp = try await syncService.submitAppeal(
            phoneNumber: phoneNumber,
            appealType: appealType,
            reason: reason,
            contactPhone: contactPhone,
            contactEmail: contactEmail,
            proofSnippet: proofSnippet
        )
        self.appealResultMessage = resp.message ?? "申诉已成功受理！"
    }

    // 筛选计算属性
    public var filteredRecentReports: [ReportRecord] {
        recentReports.filter { record in
            let matchText: Bool
            if reportHistoryQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                matchText = true
            } else {
                let query = reportHistoryQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let phoneMatch = record.rawPhoneNumber.contains(query) || "\(record.normalizedPhone)".contains(query)
                let labelMatch = record.customLabel?.lowercased().contains(query) ?? false
                let snippetMatch = record.contentSnippet?.lowercased().contains(query) ?? false
                let categoryMatch = record.category.displayName.lowercased().contains(query)
                matchText = phoneMatch || labelMatch || snippetMatch || categoryMatch
            }

            let matchCategory: Bool
            if let cat = reportCategoryFilter {
                matchCategory = record.category == cat
            } else {
                matchCategory = true
            }

            return matchText && matchCategory
        }
    }

    public init() {
        self.callDirectoryManager = .shared
        self.syncService = .shared
        self.reportService = .shared
        self.store = .shared
        self.quickActionCoordinator = .shared

        bindQuickActionCoordinator()
        refreshAll()
    }

    public init(
        callDirectoryManager: CallDirectoryManager,
        syncService: SyncService,
        reportService: ReportService,
        store: DirectoryStore,
        quickActionCoordinator: QuickActionCoordinator
    ) {
        self.callDirectoryManager = callDirectoryManager
        self.syncService = syncService
        self.reportService = reportService
        self.store = store
        self.quickActionCoordinator = quickActionCoordinator

        bindQuickActionCoordinator()
        refreshAll()
    }

    private func bindQuickActionCoordinator() {
        quickActionCoordinator.$activePrompt
            .receive(on: RunLoop.main)
            .sink { [weak self] prompt in
                self?.presentedQuickActionPrompt = prompt
            }
            .store(in: &cancellables)

        #if canImport(UIKit)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshAll()
            }
            .store(in: &cancellables)
        #endif
    }

    // MARK: - 总体刷新
    public func refreshAll() {
        refreshCallKitStatus()
        refreshLocalDatabaseStats()
        refreshRecentReports()
        refreshDeviceProfileAndStorage()
        refreshBackups()
    }

    // MARK: - 模块 1：CallKit 与 同步交互
    public func refreshCallKitStatus() {
        Task {
            let status = await callDirectoryManager.checkEnabledStatus()
            self.callKitStatus = status
        }
    }

    public func refreshLocalDatabaseStats() {
        self.localDatabaseVersion = store.getLocalVersion()
        self.identificationCount = store.getRecordCount(action: .identify)
        self.blockingCount = store.getRecordCount(action: .block)
        if let lastReload = callDirectoryManager.lastReloadDate {
            self.lastSyncDate = lastReload
        }

        // 计算各分类规则构成 (8 核心分类 + 1 自定义标记)
        let categories: [NumberCategory] = [.delivery, .official, .enterprise, .realEstate, .financeLoan, .marketing, .harassment, .fraud, .custom]
        self.categoryBreakdown = categories.compactMap { cat in
            let count = store.getCategoryCount(category: cat)
            return (cat, count)
        }
    }

    public func refreshDeviceProfileAndStorage() {
        // 读取规范化的加盐 SHA-256 匿名设备凭证 (与服务端 100% 绝对一致)
        self.deviceFingerprint = ReportService.resolveDeviceFingerprint()

        // 读取数据库文件物理占用
        let dbURL = AppGroupConstants.databaseURL
        if let attrs = try? FileManager.default.attributesOfItem(atPath: dbURL.path),
           let size = attrs[.size] as? Int64 {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB]
            formatter.countStyle = .file
            self.databaseFileSizeText = formatter.string(fromByteCount: size)
        } else {
            self.databaseFileSizeText = "< 1 MB"
        }
    }

    /// 重置并清空离线号码库
    public func resetLocalDatabase() {
        do {
            try store.clearAllEntries()
            refreshLocalDatabaseStats()
            refreshDeviceProfileAndStorage()
            Task {
                try? await callDirectoryManager.reloadExtension()
            }
        } catch {
            print("[MainViewModel] 重置离线库失败: \(error)")
        }
    }

    // MARK: - 服务端地址配置与连通性检测

    /// 保存并应用新的服务端地址
    public func saveServerAddress() {
        let trimmed = serverAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme, (scheme == "http" || scheme == "https") else {
            self.serverConnectionStatus = .failed(reason: "URL 格式不合法，需包含 http:// 或 https://")
            return
        }

        AppGroupConstants.serverBaseURL = url
        self.serverAddressInput = url.absoluteString

        Task {
            await syncService.updateBaseURL(url)
            await reportService.updateBaseURL(url)
            testServerConnectivity()
        }
    }

    /// 测试当前输入的服务端连通性与毫秒级延迟
    public func testServerConnectivity() {
        let trimmed = serverAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let targetURL = URL(string: trimmed), let scheme = targetURL.scheme, (scheme == "http" || scheme == "https") else {
            self.serverConnectionStatus = .failed(reason: "无效的 URL 格式")
            return
        }

        self.serverConnectionStatus = .testing

        Task {
            let start = CFAbsoluteTimeGetCurrent()
            let pingURL = targetURL.appendingPathComponent("/api/v1/sync/metadata")
            var request = URLRequest(url: pingURL)
            request.httpMethod = "GET"
            request.timeoutInterval = 5.0
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(ReportService.resolveDeviceFingerprint(), forHTTPHeaderField: "X-Device-Fingerprint")
            request.setValue("iOS", forHTTPHeaderField: "X-Client-Platform")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)

                if let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) {
                    self.serverConnectionStatus = .connected(latencyMs: max(1, elapsed))

                    // 自动解析当前设备的真实服务端信用画像
                    if let envelope = try? JSONDecoder().decode(APIResponse<SyncMetadataResponse>.self, from: data),
                       let profile = envelope.data?.deviceProfile {
                        self.deviceCreditLevel = profile.creditLevel
                        self.deviceCreditLevelName = profile.creditLevelName
                        self.deviceReputationScore = profile.reputationScore
                    }
                } else if let httpResp = response as? HTTPURLResponse {
                    self.serverConnectionStatus = .failed(reason: "HTTP \(httpResp.statusCode)")
                } else {
                    self.serverConnectionStatus = .failed(reason: "无响应")
                }
            } catch {
                self.serverConnectionStatus = .failed(reason: "连接失败: \(error.localizedDescription)")
            }
        }
    }

    /// 一键应用预设地址
    public func applyServerPreset(_ urlString: String) {
        self.serverAddressInput = urlString
        saveServerAddress()
    }

    /// 重置为默认服务端地址
    public func resetServerAddressToDefault() {
        AppGroupConstants.resetServerURL()
        let defaultURL = AppGroupConstants.defaultServerURL
        self.serverAddressInput = defaultURL.absoluteString

        Task {
            await syncService.updateBaseURL(defaultURL)
            await reportService.updateBaseURL(defaultURL)
            testServerConnectivity()
        }
    }

    /// 执行同步操作（可强制全量）
    public func performSync(forceFull: Bool = false) {
        guard case .syncing = syncPhase else {
            // 继续
            syncPhase = .checking
            Task {
                do {
                    syncPhase = .syncing(progress: nil, message: forceFull ? "正在全量拉取号码库..." : "正在获取更新差量...")
                    let result = try await syncService.sync(forceFull: forceFull)
                    
                    refreshLocalDatabaseStats()
                    let enabledStatus = await callDirectoryManager.checkEnabledStatus()
                    self.callKitStatus = enabledStatus
                    self.lastSyncDate = Date()

                    let summary: String
                    switch result {
                    case .upToDate(let ver):
                        summary = "离线号码库已是最新版本 (v\(ver))"
                    case .full(let ver, let count):
                        summary = "全量同步完成：v\(ver)，已加载 \(count) 条记录"
                    case .incremental(let ver, let added, let updated, let removed):
                        summary = "增量更新完成：v\(ver) (+ \(added), ~\(updated), -\(removed))"
                    }

                    if let metadata = try? await syncService.fetchMetadata(), let profile = metadata.deviceProfile {
                        self.deviceCreditLevel = profile.creditLevel
                        self.deviceCreditLevelName = profile.creditLevelName
                        self.deviceReputationScore = profile.reputationScore
                    }

                    self.syncPhase = .success(message: summary)
                } catch {
                    self.syncPhase = .failure(message: error.localizedDescription)
                }
            }
            return
        }
    }

    /// 仅重载 CallKit 扩展
    public func reloadCallKitExtension() {
        Task {
            do {
                try await callDirectoryManager.reloadExtension()
                self.callKitStatus = .enabled
                self.lastSyncDate = Date()
                self.syncPhase = .success(message: "系统扩展已成功重新加载离线库")
            } catch {
                self.syncPhase = .failure(message: "扩展加载失败: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 模块 2：反查与智能识别
    public func onSearchInputChanged() {
        searchTask?.cancel()
        let text = searchInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            self.searchResult = nil
            self.searchError = nil
            self.isSearching = false
            return
        }

        // 仅当输入达到基本号码特征时触发检索
        guard text.count >= 3 else {
            self.searchResult = nil
            self.searchError = nil
            self.isSearching = false
            return
        }

        self.isSearching = true
        self.searchError = nil

        searchTask = Task {
            // 防抖 300ms
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            await executeLookup(for: text)
        }
    }

    private func executeLookup(for text: String) async {
        // 1. 先进行本地离线 SQLite 反查
        if let normalized = ReportService.normalizeToE164(raw: text),
           let localEntry = store.lookup(numericPhone: normalized) {
            self.searchResult = LookupDisplayResult(
                phoneNumber: localEntry.phoneString,
                displayLabel: localEntry.label,
                category: localEntry.category,
                action: localEntry.action,
                confidence: localEntry.confidence,
                isBlocking: localEntry.isBlocking,
                isFound: true,
                sourceDescription: "本地离线库（已载入 CallKit）"
            )
            self.isSearching = false
            return
        }

        // 2. 本地未命中，尝试云端在线实时反查
        do {
            if let online = try await syncService.lookupOnline(phoneNumber: text),
               online.found == true,
               let tag = online.tagInfo {
                let category = tag.category
                let label = tag.label
                let confidence = tag.confidence
                let isBlocking = tag.isBlocking
                let action: EntryAction = isBlocking ? .block : .identify
                
                var locationText: String? = nil
                if let loc = online.location {
                    let p = loc.province ?? ""
                    let c = loc.city ?? ""
                    let combined = "\(p) \(c)".trimmingCharacters(in: .whitespaces)
                    if !combined.isEmpty {
                        locationText = combined
                    }
                }

                let carrierText: String? = (online.carrier?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) ? nil : online.carrier

                self.searchResult = LookupDisplayResult(
                    phoneNumber: online.phoneNumber,
                    displayLabel: label,
                    category: category,
                    action: action,
                    confidence: confidence,
                    isBlocking: isBlocking,
                    isFound: true,
                    sourceDescription: "云端在线反查",
                    locationDescription: locationText,
                    carrierDescription: carrierText,
                    riskLevel: online.riskInfo?.level,
                    reportCount: online.riskInfo?.reportCount
                )
                self.isSearching = false
                return
            } else {
                // 本地与云端均未收录（陌生号码，严格置信度为 0.0，标记 isFound = false，各项描述严格如实）
                if let normalized = ReportService.normalizeToE164(raw: text) {
                    self.searchResult = LookupDisplayResult(
                        phoneNumber: String(normalized),
                        displayLabel: "未收录号码",
                        category: .harassment,
                        action: .identify,
                        confidence: 0.0,
                        isBlocking: false,
                        isFound: false,
                        sourceDescription: "离线库与云端均未收录",
                        locationDescription: nil,
                        carrierDescription: nil,
                        riskLevel: nil,
                        reportCount: nil
                    )
                } else {
                    self.searchResult = nil
                }
                self.isSearching = false
            }
        } catch {
            // 如果网络离线或接口异常，若有基本格式仍做客观提示 (isFound = false, confidence = 0.0)
            if let normalized = ReportService.normalizeToE164(raw: text) {
                self.searchResult = LookupDisplayResult(
                    phoneNumber: String(normalized),
                    displayLabel: "未收录号码",
                    category: .harassment,
                    action: .identify,
                    confidence: 0.0,
                    isBlocking: false,
                    isFound: false,
                    sourceDescription: "离线库未收录（在线反查不可用）",
                    locationDescription: nil,
                    carrierDescription: nil,
                    riskLevel: nil,
                    reportCount: nil
                )
            } else {
                self.searchError = "查询失败：\(error.localizedDescription)"
                self.searchResult = nil
            }
            self.isSearching = false
        }
    }

    /// 将搜索结果快速填入标记表单
    public func prefillReport(with result: LookupDisplayResult) {
        self.reportRawPhone = result.phoneNumber
        self.reportCategory = result.isFound ? result.category : .harassment
        self.reportCustomLabel = (result.displayLabel == "未收录号码" || result.displayLabel == "未标记号码") ? "" : result.displayLabel
        self.reportActionSuggested = result.action
    }

    // MARK: - 模块 3：举报上报表单
    public func submitReport() {
        let phone = reportRawPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phone.isEmpty else {
            self.reportSubmissionNotice = reportType == .call ? "请输入需要标记的电话号码" : "请输入需要举报的发件人号码"
            return
        }

        self.isSubmittingReport = true
        self.reportSubmissionNotice = nil

        let trimmedLabel = reportCustomLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let customLabel = trimmedLabel.isEmpty ? nil : trimmedLabel
        let trimmedSnippet = reportContentSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
        let snippet = trimmedSnippet.isEmpty ? nil : trimmedSnippet

        let catToReport: String
        let resolvedCategory: CallCategory
        if reportType == .call {
            catToReport = selectedCallCategory.rawValue
            resolvedCategory = selectedCallCategory
        } else {
            if let sub = selectedSMSSubCategory, selectedSMSPrimaryAction.hasSubActions {
                catToReport = sub.rawValue
                resolvedCategory = sub.asCallCategory
            } else {
                catToReport = selectedSMSPrimaryAction.rawValue
                resolvedCategory = selectedSMSPrimaryAction == .junk ? .harassment : (selectedSMSPrimaryAction == .allow ? .official : .marketing)
            }
        }

        Task {
            do {
                _ = try await reportService.submitReport(
                    rawPhoneNumber: phone,
                    type: reportType,
                    category: resolvedCategory,
                    categoryRaw: catToReport,
                    customLabel: customLabel,
                    contentSnippet: snippet,
                    actionSuggested: reportActionSuggested
                )

                // 同时将该标记写入本地规则库，确保离线反查与 CallKit 即刻生效
                if let num = ReportService.normalizeToE164(raw: phone) {
                    let callAct = self.reportActionSuggested == .block ? 1 : 0
                    let smsAct: Int
                    let smsSub: Int
                    if callAct == 1 {
                        smsAct = 2
                        smsSub = 0
                    } else {
                        smsAct = self.reportType == .sms ? (resolvedCategory.isRisk ? 3 : 4) : 4
                        smsSub = 0
                    }
                    let effectiveLabel = customLabel ?? resolvedCategory.displayName
                    let entry = PhoneNumberEntry(
                        numericPhone: num,
                        label: effectiveLabel,
                        callAction: callAct,
                        callCategory: resolvedCategory.rawValue,
                        smsAction: smsAct,
                        smsSubAction: smsSub,
                        confidence: 1.0,
                        isDeleted: 0,
                        updatedAt: Int64(Date().timeIntervalSince1970 * 1000),
                        createdAt: Int64(Date().timeIntervalSince1970 * 1000)
                    )
                    try? self.store.batchUpsert(entries: [entry])
                }

                self.reportSubmissionNotice = "已成功保存标记"
                self.reportRawPhone = ""
                self.reportCustomLabel = ""
                self.reportContentSnippet = ""
                self.isSubmittingReport = false

                self.refreshRecentReports()
                self.refreshLocalDatabaseStats()
            } catch {
                self.reportSubmissionNotice = "提交失败: \(error.localizedDescription)"
                self.isSubmittingReport = false
            }
        }
    }

    // MARK: - 模块 4：近期记录管理
    public func refreshRecentReports() {
        do {
            self.recentReports = try store.fetchAllReports(limit: 100)
        } catch {
            print("[MainViewModel] 读取上报记录失败: \(error)")
        }
    }

    public func deleteReportRecord(id: String) {
        do {
            try store.removeReport(id: id)
            refreshRecentReports()
        } catch {
            print("[MainViewModel] 删除记录失败: \(error)")
        }
    }

    public func retryPendingUploads() {
        Task {
            let (success, failed) = await reportService.flushPendingReports()
            refreshRecentReports()
            if success > 0 || failed > 0 {
                self.reportSubmissionNotice = "队列同步完成：成功 \(success) 条，重试中 \(failed) 条"
            }
        }
    }
}
