import re
from typing import Optional
from fastapi import APIRouter, Depends, Query
import aiosqlite

from app.database import get_db
from app.schemas import (
    APIResponse,
    NumberLookupResult,
    TagInfo,
    RiskInfo,
    LocationInfo,
    BatchLookupRequest,
    BatchLookupItem,
    BatchLookupData,
)

router = APIRouter(prefix="/api/v1/numbers", tags=["号码反查模块"])

def clean_to_e164(phone_str: str) -> Optional[int]:
    """清洗号码字符串为 E.164 纯数字整数"""
    digits = re.sub(r"\D", "", phone_str)
    if not digits:
        return None
    if digits.startswith("86"):
        return int(digits)
    if len(digits) == 11 and digits.startswith("1"):
        return int("86" + digits)
    if digits.startswith("0") and len(digits) >= 10:
        return int("86" + digits[1:])
    if digits.startswith("400") or digits.startswith("800"):
        return int("86" + digits)
    if len(digits) == 5 and (digits.startswith("95") or digits.startswith("96") or digits.startswith("10")):
        return int("86" + digits)
    return int(digits)

def format_e164_display(numeric_phone: int) -> str:
    s = str(numeric_phone)
    if s.startswith("86") and len(s) == 13:
        # 86 138-0013-8000
        return f"+86 {s[2:5]}-{s[5:9]}-{s[9:]}"
    elif s.startswith("86"):
        return f"+86 {s[2:]}"
    return f"+{s}"

SMS_SUB_LABELS = {
    10000: "其他交易通知",
    10001: "金融银行服务",
    10002: "订单与物流",
    10003: "行程与预订",
    10004: "医疗健康通知",
    10005: "气象灾害预警",
    10006: "运营商官方业务",
    10007: "积分与会员奖励",
    10008: "公共政务服务",
    20000: "其他商业推广",
    20001: "商业优惠与营销",
    20002: "打折卡券与折扣",
}

SMS_ACTION_LABELS = {
    0: ("none", "普通主收件箱"),
    1: ("allow", "强放行 / 验证码"),
    2: ("junk", "垃圾短信拦截"),
    3: ("promotion", "商业推广"),
    4: ("transaction", "交易与服务"),
}

CALL_CATEGORY_NAMES = {
    "delivery": "快递外卖",
    "official": "官方政企",
    "enterprise": "机构服务",
    "real_estate": "房产中介",
    "finance_loan": "贷款理财",
    "marketing": "广告推销",
    "harassment": "恶意骚扰",
    "fraud": "疑似诈骗",
    "custom": "自定义标记",
}

def map_category_to_actions(category: str, is_blocking: bool = False) -> tuple[str, str, int, str, str, int]:
    """
    对齐官方规范：
    返回元组：
    (primary_action, primary_action_label, primary_code, sub_action, sub_action_label, sub_code)
    """
    if is_blocking:
        return ("junk", "垃圾短信拦截", 2, "none", "无", 0)
    
    if category in ["delivery", "express", "takeaway"]:
        return ("transaction", "交易与服务", 4, "orders", "订单与物流", 10002)
    elif category == "official":
        return ("transaction", "交易与服务", 4, "public_services", "公共政务服务", 10008)
    elif category in ["enterprise", "institution", "finance"]:
        return ("transaction", "交易与服务", 4, "finance", "金融银行服务", 10001)
    elif category == "real_estate":
        return ("promotion", "商业推广", 3, "others", "其他商业推广", 20000)
    elif category in ["finance_loan", "finance_telemarketing"]:
        return ("promotion", "商业推广", 3, "offers", "商业优惠与营销", 20001)
    elif category in ["marketing", "telemarketing"]:
        return ("promotion", "商业推广", 3, "offers", "商业优惠与营销", 20001)
    elif category in ["harassment", "fraud"]:
        return ("junk", "垃圾短信拦截", 2, "none", "无", 0)
    else:
        return ("allow", "强放行 / 验证码", 1, "none", "无", 0)

