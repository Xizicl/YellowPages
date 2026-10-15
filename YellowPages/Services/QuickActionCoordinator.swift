import Foundation
import Combine
import Contacts
#if canImport(UIKit)
import UIKit
#endif

/// 陌生号码快捷操作类型
nonisolated public enum QuickActionType: String, Sendable, CaseIterable {
    case saveToContacts = "save_contacts"
    case addToBlacklist = "add_blacklist"
    case markAndReport = "mark_report"
    
    public var title: String {
        switch self {
        case .saveToContacts: return "保存到通讯录"
        case .addToBlacklist: return "加入黑名单"
        case .markAndReport: return "标记并举报"
        }
    }
}

/// 剪贴板识别出的陌生号码待处理状态封装
nonisolated public struct DetectedCallPrompt: Identifiable, Equatable, Sendable {
    public var id: String { normalizedDigits }
    public let rawNumber: String
    public let normalizedDigits: String
    public let numericPhone: Int64
    public let formattedNumber: String
    public let detectedAt: Date
    
    public init(
        rawNumber: String,
        normalizedDigits: String,
        numericPhone: Int64,
        formattedNumber: String,
        detectedAt: Date = Date()
    ) {
        self.rawNumber = rawNumber
        self.normalizedDigits = normalizedDigits
        self.numericPhone = numericPhone
        self.formattedNumber = formattedNumber
        self.detectedAt = detectedAt
    }
}

/// 剪贴板智能号码捕获器与首次陌生来电挂断前台唤醒协调器
/// 用户挂断陌生号码复制后切回 App 时，快速唤起“保存到通讯录、加入黑名单、骚扰标记”操作矩阵
/// 纯净零权限架构：完全不索取通讯录读写权限，跳转调用系统原生新建联系人界面
@MainActor
public final class QuickActionCoordinator: ObservableObject {
    public static let shared = QuickActionCoordinator()
    
    // MARK: - 发布状态
    
    @Published public private(set) var activePrompt: DetectedCallPrompt? = nil
    @Published public private(set) var isProcessingAction: Bool = false
    @Published public private(set) var lastActionResultMessage: String? = nil
    
    // MARK: - 依赖服务
    
    private let directoryStore: DirectoryStore
    private let callDirectoryManager: CallDirectoryManager
    private let reportService: ReportService
    
    /// 上次已处理或已忽略的纯数字号码（防切回重复弹出）
    private var lastHandledDigits: String = ""
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        self.directoryStore = .shared
        self.callDirectoryManager = .shared
        self.reportService = .shared
        
