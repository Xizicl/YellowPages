import Foundation

/// App Group 与跨进程共享配置常量
nonisolated public enum AppGroupConstants {
    /// App Group 标识符（主 App 与 Call Directory Extension 共享数据容器）
    public static let groupIdentifier = "group.cn.xizicl.YellowPages"
    
    /// 统一 SQLite 数据库文件名
    public static let databaseFileName = "yellowpages_directory.sqlite"
    
    /// Call Directory Extension Bundle Identifier
    public static let extensionBundleIdentifier = "cn.xizicl.YellowPages.CallDirectoryExtension"
    
    /// 获取 App Group 共享数据容器路径
    public static var sharedContainerURL: URL {
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) {
            return container
        }
        // 未配置 App Group 权限时的默认存储位置
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("YellowPagesSharedGroup")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    /// SQLite 数据库文件的绝对路径 URL
    public static var databaseURL: URL {
        sharedContainerURL.appendingPathComponent(databaseFileName)
    }

    /// 备份目录的绝对路径 URL (backups/)
    public static var backupsDirectoryURL: URL {
        let dir = sharedContainerURL.appendingPathComponent("backups", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: - 服务端接入配置 (Server Endpoint)

    /// 服务端基础地址 UserDefaults 键名
    public static let serverURLKey = "cn.xizicl.YellowPages.server_base_url"

    /// 默认服务端基础 URL（对齐本地后端 8080 服务）
    public static let defaultServerURL = URL(string: "http://127.0.0.1:8080")!

    /// 当前配置的服务端基础 URL（支持动态读写与持久化）
    public static var serverBaseURL: URL {
        get {
            let defaults = UserDefaults(suiteName: groupIdentifier) ?? UserDefaults.standard
            if let saved = defaults.string(forKey: serverURLKey),
               let url = URL(string: saved),
               let scheme = url.scheme,
               (scheme == "http" || scheme == "https") {
                return url
            }
            return defaultServerURL
        }
        set {
            let defaults = UserDefaults(suiteName: groupIdentifier) ?? UserDefaults.standard
            defaults.set(newValue.absoluteString, forKey: serverURLKey)
            UserDefaults.standard.set(newValue.absoluteString, forKey: serverURLKey)
        }
    }

    /// 重置为默认服务端 URL
    public static func resetServerURL() {
        let defaults = UserDefaults(suiteName: groupIdentifier) ?? UserDefaults.standard
        defaults.removeObject(forKey: serverURLKey)
        UserDefaults.standard.removeObject(forKey: serverURLKey)
    }
}
