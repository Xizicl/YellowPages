import time
import csv
import io
from typing import Optional, List, Any
from fastapi import APIRouter, Depends, Query, Path, UploadFile, File, Form
from fastapi.responses import Response
import aiosqlite

from app.database import get_db, generate_time_version, touch_device_profile
from app.schemas import (
    APIResponse,
    AdminNumberCreate,
    AdminNumberUpdate,
    AdminNumberItem,
    AdminReportItem,
    AdminAppealItem,
    AdminDeviceItem,
    AlgorithmConfigData,
    AlgorithmConfigUpdateRequest,
    CsvImportStats,
)

router = APIRouter(prefix="/api/v1/admin", tags=["管理控制台模块"])

# MARK: - 号码库增删改查 (支持软删除与一键恢复)

@router.get("/numbers", response_model=APIResponse[dict])
async def list_admin_numbers(
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    keyword: Optional[str] = Query(None),
    category: Optional[str] = Query(None),
    action: Optional[str] = Query(None),
    status_filter: str = Query("active", description="active | deleted | all"),
    db: aiosqlite.Connection = Depends(get_db),
):
    """管理员分页查询号码库（支持活跃/已软删除过滤）"""
    offset = (page - 1) * limit
    where_clauses = []
    params = []

    if status_filter == "active":
        where_clauses.append("is_deleted = 0")
    elif status_filter == "deleted":
        where_clauses.append("is_deleted = 1")

    if keyword:
        where_clauses.append("(numeric_phone LIKE ? OR label LIKE ?)")
        params.extend([f"%{keyword}%", f"%{keyword}%"])
    if category:
        where_clauses.append("category = ?")
        params.append(category)
    if action:
        where_clauses.append("action = ?")
        params.append(action)

    where_str = f"WHERE {' AND '.join(where_clauses)}" if where_clauses else ""

    count_sql = f"SELECT COUNT(1) as total FROM numbers_directory {where_str}"
    async with db.execute(count_sql, params) as c_cur:
        c_row = await c_cur.fetchone()
        total = c_row["total"] if c_row else 0

    query_sql = f"""
    SELECT numeric_phone, label, call_action, call_category, sms_action, sms_sub_action, confidence, is_deleted, updated_at, created_at
    FROM numbers_directory
    {where_str}
    ORDER BY numeric_phone ASC
    LIMIT ? OFFSET ?;
    """
    params.extend([limit, offset])

    items = []
    async with db.execute(query_sql, params) as cur:
        async for row in cur:
            call_act = row["call_action"]
            call_cat = row["call_category"]
            items.append(
                AdminNumberItem(
                    numeric_phone=row["numeric_phone"],
                    raw_phone=str(row["numeric_phone"]),
                    label=row["label"],
                    call_action=call_act,
                    call_category=call_cat,
                    sms_action=row["sms_action"],
                    sms_sub_action=row["sms_sub_action"],
                    action="block" if call_act == 1 else "identify",
                    category=call_cat,
                    confidence=row["confidence"],
                    version=row["updated_at"],
                    updated_at=row["updated_at"],
                    created_at=row["created_at"],
                    is_deleted=bool(row["is_deleted"]),
                ).model_dump()
            )

    return APIResponse.ok(
        data={
            "page": page,
            "limit": limit,
            "total": total,
            "items": items,
        }
    )

@router.post("/numbers", response_model=APIResponse[dict])
async def create_admin_number(
    payload: AdminNumberCreate,
    db: aiosqlite.Connection = Depends(get_db),
):
    """管理员新增单个号码至库中（默认未删除状态）"""
    now = int(time.time() * 1000)

    # 获取当前版本
    async with db.execute("SELECT value FROM sync_metadata WHERE key = 'current_version'") as v_cur:
        v_row = await v_cur.fetchone()
        current_version = int(v_row["value"]) if v_row else 1

    sql = """
    INSERT OR REPLACE INTO numbers_directory (
        numeric_phone, label, call_action, call_category, sms_action, sms_sub_action, confidence, is_deleted, updated_at, created_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?);
    """
    await db.execute(
        sql,
        (
            payload.numeric_phone,
            payload.label,
            payload.call_action,
            payload.call_category,
            payload.sms_action,
            payload.sms_sub_action,
            payload.confidence,
            now,
            now,
        ),
    )

    await db.execute(
        """
        INSERT INTO numbers_delta_log (
            version, numeric_phone, op, label, call_action, call_category, sms_action, sms_sub_action, updated_at
        ) VALUES (?, ?, 'add', ?, ?, ?, ?, ?, ?);
        """,
        (
            current_version,
            payload.numeric_phone,
            payload.label,
            payload.call_action,
            payload.call_category,
            payload.sms_action,
            payload.sms_sub_action,
            now,
        ),
    )

    await db.commit()
    return APIResponse.ok(data={"numeric_phone": payload.numeric_phone, "status": "created"})

