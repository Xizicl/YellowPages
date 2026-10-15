import Foundation
import CallKit

/// 号码处理动作类型
nonisolated public enum EntryAction: String, Sendable, CaseIterable {
    /// 识别并展示标签
    case identify = "identification"
    /// 彻底拦截（黑名单）
    case block = "blocking"
    
    public var displayName: String {
        switch self {
        case .identify:
            return "识别展示"
        case .block:
            return "阻止拦截"
        }
    }
}

nonisolated extension EntryAction: Codable {}

/// 电话业务分类（8 大核心分类 + 1 自定义标记）
nonisolated public enum CallCategory: String, Sendable, CaseIterable {
    // MARK: - 显示类 (3个，addIdentificationEntry)
    case delivery = "delivery"                          // 快递外卖
    case official = "official"                          // 官方政企
    case enterprise = "enterprise"                      // 机构服务

    // MARK: - 拦截类 (5个，默认识别可设拦截 或 强力拦截)
    case realEstate = "real_estate"                     // 房产中介
    case financeLoan = "finance_loan"                   // 贷款理财
    case marketing = "marketing"                        // 广告推销
    case harassment = "harassment"                      // 恶意骚扰
    case fraud = "fraud"                                // 疑似诈骗

    // MARK: - 用户自主标记 (1个)
    case custom = "custom"                              // 自定义标记

    public var displayName: String {
        switch self {
        case .delivery: return "快递外卖"
        case .official: return "官方政企"
        case .enterprise: return "机构服务"
        case .realEstate: return "房产中介"
        case .financeLoan: return "贷款理财"
        case .marketing: return "广告推销"
        case .harassment: return "恶意骚扰"
        case .fraud: return "疑似诈骗"
        case .custom: return "自定义标记"
        }
    }

    /// 所属业务大类：“显示类”、“拦截类” 与 “自定义”
    public var groupName: String {
        switch self {
        case .delivery, .official, .enterprise:
            return "显示类"
        case .realEstate, .financeLoan, .marketing, .harassment, .fraud:
            return "拦截类"
        case .custom:
            return "自定义"
        }
    }
    
    public var systemImageName: String {
        switch self {
        case .delivery: return "box.truck.fill"
        case .official: return "building.columns.fill"
        case .enterprise: return "briefcase.fill"
        case .realEstate: return "house.fill"
        case .financeLoan: return "yensign.circle.fill"
        case .marketing: return "megaphone.fill"
        case .harassment: return "phone.down.waves.left.and.right"
        case .fraud: return "shield.slash.fill"
        case .custom: return "tag.fill"
        }
    }
    
    public var isRisk: Bool {
        switch self {
        case .realEstate, .financeLoan, .marketing, .harassment, .fraud:
            return true
        default:
            return false
        }
    }

    /// 该分类在电话系统 (CallKit) 下的默认处置行为
    public var callKitDefaultAction: EntryAction {
        switch self {
        case .harassment, .fraud:
            return .block
        case .delivery, .official, .enterprise, .realEstate, .financeLoan, .marketing, .custom:
            return .identify
        }
    }
}

nonisolated extension CallCategory: Codable {}

public typealias NumberCategory = CallCategory

