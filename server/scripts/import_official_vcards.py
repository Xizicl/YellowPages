#!/usr/bin/env python3
import os
import re
import sys
import time
import sqlite3
from pathlib import Path
from typing import Any
from collections import defaultdict
import yaml

# 定位路径
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
VCARDS_DATA_DIR = REPO_ROOT / "data" / "vCards" / "data"
DB_PATH = SCRIPT_DIR.parent / "data" / "yellowpages_server.sqlite"

# 19 个原始分类目录向 8 大核心标准分类的权威映射
CATEGORY_MAPPING = {
    "快递物流": "delivery",              # 快递外卖
    "外卖订餐": "delivery",              # 快递外卖
    "政府机构": "official",              # 官方政企
    "通讯服务": "official",              # 官方政企
    "金融银行": "enterprise",            # 机构服务
    "证券保险": "enterprise",            # 机构服务
    "民用航空": "enterprise",            # 机构服务
    "出行购票": "enterprise",            # 机构服务
    "房产中介": "real_estate",           # 房产中介
    # 其余官方机构与行业客服统一归入 enterprise (机构服务)
    "互联网": "enterprise",
    "汽车行业": "enterprise",
    "电商购物": "enterprise",
    "租车代驾": "enterprise",
    "影音娱乐": "enterprise",
    "应用软件": "enterprise",
    "酒店住宿": "enterprise",
    "本地生活": "enterprise",
    "云服务": "enterprise",
    "其它": "enterprise",
}

CATEGORY_NAMES = {
    "delivery": "快递外卖",
    "official": "官方政企",
    "enterprise": "机构服务",
    "real_estate": "房产中介",
    "finance_loan": "贷款理财",
    "marketing": "广告推销",
    "harassment": "恶意骚扰",
    "fraud": "疑似诈骗",
}

SMS_ACTION_MAP = {
    "delivery": (4, 10002, "订单与物流"),
    "official": (4, 10008, "公共政务服务"),
    "enterprise": (4, 10001, "金融银行服务"),
    "real_estate": (3, 20000, "其他商业推广"),
    "finance_loan": (3, 20001, "商业优惠与营销"),
    "marketing": (3, 20001, "商业优惠与营销"),
    "harassment": (2, 0, "垃圾短信拦截"),
    "fraud": (2, 0, "疑似诈骗"),
}

def infer_category(folder_name: str, label: str) -> str:
    """结合文件夹来源与标签语义推导最终核心分类"""
    base = CATEGORY_MAPPING.get(folder_name, "enterprise")
    lower_label = label.lower()

    if any(k in lower_label for k in ["诈骗", "假冒", "钓鱼", "刷单"]):
        return "fraud"
    if any(k in lower_label for k in ["骚扰", "响一声", "黑名单"]):
        return "harassment"
    if any(k in lower_label for k in ["房产", "中介", "置业", "地产", "链家", "安居客", "我爱我家", "贝壳"]):
        return "real_estate"
    if any(k in lower_label for k in ["贷款", "催收", "理财推销", "信贷", "小贷", "分期推销"]):
        return "finance_loan"
    if any(k in lower_label for k in ["推销", "营销", "推介", "广告"]):
        return "marketing"
    if any(k in lower_label for k in ["快递", "外卖", "速递", "物流", "闪送", "转运", "送餐"]):
        return "delivery"
    if any(k in lower_label for k in ["公安", "派出所", "交警", "市民热线", "12345", "政务", "法院", "检察", "应急", "电网", "水务", "燃气"]):
        return "official"

    return base

