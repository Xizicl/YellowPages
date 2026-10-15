import time
from fastapi import APIRouter, Depends, Header
from typing import Optional
import aiosqlite

from app.database import get_db, touch_device_profile
from app.schemas import APIResponse, ReportCreateRequest, ReportResponseData
from app.routes.numbers import clean_to_e164

router = APIRouter(prefix="/api/v1/reports", tags=["用户标记与举报模块"])

@router.post("", response_model=APIResponse[ReportResponseData])
async def submit_user_report(
    payload: ReportCreateRequest,
    x_device_fingerprint: Optional[str] = Header(None, alias="X-Device-Fingerprint"),
    db: aiosqlite.Connection = Depends(get_db),
):
    """接收用户标记与来电/短信骚扰举报，并自动触发社区聚合计入规则库"""
    raw_phone = payload.phone_number
    numeric_phone = clean_to_e164(raw_phone)
    if not numeric_phone:
        return APIResponse.error(code=40001, message=f"无法解析的手机号码: {raw_phone}")

    device_fp = x_device_fingerprint or payload.device_fingerprint or "anonymous_device"
    now = int(time.time() * 1000)
    channel = payload.channel or payload.report_type or "call"
    final_category = payload.call_category or payload.sms_category or payload.category or "custom"
    label = payload.custom_label or payload.suggested_label or payload.label or "用户标记"

    # 1. 存入 user_reports 表
    insert_sql = """
    INSERT INTO user_reports (
        numeric_phone, raw_phone, channel, category, suggested_label,
        content_snippet, device_fingerprint, client_timestamp, status, created_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?);
    """
    cursor = await db.execute(
        insert_sql,
        (
            numeric_phone,
            raw_phone,
            channel,
            final_category,
            label,
            payload.content_snippet,
            device_fp,
            payload.client_timestamp or now,
            now,
        ),
    )
    report_id = cursor.lastrowid or 0

    # 1.1 自动计入设备信用与流水
    await touch_device_profile(db, device_fp, action="report")

    # 2. 自动化社区聚合触发器 (Community Confidence Convergence)
    # 统计该号码的独立设备举报数量与分类聚合
    agg_sql = """
    SELECT COUNT(DISTINCT device_fingerprint) as device_count, category, suggested_label
    FROM user_reports
    WHERE numeric_phone = ?
    GROUP BY category
    ORDER BY device_count DESC
    LIMIT 1;
    """
    async with db.execute(agg_sql, (numeric_phone,)) as agg_cur:
        agg_row = await agg_cur.fetchone()
        if agg_row:
            device_count = agg_row["device_count"]
            top_category = agg_row["category"]
            best_label = agg_row["suggested_label"] or label

            # 若不同独立设备举报达到 3 次以上，收敛入号码主库
            if device_count >= 3:
                is_high_risk = top_category in ["fraud", "harassment", "marketing", "telemarketing", "real_estate", "finance_loan", "finance_telemarketing"]
                # 5个以上独立设备举报高危则直接触发拦截
                action = "block" if (is_high_risk and device_count >= 5) else "identify"
                confidence = min(0.99, 0.5 + device_count * 0.1)

                # 检查是否存在，若不存在则新增
                async with db.execute(
                    "SELECT numeric_phone, action FROM numbers_directory WHERE numeric_phone = ?",
                    (numeric_phone,),
                ) as check_cur:
                    existing = await check_cur.fetchone()

                if not existing:
                    call_action = 1 if action == "block" else 0
                    disp_label = f"[{top_category}] {best_label}"

                    await db.execute(
                        """
                        INSERT OR REPLACE INTO phone_numbers (
                            numeric_phone, label, org_name, confidence, is_official, is_deleted, created_at, updated_at
                        ) VALUES (?, ?, '社区上报', ?, 0, 0, ?, ?);
                        """,
                        (numeric_phone, best_label, confidence, now, now),
                    )
                    await db.execute(
                        """
                        INSERT OR REPLACE INTO call_directory (
                            numeric_phone, call_category, call_action, display_label, updated_at
                        ) VALUES (?, ?, ?, ?, ?);
                        """,
                        (numeric_phone, top_category, call_action, disp_label, now),
                    )
                    if channel == "sms" and payload.sms_primary_action is not None:
                        sms_act = payload.sms_primary_action
                        sms_sub = payload.sms_sub_action or 0
                        await db.execute(
                            """
                            INSERT OR REPLACE INTO sms_directory (
                                numeric_phone, match_type, pattern, sms_action, sms_sub_action, rule_name, updated_at
                            ) VALUES (?, 'exact', ?, ?, ?, ?, ?);
                            """,
                            (numeric_phone, str(numeric_phone), sms_act, sms_sub, best_label, now),
                        )

    await db.commit()

    return APIResponse.ok(
        data=ReportResponseData(
            report_id=report_id,
            status="accepted",
            accepted=True,
        )
    )