@router.put("/numbers/{phone}", response_model=APIResponse[dict])
async def update_admin_number(
    phone: int = Path(..., description="E.164 纯数字"),
    payload: AdminNumberUpdate = None,  # type: ignore
    db: aiosqlite.Connection = Depends(get_db),
):
    """管理员修改号码属性"""
    now = int(time.time() * 1000)

    # 获取当前数据
    async with db.execute("SELECT * FROM numbers_directory WHERE numeric_phone = ?", (phone,)) as cur:
        row = await cur.fetchone()
        if not row:
            return APIResponse.error(code=40401, message=f"未找到号码: {phone}")

    new_label = payload.label if (payload and payload.label is not None) else row["label"]
    new_call_category = payload.call_category if (payload and payload.call_category is not None) else row["call_category"]
    new_call_action = payload.call_action if (payload and payload.call_action is not None) else row["call_action"]
    new_sms_action = payload.sms_action if (payload and payload.sms_action is not None) else row["sms_action"]
    new_sms_sub_action = payload.sms_sub_action if (payload and payload.sms_sub_action is not None) else row["sms_sub_action"]
    new_confidence = payload.confidence if (payload and payload.confidence is not None) else row["confidence"]

    # 当前版本
    async with db.execute("SELECT value FROM sync_metadata WHERE key = 'current_version'") as v_cur:
        v_row = await v_cur.fetchone()
        current_version = int(v_row["value"]) if v_row else 1

    update_sql = """
    UPDATE numbers_directory
    SET label = ?, call_action = ?, call_category = ?, sms_action = ?, sms_sub_action = ?, confidence = ?, updated_at = ?
    WHERE numeric_phone = ?;
    """
    await db.execute(update_sql, (new_label, new_call_action, new_call_category, new_sms_action, new_sms_sub_action, new_confidence, now, phone))

    await db.execute(
        """
        INSERT INTO numbers_delta_log (
            version, numeric_phone, op, label, call_action, call_category, sms_action, sms_sub_action, updated_at
        ) VALUES (?, ?, 'update', ?, ?, ?, ?, ?, ?);
        """,
        (
            current_version,
            phone,
            new_label,
            new_call_action,
            new_call_category,
            new_sms_action,
            new_sms_sub_action,
            now,
        ),
    )

    await db.commit()
    return APIResponse.ok(data={"numeric_phone": phone, "status": "updated"})

@router.delete("/numbers/{phone}", response_model=APIResponse[dict])
async def delete_admin_number(
    phone: int = Path(..., description="E.164 纯数字"),
    db: aiosqlite.Connection = Depends(get_db),
):
    """管理员软删除号码（只标记不物理删除，写入 Tombstone 墓碑差量日志）"""
    now = int(time.time() * 1000)
    async with db.execute("SELECT * FROM numbers_directory WHERE numeric_phone = ?", (phone,)) as cur:
        row = await cur.fetchone()
        if not row:
            return APIResponse.error(code=40401, message=f"未找到号码: {phone}")

    # 当前版本
    async with db.execute("SELECT value FROM sync_metadata WHERE key = 'current_version'") as v_cur:
        v_row = await v_cur.fetchone()
        current_version = int(v_row["value"]) if v_row else 1

    # 软删除标记
    await db.execute(
        "UPDATE numbers_directory SET is_deleted = 1, updated_at = ? WHERE numeric_phone = ?;",
        (now, phone),
    )

    # 记录 remove 增量墓碑日志
    await db.execute(
        """
        INSERT INTO numbers_delta_log (
            version, numeric_phone, op, label, call_action, call_category, sms_action, sms_sub_action, updated_at
        ) VALUES (?, ?, 'remove', NULL, 0, NULL, 0, 0, ?);
        """,
        (current_version, phone, now),
    )

    await db.commit()
    return APIResponse.ok(data={"numeric_phone": phone, "status": "soft_deleted"})

@router.post("/numbers/{phone}/restore", response_model=APIResponse[dict])
async def restore_admin_number(
    phone: int = Path(..., description="E.164 纯数字"),
    db: aiosqlite.Connection = Depends(get_db),
):
    """管理员撤销软删除，恢复已删除号码并下发增加日志"""
    now = int(time.time() * 1000)
    async with db.execute("SELECT * FROM numbers_directory WHERE numeric_phone = ?", (phone,)) as cur:
        row = await cur.fetchone()
        if not row:
            return APIResponse.error(code=40401, message=f"未找到号码: {phone}")

    async with db.execute("SELECT value FROM sync_metadata WHERE key = 'current_version'") as v_cur:
        v_row = await v_cur.fetchone()
        current_version = int(v_row["value"]) if v_row else 1

    await db.execute(
        "UPDATE numbers_directory SET is_deleted = 0, updated_at = ? WHERE numeric_phone = ?;",
        (now, phone),
    )

    await db.execute(
        """
        INSERT INTO numbers_delta_log (
            version, numeric_phone, op, label, call_action, call_category, sms_action, sms_sub_action, updated_at
        ) VALUES (?, ?, 'add', ?, ?, ?, ?, ?, ?);
        """,
        (
            current_version,
            phone,
            row["label"],
            row["call_action"],
            row["call_category"],
            row["sms_action"],
            row["sms_sub_action"],
            now,
        ),
    )

    await db.commit()
    return APIResponse.ok(data={"numeric_phone": phone, "status": "restored"})

