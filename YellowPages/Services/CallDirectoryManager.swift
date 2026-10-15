import Foundation
import Combine
#if canImport(CallKit)
import CallKit
#endif

/// CallKit 扩展管理器错误
nonisolated public enum CallDirectoryError: LocalizedError, Sendable {
    case extensionDisabled
    case reloadFailed(code: Int, description: String)
    case timeout
    case unsupportedPlatform
    case unknown
    
    public var errorDescription: String? {
        switch self {
        case .extensionDisabled:
            return "电话识别扩展未在系统设置中启用，请前往「设置 - 电话 - 通话阻止与身份识别」开启"
        case .reloadFailed(let code, let description):
            return "CallKit 扩展刷新失败 [代码: \(code)]: \(description)"
        case .timeout:
            return "请求 CallKit 扩展操作超时"
        case .unsupportedPlatform:
            return "当前平台不支持 CallKit 电话识别功能"
        case .unknown:
            return "未知 CallKit 错误"
        }
    }
}

/// CallKit 扩展启用状态
nonisolated public enum CallDirectoryStatus: Equatable, Sendable {
    case unknown
    case disabled
    case enabled
    case error(String)
    
    public var isEnabled: Bool {
        self == .enabled
    }
}

/// CallKit 来电识别系统扩展统一协调器
/// 负责与系统的 CXCallDirectoryManager 通信、状态探测与数据重载触发
@MainActor
public final class CallDirectoryManager: ObservableObject {
    public static let shared = CallDirectoryManager()
    
    @Published public private(set) var status: CallDirectoryStatus = .unknown
    @Published public private(set) var isReloading: Bool = false
    @Published public private(set) var lastReloadDate: Date? = nil
    @Published public private(set) var lastErrorMessage: String? = nil
    
    public let extensionIdentifier: String
    
    public init(extensionIdentifier: String = AppGroupConstants.extensionBundleIdentifier) {
        self.extensionIdentifier = extensionIdentifier
    }
    
    // MARK: - 状态检查
    
    /// 检查 CallKit 扩展在系统设置中的开启状态
    @discardableResult
    public func checkEnabledStatus() async -> CallDirectoryStatus {
        #if os(iOS) || targetEnvironment(macCatalyst)
        let (newStatus, errorMessage) = await withCheckedContinuation { continuation in
            CXCallDirectoryManager.sharedInstance.getEnabledStatusForExtension(withIdentifier: extensionIdentifier) { enabledStatus, error in
                if let error = error {
                    continuation.resume(returning: (CallDirectoryStatus.error(error.localizedDescription), error.localizedDescription as String?))
                    return
                }
                
                let resolved: CallDirectoryStatus
                switch enabledStatus {
                case .enabled:
                    resolved = .enabled
                case .disabled:
                    resolved = .disabled
                case .unknown:
                    resolved = .unknown
                @unknown default:
                    resolved = .unknown
                }
                continuation.resume(returning: (resolved, nil as String?))
            }
        }
        
        self.status = newStatus
        self.lastErrorMessage = errorMessage
        return newStatus
        #else
        let newStatus = CallDirectoryStatus.enabled
        self.status = newStatus
        return newStatus
        #endif
    }
    
    // MARK: - 重载扩展数据
    
    /// 触发系统 CallKit 扩展重新加载单一事实源 SQLite 数据库中的最新号码
    public func reloadExtension() async throws {
        guard !isReloading else { return }
        
        isReloading = true
        lastErrorMessage = nil
        
        defer {
            isReloading = false
        }
        
        #if os(iOS) || targetEnvironment(macCatalyst)
        let maybeError: Error? = await withCheckedContinuation { continuation in
            CXCallDirectoryManager.sharedInstance.reloadExtension(withIdentifier: extensionIdentifier) { error in
                continuation.resume(returning: error)
            }
        }
        
        if let error = maybeError {
            let parsedError = Self.mapCallKitError(error)
            self.lastErrorMessage = parsedError.localizedDescription
            throw parsedError
        } else {
            self.lastReloadDate = Date()
            self.status = .enabled
            self.lastErrorMessage = nil
        }
        #else
        self.lastReloadDate = Date()
        self.status = .enabled
        #endif
    }
    
    // MARK: - 错误映射解析
    
    #if os(iOS) || targetEnvironment(macCatalyst)
    private static func mapCallKitError(_ error: Error) -> CallDirectoryError {
        let nsError = error as NSError
        guard nsError.domain == CXErrorDomainCallDirectoryManager else {
            return .reloadFailed(code: nsError.code, description: error.localizedDescription)
        }
        
        if let code = CXErrorCodeCallDirectoryManagerError.Code(rawValue: nsError.code) {
            switch code {
            case .unknown:
                return .reloadFailed(code: nsError.code, description: "未知错误")
            case .noExtensionFound:
                return .reloadFailed(code: nsError.code, description: "未找到指定的 Call Directory 扩展，请检查 Bundle ID 配置")
            case .loadingInterrupted:
                return .reloadFailed(code: nsError.code, description: "系统中断了扩展数据加载")
            case .entriesOutOfOrder:
                return .reloadFailed(code: nsError.code, description: "号码未严格按升序排列，已被 CallKit 拒绝")
            case .duplicateEntries:
                return .reloadFailed(code: nsError.code, description: "号码库中包含重复号码")
            case .maximumEntriesExceeded:
                return .reloadFailed(code: nsError.code, description: "号码数量超过 CallKit 限制")
            case .extensionDisabled:
                return .extensionDisabled
            case .currentlyLoading:
                return .reloadFailed(code: nsError.code, description: "扩展正在加载中，请勿频繁请求")
            case .unexpectedIncrementalRemoval:
                return .reloadFailed(code: nsError.code, description: "增量移除不存在的记录")
            @unknown default:
                return .reloadFailed(code: nsError.code, description: error.localizedDescription)
            }
        }
        
        return .reloadFailed(code: nsError.code, description: error.localizedDescription)
    }
    #endif
}
