import math
from typing import Optional
from fastapi import APIRouter, Depends, Query, Header
import aiosqlite

from app.database import get_db, touch_device_profile
from app.schemas import (
    APIResponse,
    SyncMetadataData,
    SyncFullData,
    PhoneNumberRecord,
    SyncDeltaData,
    DeltaItem,
    DeviceProfileSummary,
)

router = APIRouter(prefix="/api/v1/sync", tags=["同步模块"])

@router.get("/metadata", response_model=APIResponse[SyncMetadataData])
async def get_sync_metadata(
    x_device_fingerprint: Optional[str] = Header(None, alias="X-Device-Fingerprint"),
    x_client_platform: Optional[str] = Header("iOS", alias="X-Client-Platform"),
    db: aiosqlite.Connection = Depends(get_db),
):
    """获取号码库最新版本元信息与统计数据，并自动建立/更新活跃设备信誉档案"""
    device_summary = None
    if x_device_fingerprint:
        await touch_device_profile(db, x_device_fingerprint, platform=x_client_platform or "iOS")
        await db.commit()

        async with db.execute(
            "SELECT credit_level, reputation_score, total_reports, approved_reports, is_blocked FROM device_profiles WHERE device_fingerprint = ?",
            (x_device_fingerprint,),
        ) as dev_cur:
            dev_row = await dev_cur.fetchone()
            if dev_row:
                lvl = dev_row["credit_level"]
                lvl_names = {
                    "excellent": "极佳",
                    "good": "良好",
                    "fair": "中等",
                    "poor": "高风险"
                }
                device_summary = DeviceProfileSummary(
                    device_fingerprint=x_device_fingerprint,
                    credit_level=lvl,
                    credit_level_name=lvl_names.get(lvl, "良好"),
                    reputation_score=float(dev_row["reputation_score"]),
                    total_reports=int(dev_row["total_reports"]),
                    approved_reports=int(dev_row["approved_reports"]),
                    is_blocked=bool(dev_row["is_blocked"]),
                )
    async with db.execute("SELECT value FROM sync_metadata WHERE key = 'current_version'") as cursor:
        v_row = await cursor.fetchone()
        current_version = int(v_row["value"]) if v_row else 1

    async with db.execute("SELECT value FROM sync_metadata WHERE key = 'updated_at'") as cursor:
        u_row = await cursor.fetchone()
        updated_at_str = u_row["value"] if u_row else "1791880200000"

    async with db.execute("SELECT COUNT(1) as total FROM numbers_directory WHERE is_deleted = 0") as cursor:
        row = await cursor.fetchone()
        total_count = row["total"] if row else 0

    async with db.execute("SELECT COUNT(1) as c FROM numbers_directory WHERE call_action = 0 AND is_deleted = 0") as cursor:
        row = await cursor.fetchone()
        ident_count = row["c"] if row else 0

    async with db.execute("SELECT COUNT(1) as c FROM numbers_directory WHERE call_action = 1 AND is_deleted = 0") as cursor:
        row = await cursor.fetchone()
        block_count = row["c"] if row else 0

    chunk_size = 50000
    full_sync_chunks = max(1, math.ceil(total_count / chunk_size)) if total_count > 0 else 1

    data = SyncMetadataData(
        current_version=current_version,
        latest_version=current_version,
        min_supported_version=1,
        total_count=total_count,
        identification_count=ident_count,
        blocking_count=block_count,
        full_sync_chunks=full_sync_chunks,
        chunk_size=chunk_size,
        recommended_chunk_size=chunk_size,
        latest_updated_at=updated_at_str,
        updated_at=updated_at_str,
        device_profile=device_summary,
    )
    return APIResponse.ok(data=data)

