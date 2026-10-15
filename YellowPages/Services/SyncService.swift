import Foundation

/// 同步服务异常定义
nonisolated public enum SyncError: LocalizedError, Sendable {
    case invalidURL
    case httpError(statusCode: Int)
    case serverError(code: Int, message: String)
    case decodingError(String)
    case emptyData
    case invalidCursor
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的请求 URL"
        case .httpError(let code): return "网络请求异常，HTTP 状态码: \(code)"
        case .serverError(let code, let msg): return "服务端业务异常 [\(code)]: \(msg)"
        case .decodingError(let msg): return "数据解析失败: \(msg)"
        case .emptyData: return "服务端返回空数据"
        case .invalidCursor: return "同步游标失效"
        }
    }
}

/// 同步操作结果返回
nonisolated public enum SyncResult: Equatable, Sendable {
    case upToDate(version: Int64)
    case full(version: Int64, totalCount: Int)
    case incremental(version: Int64, added: Int, updated: Int, removed: Int)
}

/// 云端与本地离线数据库的同步协调服务
public actor SyncService {
    public static let shared = SyncService()
    
    private var baseURL: URL
    private let session: URLSession
    private let store: DirectoryStore
    
    public init(
        baseURL: URL = AppGroupConstants.serverBaseURL,
        session: URLSession = .shared,
        store: DirectoryStore = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
        self.store = store
    }

    /// 动态热更新服务端地址
    public func updateBaseURL(_ newURL: URL) {
        self.baseURL = newURL
    }

    /// 获取当前生效的服务端地址
    public func getBaseURL() -> URL {
        return self.baseURL
    }
    
    // MARK: - 主同步流程
    
    /// 执行同步（自动决策全量或增量更新，并在完成后自动触发 CallKit 扩展重载）
    public func sync(forceFull: Bool = false) async throws -> SyncResult {
        let localVersion = store.getLocalVersion()
        let metadata = try await fetchMetadata()
        
        // 1. 本地无数据、强制全量、或本地版本落后于最小兼容版本时，走全量拉取
        if forceFull || localVersion == 0 || localVersion < metadata.minSupportedVersion {
            let total = try await performFullSync(latestVersion: metadata.latestVersion, totalChunks: metadata.fullSyncChunks)
            await reloadCallDirectory()
            return .full(version: metadata.latestVersion, totalCount: total)
        }
        
        // 2. 本地版本已是最新
        if localVersion >= metadata.latestVersion {
            return .upToDate(version: localVersion)
        }
        
        // 3. 尝试拉取增量差异
        let delta = try await fetchDelta(sinceVersion: localVersion)
        
        if delta.requireFullReload {
            // 服务端判定跨度过大，安全降级为全量同步
            let total = try await performFullSync(latestVersion: delta.targetVersion, totalChunks: metadata.fullSyncChunks)
            await reloadCallDirectory()
            return .full(version: delta.targetVersion, totalCount: total)
        }
        
        // 4. 应用增量更新
        var addedCount = 0
        var updatedCount = 0
        var removedCount = 0
        
        for change in delta.changes {
            switch change.op {
            case .add: addedCount += 1
            case .update: updatedCount += 1
            case .remove: removedCount += 1
            }
        }
        
        try store.applyDelta(changes: delta.changes)
        try store.setLocalVersion(delta.targetVersion)
        
        await reloadCallDirectory()
        return .incremental(version: delta.targetVersion, added: addedCount, updated: updatedCount, removed: removedCount)
    }
    
    // MARK: - 全量分片同步实现
    
    private func performFullSync(latestVersion: Int64, totalChunks: Int) async throws -> Int {
        var allEntries: [PhoneNumberEntry] = []
        let chunkCount = max(1, totalChunks)
        
        for chunkIndex in 0..<chunkCount {
            let chunk = try await fetchFullChunk(index: chunkIndex)
            let entries = chunk.records.map { $0.toEntry() }
            allEntries.append(contentsOf: entries)
            
            if !chunk.hasMore {
                break
            }
        }
        
        // 清除旧库并全量写入
        try store.clearAllEntries()
        try store.batchUpsert(entries: allEntries)
        try store.setLocalVersion(latestVersion)
        
        // 全量同步完成后自动触发一次本地快照备份（保留最近 5 次）
        _ = try? store.createBackup(maxKeep: 5)
        
        return allEntries.count
    }
    
    private func reloadCallDirectory() async {
        Task { @MainActor in
            _ = try? await CallDirectoryManager.shared.reloadExtension()
        }
    }
    
    // MARK: - 网络请求细节
    
    public func fetchMetadata() async throws -> SyncMetadataResponse {
        let url = baseURL.appendingPathComponent("/api/v1/sync/metadata")
        return try await sendGet(url: url)
    }
    
    private func fetchFullChunk(index: Int) async throws -> SyncFullChunkResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("/api/v1/sync/full"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "chunk_index", value: String(index)),
            URLQueryItem(name: "chunk_size", value: "50000")
        ]
        guard let url = components?.url else { throw SyncError.invalidURL }
        return try await sendGet(url: url)
    }
    
    private func fetchDelta(sinceVersion: Int64, cursor: String? = nil) async throws -> SyncDeltaResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("/api/v1/sync/delta"), resolvingAgainstBaseURL: false)
        var queryItems = [
            URLQueryItem(name: "since_version", value: String(sinceVersion))
        ]
        if let cursor = cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { throw SyncError.invalidURL }
        return try await sendGet(url: url)
    }
    
    // MARK: - 在线反查能力 (Online Lookup)
    
    /// 单个号码实时反查（用于未收录离线库时的兜底查询）
    public func lookupOnline(phoneNumber: String) async throws -> NumberLookupResult? {
        var components = URLComponents(url: baseURL.appendingPathComponent("/api/v1/numbers/lookup"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "phone_number", value: phoneNumber)
        ]
        guard let url = components?.url else { throw SyncError.invalidURL }
        return try await sendGet(url: url)
    }
    
    // MARK: - 误标记申诉与纠错

    /// 提交误标记申诉申请（支持电话与邮箱双重必填字段）
    public func submitAppeal(
        phoneNumber: String,
        appealType: String = "false_spam",
        reason: String,
        contactPhone: String,
        contactEmail: String,
        proofSnippet: String? = nil
    ) async throws -> AppealResponseData {
        let url = baseURL.appendingPathComponent("/api/v1/appeals")
        let requestBody = AppealRequestBody(
            phoneNumber: phoneNumber,
            appealType: appealType,
            reason: reason,
            contactPhone: contactPhone,
            contactEmail: contactEmail,
            contactInfo: "\(contactPhone) | \(contactEmail)",
            proofSnippet: proofSnippet
        )
        return try await sendPost(url: url, body: requestBody)
    }
    
    // MARK: - 底层 HTTP 工具
    
    private func sendGet<T: Decodable & Sendable>(url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(ReportService.resolveDeviceFingerprint(), forHTTPHeaderField: "X-Device-Fingerprint")
        request.setValue("iOS", forHTTPHeaderField: "X-Client-Platform")
        
        let (data, response) = try await session.data(for: request)
        return try Self.handleResponse(data: data, response: response)
    }
    
    private func sendPost<Req: Encodable & Sendable, Resp: Decodable & Sendable>(url: URL, body: Req) async throws -> Resp {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(ReportService.resolveDeviceFingerprint(), forHTTPHeaderField: "X-Device-Fingerprint")
        request.setValue("iOS", forHTTPHeaderField: "X-Client-Platform")
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await session.data(for: request)
        return try Self.handleResponse(data: data, response: response)
    }
    
    nonisolated private static func handleResponse<T: Decodable & Sendable>(data: Data, response: URLResponse) throws -> T {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.httpError(statusCode: -1)
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw SyncError.httpError(statusCode: httpResponse.statusCode)
        }
        
        do {
            let envelope = try JSONDecoder().decode(APIResponse<T>.self, from: data)
            if envelope.isSuccess, let payload = envelope.data {
                return payload
            } else {
                throw SyncError.serverError(code: envelope.code, message: envelope.message)
            }
        } catch let err as SyncError {
            throw err
        } catch {
            throw SyncError.decodingError(error.localizedDescription)
        }
    }
}