def to_e164_numeric(val: Any) -> tuple[int, str]:
    """
    转换为 E.164 纯数字及带国家区号展示格式
    未带国际区号按中国大陆补 +86，带 + 的保留原国际区号 (对齐 vCards 原工程)
    """
    s = str(val).strip()
    if s.startswith("+"):
        digits_only = re.sub(r"\D", "", s[1:])
        numeric = int(digits_only)
        display = f"+{digits_only}"
    else:
        raw_digits = re.sub(r"\D", "", s)
        # 若以 86 开头且长度长，避免重复 8686
        if raw_digits.startswith("86") and len(raw_digits) > 7:
            numeric = int(raw_digits)
            display = f"+{raw_digits}"
        else:
            numeric = int("86" + raw_digits)
            display = f"+86 {s}"
    return numeric, display

def run_import():
    print("=" * 60)
    print("🚀 开始导入权威官方中国常用电话黄页 (data/vCards/data)")
    print("=" * 60)

    if not VCARDS_DATA_DIR.exists():
        print(f"❌ 错误: 未找到 vCards 数据目录: {VCARDS_DATA_DIR}")
        sys.exit(1)

    now = int(time.time() * 1000)
    time_version = int(time.strftime("%Y%m%d%H%M"))

    yaml_files = list(VCARDS_DATA_DIR.glob("**/*.yaml"))
    print(f"📦 扫描到 YAML 配置文件共: {len(yaml_files)} 个")

    records_by_phone = {}
    stats_by_category = defaultdict(int)
    stats_by_folder = defaultdict(int)
    total_phone_extracted = 0

    for y_path in yaml_files:
        folder_name = y_path.parent.name
        standard_category = CATEGORY_MAPPING.get(folder_name, "custom")

        try:
            with open(y_path, "r", encoding="utf-8") as f:
                doc = yaml.safe_load(f)
        except Exception as e:
            print(f"⚠️ 解析失败: {y_path.name}: {e}")
            continue

        if not doc or not isinstance(doc, dict):
            continue

        basic = doc.get("basic", {})
        org = basic.get("organization", "").strip()
        if not org:
            org = y_path.stem

        cell_phones = basic.get("cellPhone", [])
        if not cell_phones:
            continue

        for item in cell_phones:
            sub_label = ""
            if isinstance(item, dict):
                raw_num = str(item.get("number", "")).strip()
                sub_label = str(item.get("label", "")).strip()
            else:
                raw_num = str(item).strip()

            if not raw_num:
                continue

            try:
                numeric_phone, raw_display = to_e164_numeric(raw_num)
            except Exception:
                continue

            total_phone_extracted += 1

            # 构造完整展示标签
            if sub_label:
                final_label = f"{org} ({sub_label})"
            else:
                final_label = org

            # 针对不收录的长号（如 106 开头超长短信通道码 > 11位）过滤
            digits_str = str(numeric_phone)
            if digits_str.startswith("86106") and len(digits_str) > 13:
                continue

            final_category = infer_category(folder_name, final_label)
            is_blocking = final_category in ["fraud", "harassment"]
            action = "block" if is_blocking else "identify"

            records_by_phone[numeric_phone] = {
                "numeric_phone": numeric_phone,
                "raw_phone": raw_num,
                "label": final_label,
                "category": final_category,
                "action": action,
                "is_blocking": is_blocking,
                "confidence": 1.0,
                "origin_folder": folder_name,
            }
            stats_by_category[final_category] += 1
            stats_by_folder[folder_name] += 1

    # 严格按照 numeric_phone ASC 升序排列
    sorted_records = sorted(records_by_phone.values(), key=lambda x: x["numeric_phone"])
    total_unique = len(sorted_records)

    print(f"📊 提取号码总行次: {total_phone_extracted}")
    print(f"✨ 去重后有效纯数字号码总数: {total_unique}")

    # 执行数据库写入事务
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA journal_mode = WAL;")
    conn.execute("PRAGMA synchronous = NORMAL;")

    with conn:
        # 1. 确保建表（单张高性能宽表 numbers_directory，10 核心物理字段单一事实源）
        try:
            conn.execute("DROP VIEW IF EXISTS numbers_directory;")
        except Exception:
            pass
        try:
            conn.execute("DROP TABLE IF EXISTS numbers_directory;")
        except Exception:
            pass
        try:
            conn.execute("DROP TABLE IF EXISTS phone_numbers;")
        except Exception:
            pass
        try:
            conn.execute("DROP TABLE IF EXISTS call_directory;")
        except Exception:
            pass
        try:
            conn.execute("DROP TABLE IF EXISTS sms_directory;")
        except Exception:
            pass
        try:
            conn.execute("DROP TABLE IF EXISTS numbers_delta_log;")
        except Exception:
            pass

        conn.execute("""
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
        conn.execute("CREATE INDEX IF NOT EXISTS idx_numbers_deleted_phone ON numbers_directory(is_deleted, numeric_phone ASC);")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_numbers_call_action ON numbers_directory(call_action, numeric_phone ASC);")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_numbers_sms ON numbers_directory(sms_action, sms_sub_action);")

        conn.execute("""
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
        conn.execute("CREATE INDEX IF NOT EXISTS idx_delta_version ON numbers_delta_log(version, numeric_phone ASC);")

        conn.execute("""
        CREATE TABLE IF NOT EXISTS sync_metadata (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """)

        # 2. 全量清空覆盖导入
        conn.execute("DELETE FROM numbers_directory;")
        conn.execute("DELETE FROM numbers_delta_log;")

        # 3. 升序批量插入宽表
        insert_sql = """
        INSERT INTO numbers_directory (
            numeric_phone, label, call_action, call_category, sms_action, sms_sub_action, confidence, is_deleted, updated_at, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?);
        """
        delta_sql = """
        INSERT INTO numbers_delta_log (
            version, numeric_phone, op, label, call_action, call_category, sms_action, sms_sub_action, updated_at
        ) VALUES (?, ?, 'add', ?, ?, ?, ?, ?, ?);
        """

        for item in sorted_records:
            cat = item["category"]
            cat_name = CATEGORY_NAMES.get(cat, "机构服务")
            formatted_display_label = f"[{cat_name}] {item['label']}"
            call_action = 1 if item["is_blocking"] else 0
            sms_act, sms_sub, rule_name = SMS_ACTION_MAP.get(cat, (4, 10001, "金融银行服务"))

            conn.execute(
                insert_sql,
                (
                    item["numeric_phone"],
                    formatted_display_label,
                    call_action,
                    cat,
                    sms_act,
                    sms_sub,
                    item["confidence"],
                    now,
                    now,
                ),
            )
            conn.execute(
                delta_sql,
                (
                    time_version,
                    item["numeric_phone"],
                    formatted_display_label,
                    call_action,
                    cat,
                    sms_act,
                    sms_sub,
                    now,
                ),
            )

        # 4. 更新版本元数据
        conn.execute("INSERT OR REPLACE INTO sync_metadata (key, value) VALUES ('current_version', ?);", (str(time_version),))
        conn.execute("INSERT OR REPLACE INTO sync_metadata (key, value) VALUES ('updated_at', ?);", (str(now),))

    conn.close()

    print("\n✅ 数据导入成功并完成事务提交！")
    print(f"🏷️ 全新单一事实源基准版本号: v{time_version}")
    print("\n📈 标准分类分布明细:")
    categories = [
        "delivery",
        "official",
        "enterprise",
        "real_estate",
        "finance_loan",
        "marketing",
        "harassment",
        "fraud",
    ]
    for cat in categories:
        count = sum(1 for r in sorted_records if r["category"] == cat)
        print(f"  • {cat.ljust(22)}: {count} 条")

    print("\n📁 原始文件夹来源明细 (前 10):")
    for f_name, count in sorted(stats_by_folder.items(), key=lambda x: x[1], reverse=True)[:10]:
        print(f"  • {f_name.ljust(10)}: {count} 个")

    print("=" * 60)

if __name__ == "__main__":
    run_import()