@router.get("/full", response_model=APIResponse[SyncFullData])
async def get_full_sync(
    chunk_index: int = Query(0, ge=0, description="分片索引，从 0 开始"),
    chunk_size: int = Query(50000, ge=1, le=100000, description="单批次数量"),
    db: aiosqlite.Connection = Depends(get_db),
):
    """全量分片下载，严格遵循 numbers_directory 单表 ORDER BY numeric_phone ASC 零 JOIN 流式下发"""
    async with db.execute("SELECT value FROM sync_metadata WHERE key = 'current_version'") as cursor:
        v_row = await cursor.fetchone()
        version = int(v_row["value"]) if v_row else 1

    async with db.execute("SELECT COUNT(1) as total FROM numbers_directory WHERE is_deleted = 0") as cursor:
        row = await cursor.fetchone()
        total_count = row["total"] if row else 0

    total_chunks = max(1, math.ceil(total_count / chunk_size)) if total_count > 0 else 1
    offset = chunk_index * chunk_size

    query = """
    SELECT numeric_phone, label, call_action, call_category, sms_action, sms_sub_action, confidence, updated_at, created_at
    FROM numbers_directory
    WHERE is_deleted = 0
    ORDER BY numeric_phone ASC
    LIMIT ? OFFSET ?;
    """

    records = []
    async with db.execute(query, (chunk_size, offset)) as cursor:
        async for row in cursor:
            call_act = row["call_action"]
            is_blocking = call_act == 1
            call_cat = row["call_category"]
            records.append(
                PhoneNumberRecord(
                    numeric_phone=row["numeric_phone"],
                    phone_number=str(row["numeric_phone"]),
                    label=row["label"],
                    call_action=call_act,
                    call_category=call_cat,
                    sms_action=row["sms_action"],
                    sms_sub_action=row["sms_sub_action"],
                    confidence=float(row["confidence"]),
                    action="blocking" if is_blocking else "identification",
                    category=call_cat,
                    is_blocking=is_blocking,
                    updated_at=row["updated_at"],
                    created_at=row["created_at"],
                )
            )

    has_more = (offset + len(records)) < total_count

    data = SyncFullData(
        version=version,
        chunk_index=chunk_index,
        total_chunks=total_chunks,
        has_more=has_more,
        records=records,
    )
    return APIResponse.ok(data=data)

@router.get("/delta", response_model=APIResponse[SyncDeltaData])
async def get_incremental_delta(
    since_version: Optional[int] = Query(None, description="客户端本地版本号"),
    client_version: Optional[int] = Query(None, description="别名：客户端版本号"),
    cursor: Optional[str] = Query(None, description="游标"),
    limit: int = Query(20000, ge=1, le=50000),
    db: aiosqlite.Connection = Depends(get_db),
):
    """增量同步接口，查询 numbers_delta_log 中大于 client_version 的更新差异"""
    effective_since = client_version if client_version is not None else (since_version if since_version is not None else 0)

    async with db.execute("SELECT value FROM sync_metadata WHERE key = 'current_version'") as v_cur:
        v_row = await v_cur.fetchone()
        target_version = int(v_row["value"]) if v_row else 1

    # 统计差异记录总条数
    async with db.execute("SELECT COUNT(1) as c FROM numbers_delta_log WHERE version > ?", (effective_since,)) as c_cur:
        c_row = await c_cur.fetchone()
        delta_count = c_row["c"] if c_row else 0

    # 若差异记录超过 20000 条，或者客户端为初始 0，强制降级要求全量重载
    if delta_count > 20000 or effective_since == 0:
        data = SyncDeltaData(
            base_version=effective_since,
            target_version=target_version,
            require_full_reload=True,
            next_cursor=None,
            has_more=False,
            changes=[],
        )
        return APIResponse.ok(data=data)

    query = """
    SELECT version, numeric_phone, op, label, call_action, call_category, sms_action, sms_sub_action, updated_at
    FROM numbers_delta_log
    WHERE version > ?
    ORDER BY version ASC, numeric_phone ASC
    LIMIT ?;
    """

    changes = []
    async with db.execute(query, (effective_since, limit)) as log_cur:
        async for row in log_cur:
            op = row["op"]
            call_act = row["call_action"] or 0
            is_blocking = call_act == 1
            call_cat = row["call_category"] or "enterprise"
            changes.append(
                DeltaItem(
                    op=op,
                    numeric_phone=row["numeric_phone"],
                    phone_number=str(row["numeric_phone"]),
                    label=row["label"],
                    call_action=call_act,
                    call_category=call_cat,
                    sms_action=row["sms_action"] or 4,
                    sms_sub_action=row["sms_sub_action"] or 0,
                    confidence=1.0,
                    action="blocking" if is_blocking else "identification",
                    category=call_cat,
                    is_blocking=is_blocking,
                    updated_at=row["updated_at"],
                )
            )

    data = SyncDeltaData(
        base_version=effective_since,
        target_version=target_version,
        require_full_reload=False,
        next_cursor=None,
        has_more=len(changes) < delta_count,
        changes=changes,
    )
    return APIResponse.ok(data=data)
