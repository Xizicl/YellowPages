import SwiftUI

/// 举报扩展分类模型（严格物理区分：电话 8 核心+1自定义 vs 短信 10 苹果原生细分+1自定义）
enum ExtensionCategory: String, CaseIterable, Identifiable {
    // 电话专属 (8 核心 + 1 自定义)
    case delivery = "delivery"
    case official = "official"
    case enterprise = "enterprise"
    case realEstate = "real_estate"
    case financeLoan = "finance_loan"
    case marketing = "marketing"
    case harassment = "harassment"
    case fraud = "fraud"

    // 短信专属 (10 细分 + 1 自定义)
    case smsJunk = "junk"
    case smsAllow = "allow"
    case smsOffers = "offers"
    case smsCoupons = "coupons"
    case smsPromotionOthers = "promotion_others"
    case smsOrders = "orders"
    case smsFinance = "finance"
    case smsPublicServices = "public_services"
    case smsReminders = "reminders"

    // 自定义
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .delivery: return "快递外卖"
        case .official: return "官方政企"
        case .enterprise: return "机构服务"
        case .realEstate: return "房产中介"
        case .financeLoan: return "贷款理财"
        case .marketing: return "广告推销"
        case .harassment: return "恶意骚扰"
        case .fraud: return "疑似诈骗"
        case .smsJunk: return "垃圾拦截"
        case .smsAllow: return "验证码放行"
        case .smsOffers: return "优惠营销"
        case .smsCoupons: return "打折卡券"
        case .smsPromotionOthers: return "其他推广"
        case .smsOrders: return "订单与物流"
        case .smsFinance: return "金融银行"
        case .smsPublicServices: return "公共政务"
        case .smsReminders: return "行程预订"
        case .custom: return "自定义标记"
        }
    }

    var groupSubtitle: String {
        switch self {
        case .delivery, .official, .enterprise: return "身份识别"
        case .realEstate, .financeLoan, .marketing: return "默认识别"
        case .harassment, .fraud: return "强力拦截"
        case .smsJunk: return "垃圾拦截"
        case .smsAllow: return "主收件箱"
        case .smsOffers, .smsCoupons, .smsPromotionOthers: return "商业推广"
        case .smsOrders, .smsFinance, .smsPublicServices, .smsReminders: return "交易服务"
        case .custom: return "自主定义"
        }
    }

    var systemImage: String {
        switch self {
        case .delivery: return "box.truck.fill"
        case .official: return "building.columns.fill"
        case .enterprise: return "briefcase.fill"
        case .realEstate: return "house.fill"
        case .financeLoan: return "yensign.circle.fill"
        case .marketing: return "megaphone.fill"
        case .harassment: return "phone.down.waves.left.and.right"
        case .fraud: return "shield.slash.fill"
        case .smsJunk: return "shield.slash.fill"
        case .smsAllow: return "checkmark.shield.fill"
        case .smsOffers: return "tag.fill"
        case .smsCoupons: return "ticket.fill"
        case .smsPromotionOthers: return "megaphone.fill"
        case .smsOrders: return "shippingbox.fill"
        case .smsFinance: return "creditcard.fill"
        case .smsPublicServices: return "building.columns.fill"
        case .smsReminders: return "calendar.badge.clock"
        case .custom: return "slider.horizontal.3"
        }
    }

    var isRisk: Bool {
        switch self {
        case .realEstate, .financeLoan, .marketing, .harassment, .fraud,
             .smsJunk, .smsOffers, .smsCoupons, .smsPromotionOthers:
            return true
        default:
            return false
        }
    }

    static var callCategories: [ExtensionCategory] {
        [.delivery, .official, .enterprise, .realEstate, .financeLoan, .marketing, .harassment, .fraud, .custom]
    }

    static var smsCategories: [ExtensionCategory] {
        [.smsJunk, .smsAllow, .smsOffers, .smsCoupons, .smsPromotionOthers, .smsOrders, .smsFinance, .smsPublicServices, .smsReminders, .custom]
    }
}

/// 系统垃圾通讯举报扩展原生交互界面
struct ReportExtensionView: View {
    let rawSender: String
    let channel: String
    let snippet: String?
    let reportedDate: Date

    var onStateChanged: (ExtensionCategory, String?, Bool) -> Void

    @State private var selectedCategory: ExtensionCategory = .harassment
    @State private var customTag: String = ""
    @State private var alsoAddToBlacklist: Bool = true

    private var channelDisplayName: String {
        channel == "sms" ? "垃圾短信" : "骚扰来电"
    }