/// 短信业务分类
nonisolated public enum SMSCategory: String, Sendable, CaseIterable, Identifiable {
    // MARK: - 商业推广类 (Action: 3)
    case offers = "offers"                              // 商业优惠与营销 (20001)
    case coupons = "coupons"                            // 打折卡券与折扣 (20002)
    case promotionOthers = "promotion_others"           // 其他商业推广 (20000)

    // MARK: - 交易与服务类 (Action: 4)
    case orders = "orders"                              // 订单与物流 (10002)
    case finance = "finance"                            // 金融银行服务 (10001)
    case publicServices = "public_services"              // 公共政务便民服务 (10008)
    case reminders = "reminders"                        // 行程与预订 (10003)
    case health = "health"                              // 医疗健康通知 (10004)
    case weather = "weather"                            // 气象灾害预警 (10005)
    case carrier = "carrier"                            // 运营商官方业务 (10006)
    case rewards = "rewards"                            // 积分与会员奖励 (10007)
    case transactionOthers = "transaction_others"       // 其他交易通知 (10000)

    // MARK: - 拦截与强放行类
    case junk = "junk"                                  // 垃圾与高危拦截 (Action: 2)
    case allow = "allow"                                // 强放行/验证码 (Action: 1)
    case none = "none"                                  // 默认放行 (Action: 0)

    // MARK: - 自定义规则
    case custom = "custom"                              // 自定义规则

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .offers: return "商业优惠与营销"
        case .coupons: return "打折卡券与折扣"
        case .promotionOthers: return "其他商业推广"
        case .orders: return "订单与物流"
        case .finance: return "金融银行服务"
        case .publicServices: return "公共政务服务"
        case .reminders: return "行程与预订"
        case .health: return "医疗健康通知"
        case .weather: return "气象灾害预警"
        case .carrier: return "运营商官方业务"
        case .rewards: return "积分与会员奖励"
        case .transactionOthers: return "其他交易通知"
        case .junk: return "垃圾拦截"
        case .allow: return "验证码放行"
        case .none: return "普通放行"
        case .custom: return "自定义规则"
        }
    }

    public var fullActionTitle: String {
        switch self {
        case .offers: return "推广信息 · 商业优惠与营销 (20001)"
        case .coupons: return "推广信息 · 优惠券与折扣 (20002)"
        case .promotionOthers: return "推广信息 · 其他商业推广 (20000)"
        case .orders: return "交易信息 · 订单与物流配送 (10002)"
        case .finance: return "交易信息 · 金融银行服务 (10001)"
        case .publicServices: return "交易信息 · 公共政务便民服务 (10008)"
        case .reminders: return "交易信息 · 行程与预订通知 (10003)"
        case .health: return "交易信息 · 医疗健康就诊通知 (10004)"
        case .weather: return "交易信息 · 气象灾害预警信号 (10005)"
        case .carrier: return "交易信息 · 运营商官方业务通知 (10006)"
        case .rewards: return "交易信息 · 积分与会员权益奖励 (10007)"
        case .transactionOthers: return "交易信息 · 其他交易通知 (10000)"
        case .junk: return "垃圾短信 · 强力拦截并静默归档 (2)"
        case .allow: return "普通收件箱 · 动态口令强放行 (1)"
        case .none: return "普通主收件箱 · 默认放行 (0)"
        case .custom: return "自定义规则 · 用户自主匹配"
        }
    }

    public var groupName: String {
        switch self {
        case .offers, .coupons, .promotionOthers:
            return "商业推广"
        case .orders, .finance, .publicServices, .reminders, .health, .weather, .carrier, .rewards, .transactionOthers:
            return "交易与服务"
        case .junk:
            return "垃圾拦截"
        case .allow:
            return "验证码放行"
        case .none:
            return "普通放行"
        case .custom:
            return "自定义"
        }
    }

    public var systemImageName: String {
        switch self {
        case .offers: return "tag.fill"
        case .coupons: return "ticket.fill"
        case .promotionOthers: return "megaphone.fill"
        case .orders: return "shippingbox.fill"
        case .finance: return "creditcard.fill"
        case .publicServices: return "building.columns.fill"
        case .reminders: return "calendar.badge.clock"
        case .health: return "cross.case.fill"
        case .weather: return "cloud.bolt.rain.fill"
        case .carrier: return "antenna.radiowaves.left.and.right"
        case .rewards: return "star.circle.fill"
        case .transactionOthers: return "doc.text.fill"
        case .junk: return "shield.slash.fill"
        case .allow: return "checkmark.shield.fill"
        case .none: return "bubble.left.and.bubble.right.fill"
        case .custom: return "slider.horizontal.3"
        }
    }

    public var isRisk: Bool {
        switch self {
        case .junk, .offers, .coupons, .promotionOthers:
            return true
        default:
            return false
        }
    }

    public var actionCode: Int {
        switch self {
        case .none: return 0
        case .allow: return 1
        case .junk: return 2
        case .offers, .coupons, .promotionOthers: return 3
        case .orders, .finance, .publicServices, .reminders, .health, .weather, .carrier, .rewards, .transactionOthers: return 4
        case .custom: return 0
        }
    }

    public var subActionCode: Int {
        switch self {
        case .orders: return 10002
        case .finance: return 10001
        case .publicServices: return 10008
        case .reminders: return 10003
        case .health: return 10004
        case .weather: return 10005
        case .carrier: return 10006
        case .rewards: return 10007
        case .transactionOthers: return 10000
        case .offers: return 20001
        case .coupons: return 20002
        case .promotionOthers: return 20000
        default: return 0
        }
    }

    /// 映射回对应相近的电话业务大类
    public var asCallCategory: CallCategory {
        switch self {
        case .orders: return .delivery
        case .publicServices: return .official
        case .finance, .reminders, .health, .weather, .carrier, .rewards, .transactionOthers: return .enterprise
        case .promotionOthers: return .realEstate
        case .offers, .coupons: return .marketing
        case .junk: return .harassment
        case .allow: return .official
        case .none: return .official
        case .custom: return .custom
        }
    }
}

nonisolated extension SMSCategory: Codable {}