# MARK: - 举报审核与采纳

@router.get("/reports", response_model=APIResponse[dict])
async def list_admin_reports(
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    status: Optional[str] = Query(None),
    db: aiosqlite.Connection = Depends(get_db),
):
    """分页查看用户举报流水"""
    offset = (page - 1) * limit
    where_str = "WHERE status = ?" if status else ""
    params: List[Any] = [status] if status else []

    count_sql = f"SELECT COUNT(1) as total FROM user_reports {where_str}"
    async with db.execute(count_sql, params) as c_cur:
        c_row = await c_cur.fetchone()
        total = c_row["total"] if c_row else 0

    query_sql = f"""
    SELECT id, numeric_phone, raw_phone, channel, category, suggested_label,
           content_snippet, device_fingerprint, status, created_at
    FROM user_reports
    {where_str}
    ORDER BY created_at DESC
    LIMIT ? OFFSET ?;
    """
    params.extend([limit, offset])

    items = []
    async with db.execute(query_sql, params) as cur:
        async for row in cur:
            items.append(
                AdminReportItem(
                    id=row["id"],
                    numeric_phone=row["numeric_phone"],
                    raw_phone=row["raw_phone"],
                    channel=row["channel"],
                    category=row["category"],
                    suggested_label=row["suggested_label"],
                    content_snippet=row["content_snippet"],
                    device_fingerprint=row["device_fingerprint"],
                    status=row["status"],
                    created_at=row["created_at"],
                ).model_dump()
            )

    return APIResponse.ok(data={"page": page, "limit": limit, "total": total, "items": items})

@router.post("/reports/{report_id}/approve", response_model=APIResponse[dict])
async def approve_report(
    report_id: int = Path(..., description="举报流水 ID"),
    db: aiosqlite.Connection = Depends(get_db),
):
    """采纳用户举报：将举报标签与分类收录进入号码主库"""
    now = int(time.time() * 1000)
    async with db.execute("SELECT * FROM user_reports WHERE id = ?", (report_id,)) as cur:
        rep = await cur.fetchone()
        if not rep:
            return APIResponse.error(code=40401, message=f"未找到举报记录: {report_id}")

    # 获取当前版本
    async with db.execute("SELECT value FROM sync_metadata WHERE key = 'current_version'") as v_cur:
        v_row = await v_cur.fetchone()
        current_version = int(v_row["value"]) if v_row else 1

    numeric_phone = rep["numeric_phone"]
    raw_phone = rep["raw_phone"] or str(numeric_phone)
    label = rep["suggested_label"] or "社区核实"
    category = rep["category"]
    action = "block" if category in ["fraud", "harassment"] else "identify"

    # 插入或覆盖主库 (活跃状态)
    await db.execute(
        """
        INSERT OR REPLACE INTO numbers_directory (
            numeric_phone, raw_phone, label, category, action, confidence, version, updated_at, is_deleted, deleted_at
        ) VALUES (?, ?, ?, ?, ?, 0.95, ?, ?, 0, NULL);
        """,
        (numeric_phone, raw_phone, label, category, action, current_version, now),
    )

    # 更新举报状态
    await db.execute("UPDATE user_reports SET status = 'approved' WHERE id = ?", (report_id,))

    # 写入 delta 记录
    await db.execute(
        """
        INSERT INTO numbers_delta_log (
            version, numeric_phone, action, label, category, is_blocking, confidence, created_at
        ) VALUES (?, ?, 'add', ?, ?, ?, 0.95, ?);
        """,
        (current_version, numeric_phone, label, category, 1 if action == "block" else 0, now),
    )

    # 奖励上报设备的信誉积分 (+2分)
    if rep["device_fingerprint"]:
        await touch_device_profile(db, rep["device_fingerprint"], action="approve")

    await db.commit()
    return APIResponse.ok(data={"report_id": report_id, "status": "approved"})

@router.post("/reports/{report_id}/reject", response_model=APIResponse[dict])
async def reject_report(
    report_id: int = Path(..., description="举报流水 ID"),
    db: aiosqlite.Connection = Depends(get_db),
):
    """驳回用户举报"""
    async with db.execute("SELECT id, device_fingerprint FROM user_reports WHERE id = ?", (report_id,)) as cur:
        rep = await cur.fetchone()
        if not rep:
            return APIResponse.error(code=40401, message=f"未找到举报记录: {report_id}")

    await db.execute("UPDATE user_reports SET status = 'rejected' WHERE id = ?", (report_id,))

    # 惩罚作弊或误报设备信誉积分 (-5分)
    if rep["device_fingerprint"]:
        await touch_device_profile(db, rep["device_fingerprint"], action="reject")

    await db.commit()
    return APIResponse.ok(data={"report_id": report_id, "status": "rejected"})

