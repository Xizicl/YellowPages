import os
import time
from typing import Optional
import aiosqlite
from pathlib import Path

# 数据库文件路径定位
BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BASE_DIR / "data"
DB_PATH = DATA_DIR / "yellowpages_server.sqlite"

def generate_time_version() -> int:
    """生成以时间为准的标准版本号格式 YYYYMMDDHHmm (如 202610131530)"""
    return int(time.strftime("%Y%m%d%H%M"))

# 默认算法与风控参数配置（默认 365 天稳妥长周期）
DEFAULT_ALGORITHM_CONFIG = {
    "decay_half_life_days": {
        "value": "365",
        "description": "社区标记时间衰减半衰期 (天，超过此时间置信度减半，避免陈旧误杀)",
    },
    "min_active_confidence": {
        "value": "0.85",
        "description": "收敛进入全量/增量离线识别库的最低置信度门限 (0.00 ~ 1.00)",
    },
    "min_block_confidence": {
        "value": "0.90",
        "description": "自动执行 CallKit 主动拦截 (Blocking) 的最高置信度门限 (0.00 ~ 1.00)",
    },
    "min_distinct_devices": {
        "value": "3",
        "description": "触发规则聚合并发最低独立上报设备指纹数 (防刷防作弊门限)",
    },
    "category_dominant_ratio": {
        "value": "0.70",
        "description": "单一分类多数裁定占比阈值 (例如诈骗标记占比需超过 70%)",
    },
    "dispute_penalty_factor": {
        "value": "0.50",
        "description": "号码处于纠错申诉争议期间的置信度抑制系数 (乘法抑制因子)",
    },
}

async def get_db():
    """获取数据库异步连接生成器"""
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        await db.execute("PRAGMA journal_mode = WAL;")
        await db.execute("PRAGMA synchronous = NORMAL;")
        yield db

async def init_db():
    """初始化数据库表结构、软删除模式与动态算法配置（纯净空白库，无任何假测试种子数据）"""
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    now = int(time.time() * 1000)
    time_version = generate_time_version()

    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        await db.execute("PRAGMA journal_mode = WAL;")
        await db.execute("PRAGMA synchronous = NORMAL;")

        # 1. 终极架构：单张高性能宽表 numbers_directory (10 核心物理字段单一事实源)
        # 彻底废除多余的三表拆分与冗余联查，支持零 JOIN 毫秒级极速反查与流式下发
        await db.execute("""
        CREATE TABLE IF NOT EXISTS numbers_directory (
            numeric_phone   INTEGER PRIMARY KEY,
            label           TEXT NOT NULL,
            call_action     INTEGER NOT NULL DEFAULT 0,
            call_category   TEXT NOT NULL,
            sms_action      INTEGER NOT NULL DEFAULT 4,
            sms_sub_action  INTEGER NOT NULL DEFAULT 0,
            confidence      REAL NOT NULL DEFAULT 1.0,
            is_deleted      INTEGER NOT NULL DEFAULT 0,
            updated_at      INTEGER NOT NULL,
            created_at      INTEGER NOT NULL
        );
        """)
        await db.execute("CREATE INDEX IF NOT EXISTS idx_numbers_deleted_phone ON numbers_directory(is_deleted, numeric_phone ASC);")
        await db.execute("CREATE INDEX IF NOT EXISTS idx_numbers_call_action ON numbers_directory(call_action, numeric_phone ASC);")
        await db.execute("CREATE INDEX IF NOT EXISTS idx_numbers_sms ON numbers_directory(sms_action, sms_sub_action);")

        # 2. 增量变更流水日志表 (对齐 10 核心物理字段)
        await db.execute("""
        CREATE TABLE IF NOT EXISTS numbers_delta_log (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            version         INTEGER NOT NULL,
            numeric_phone   INTEGER NOT NULL,
            op              TEXT NOT NULL,
            label           TEXT,
            call_action     INTEGER NOT NULL DEFAULT 0,
            call_category   TEXT,
            sms_action      INTEGER NOT NULL DEFAULT 4,
            sms_sub_action  INTEGER NOT NULL DEFAULT 0,
            updated_at      INTEGER NOT NULL
        );
        """)
        await db.execute("CREATE INDEX IF NOT EXISTS idx_delta_version ON numbers_delta_log(version, numeric_phone ASC);")

        # 3. 用户标记与来电/短信举报表
        await db.execute("""
        CREATE TABLE IF NOT EXISTS user_reports (
            id                  INTEGER PRIMARY KEY AUTOINCREMENT,
            numeric_phone       INTEGER NOT NULL,
            raw_phone           TEXT,
            channel             TEXT NOT NULL,
            category            TEXT NOT NULL,
            suggested_label     TEXT,
            content_snippet     TEXT,
            device_fingerprint  TEXT,
            client_timestamp    INTEGER,
            status              TEXT DEFAULT 'pending',
            created_at          INTEGER NOT NULL
        );
        """)
        await db.execute("CREATE INDEX IF NOT EXISTS idx_reports_phone ON user_reports(numeric_phone, created_at DESC);")
        await db.execute("CREATE INDEX IF NOT EXISTS idx_reports_device ON user_reports(device_fingerprint, numeric_phone);")

        # 4. 同步元数据表
        await db.execute("""
        CREATE TABLE IF NOT EXISTS sync_metadata (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """)

        # 5. 号码误标申诉表 (Number Appeals)
        await db.execute("""
        CREATE TABLE IF NOT EXISTS number_appeals (
            id                  INTEGER PRIMARY KEY AUTOINCREMENT,
            numeric_phone       INTEGER NOT NULL,
            raw_phone           TEXT,
            appeal_type         TEXT NOT NULL,
            reason              TEXT NOT NULL,
            contact_info        TEXT NOT NULL,
            contact_phone       TEXT,
            contact_email       TEXT,
            proof_snippet       TEXT,
            status              TEXT DEFAULT 'pending',
            review_notes        TEXT,
            created_at          INTEGER NOT NULL,
            reviewed_at         INTEGER
        );
        """)
        try:
            await db.execute("ALTER TABLE number_appeals ADD COLUMN contact_phone TEXT;")
        except Exception:
            pass
        try:
            await db.execute("ALTER TABLE number_appeals ADD COLUMN contact_email TEXT;")
        except Exception:
            pass
        await db.execute("CREATE INDEX IF NOT EXISTS idx_appeals_phone ON number_appeals(numeric_phone, created_at DESC);")
        await db.execute("CREATE INDEX IF NOT EXISTS idx_appeals_status ON number_appeals(status, created_at DESC);")

        # 6. 系统风控与置信度算法动态参数配置表
        await db.execute("""
        CREATE TABLE IF NOT EXISTS system_configs (
            key         TEXT PRIMARY KEY,
            value       TEXT NOT NULL,
            description TEXT,
            updated_at  INTEGER NOT NULL
        );
        """)

        # 7. 匿名设备信用与指纹管理表 (Device Profiles & Reputation)
        await db.execute("""
        CREATE TABLE IF NOT EXISTS device_profiles (
            device_fingerprint  TEXT PRIMARY KEY,
            device_name         TEXT,
            platform            TEXT DEFAULT 'iOS',
            reputation_score    REAL DEFAULT 100.0,
            credit_level        TEXT DEFAULT 'excellent',
            total_reports       INTEGER DEFAULT 0,
            approved_reports    INTEGER DEFAULT 0,
            rejected_reports    INTEGER DEFAULT 0,
            total_appeals       INTEGER DEFAULT 0,
            is_blocked          INTEGER DEFAULT 0,
            first_seen_at       INTEGER NOT NULL,
            last_active_at      INTEGER NOT NULL
        );
        """)
        await db.execute("CREATE INDEX IF NOT EXISTS idx_devices_active ON device_profiles(last_active_at DESC);")
        await db.execute("CREATE INDEX IF NOT EXISTS idx_devices_reputation ON device_profiles(reputation_score DESC);")

        for cfg_key, cfg_meta in DEFAULT_ALGORITHM_CONFIG.items():
            await db.execute("""
            INSERT OR IGNORE INTO system_configs (key, value, description, updated_at)
            VALUES (?, ?, ?, ?);
            """, (cfg_key, cfg_meta["value"], cfg_meta["description"], now))

        # 确保元数据中存在时间格式版本号
        async with db.execute("SELECT value FROM sync_metadata WHERE key = 'current_version'") as cursor:
            row = await cursor.fetchone()
            current_v = int(row["value"]) if row else 0

        if current_v < 202601010000:
            await db.execute("INSERT OR REPLACE INTO sync_metadata (key, value) VALUES ('current_version', ?);", (str(time_version),))
            await db.execute("INSERT OR REPLACE INTO sync_metadata (key, value) VALUES ('updated_at', ?);", (str(now),))

        await db.commit()