    private var formattedDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: reportedDate)
    }

    private var displayedCategories: [ExtensionCategory] {
        channel == "sms" ? ExtensionCategory.smsCategories : ExtensionCategory.callCategories
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // 头部被标记通讯主体卡片
                targetCommunicationCard

                // 核心分类点选（根据 channel 渲染分类矩阵）
                categorySelectionCard

                // 补充说明与防护选项
                optionsCard

                // 底部指引提示（系统原生「✓」为唯一完成入口，绝不产生白屏）
                actionGuideSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .onAppear {
            if channel == "sms" {
                selectedCategory = .smsJunk
            } else {
                selectedCategory = .harassment
            }
            alsoAddToBlacklist = selectedCategory.isRisk
            notifyStateChange()
        }
    }

    private func notifyStateChange() {
        let tag = customTag.trimmingCharacters(in: .whitespacesAndNewlines)
        onStateChanged(selectedCategory, tag.isEmpty ? nil : tag, alsoAddToBlacklist)
    }

    // MARK: - 目标通讯摘要卡片
    private var targetCommunicationCard: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: channel == "sms" ? "message.badge.filled.fill" : "phone.down.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.red)
            }

            VStack(spacing: 3) {
                Text(rawSender)
                    .font(.system(.title3, design: .monospaced).weight(.bold))
                    .foregroundColor(.primary)

                HStack(spacing: 6) {
                    Text(channel == "sms" ? "为此短信添加标记" : "为此来电添加标记")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.primary)

                    Text(formattedDateString)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
            }

            if let snippet = snippet, !snippet.isEmpty {
                Text(snippet)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(UIColor.tertiarySystemGroupedBackground))
                    .cornerRadius(8)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }

    // MARK: - 分类点选网格
    private var categorySelectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(channel == "sms" ? "选择短信标记分类" : "选择来电标记分类")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text(channel == "sms" ? "苹果原生分类规则" : "CallKit 原生防护")
                    .font(.system(size: 10))
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(displayedCategories.filter { $0 != .custom }) { cat in
                    categoryButton(cat: cat)
                }
            }

            if let customCat = displayedCategories.first(where: { $0 == .custom }) {
                categoryButton(cat: customCat)
            }
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }

    private func categoryButton(cat: ExtensionCategory) -> some View {
        let isSelected = selectedCategory == cat
        return Button(action: {
            selectedCategory = cat
            alsoAddToBlacklist = cat.isRisk
            notifyStateChange()
        }) {
            HStack(spacing: 6) {
                Image(systemName: cat.systemImage)
                    .font(.system(size: 12))
                VStack(alignment: .leading, spacing: 1) {
                    Text(cat.displayName)
                        .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    Text(cat.groupSubtitle)
                        .font(.system(size: 9))
                        .opacity(isSelected ? 0.9 : 0.65)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .foregroundColor(isSelected ? .white : (cat.isRisk ? .red : .primary))
            .background(isSelected ? (cat.isRisk ? Color.red : Color.accentColor) : Color(UIColor.tertiarySystemGroupedBackground))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 选项卡片
    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "tag.fill")
                    .foregroundColor(selectedCategory == .custom ? .accentColor : .secondary)
                    .font(.caption)
                TextField(
                    selectedCategory == .custom
                        ? (channel == "sms" ? "自定义短信规则名称与关键词 (必填)" : "自定义来电标签名称 (必填)")
                        : (channel == "sms" ? "发件机构或补充说明（可选）" : "自定义备注标签（可选，如：中介推销）"),
                    text: $customTag
                )
                .font(.caption)
                .onChange(of: customTag) { _, _ in
                    notifyStateChange()
                }
            }
            .padding(10)
            .background(Color(UIColor.tertiarySystemGroupedBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selectedCategory == .custom ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
            )
            .cornerRadius(8)

            Toggle(isOn: $alsoAddToBlacklist) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel == "sms" ? "同时加入本地短信垃圾箱" : "同时加入本地拦截黑名单")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Text(channel == "sms" ? "后续该发件人再次发送将由系统彻底静默拦截" : "后续此号码再次呼入将由系统底层静默挂断")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: .red))
            .padding(.vertical, 2)
            .onChange(of: alsoAddToBlacklist) { _, _ in
                notifyStateChange()
            }
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }

    // MARK: - 底部操作指引卡片（对接系统原生「✓」为唯一完成入口，绝无白屏）
    private var actionGuideSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.green)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("请点击右上角「✓」完成标记并保存")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                    Text(alsoAddToBlacklist ? "系统将写入本地黑名单，来电直接底层静默挂断拒接" : "系统将添加此号码识别标记，并即时刷新通话记录")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
            )

            Text("标记记录将写入本地离线规则库，并在网络恢复时参与云端同步。")
                .font(.system(size: 10))
                .foregroundColor(Color(UIColor.tertiaryLabel))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }
}