# MARK: - 申诉审核与纠错处理 (软删除解除拦截)

@router.get("/appeals", response_model=APIResponse[dict])
async def list_admin_appeals(
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    status: Optional[str] = Query(None),
    db: aiosqlite.Connection = Depends(get_db),
):
    """分页查看用户/企业误标申诉列表"""
    offset = (page - 1) * limit
    where_str = "WHERE status = ?" if status else ""
    params: List[Any] = [status] if status else []

    count_sql = f"SELECT COUNT(1) as total FROM number_appeals {where_str}"
    async with db.execute(count_sql, params) as c_cur:
        c_row = await c_cur.fetchone()
        total = c_row["total"] if c_row else 0

    query_sql = f"""
    SELECT id, numeric_phone, raw_phone, appeal_type, reason, contact_info,
           contact_phone, contact_email, proof_snippet, status, review_notes, created_at, reviewed_at
    FROM number_appeals
    {where_str}
    ORDER BY created_at DESC
    LIMIT ? OFFSET ?;
    """
    params.extend([limit, offset])

    items = []
    async with db.execute(query_sql, params) as cur:
        async for row in cur:
            items.append(
                AdminAppealItem(
                    id=row["id"],
                    numeric_phone=row["numeric_phone"],
                    raw_phone=row["raw_phone"],
                    appeal_type=row["appeal_type"],
                    reason=row["reason"],
                    contact_info=row["contact_info"],
                    contact_phone=row["contact_phone"] if "contact_phone" in row.keys() else None,
                    contact_email=row["contact_email"] if "contact_email" in row.keys() else None,
                    proof_snippet=row["proof_snippet"],
                    status=row["status"],
                    review_notes=row["review_notes"],
                    created_at=row["created_at"],
                    reviewed_at=row["reviewed_at"],
                ).model_dump()
            )

    return APIResponse.ok(data={"page": page, "limit": limit, "total": total, "items": items})

@router.post("/appeals/{appeal_id}/approve", response_model=APIResponse[dict])
async def approve_appeal(
    appeal_id: int = Path(..., description="申诉 ID"),
    review_notes: Optional[str] = Query(None, description="审核批注"),
    db: aiosqlite.Connection = Depends(get_db),
):
    """采纳申诉：软删除拦截记录（打上 remove 墓碑差量日志，数据留存可追溯）"""
    now = int(time.time() * 1000)
    async with db.execute("SELECT * FROM number_appeals WHERE id = ?", (appeal_id,)) as cur:
        appeal = await cur.fetchone()
        if not appeal:
            return APIResponse.error(code=40401, message=f"未找到申诉记录: {appeal_id}")

    async with db.execute("SELECT value FROM sync_metadata WHERE key = 'current_version'") as v_cur:
        v_row = await v_cur.fetchone()
        current_version = int(v_row["value"]) if v_row else 1

    numeric_phone = appeal["numeric_phone"]

    # 检查库中是否有该记录
    async with db.execute("SELECT * FROM numbers_directory WHERE numeric_phone = ?", (numeric_phone,)) as check_cur:
        num_row = await check_cur.fetchone()

    tombstone_generated = False
    if num_row:
        # 软删除标记，保留物理数据以供审计追溯
        await db.execute(
            "UPDATE numbers_directory SET is_deleted = 1, deleted_at = ?, updated_at = ? WHERE numeric_phone = ?;",
            (now, now, numeric_phone),
        )
        await db.execute(
            """
            INSERT INTO numbers_delta_log (
                version, numeric_phone, action, label, category, is_blocking, confidence, created_at
            ) VALUES (?, ?, 'remove', NULL, NULL, 0, 0.0, ?);
            """,
            (current_version, numeric_phone, now),
        )
        tombstone_generated = True

    # 更新申诉状态
    notes = review_notes or "审核通过，已从骚扰拦截库解除并下发墓碑差量同步"
    await db.execute(
        "UPDATE number_appeals SET status = 'approved', review_notes = ?, reviewed_at = ? WHERE id = ?",
        (notes, now, appeal_id),
    )

    await db.commit()
    return APIResponse.ok(
        data={
            "appeal_id": appeal_id,
            "status": "approved",
            "tombstone_generated": tombstone_generated,
        }
    )

@router.post("/appeals/{appeal_id}/reject", response_model=APIResponse[dict])
async def reject_appeal(
    appeal_id: int = Path(..., description="申诉 ID"),
    review_notes: Optional[str] = Query(None, description="驳回原因"),
    db: aiosqlite.Connection = Depends(get_db),
):
    """驳回号码申诉"""
    now = int(time.time() * 1000)
    async with db.execute("SELECT id FROM number_appeals WHERE id = ?", (appeal_id,)) as cur:
        appeal = await cur.fetchone()
        if not appeal:
            return APIResponse.error(code=40401, message=f"未找到申诉记录: {appeal_id}")

    notes = review_notes or "证据不足，维持当前标记"
    await db.execute(
        "UPDATE number_appeals SET status = 'rejected', review_notes = ?, reviewed_at = ? WHERE id = ?",
        (notes, now, appeal_id),
    )
    await db.commit()
    return APIResponse.ok(data={"appeal_id": appeal_id, "status": "rejected"})