        setupLifecycleObserver()
    }
    
    public init(
        directoryStore: DirectoryStore,
        callDirectoryManager: CallDirectoryManager,
        reportService: ReportService
    ) {
        self.directoryStore = directoryStore
        self.callDirectoryManager = callDirectoryManager
        self.reportService = reportService
        
        setupLifecycleObserver()
    }
    
    // MARK: - 生命周期监听
    
    private func setupLifecycleObserver() {
        #if canImport(UIKit) && !os(macOS)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.inspectClipboard()
            }
            .store(in: &cancellables)
        #endif
    }
    
    // MARK: - 剪贴板号码解析与智能防抖
    
    /// 主动探测剪贴板文本
    public func inspectClipboard() {
        #if canImport(UIKit) && !os(macOS)
        guard UIPasteboard.general.hasStrings else { return }
        guard let clipboardText = UIPasteboard.general.string else { return }
        
        guard let prompt = Self.parsePhoneNumber(from: clipboardText) else { return }
        
        // 防重复检查：如果与上次处理或弹出的号码一致，则不重复提示
        guard prompt.normalizedDigits != lastHandledDigits else { return }
        
        // 检查本地黑名单：若已在黑名单中，直接跳过
        let isAlreadyBlocked = directoryStore.isBlacklisted(phone: prompt.numericPhone)
        if isAlreadyBlocked {
            return
        }
        
        self.activePrompt = prompt
        #endif
    }
    
    /// 严格正则清洗与号码识别
    nonisolated public static func parsePhoneNumber(from input: String) -> DetectedCallPrompt? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty && trimmed.count <= 32 else { return nil }
        
        // 过滤常见电话修饰符：空格、横杠、括号、点
        var sanitized = trimmed.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "") // 不间断空格
        
        // 剥离国家代码前缀 +86 或 0086
        if sanitized.hasPrefix("+86") {
            sanitized = String(sanitized.dropFirst(3))
        } else if sanitized.hasPrefix("0086") {
            sanitized = String(sanitized.dropFirst(4))
        } else if sanitized.hasPrefix("+") {
            sanitized = String(sanitized.dropFirst())
        }
        
        // 验证剩余纯数字
        guard !sanitized.isEmpty && sanitized.allSatisfy({ $0.isNumber }) else {
            return nil
        }
        
        // 严格正则校验规则：
        // 1. 中国大陆 11 位手机号：1[3-9]\d{9}
        // 2. 带区号座机：0\d{2,3}\d{7,8} (长度 10-12 位)
        // 3. 企业 400/800 电话：(400|800)\d{7} (长度 10 位)
        let mobilePattern = #"^1[3-9]\d{9}$"#
        let landlinePattern = #"^0\d{2,3}\d{7,8}$"#
        let servicePattern = #"^(400|800)\d{7}$"#
        
        let isMobile = sanitized.range(of: mobilePattern, options: .regularExpression) != nil
        let isLandline = sanitized.range(of: landlinePattern, options: .regularExpression) != nil
        let isService = sanitized.range(of: servicePattern, options: .regularExpression) != nil
        
        guard isMobile || isLandline || isService else {
            return nil
        }
        
        // 映射为 E.164 纯数字 (Int64)
        guard let numericPhone = ReportService.normalizeToE164(raw: sanitized) else {
            return nil
        }
        
        // 格式化输出
        let formatted: String
        if isMobile && sanitized.count == 11 {
            let start = sanitized.startIndex
            let p1 = sanitized[start..<sanitized.index(start, offsetBy: 3)]
            let p2 = sanitized[sanitized.index(start, offsetBy: 3)..<sanitized.index(start, offsetBy: 7)]
            let p3 = sanitized[sanitized.index(start, offsetBy: 7)...]
            formatted = "\(p1)-\(p2)-\(p3)"
        } else {
            formatted = sanitized
        }
        
        return DetectedCallPrompt(
            rawNumber: trimmed,
            normalizedDigits: sanitized,
            numericPhone: numericPhone,
            formattedNumber: formatted
        )
    }
    
    // MARK: - 快捷操作执行
    
    /// 操作 1：准备原生新建联系人对象（零权限跳转）
    public func prepareNewContact(name: String) -> CNMutableContact? {
        guard let prompt = activePrompt else { return nil }
        
        let saveName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "陌生联系人 (\(prompt.formattedNumber))" : name
        let contact = NativeNewContactSheet.makeContact(name: saveName, phoneNumber: prompt.normalizedDigits, note: "黄页陌生来电")
        
        markPromptResolved(message: "已调起系统新建联系人页面")
        return contact
    }
    
    /// 操作 2：一键加入本地黑名单（拦截并立即重载 CallKit）
    public func actionAddToBlacklist(label: String? = nil, category: NumberCategory = .harassment) async throws {
        guard let prompt = activePrompt else { return }
        
        isProcessingAction = true
        defer { isProcessingAction = false }
        
        let displayLabel = (label?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ? "用户主动拉黑" : label!
        
        // 1. 写入本地 SQLite 黑名单
        try directoryStore.addBlacklistNumber(phone: prompt.numericPhone, label: displayLabel, category: category)
        
        // 2. 触发 CallKit 扩展热重载生效
        try await callDirectoryManager.reloadExtension()
        
        markPromptResolved(message: "已将 \(prompt.formattedNumber) 加入拦截黑名单并生效")
    }
    
    /// 操作 3：标记并向云端举报
    public func actionMarkAndReport(
        category: NumberCategory,
        label: String? = nil,
        snippet: String? = nil
    ) async throws {
        guard let prompt = activePrompt else { return }
        
        isProcessingAction = true
        defer { isProcessingAction = false }
        
        // 1. 提交举报流水到 ReportService（本地离线队列 + 云端异步上报）
        try await reportService.submitReport(
            rawPhoneNumber: prompt.normalizedDigits,
            type: .call,
            category: category,
            customLabel: label,
            contentSnippet: snippet,
            actionSuggested: category.isRisk ? .block : .identify
        )
        
        // 2. 若是骚扰或诈骗高危分类，同步加进本地黑名单阻断
        if category.isRisk {
            try? directoryStore.addBlacklistNumber(phone: prompt.numericPhone, label: label ?? category.displayName, category: category)
            try? await callDirectoryManager.reloadExtension()
        }
        
        markPromptResolved(message: "已成功标记并上报 \(prompt.formattedNumber)")
    }
    
    /// 忽略当前弹出的号码
    public func dismissCurrentPrompt() {
        if let current = activePrompt {
            lastHandledDigits = current.normalizedDigits
        }
        self.activePrompt = nil
    }
    
    private func markPromptResolved(message: String) {
        if let current = activePrompt {
            lastHandledDigits = current.normalizedDigits
        }
        self.activePrompt = nil
        self.lastActionResultMessage = message
    }
}
