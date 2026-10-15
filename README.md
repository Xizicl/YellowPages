# YellowPages

License: MIT

基于苹果原生 CallKit 与 IdentityLookup 框架，提供来电号码识别、骚扰电话拦截、短信智能分流与原生就地标记的纯原生 iOS App 与配套同步服务。

## 功能特性

- **来电识别与展示**：基于 CallKit（`CXCallDirectoryProvider`）实现，官方客服、快递外卖、政企机构来电时在系统来电界面原生显示名称。
- **骚扰电话强力拦截**：毫秒级自动挂断高频骚扰、诈骗、推销、中介及贷款电话，不打扰日常使用。
- **短信智能实时分流**：基于 IdentityLookup（`ILMessageFilterExtension`），短信到达基带瞬间在本地完成毫秒级匹配，自动归档至系统「交易信息」（订单物流/金融还款/公共服务/提醒/运营商）、「推广信息」或「垃圾短信」。
- **系统原生左滑标记**：基于 IdentityLookupUI（`ILClassificationUIExtensionViewController`），在系统「通话记录」或「信息」列表左滑点击「报告」，即可拉起半屏原生抽屉就地标记并实时生效。
- **纯原生 C-API 存储引擎**：剥离任何第三方 ORM，直接使用原生 SQLite3 C-API 配合 WAL 模式，内存峰值控制在 8MB 内，严格满足系统扩展 15MB 内存红线。
- **零通讯录权限与离线优先**：不需要读取用户通讯录（零 Contacts 权限），匹配与规则决策 100% 运行于本地沙盒，断网亦可秒级识别。
- **增量差量同步（Delta Sync）**：配套 Python FastAPI 独立服务端，支持单调递增时间戳版本控制、全量快照与增量补丁同步。
- **防刷风控与设备信誉**：服务端内置设备信誉评分模型与衰减半衰期算法，防范恶意批量标记。
- **本地快照与备份还原**：App 内支持一键创建 SQLite 数据快照，支持随时回滚历史版本与分享备份文件。
- **Web 管理控制台**：配套轻量 Vue 3 管理后台，支持号码全量/增量检索、一键 CSV 与 vCard 格式导入导出。

## 原理

YellowPages 严格遵循苹果原生扩展管道与沙盒安全机制实现：

1. **号码注入**：主 App 准备好号码库后，触发 `CXCallDirectoryManager.reloadExtension`。扩展通过只读连接打开 App Group 共享的 SQLite 文件，以单调递增纯数字（E.164 规范）升序流式调用 `addIdentificationEntry` 与 `addBlockingEntry` 写入 iOS 内核。
2. **短信判定**：短信到达时，系统异步询问 `MessageFilterExtension`，扩展读取共享数据库的 `sms_action` 与关键词分类，直接返回系统原生二级子动作代码（`ILMessageFilterSubAction`），全程零网络延迟。
3. **就地标记**：在原生通话记录触发报告时，`ReportExtensionView` 获取系统传入的号码，写入 `pending_reports` 表与用户自定义标记表，并触发 CallKit 后台热重载。
4. **单一事实源（SSOT）**：主 App 与三个扩展通过 App Group（`group.cn.xizicl.YellowPages`）共享唯一的 `yellowpages_directory.sqlite` 数据库，开启 `PRAGMA journal_mode = WAL;` 与 `SQLITE_OPEN_FULLMUTEX` 保障跨进程并发读写安全。

## 数据分类与系统映射

| 业务分类 | CallKit 动作 | SMSFilter 映射子分类 | 典型场景 |
| :--- | :--- | :--- | :--- |
| **快递外卖 (delivery)** | 识别展示 | transactionalOrders (订单物流) | 顺丰、京东、美团、饿了么等 |
| **官方政企 (official)** | 识别展示 | transactionalPublicServices (公共服务) | 110、12345、政务热线、税务等 |
| **机构服务 (enterprise)** | 识别展示 | transactionalFinance / Carrier (金融运营商) | 银行客服、航空、三家运营商等 |
| **房产中介 (real_estate)** | 阻止拦截 / 识别 | promotionalOffers (商业推广) / junk | 房产经纪、商铺租赁等 |
| **贷款理财 (finance_loan)** | 阻止拦截 / 识别 | promotionalOffers (商业推广) / junk | 抵押贷款、网贷推销等 |
| **广告推销 (marketing)** | 阻止拦截 / 识别 | promotionalOthers / junk | 装修设计、课程培训等推广 |
| **恶意骚扰 (harassment)** | 阻止拦截 | junk (垃圾信息) | 催收骚扰、响一声来电等 |
| **疑似诈骗 (fraud)** | 阻止拦截 | junk (垃圾信息) | 冒充公检法、刷单返利等 |
| **自定义标记 (custom)** | 用户自选 | 用户自定义规则 | 用户在 App 内或原生抽屉手动标记 |

## 目录结构