# MARK: - 算法与风控动态配置

@router.get("/algorithm-config", response_model=APIResponse[AlgorithmConfigData])
async def get_algorithm_config(db: aiosqlite.Connection = Depends(get_db)):
    """获取动态算法与风控参数配置字典"""
    configs = {}
    descriptions = {}
    async with db.execute("SELECT key, value, description FROM system_configs") as cur:
        async for row in cur:
            configs[row["key"]] = row["value"]
            descriptions[row["key"]] = row["description"] or ""

    return APIResponse.ok(data=AlgorithmConfigData(configs=configs, descriptions=descriptions))

@router.put("/algorithm-config", response_model=APIResponse[dict])
async def update_algorithm_config(
    payload: AlgorithmConfigUpdateRequest,
    db: aiosqlite.Connection = Depends(get_db),
):
    """更新算法与风控参数配置（半衰期天数、置信度门限等）"""
    now = int(time.time() * 1000)
    for key, value in payload.configs.items():
        await db.execute(
            "UPDATE system_configs SET value = ?, updated_at = ? WHERE key = ?;",
            (str(value), now, key),
        )
    await db.commit()
    return APIResponse.ok(data={"status": "updated", "updated_keys": list(payload.configs.keys())})

# MARK: - 发布新版本

@router.post("/publish-version", response_model=APIResponse[dict])
async def publish_new_version(
    db: aiosqlite.Connection = Depends(get_db),
):
    """以当前时间戳 (YYYYMMDDHHmm) 原子发布新版本，保证数值严格单调递增并触发差量同步"""
    now = int(time.time() * 1000)
    time_version = generate_time_version()

    async with db.execute("SELECT value FROM sync_metadata WHERE key = 'current_version'") as v_cur:
        v_row = await v_cur.fetchone()
        current_version = int(v_row["value"]) if v_row else 1

    # 保证严格递增
    new_version = max(current_version + 1, time_version)

    # 更新元数据
    await db.execute("UPDATE sync_metadata SET value = ? WHERE key = 'current_version';", (str(new_version),))
    await db.execute("UPDATE sync_metadata SET value = ? WHERE key = 'updated_at';", (str(now),))

    await db.commit()

    return APIResponse.ok(
        data={
            "previous_version": current_version,
            "new_version": new_version,
            "published_at": now,
        }
    )

# MARK: - CSV 数据导出与批量导入 (基于 10 核心物理字段大宽表)

@router.get("/export/csv")
async def export_numbers_csv(
    db: aiosqlite.Connection = Depends(get_db),
):
    """
    全量导出号码数据为标准 CSV 文件 (UTF-8 BOM 编码，适配 Excel 及各大表格软件，零乱码)
    表头 10 列：numeric_phone,label,call_action,call_category,sms_action,sms_sub_action,confidence,is_official,updated_at,created_at
    """
    query = """
    SELECT numeric_phone, label, call_action, call_category, sms_action, sms_sub_action, confidence, 1 as is_official, updated_at, created_at
    FROM numbers_directory
    WHERE is_deleted = 0
    ORDER BY numeric_phone ASC;
    """

    output = io.StringIO()
    # 写入 UTF-8 BOM 确保 Windows/Mac Excel 打开中文不乱码
    output.write("\ufeff")
    writer = csv.writer(output)

    headers = [
        "numeric_phone",
        "label",
        "call_action",
        "call_category",
        "sms_action",
        "sms_sub_action",
        "confidence",
        "is_official",
        "updated_at",
        "created_at",
    ]
    writer.writerow(headers)

    async with db.execute(query) as cursor:
        async for row in cursor:
            writer.writerow([
                row["numeric_phone"],
                row["label"],
                row["call_action"],
                row["call_category"],
                row["sms_action"],
                row["sms_sub_action"],
                row["confidence"],
                row["is_official"],
                row["updated_at"],
                row["created_at"],
            ])

    csv_content = output.getvalue()
    now_str = time.strftime("%Y%m%d_%H%M%S")
    filename = f"yellowpages_export_{now_str}.csv"

    return Response(
        content=csv_content.encode("utf-8"),
        media_type="text/csv; charset=utf-8",
        headers={
            "Content-Disposition": f'attachment; filename="{filename}"',
            "Access-Control-Expose-Headers": "Content-Disposition",
        },
    )