/// 苹果官方短信一级过滤动作 (Action 0~4 + 自定义)
nonisolated public enum SMSPrimaryAction: String, Sendable, CaseIterable, Identifiable {
    case junk = "junk"                  // 垃圾与高危拦截 (Action: 2 / Junk)
    case allow = "allow"                // 强放行 / 验证码 (Action: 1 / Allow)
    case promotion = "promotion"        // 商业推广信息 (Action: 3 / Promotion)
    case transaction = "transaction"    // 交易与服务信息 (Action: 4 / Transaction)
    case none = "none"                  // 默认放行 / 个人沟通 (Action: 0 / None)
    case custom = "custom"              // 自定义规则 (Custom)

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .junk: return "垃圾与高危拦截"
        case .allow: return "强放行 / 验证码"
        case .promotion: return "商业推广信息"
        case .transaction: return "交易与服务信息"
        case .none: return "默认放行 / 沟通"
        case .custom: return "自定义短信规则"
        }
    }

    public var officialName: String {
        switch self {
        case .junk: return "Junk (2)"
        case .allow: return "Allow (1)"
        case .promotion: return "Promotion (3)"
        case .transaction: return "Transaction (4)"
        case .none: return "None (0)"
        case .custom: return "Custom (0)"
        }
    }

    public var systemImageName: String {
        switch self {
        case .junk: return "shield.slash.fill"
        case .allow: return "checkmark.shield.fill"
        case .promotion: return "megaphone.fill"
        case .transaction: return "tray.2.fill"
        case .none: return "bubble.left.and.bubble.right.fill"
        case .custom: return "slider.horizontal.3"
        }
    }

    public var actionCode: Int {
        switch self {
        case .none: return 0
        case .allow: return 1
        case .junk: return 2
        case .promotion: return 3
        case .transaction: return 4
        case .custom: return 0
        }
    }

    public var hasSubActions: Bool {
        self == .promotion || self == .transaction
    }

    public var subCategories: [SMSCategory] {
        switch self {
        case .promotion:
            return [.offers, .coupons, .promotionOthers]
        case .transaction:
            return [.orders, .finance, .publicServices, .reminders, .health, .weather, .carrier, .rewards, .transactionOthers]
        default:
            return []
        }
    }

    public var isRisk: Bool {
        self == .junk || self == .promotion
    }
}

nonisolated extension SMSPrimaryAction: Codable {}

/// 单条电话号码记录模型（精准对齐 10 核心物理字段单一大宽表模式）
nonisolated public struct PhoneNumberEntry: Identifiable, Equatable, Hashable, Sendable {
    public var id: Int64 { numericPhone }
    
    // MARK: - 10 核心物理字段
    public let numericPhone: Int64
    public let label: String
    public let callAction: Int               // 0: 识别, 1: 拦截
    public let callCategory: String          // delivery, official, enterprise, real_estate, finance_loan, marketing, harassment, fraud, custom
    public let smsAction: Int                // 0: None, 1: Allow, 2: Junk, 3: Promo, 4: Trans
    public let smsSubAction: Int             // 10001, 10002, 10008, 20000, 20001...
    public let confidence: Double            // 0.0 ~ 1.0
    public let isDeleted: Int                // 0 or 1
    public let updatedAt: Int64              // 毫秒时间戳
    public let createdAt: Int64              // 毫秒时间戳
    
    // MARK: - 便利计算属性
    public var phoneString: String { String(numericPhone) }
    public var isBlocking: Bool { callAction == 1 }
    public var category: CallCategory { CallCategory(rawValue: callCategory) ?? .custom }
    public var action: EntryAction { isBlocking ? .block : .identify }
    
    /// 传给系统 CallKit 的格式化标签：形如 `[快递外卖] 顺丰速运`
    public var formattedDisplayLabel: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[") {
            return trimmed
        }
        return "[\(category.displayName)] \(trimmed)"
    }
    
    public init(
        numericPhone: Int64,
        label: String,
        callAction: Int = 0,
        callCategory: String = "enterprise",
        smsAction: Int = 4,
        smsSubAction: Int = 0,
        confidence: Double = 1.0,
        isDeleted: Int = 0,
        updatedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.numericPhone = numericPhone
        self.label = label
        self.callAction = callAction
        self.callCategory = callCategory
        self.smsAction = smsAction
        self.smsSubAction = smsSubAction
        self.confidence = confidence
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
        self.createdAt = createdAt
    }

    /// 便利构造器
    public init(
        numericPhone: Int64,
        phoneString: String? = nil,
        label: String,
        category: CallCategory,
        action: EntryAction = .identify,
        confidence: Double = 1.0,
        isBlocking: Bool? = nil,
        updatedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        let blocking = isBlocking ?? (action == .block)
        let callAct = blocking ? 1 : 0
        let smsAct = blocking ? 2 : (category.isRisk ? 3 : 4)
        let smsSub = blocking ? 0 : (category == .delivery ? 10002 : (category == .official ? 10008 : 10001))
        
        self.init(
            numericPhone: numericPhone,
            label: label,
            callAction: callAct,
            callCategory: category.rawValue,
            smsAction: smsAct,
            smsSubAction: smsSub,
            confidence: confidence,
            isDeleted: 0,
            updatedAt: updatedAt,
            createdAt: updatedAt
        )
    }
}

nonisolated extension PhoneNumberEntry: Codable {
    enum CodingKeys: String, CodingKey {
        case numericPhone = "numeric_phone"
        case label
        case callAction = "call_action"
        case callCategory = "call_category"
        case smsAction = "sms_action"
        case smsSubAction = "sms_sub_action"
        case confidence
        case isDeleted = "is_deleted"
        case updatedAt = "updated_at"
        case createdAt = "created_at"
    }
}

nonisolated extension PhoneNumberEntry: Comparable {
    public static func < (lhs: PhoneNumberEntry, rhs: PhoneNumberEntry) -> Bool {
        lhs.numericPhone < rhs.numericPhone
    }
}
