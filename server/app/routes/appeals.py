import time
from typing import Optional
from fastapi import APIRouter, Depends, Header
import aiosqlite

from app.database import get_db, touch_device_profile
from app.schemas import APIResponse, AppealCreateRequest, AppealResponseData
from app.routes.numbers import clean_to_e164

router = APIRouter(prefix="/api/v1/appeals", tags=["号码误标申诉与纠错模块"])

@router.post("", response_model=APIResponse[AppealResponseData])
async def submit_number_appeal(
    payload: AppealCreateRequest,
    x_device_fingerprint: Optional[str] = Header(None, alias="X-Device-Fingerprint"),
    db: aiosqlite.Connection = Depends(get_db),
):
    """接收公众/企业对被误标号码的申诉请求"""
    raw_phone = payload.phone_number
    numeric_phone = clean_to_e164(raw_phone)
    if not numeric_phone:
        return APIResponse.error(code=40001, message=f"无法解析的手机号码: {raw_phone}")

    now = int(time.time() * 1000)
    phone_contact = payload.contact_phone or ""
    email_contact = payload.contact_email or ""
    combined_contact = payload.contact_info or f"{phone_contact} | {email_contact}".strip(" |")

    sql = """
    INSERT INTO number_appeals (
        numeric_phone, raw_phone, appeal_type, reason, contact_info,
        contact_phone, contact_email, proof_snippet, status, created_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?);
    """
    cursor = await db.execute(
        sql,
        (
            numeric_phone,
            raw_phone,
            payload.appeal_type,
            payload.reason,
            combined_contact,
            phone_contact,
            email_contact,
            payload.proof_snippet,
            now,
        ),
    )
    appeal_id = cursor.lastrowid or 0

    if x_device_fingerprint or phone_contact:
        await touch_device_profile(db, x_device_fingerprint or phone_contact, action="appeal")

    await db.commit()

    return APIResponse.ok(
        data=AppealResponseData(
            appeal_id=appeal_id,
            status="pending",
            accepted=True,
            message="申诉已受理，工作人员核实后将自动生成墓碑差量日志纠错并全量推送",
        )
    )