@router.post("/import/csv", response_model=APIResponse[CsvImportStats])
async def import_numbers_csv(
    file: Optional[UploadFile] = File(None),
    csv_text: Optional[str] = Form(None),
    mode: str = Form("incremental", description="full: 全量覆盖导入 | incremental: 增量合并"),
    db: aiosqlite.Connection = Depends(get_db),
):
    """
    批量导入 CSV 号码数据，支持文件上传与文本直接粘贴。
    灵活支持标准 10 列表头或常见别名（numeric_phone, label, call_action, call_category...）。
    """
    raw_content = ""
    if file and file.filename:
        content_bytes = await file.read()
        for encoding in ["utf-8-sig", "utf-8", "gb18030", "gbk", "latin1"]:
            try:
                raw_content = content_bytes.decode(encoding)
                break
            except UnicodeDecodeError:
                continue
        if not raw_content:
            raw_content = content_bytes.decode("utf-8", errors="replace")
    elif csv_text:
        raw_content = csv_text

    if not raw_content.strip():
        return APIResponse.error(code=40001, message="未检测到任何有效的 CSV 文件内容或文本")

    if raw_content.startswith("\ufeff"):
        raw_content = raw_content[1:]

    reader = csv.reader(io.StringIO(raw_content))
    rows = [r for r in reader if r and any(field.strip() for field in r)]
    if not rows:
        return APIResponse.error(code=40001, message="CSV 内容为空")

    header = [c.strip().lower() for c in rows[0]]
    data_rows = rows[1:]

    def find_idx(col_names: list[str]) -> int:
        for name in col_names:
            if name in header:
                return header.index(name)
        return -1

    phone_idx = find_idx(["numeric_phone", "phone", "phone_number", "number", "号码", "电话"])
    label_idx = find_idx(["label", "name", "org_name", "机构名称", "名称", "标识"])
    call_act_idx = find_idx(["call_action", "action", "电话动作", "动作"])
    call_cat_idx = find_idx(["call_category", "category", "分类", "电话分类"])
    sms_act_idx = find_idx(["sms_action", "短信动作"])
    sms_sub_idx = find_idx(["sms_sub_action", "sms_sub", "短信细分"])
    conf_idx = find_idx(["confidence", "置信度"])

    # 若第一行不是表头而是数据
    has_header = phone_idx != -1 or label_idx != -1
    if not has_header:
        data_rows = rows
        phone_idx = 0
        label_idx = 1 if len(rows[0]) > 1 else -1
        call_act_idx = 2 if len(rows[0]) > 2 else -1
        call_cat_idx = 3 if len(rows[0]) > 3 else -1
        sms_act_idx = 4 if len(rows[0]) > 4 else -1
        sms_sub_idx = 5 if len(rows[0]) > 5 else -1
        conf_idx = 6 if len(rows[0]) > 6 else -1

    parsed_records = []
    skipped_count = 0

    for row in data_rows:
        try:
            raw_phone_str = row[phone_idx].strip() if phone_idx < len(row) else ""
            digits_only = "".join(filter(str.isdigit, raw_phone_str))
            if not digits_only:
                skipped_count += 1
                continue
            numeric_phone = int(digits_only)

            raw_label = row[label_idx].strip() if (label_idx != -1 and label_idx < len(row)) else "未知机构"
            if not raw_label:
                raw_label = "未知机构"

            call_action_val = 0
            if call_act_idx != -1 and call_act_idx < len(row):
                act_str = row[call_act_idx].strip().lower()
                if act_str in ["1", "block", "拦截", "阻止拦截"]:
                    call_action_val = 1

            call_cat = "enterprise"
            if call_cat_idx != -1 and call_cat_idx < len(row):
                cat_val = row[call_cat_idx].strip().lower()
                if cat_val:
                    call_cat = cat_val

            sms_act = 2 if call_action_val == 1 else (3 if call_cat in ["marketing", "real_estate", "finance_loan"] else 4)
            if sms_act_idx != -1 and sms_act_idx < len(row):
                try:
                    sms_act = int(row[sms_act_idx].strip())
                except ValueError:
                    pass

            sms_sub = 0 if call_action_val == 1 else 10001
            if sms_sub_idx != -1 and sms_sub_idx < len(row):
                try:
                    sms_sub = int(row[sms_sub_idx].strip())
                except ValueError:
                    pass

            confidence = 1.0
            if conf_idx != -1 and conf_idx < len(row):
                try:
                    confidence = float(row[conf_idx].strip())
                except ValueError:
                    pass

            parsed_records.append({
                "numeric_phone": numeric_phone,
                "label": raw_label,
                "call_action": call_action_val,
                "call_category": call_cat,
                "sms_action": sms_act,
                "sms_sub_action": sms_sub,
                "confidence": confidence,
            })
        except Exception:
            skipped_count += 1
            continue

    if not parsed_records:
        return APIResponse.error(code=40001, message=f"未能从 CSV 中解析出任何有效号码（跳过无效行 {skipped_count} 条）")

    # 去重并排序 (按 numeric_phone 升序)
    unique_map = {}
    for r in parsed_records:
        unique_map[r["numeric_phone"]] = r
    sorted_records = sorted(unique_map.values(), key=lambda x: x["numeric_phone"])

    now = int(time.time() * 1000)
    time_version = generate_time_version()

    async with db.execute("SELECT value FROM sync_metadata WHERE key = 'current_version'") as v_cur:
        v_row = await v_cur.fetchone()
        current_version = int(v_row["value"]) if v_row else 1

    new_version = max(current_version + 1, time_version)
    imported_count = 0
    updated_count = 0

    if mode == "full":
        await db.execute("DELETE FROM numbers_directory;")
        await db.execute("DELETE FROM numbers_delta_log;")

        for item in sorted_records:
            await db.execute(
                """
                INSERT INTO numbers_directory (
                    numeric_phone, label, call_action, call_category, sms_action, sms_sub_action, confidence, is_deleted, updated_at, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?);
                """,
                (
                    item["numeric_phone"],
                    item["label"],
                    item["call_action"],
                    item["call_category"],
                    item["sms_action"],
                    item["sms_sub_action"],
                    item["confidence"],
                    now,
                    now,
                ),
            )
            await db.execute(
                """
                INSERT INTO numbers_delta_log (
                    version, numeric_phone, op, label, call_action, call_category, sms_action, sms_sub_action, updated_at
                ) VALUES (?, ?, 'add', ?, ?, ?, ?, ?, ?);
                """,
                (
                    new_version,
                    item["numeric_phone"],
                    item["label"],
                    item["call_action"],
                    item["call_category"],
                    item["sms_action"],
                    item["sms_sub_action"],
                    now,
                ),
            )
            imported_count += 1
    else:
        for item in sorted_records:
            num = item["numeric_phone"]
            async with db.execute(
                "SELECT numeric_phone FROM numbers_directory WHERE numeric_phone = ?",
                (num,),
            ) as chk_cur:
                existing = await chk_cur.fetchone()

            if existing:
                await db.execute(
                    """
                    UPDATE numbers_directory
                    SET label = ?, call_action = ?, call_category = ?, sms_action = ?, sms_sub_action = ?, confidence = ?, updated_at = ?, is_deleted = 0
                    WHERE numeric_phone = ?;
                    """,
                    (
                        item["label"],
                        item["call_action"],
                        item["call_category"],
                        item["sms_action"],
                        item["sms_sub_action"],
                        item["confidence"],
                        now,
                        num,
                    ),
                )
                await db.execute(
                    """
                    INSERT INTO numbers_delta_log (
                        version, numeric_phone, op, label, call_action, call_category, sms_action, sms_sub_action, updated_at
                    ) VALUES (?, ?, 'update', ?, ?, ?, ?, ?, ?);
                    """,
                    (
                        new_version,
                        num,
                        item["label"],
                        item["call_action"],
                        item["call_category"],
                        item["sms_action"],
                        item["sms_sub_action"],
                        now,
                    ),
                )
                updated_count += 1
            else:
                await db.execute(
                    """
                    INSERT INTO numbers_directory (
                        numeric_phone, label, call_action, call_category, sms_action, sms_sub_action, confidence, is_deleted, updated_at, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?);
                    """,
                    (
                        num,
                        item["label"],
                        item["call_action"],
                        item["call_category"],
                        item["sms_action"],
                        item["sms_sub_action"],
                        item["confidence"],
                        now,
                        now,
                    ),
                )
                await db.execute(
                    """
                    INSERT INTO numbers_delta_log (
                        version, numeric_phone, op, label, call_action, call_category, sms_action, sms_sub_action, updated_at
                    ) VALUES (?, ?, 'add', ?, ?, ?, ?, ?, ?);
                    """,
                    (
                        new_version,
                        num,
                        item["label"],
                        item["call_action"],
                        item["call_category"],
                        item["sms_action"],
                        item["sms_sub_action"],
                        now,
                    ),
                )
                imported_count += 1

    await db.execute("UPDATE sync_metadata SET value = ? WHERE key = 'current_version';", (str(new_version),))
    await db.execute("UPDATE sync_metadata SET value = ? WHERE key = 'updated_at';", (str(now),))
    await db.commit()

    stats = CsvImportStats(
        mode=mode,
        total_rows=len(data_rows),
        imported_count=imported_count,
        updated_count=updated_count,
        skipped_count=skipped_count,
        new_version=new_version,
    )
    return APIResponse.ok(data=stats)

