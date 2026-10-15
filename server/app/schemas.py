import time
from typing import Any, Optional, List, Generic, TypeVar
from pydantic import BaseModel, Field

T = TypeVar("T")

class APIResponse(BaseModel, Generic[T]):
    code: int = 0
    message: str = "success"
    data: Optional[T] = None
    timestamp: int = Field(default_factory=lambda: int(time.time() * 1000))

    @classmethod
    def ok(cls, data: Optional[T] = None, message: str = "success") -> "APIResponse[T]":
        return cls(code=0, message=message, data=data)

    @classmethod
    def error(cls, code: int = 40001, message: str = "error") -> "APIResponse[Any]":
        return cls(code=code, message=message, data=None)

# MARK: - 同步相关 Schema

class DeviceProfileSummary(BaseModel):
    device_fingerprint: str
    credit_level: str
    credit_level_name: str
    reputation_score: float
    total_reports: int = 0
    approved_reports: int = 0
    is_blocked: bool = False

class SyncMetadataData(BaseModel):
    current_version: int
    latest_version: int
    min_supported_version: int = 1
    total_count: int
    identification_count: int
    blocking_count: int
    full_sync_chunks: int
    chunk_size: int
    recommended_chunk_size: int
    latest_updated_at: str
    updated_at: str
    device_profile: Optional[DeviceProfileSummary] = None

class PhoneNumberRecord(BaseModel):
    numeric_phone: int
    phone_number: str
    label: str
    call_action: int = 0
    call_category: str
    sms_action: int = 4
    sms_sub_action: int = 0
    confidence: float = 1.0
    action: str = "identification"
    category: str = "enterprise"
    is_blocking: bool = False
    updated_at: int = 0
    created_at: Optional[int] = None

class SyncFullData(BaseModel):
    version: int
    chunk_index: int
    total_chunks: int
    has_more: bool
    records: List[PhoneNumberRecord]

class DeltaItem(BaseModel):
    op: str
    numeric_phone: int
    phone_number: str
    label: Optional[str] = None
    call_action: Optional[int] = 0
    call_category: Optional[str] = None
    sms_action: Optional[int] = 4
    sms_sub_action: Optional[int] = 0
    confidence: float = 1.0
    action: Optional[str] = "identification"
    category: Optional[str] = "enterprise"
    is_blocking: bool = False
    updated_at: int = 0

class SyncDeltaData(BaseModel):
    base_version: int
    target_version: int
    require_full_reload: bool
    next_cursor: Optional[str] = None
    has_more: bool = False
    changes: List[DeltaItem]

# MARK: - 反查相关 Schema

class LocationInfo(BaseModel):
    province: Optional[str] = None
    city: Optional[str] = None

class TagInfo(BaseModel):
    label: str
    category: str
    confidence: float = 1.0
    source_type: str = "official"  # official / community / custom
    is_official: bool = True
    is_blocking: bool = False
    call_action: Optional[str] = "identify"          # identify / block
    call_action_label: Optional[str] = "身份识别"    # 身份识别 / 阻止拦截
    primary_action: Optional[str] = "none"           # none / allow / transaction / promotion / junk
    primary_action_label: Optional[str] = "允许放行" # 交易与服务 / 商业推广 / 垃圾短信拦截 / 允许放行
    primary_action_code: Optional[int] = 1           # 0, 1, 2, 3, 4
    sub_action: Optional[str] = "none"               # orders / finance / public_services / offers / others / none
    sub_action_label: Optional[str] = "无"           # 订单物流 / 金融银行 / 公共政务服务 / 优惠活动 / 其他推广 / 无
    sub_action_code: Optional[int] = 0               # 0, 10001, 10002, 10008, 20000, 20001

class RiskInfo(BaseModel):
    level: str = "none"
    score: float = 0.0
    report_count: int = 0

class NumberLookupResult(BaseModel):
    phone_number: str
    numeric_phone: int
    formatted: str
    country_code: str = "CN"
    carrier: Optional[str] = None
    location: Optional[LocationInfo] = None
    tag_info: Optional[TagInfo] = None
    risk_info: Optional[RiskInfo] = None
    found: bool = False

class BatchLookupRequest(BaseModel):
    phone_numbers: List[str]