async def touch_device_profile(
    db: aiosqlite.Connection,
    device_fingerprint: str,
    platform: str = "iOS",
    device_name: Optional[str] = None,
    action: Optional[str] = None,  # None | 'report' | 'appeal' | 'approve' | 'reject'
) -> None:
    """自动注册或更新活跃设备的信用分与流水统计"""
    if not device_fingerprint:
        return
    now = int(time.time() * 1000)
    async with db.execute(
        "SELECT * FROM device_profiles WHERE device_fingerprint = ?",
        (device_fingerprint,),
    ) as cur:
        row = await cur.fetchone()

    if not row:
        name = device_name or f"iPhone ({device_fingerprint[:8]})"
        reports = 1 if action == "report" else 0
        appeals = 1 if action == "appeal" else 0
        await db.execute(
            """
            INSERT INTO device_profiles (
                device_fingerprint, device_name, platform, reputation_score, credit_level,
                total_reports, approved_reports, rejected_reports, total_appeals, is_blocked,
                first_seen_at, last_active_at
            ) VALUES (?, ?, ?, 100.0, 'excellent', ?, 0, 0, ?, 0, ?, ?);
            """,
            (device_fingerprint, name, platform, reports, appeals, now, now),
        )
    else:
        score = float(row["reputation_score"])
        tot_rep = int(row["total_reports"])
        app_rep = int(row["approved_reports"])
        rej_rep = int(row["rejected_reports"])
        tot_app = int(row["total_appeals"])

        if action == "report":
            tot_rep += 1
        elif action == "appeal":
            tot_app += 1
        elif action == "approve":
            app_rep += 1
            score = min(100.0, score + 2.0)
        elif action == "reject":
            rej_rep += 1
            score = max(0.0, score - 5.0)

        if score >= 90:
            level = "excellent"
        elif score >= 70:
            level = "good"
        elif score >= 50:
            level = "fair"
        else:
            level = "poor"

        await db.execute(
            """
            UPDATE device_profiles
            SET last_active_at = ?, reputation_score = ?, credit_level = ?,
                total_reports = ?, approved_reports = ?, rejected_reports = ?, total_appeals = ?
            WHERE device_fingerprint = ?;
            """,
            (now, score, level, tot_rep, app_rep, rej_rep, tot_app, device_fingerprint),
        )