# MARK: - 匿名设备信用画像管理

@router.get("/devices", response_model=APIResponse[dict])
async def list_admin_devices(
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    keyword: Optional[str] = Query(None),
    credit_level: Optional[str] = Query(None),
    is_blocked: Optional[int] = Query(None),
    db: aiosqlite.Connection = Depends(get_db),
):
    """分页查询所有接入客户端匿名设备信誉档案"""
    offset = (page - 1) * limit
    where_clauses = []
    params: List[Any] = []

    if keyword:
        where_clauses.append("(device_fingerprint LIKE ? OR device_name LIKE ?)")
        params.extend([f"%{keyword}%", f"%{keyword}%"])
    if credit_level:
        where_clauses.append("credit_level = ?")
        params.append(credit_level)
    if is_blocked is not None:
        where_clauses.append("is_blocked = ?")
        params.append(is_blocked)

    where_str = f"WHERE {' AND '.join(where_clauses)}" if where_clauses else ""

    count_sql = f"SELECT COUNT(1) as total FROM device_profiles {where_str}"
    async with db.execute(count_sql, params) as c_cur:
        c_row = await c_cur.fetchone()
        total = c_row["total"] if c_row else 0

    query_sql = f"""
    SELECT device_fingerprint, device_name, platform, reputation_score, credit_level,
           total_reports, approved_reports, rejected_reports, total_appeals, is_blocked,
           first_seen_at, last_active_at
    FROM device_profiles
    {where_str}
    ORDER BY last_active_at DESC
    LIMIT ? OFFSET ?;
    """
    params.extend([limit, offset])

    items = []
    async with db.execute(query_sql, params) as cur:
        async for row in cur:
            items.append(
                AdminDeviceItem(
                    device_fingerprint=row["device_fingerprint"],
                    device_name=row["device_name"],
                    platform=row["platform"],
                    reputation_score=row["reputation_score"],
                    credit_level=row["credit_level"],
                    total_reports=row["total_reports"],
                    approved_reports=row["approved_reports"],
                    rejected_reports=row["rejected_reports"],
                    total_appeals=row["total_appeals"],
                    is_blocked=bool(row["is_blocked"]),
                    first_seen_at=row["first_seen_at"],
                    last_active_at=row["last_active_at"],
                ).model_dump()
            )

    return APIResponse.ok(data={"page": page, "limit": limit, "total": total, "items": items})