```text
YellowPages/
├── YellowPages/                # 主 App 宿主工程 (SwiftUI 原生架构)
│   ├── MyApp.swift             # App 入口
│   ├── Services/               # 核心服务 (CallKit 管理器、增量同步服务、举报管理服务)
│   ├── Shared/Models/          # 跨组件共享数据模型契约 (号码实体、同步 DTO)
│   ├── Shared/Storage/         # 存储层 (DirectoryStore 原生 SQLite3 C-API 封装、AppGroup 配置)
│   ├── ViewModels/             # MainViewModel 响应式状态流
│   └── Views/                  # 原生视图 (仪表盘、快速查号、标记、设置与备份还原)
│
├── CallDirectoryExtension/     # 扩展 1：CallKit 来电识别与号码拦截插件
├── SMSFilterExtension/         # 扩展 2：IdentityLookup 短信智能分流插件
├── ReportExtension/            # 扩展 3：IdentityLookupUI 通话/短信原生就地标记抽屉
│
├── server/                     # 配套独立同步后端工程
│   ├── app/                    # FastAPI 路由、数据模型定义、版本管理与风控
│   ├── scripts/                # 权威官方名片清洗导入脚本
│   └── web/                    # Vue 3 + Vite 轻量管理控制台
│
├── data/vCards/                # 初始内置官方机构名片数据源
└── docs/                       # 系统架构、数据库模式设计与接口契约文档
```

## 前置条件

- **macOS 27.0+**
- **Xcode 27.0+**（推荐部署目标 iOS 27.0+）
- **Python 3.14+** 与 [uv](https://github.com/astral-sh/uv)（若需运行后端服务）
- **Node.js 22+**（若需编译 Web 控制台）
- 真机调试 CallKit 与 App Group 建议使用付费 Apple 开发者账号

## 构建与运行

### 1. iOS 工程构建

在 Xcode 27.0+ 中打开 `YellowPages.xcodeproj`：

1. 确认 4 个 Target（`YellowPages`、`CallDirectoryExtension`、`SMSFilterExtension`、`ReportExtension`）已正确选择开发团队签名；
2. 确认 4 个 Target 在 `Signing & Capabilities` 中均已勾选并对齐相同的 App Group 标识符（默认为 `group.cn.xizicl.YellowPages`）；
3. 选择 `YellowPages` Scheme，直接编译运行到模拟器或真机。

### 2. 同步后端运行（可选）

```bash
cd server

# 使用 uv 安装依赖并启动服务（默认监听 8080 端口）
uv run uvicorn app.main:app --host 0.0.0.0 --port 8080 --reload
```

启动后可在浏览器访问 `http://localhost:8080` 体验 Web 管理面板。

## 使用说明

1. 首次打开 App，在系统弹窗中允许必要的通知权限；
2. 进入 iOS 系统「设置」→「电话」→「通话阻止与身份识别」，开启「YellowPages」开关；
3. 进入 iOS 系统「设置」→「信息」→「未知与垃圾信息」，在短信过滤项中选择「YellowPages」；
4. 返回 App 主界面，可在「防护中枢」查看当前已载入的号码总数及拦截/识别规则分布；
5. 在「快速查号」中可随时离线检索任意陌生号码，支持快速添加到个人白名单或拦截库；
6. 当接到未识别的陌生电话后，在系统通话记录向左滑动选择「报告」，即可拉起半屏抽屉快速标记。

## 注意事项

- **技术方向**：本项目遵循纯原生、干净极简的开发原则，不引入任何冗余第三方 SDK，存储层直接使用原生 C-API，杜绝臃肿与过时规范。
- **内存看门狗限制**：系统扩展受 iOS 15MB 严苛内存限制。本工程在数据库层使用单步预编译游标流式遍历（Streaming Cursor），严禁在扩展中把全量数组拉入内存，实测运行内存维持在 6~8MB 左右。
- **号码数值严格升序**：CallKit 内核强制要求传入的 E.164 格式号码必须为正整数且严格单调递增，本工程已在底层 SQL 注入时强行追加 `ORDER BY numeric_phone ASC`，修改逻辑时切勿破坏此约束。
- **iOS 18 Live Caller ID 说明**：本项目目前未接入 iOS 18 新增的 Live Caller ID 实时网络查号机制，坚持优先保障完全本地离线、零延迟与无网络隐私风险。
- **真机运行权限说明**：免费个人 Apple ID 签名的系统扩展在真机上受限于 7 天有效期与部分 App Group 策略，建议配合付费开发者账号使用以获得完整持久体验。

## 鸣谢与数据源

本项目初始整理内置的公共机构号码数据，来源于开源项目：
- [metowolf/vCards](https://github.com/metowolf/vCards)

非常感谢原作者 [@metowolf](https://github.com/metowolf) 为中文开源生态所做的优质整理！

## 许可证

本项目以 [MIT License](LICENSE) 开源。