@router.get("/lookup", response_model=APIResponse[NumberLookupResult])
async def lookup_number(
    phone: Optional[str] = Query(None, description="待查号码"),
    phone_number: Optional[str] = Query(None, description="别名：待查号码"),
    db: aiosqlite.Connection = Depends(get_db),
):
    """
    单号码在线实时反查（基于 numbers_directory 单一事实源单表极速查询，零 JOIN）
    """
    target = phone or phone_number
    if not target:
        return APIResponse.error(code=40001, message="缺少待查询的号码参数 phone")

    numeric_phone = clean_to_e164(target)
    if not numeric_phone:
        return APIResponse.error(code=40001, message=f"无法解析的手机号码: {target}")

    formatted = format_e164_display(numeric_phone)

    # 1. 优先从 numbers_directory 单表查询 (零 JOIN 毫秒响应)
    query = """
    SELECT numeric_phone, label, call_action, call_category, sms_action, sms_sub_action, confidence
    FROM numbers_directory
    WHERE numeric_phone = ? AND is_deleted = 0
    LIMIT 1;
    """
    async with db.execute(query, (numeric_phone,)) as cursor:
        row = await cursor.fetchone()
        if row:
            call_action_val = row["call_action"]
            is_blocking = call_action_val == 1
            call_cat = row["call_category"]
            sms_act = row["sms_action"]
            sms_sub = row["sms_sub_action"]
            raw_label = row["label"]
            cat_name = CALL_CATEGORY_NAMES.get(call_cat, "机构服务")
            display_lbl = raw_label if raw_label.startswith("[") else f"[{cat_name}] {raw_label}"

            prim_action, prim_label = SMS_ACTION_LABELS.get(sms_act, ("transaction", "交易与服务"))
            sub_label = SMS_SUB_LABELS.get(sms_sub, "无")
            sub_action_slug = "none" if sms_sub == 0 else f"code_{sms_sub}"

            result = NumberLookupResult(
                phone_number=str(row["numeric_phone"]),
                numeric_phone=row["numeric_phone"],
                formatted=formatted,
                country_code="CN",
                carrier=None,  # 数据库无存储时不臆造，严格留空
                location=None, # 数据库无存储时不臆造，严格留空
                tag_info=TagInfo(
                    label=display_lbl,
                    category=call_cat,
                    confidence=float(row["confidence"]),
                    source_type="official",
                    is_official=True,
                    is_blocking=is_blocking,
                    call_action="block" if is_blocking else "identify",
                    call_action_label="阻止拦截" if is_blocking else "身份识别",
                    primary_action=prim_action,
                    primary_action_label=prim_label,
                    primary_action_code=sms_act,
                    sub_action=sub_action_slug,
                    sub_action_label=sub_label,
                    sub_action_code=sms_sub,
                ),
                risk_info=RiskInfo(
                    level="high" if is_blocking else "low",
                    score=float(row["confidence"]) if is_blocking else 0.0,
                    report_count=0,
                ) if is_blocking else None,
                found=True,
            )
            return APIResponse.ok(data=result)

    # 2. 检查用户举报库中的社区标记聚合统计
    rep_query = """
    SELECT COUNT(1) as total, category, suggested_label
    FROM user_reports
    WHERE numeric_phone = ?
    GROUP BY category
    ORDER BY total DESC
    LIMIT 1;
    """
    async with db.execute(rep_query, (numeric_phone,)) as rep_cur:
        rep_row = await rep_cur.fetchone()
        if rep_row and rep_row["total"] > 0:
            count = rep_row["total"]
            label = rep_row["suggested_label"] or f"社区标记: {rep_row['category']}"
            category = rep_row["category"]
            is_risk = category in ["harassment", "marketing", "telemarketing", "fraud", "real_estate", "finance_loan", "finance_telemarketing"]
            is_blocking = is_risk and count >= 5
            prim_action, prim_label, prim_code, sub_action, sub_label, sub_code = map_category_to_actions(category, is_blocking)

            result = NumberLookupResult(
                phone_number=str(numeric_phone),
                numeric_phone=numeric_phone,
                formatted=formatted,
                country_code="CN",
                carrier=None,
                location=None,
                tag_info=TagInfo(
                    label=label,
                    category=category,
                    confidence=min(0.95, round(0.4 + count * 0.1, 2)),
                    source_type="community",
                    is_official=False,
                    is_blocking=is_blocking,
                    call_action="block" if is_blocking else "identify",
                    call_action_label="阻止拦截" if is_blocking else "身份识别",
                    primary_action=prim_action,
                    primary_action_label=prim_label,
                    primary_action_code=prim_code,
                    sub_action=sub_action,
                    sub_action_label=sub_label,
                    sub_action_code=sub_code,
                ),
                risk_info=RiskInfo(
                    level="high" if (is_risk and count >= 3) else "medium",
                    score=min(1.0, round(count * 0.2, 2)),
                    report_count=count,
                ),
                found=True,
            )
            return APIResponse.ok(data=result)

    # 3. 未找到任何记录，严格遵循真实事实，零虚假数据
    empty_result = NumberLookupResult(
        phone_number=str(numeric_phone),
        numeric_phone=numeric_phone,
        formatted=formatted,
        country_code="CN",
        carrier=None,
        location=None,
        tag_info=None,
        risk_info=None,
        found=False,
    )
    return APIResponse.ok(data=empty_result)

@router.post("/batch-lookup", response_model=APIResponse[BatchLookupData])
async def batch_lookup_numbers(
    payload: BatchLookupRequest,
    db: aiosqlite.Connection = Depends(get_db),
):
    """批量号码实时反查（单批上限 100 条）"""
    phone_numbers = payload.phone_numbers[:100]
    if not phone_numbers:
        return APIResponse.ok(data=BatchLookupData(results=[]))

    numeric_map = {}
    for p in phone_numbers:
        clean = clean_to_e164(p)
        if clean:
            numeric_map[clean] = p

    if not numeric_map:
        empty_items = [BatchLookupItem(phone_number=p, found=False) for p in phone_numbers]
        return APIResponse.ok(data=BatchLookupData(results=empty_items))

    placeholders = ",".join(["?"] * len(numeric_map))
    query = f"""
    SELECT numeric_phone, label, call_category, call_action, confidence
    FROM numbers_directory
    WHERE numeric_phone IN ({placeholders}) AND is_deleted = 0;
    """

    found_rows = {}
    async with db.execute(query, list(numeric_map.keys())) as cursor:
        async for row in cursor:
            found_rows[row["numeric_phone"]] = row

    items = []
    for num, orig in numeric_map.items():
        if num in found_rows:
            r = found_rows[num]
            items.append(
                BatchLookupItem(
                    phone_number=orig,
                    found=True,
                    label=r["label"],
                    category=r["call_category"],
                    confidence=r["confidence"],
                    is_blocking=r["call_action"] == 1,
                )
            )
        else:
            items.append(
                BatchLookupItem(
                    phone_number=orig,
                    found=False,
                    label=None,
                    category=None,
                    confidence=0.0,
                    is_blocking=False,
                )
            )

    return APIResponse.ok(data=BatchLookupData(results=items))