@router.post("/devices/{fingerprint}/block", response_model=APIResponse[dict])
async def block_device(
    fingerprint: str = Path(..., description="设备指纹 SHA-256"),
    db: aiosqlite.Connection = Depends(get_db),
):
    """封禁恶意/作弊设备（标记为黑名单，其上报与申诉将被系统拦截忽略）"""
    await db.execute(
        "UPDATE device_profiles SET is_blocked = 1, reputation_score = 0.0, credit_level = 'poor' WHERE device_fingerprint = ?;",
        (fingerprint,),
    )
    await db.commit()
    return APIResponse.ok(data={"device_fingerprint": fingerprint, "is_blocked": True})

@router.post("/devices/{fingerprint}/unblock", response_model=APIResponse[dict])
async def unblock_device(
    fingerprint: str = Path(..., description="设备指纹 SHA-256"),
    db: aiosqlite.Connection = Depends(get_db),
):
    """解封设备并恢复良好信用"""
    await db.execute(
        "UPDATE device_profiles SET is_blocked = 0, reputation_score = 80.0, credit_level = 'good' WHERE device_fingerprint = ?;",
        (fingerprint,),
    )
    await db.commit()
    return APIResponse.ok(data={"device_fingerprint": fingerprint, "is_blocked": False})

@router.post("/devices/{fingerprint}/reset-reputation", response_model=APIResponse[dict])
async def reset_device_reputation(
    fingerprint: str = Path(..., description="设备指纹 SHA-256"),
    db: aiosqlite.Connection = Depends(get_db),
):
    """一键重置指定设备的信誉评级（置为 100 分极佳，解除封禁）"""
    now = int(time.time() * 1000)
    async with db.execute("SELECT 1 FROM device_profiles WHERE device_fingerprint = ?", (fingerprint,)) as cur:
        row = await cur.fetchone()
        if not row:
            return APIResponse.error(code=40401, message=f"未找到对应设备记录: {fingerprint}")

    await db.execute(
        """
        UPDATE device_profiles
        SET reputation_score = 100.0, credit_level = 'excellent', is_blocked = 0, last_active_at = ?
        WHERE device_fingerprint = ?;
        """,
        (now, fingerprint),
    )
    await db.commit()
    return APIResponse.ok(data={"device_fingerprint": fingerprint, "reputation_score": 100.0, "credit_level": "excellent", "status": "reset"})

@router.delete("/devices/{fingerprint}", response_model=APIResponse[dict])
async def delete_device(
    fingerprint: str = Path(..., description="设备指纹 SHA-256"),
    db: aiosqlite.Connection = Depends(get_db),
):
    """彻底删除并解绑指定设备记录"""
    async with db.execute("SELECT 1 FROM device_profiles WHERE device_fingerprint = ?", (fingerprint,)) as cur:
        row = await cur.fetchone()
        if not row:
            return APIResponse.error(code=40401, message=f"未找到对应设备记录: {fingerprint}")

    await db.execute("DELETE FROM device_profiles WHERE device_fingerprint = ?;", (fingerprint,))
    await db.commit()
    return APIResponse.ok(data={"device_fingerprint": fingerprint, "status": "deleted"})