class BatchLookupItem(BaseModel):
    phone_number: str
    found: bool
    label: Optional[str] = None
    category: Optional[str] = None
    confidence: float = 0.0
    is_blocking: bool = False

class BatchLookupData(BaseModel):
    results: List[BatchLookupItem]

# MARK: - 举报上报相关 Schema

class ReportCreateRequest(BaseModel):
    phone_number: str
    report_type: str = "call"
    channel: Optional[str] = None
    category: Optional[str] = None
    call_category: Optional[str] = None
    sms_category: Optional[str] = None
    sms_primary_action: Optional[int] = None
    sms_sub_action: Optional[int] = None
    label: Optional[str] = None
    suggested_label: Optional[str] = None
    custom_label: Optional[str] = None
    content_snippet: Optional[str] = None
    device_fingerprint: Optional[str] = None
    reported_at: Optional[str] = None
    client_timestamp: Optional[int] = None
    action_suggested: str = "identify"

class ReportResponseData(BaseModel):
    report_id: int
    status: str
    accepted: bool = True

# MARK: - 号码申诉与纠错相关 Schema

class AppealCreateRequest(BaseModel):
    phone_number: str
    appeal_type: str = "false_spam"
    reason: str
    contact_phone: Optional[str] = None
    contact_email: Optional[str] = None
    contact_info: Optional[str] = None
    proof_snippet: Optional[str] = None

class AppealResponseData(BaseModel):
    appeal_id: int
    status: str = "pending"
    accepted: bool = True
    message: str = "申诉已提交，我们将尽快核实处理并下发纠错更新"

class AdminAppealItem(BaseModel):
    id: int
    numeric_phone: int
    raw_phone: Optional[str]
    appeal_type: str
    reason: str
    contact_info: str
    contact_phone: Optional[str] = None
    contact_email: Optional[str] = None
    proof_snippet: Optional[str]
    status: str
    review_notes: Optional[str]
    created_at: int
    reviewed_at: Optional[int]

# MARK: - 管理控制台相关 Schema

class AdminNumberCreate(BaseModel):
    numeric_phone: int
    raw_phone: Optional[str] = None
    label: str
    call_action: int = 0
    call_category: str = "enterprise"
    sms_action: int = 4
    sms_sub_action: int = 0
    confidence: float = 1.0

class AdminNumberUpdate(BaseModel):
    label: Optional[str] = None
    call_action: Optional[int] = None
    call_category: Optional[str] = None
    sms_action: Optional[int] = None
    sms_sub_action: Optional[int] = None
    confidence: Optional[float] = None

class AdminNumberItem(BaseModel):
    numeric_phone: int
    raw_phone: Optional[str] = None
    label: str
    call_action: int = 0
    call_category: str
    sms_action: int = 4
    sms_sub_action: int = 0
    confidence: float = 1.0
    action: str = "identify"
    category: str = "enterprise"
    version: int = 0
    updated_at: int
    created_at: Optional[int] = None
    is_deleted: bool = False
    deleted_at: Optional[int] = None

# MARK: - 算法与风控动态配置相关 Schema

class AlgorithmConfigData(BaseModel):
    configs: dict[str, str]
    descriptions: dict[str, str]

class AlgorithmConfigUpdateRequest(BaseModel):
    configs: dict[str, str]

# MARK: - CSV 数据导入相关 Schema

class CsvImportStats(BaseModel):
    mode: str
    total_rows: int
    imported_count: int
    updated_count: int = 0
    skipped_count: int = 0
    new_version: int

# MARK: - 匿名设备信用画像管理 Schema

class AdminDeviceItem(BaseModel):
    device_fingerprint: str
    device_name: Optional[str]
    platform: str = "iOS"
    reputation_score: float = 100.0
    credit_level: str = "excellent"
    total_reports: int = 0
    approved_reports: int = 0
    rejected_reports: int = 0
    total_appeals: int = 0
    is_blocked: bool = False
    first_seen_at: int
    last_active_at: int

class AdminReportItem(BaseModel):
    id: int
    numeric_phone: int
    raw_phone: Optional[str]
    channel: str
    category: str
    suggested_label: Optional[str]
    content_snippet: Optional[str]
    device_fingerprint: Optional[str]
    status: str
    created_at: int
