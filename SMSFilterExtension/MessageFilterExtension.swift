//
//  MessageFilterExtension.swift
//  SMSFilterExtension
//
//  Created for YellowPages.
//

import Foundation
import IdentityLookup
import SQLite3

final class MessageFilterExtension: ILMessageFilterExtension {}

extension MessageFilterExtension: ILMessageFilterQueryHandling, ILMessageFilterCapabilitiesQueryHandling {

    // MARK: - 宣告支持的二级分类 Capabilities
    func handle(
        _ capabilitiesQueryRequest: ILMessageFilterCapabilitiesQueryRequest,
        context: ILMessageFilterExtensionContext,
        completion: @escaping (ILMessageFilterCapabilitiesQueryResponse) -> Void
    ) {
        let response = ILMessageFilterCapabilitiesQueryResponse()
        response.transactionalSubActions = [
            .transactionalOrders,
            .transactionalFinance,
            .transactionalPublicServices,
            .transactionalReminders,
            .transactionalHealth,
            .transactionalWeather,
            .transactionalCarrier,
            .transactionalRewards,
            .transactionalOthers
        ]
        response.promotionalSubActions = [
            .promotionalOffers,
            .promotionalCoupons,
            .promotionalOthers
        ]
        completion(response)
    }

    // MARK: - 短信过滤实时判定（零网络延迟，<1ms 极速本地反查）
    func handle(
        _ queryRequest: ILMessageFilterQueryRequest,
        context: ILMessageFilterExtensionContext,
        completion: @escaping (ILMessageFilterQueryResponse) -> Void
    ) {
        let (offlineAction, offlineSubAction) = self.offlineAction(for: queryRequest)

        let response = ILMessageFilterQueryResponse()
        response.action = offlineAction
        response.subAction = offlineSubAction
        completion(response)
    }

    // MARK: - 本地 SQLite 极速反查决策
    private func offlineAction(for queryRequest: ILMessageFilterQueryRequest) -> (ILMessageFilterAction, ILMessageFilterSubAction) {
        guard let rawSender = queryRequest.sender?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawSender.isEmpty else {
            return (.none, .none)
        }

        guard let dbURL = getDatabaseURL() else {
            return (.none, .none)
        }

        let digits = rawSender.filter { $0.isNumber }
        guard !digits.isEmpty else { return (.none, .none) }

        let normalizedE164 = normalizeToE164(raw: rawSender) ?? 0
        let directNumber = Int64(digits) ?? 0

        var db: OpaquePointer?
        let uri = "file:\(dbURL.path)?immutable=1"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK,
              let db = db else {
            return (.none, .none)
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT sms_action, sms_sub_action, is_deleted
        FROM phone_directory
        WHERE numeric_phone = ? OR numeric_phone = ?
        LIMIT 1;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return (.none, .none)
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, normalizedE164)
        sqlite3_bind_int64(stmt, 2, directNumber)

        if sqlite3_step(stmt) == SQLITE_ROW {
            let isDeleted = sqlite3_column_int(stmt, 2)
            if isDeleted == 1 {
                return (.none, .none)
            }

            let smsActionCode = Int(sqlite3_column_int(stmt, 0))
            let smsSubActionCode = Int(sqlite3_column_int(stmt, 1))

            let action = mapAction(smsActionCode)
            let subAction = mapSubAction(smsSubActionCode)

            return (action, subAction)
        }

        // 遵循如无把握绝不误杀原则，未收录发件人直接放行
        return (.none, .none)
    }

    // MARK: - 辅助映射与数据库寻址

    private func mapAction(_ code: Int) -> ILMessageFilterAction {
        switch code {
        case 1:
            return .allow
        case 2:
            return .junk
        case 3:
            return .promotion
        case 4:
            return .transaction
        default:
            return .none
        }
    }

    private func mapSubAction(_ code: Int) -> ILMessageFilterSubAction {
        switch code {
        case 10000:
            return .transactionalOthers
        case 10001:
            return .transactionalFinance
        case 10002:
            return .transactionalOrders
        case 10003:
            return .transactionalReminders
        case 10004:
            return .transactionalHealth
        case 10005:
            return .transactionalWeather
        case 10006:
            return .transactionalCarrier
        case 10007:
            return .transactionalRewards
        case 10008:
            return .transactionalPublicServices
        case 20000:
            return .promotionalOthers
        case 20001:
            return .promotionalOffers
        case 20002:
            return .promotionalCoupons
        default:
            return .none
        }
    }

    private func normalizeToE164(raw: String) -> Int64? {
        let digits = raw.filter { $0.isNumber }
        guard !digits.isEmpty else { return nil }

        if digits.hasPrefix("86") {
            return Int64(digits)
        }
        if digits.count == 11, digits.hasPrefix("1") {
            return Int64("86" + digits)
        }
        if digits.hasPrefix("0") && digits.count >= 10 {
            return Int64("86" + digits.dropFirst())
        }
        if digits.hasPrefix("400") || digits.hasPrefix("800") {
            return Int64("86" + digits)
        }
        return Int64("86" + digits) ?? Int64(digits)
    }

    private func getDatabaseURL() -> URL? {
        let appGroupID = "group.cn.xizicl.YellowPages"
        let databaseFilename = "yellowpages_directory.sqlite"

        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            let fileURL = containerURL.appendingPathComponent(databaseFilename)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return fileURL
            }
        }

        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("YellowPagesSharedGroup")
        let fallbackURL = dir.appendingPathComponent(databaseFilename)
        if FileManager.default.fileExists(atPath: fallbackURL.path) {
            return fallbackURL
        }
        return nil
    }
}
