<template>
  <div class="console-root">
    <!-- 顶部状态导航栏 (Apple Engineering Bar) -->
    <header class="console-header">
      <div class="header-left">
        <div class="brand-logo">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <rect x="3" y="3" width="18" height="18" rx="4" />
            <path d="M7 8h10M7 12h10M7 16h6" />
          </svg>
        </div>
        <div class="brand-info">
          <span class="brand-title">YellowPages</span>
          <span class="brand-subtitle">管理控制台</span>
        </div>
      </div>

      <nav class="nav-tabs">
        <button 
          v-for="tab in tabs" 
          :key="tab.id"
          class="nav-tab-btn" 
          :class="{ active: currentTab === tab.id }"
          @click="currentTab = tab.id"
        >
          {{ tab.name }}
          <span v-if="tab.badge !== undefined" class="tab-badge">{{ tab.badge }}</span>
        </button>
      </nav>

      <div class="header-right">
        <span class="system-indicator">
          <span class="pulse-dot"></span>
          服务正常运行 (8080)
        </span>
        <button class="btn btn-sm" @click="refreshCurrentTab">刷新数据</button>
      </div>
    </header>

    <!-- 主工作区容器 -->
    <main class="console-main">
      <!-- 面板 1：数据版本发布与同步概览 -->
      <section v-if="currentTab === 'overview'" class="tab-panel">
        <div class="panel-header-section">
          <div>
            <h2 class="panel-title">数据版本发布与同步概览</h2>
            <p class="panel-desc">管理离线号码识别数据库版本，生成原子增量更新并调度发布。</p>
          </div>
          <button class="btn btn-primary" :disabled="isPublishing" @click="handlePublishVersion">
            <span v-if="isPublishing">正在发布中...</span>
            <span v-else>发布新版本</span>
          </button>
        </div>

        <!-- 关键指标矩阵 -->
        <div class="kpi-grid">
          <div class="kpi-card">
            <div class="kpi-title">当前版本库</div>
            <div class="kpi-value font-mono">v{{ metadata.current_version || 1 }}</div>
            <div class="kpi-sub">全量分片: {{ metadata.full_sync_chunks || 1 }} 组</div>
          </div>
          <div class="kpi-card">
            <div class="kpi-title">总收录规则条数</div>
            <div class="kpi-value font-mono">{{ (metadata.total_count || 0).toLocaleString() }}</div>
            <div class="kpi-sub">分片容量: {{ (metadata.chunk_size || 50000).toLocaleString() }} 条/片</div>
          </div>
          <div class="kpi-card">
            <div class="kpi-title">主动阻止规则</div>
            <div class="kpi-value font-mono text-danger">{{ (metadata.blocking_count || 0).toLocaleString() }}</div>
            <div class="kpi-sub">离线静默拦截号码</div>
          </div>
          <div class="kpi-card">
            <div class="kpi-title">身份识别规则</div>
            <div class="kpi-value font-mono text-success">{{ (metadata.identification_count || 0).toLocaleString() }}</div>
            <div class="kpi-sub">企业黄页与机构标识</div>
          </div>
        </div>

        <!-- 增量同步与全量分片架构说明卡片 -->
        <div class="content-box">
          <div class="box-header">
            <h3>号码识别与拦截同步架构说明</h3>
          </div>
          <div class="box-body font-mono-desc">
            <div class="desc-row">
              <span class="desc-k">号码格式规范:</span>
              <span class="desc-v">国际标准纯数字编码 · 分片二进制数据流</span>
            </div>
            <div class="desc-row">
              <span class="desc-k">增量更新策略:</span>
              <span class="desc-v">基于增量流水日志原子追踪新增、修改与移除操作</span>
            </div>
            <div class="desc-row">
              <span class="desc-k">最后发布时间:</span>
              <span class="desc-v">{{ formatTimestamp(metadata.latest_updated_at || metadata.updated_at) }}</span>
            </div>
          </div>
        </div>
      </section>

      <!-- 面板 2：号码规则库管理 (CRUD & 搜索) -->
      <section v-if="currentTab === 'numbers'" class="tab-panel">
        <div class="panel-header-section">
          <div>
            <h2 class="panel-title">号码规则库管理</h2>
            <p class="panel-desc">检索、录入及维护离线号码识别与拦截规则库。</p>
          </div>
          <button class="btn btn-primary" @click="openCreateNumberModal">新增收录号码</button>
        </div>

        <!-- 筛选栏 -->
        <div class="filter-toolbar">
          <div class="toolbar-group">
            <input 
              v-model="numberFilter.keyword" 
              type="text" 
              class="input-text" 
              placeholder="搜索电话号码或机构名称..."
              @keyup.enter="fetchNumbers(1)"
            />
            <select v-model="numberFilter.category" class="input-text" @change="fetchNumbers(1)">
              <option value="">全部分类</option>
              <option v-for="(name, key) in categoryMap" :key="key" :value="key">{{ name }}</option>
            </select>
            <select v-model="numberFilter.action" class="input-text" @change="fetchNumbers(1)">
              <option value="">全部动作</option>
              <option value="identify">识别展示</option>
              <option value="block">阻止拦截</option>
            </select>
            <select v-model="numberFilter.status_filter" class="input-text" @change="fetchNumbers(1)">
              <option value="active">活跃号码库</option>
              <option value="deleted">已下架归档</option>
              <option value="all">全部状态 (包含已下架)</option>
            </select>
            <button class="btn" @click="fetchNumbers(1)">查询</button>
            <button class="btn" @click="resetNumberFilter">重置</button>
          </div>

          <div class="toolbar-stats">
            共 <span class="font-mono">{{ numberTable.total }}</span> 条记录
          </div>
        </div>

        <!-- 紧凑高密度数据报表 -->
        <div class="table-container">
          <table class="report-table">
            <thead>
              <tr>
                <th style="width: 150px;">电话号码 (纯数字)</th>
                <th style="width: 200px;">机构与号码名称</th>
                <th style="width: 150px;">电话分类与动作</th>
                <th style="width: 210px;">信息分流标签</th>
                <th style="width: 80px;">置信度</th>
                <th style="width: 140px;">更新时间</th>
                <th style="width: 140px; text-align: right;">操作</th>
              </tr>
            </thead>
            <tbody>
              <tr v-if="numberTable.loading">
                <td colspan="7" class="table-empty">正在加载数据...</td>
              </tr>
              <tr v-else-if="numberTable.items.length === 0">
                <td colspan="7" class="table-empty">暂无匹配的号码数据</td>
              </tr>
              <tr v-for="item in numberTable.items" :key="item.numeric_phone">
                <td class="font-mono font-bold">{{ item.numeric_phone }}</td>
                <td>
                  <span class="font-medium">{{ item.label }}</span>
                  <span v-if="item.is_deleted" class="badge badge-red" style="margin-left: 6px; font-size: 10px;">已下架</span>
                </td>
                <td>
                  <div class="flex items-center gap-1">
                    <span class="badge badge-gray">{{ categoryMap[item.call_category || item.category] || item.call_category || item.category }}</span>
                    <span class="badge" :class="(item.call_action === 1 || item.action === 'block') ? 'badge-red' : 'badge-blue'">
                      {{ (item.call_action === 1 || item.action === 'block') ? '拦截' : '识别' }}
                    </span>
                  </div>
                </td>
                <td>
                  <div class="font-mono text-secondary" style="font-size: 11px;">
                    {{ formatSmsAction(item.sms_action, item.sms_sub_action) }}
                  </div>
                </td>
                <td class="font-mono">
                  <span :class="item.confidence >= 0.8 ? 'text-success' : 'text-warning'">
                    {{ Math.round(item.confidence * 100) }}%
                  </span>
                </td>
                <td class="font-mono text-secondary">{{ formatTimestamp(item.updated_at) }}</td>
                <td style="text-align: right;">
                  <template v-if="item.is_deleted">
                    <button class="btn btn-xs btn-success" @click="handleRestoreNumber(item)">恢复上架</button>
                  </template>
                  <template v-else>
                    <button class="btn btn-xs" @click="openEditNumberModal(item)">编辑</button>
                    <button class="btn btn-xs btn-danger" @click="handleDeleteNumber(item)">下架</button>
                  </template>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <!-- 分页控件 -->
        <div class="pagination-bar">
          <button class="btn btn-sm" :disabled="numberTable.page <= 1" @click="fetchNumbers(numberTable.page - 1)">上一页</button>
          <span class="page-indicator font-mono">
            第 {{ numberTable.page }} / {{ Math.max(1, Math.ceil(numberTable.total / numberTable.limit)) }} 页
          </span>
          <button class="btn btn-sm" :disabled="numberTable.page >= Math.ceil(numberTable.total / numberTable.limit)" @click="fetchNumbers(numberTable.page + 1)">下一页</button>
        </div>
      </section>

      <!-- 面板 3：数据导入与导出 (CSV) -->
      <section v-if="currentTab === 'data_io'" class="tab-panel">
        <div class="panel-header-section">
          <div>
            <h2 class="panel-title">数据导入与导出 (CSV)</h2>
            <p class="panel-desc">支持号码规则库标准 CSV 格式的一键导出下载与批量导入，保障系统数据原子更新。</p>
          </div>
        </div>

        <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(360px, 1fr)); gap: 20px;">
          <!-- 卡片 1: 全量号码数据导出 -->
          <div class="content-box">
            <div class="box-header">
              <h3>全量号码数据导出</h3>
            </div>
            <div class="box-body" style="display: flex; flex-direction: column; gap: 14px;">
              <p class="text-secondary" style="font-size: 13px; line-height: 1.6;">
                将数据库中全部有效号码导出为标准 CSV 表格文件（适配 Excel、Numbers 等常见办公软件，中文编码自动兼容）。
              </p>

              <div style="background: var(--bg-subtle); border: 1px solid var(--border-color); padding: 12px; border-radius: var(--radius-md);">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px;">
                  <span class="text-secondary" style="font-size: 12px;">当前有效号码总数:</span>
                  <span class="font-mono font-bold text-primary" style="font-size: 16px;">{{ metadata.total_count }} 条</span>
                </div>
                <div style="display: flex; justify-content: space-between; align-items: center; font-size: 11px;">
                  <span class="text-muted">当前数据版本:</span>
                  <span class="font-mono text-muted">v{{ metadata.current_version }}</span>
                </div>
              </div>

              <div style="font-size: 11px; color: var(--text-secondary); line-height: 1.5;">
                <div class="font-bold" style="margin-bottom: 4px;">导出包含的标准字段列表：</div>
                <code class="font-mono text-muted" style="word-break: break-all; font-size: 10px;">
                  numeric_phone, label, call_action, call_category, sms_action, sms_sub_action, confidence, is_official, updated_at, created_at
                </code>
              </div>

              <div style="margin-top: auto; padding-top: 10px;">
                <button class="btn btn-primary" style="width: 100%; padding: 10px;" @click="handleExportCsv">
                  导出全量号码 CSV 文件
                </button>
              </div>
            </div>
          </div>

          <!-- 卡片 2: 号码数据批量导入 -->
          <div class="content-box">
            <div class="box-header">
              <h3>号码数据批量导入</h3>
            </div>
            <div class="box-body" style="display: flex; flex-direction: column; gap: 14px;">
              <!-- 导入模式选择 -->
              <div class="mode-selector-grid" style="margin-bottom: 0;">
                <div 
                  class="mode-card" 
                  :class="{ 'mode-card-selected': csvForm.mode === 'incremental' }"
                  style="padding: 10px 12px;"
                  @click="csvForm.mode = 'incremental'"
                >
                  <div class="mode-card-header" style="margin-bottom: 4px;">
                    <span class="badge badge-green" style="font-size: 10px;">推荐</span>
                    <div class="radio-indicator" :class="{ 'radio-checked': csvForm.mode === 'incremental' }">
                      <div v-if="csvForm.mode === 'incremental'" class="radio-dot"></div>
                    </div>
                  </div>
                  <h4 style="margin: 0 0 2px 0; font-size: 12px;">增量合并导入</h4>
                  <p class="mode-card-desc" style="font-size: 10px; margin: 0;">保留现有号码库，按电话号码更新已有条目，追加新增条目并记录增量流水。</p>
                </div>

                <div 
                  class="mode-card" 
                  :class="{ 'mode-card-selected': csvForm.mode === 'full' }"
                  style="padding: 10px 12px;"
                  @click="csvForm.mode = 'full'"
                >
                  <div class="mode-card-header" style="margin-bottom: 4px;">
                    <span class="badge badge-red" style="font-size: 10px;">清空覆盖</span>
                    <div class="radio-indicator" :class="{ 'radio-checked': csvForm.mode === 'full' }">
                      <div v-if="csvForm.mode === 'full'" class="radio-dot"></div>
                    </div>
                  </div>
                  <h4 style="margin: 0 0 2px 0; font-size: 12px;">全量覆盖导入</h4>
                  <p class="mode-card-desc" style="font-size: 10px; margin: 0;">重置当前号码库，以导入的数据作为全新基准并同步发布。</p>
                </div>
              </div>

              <!-- 上传与粘贴区 -->
              <div 
                class="drop-zone" 
                :class="{ 'drop-active': isDragging }"
                style="padding: 16px;"
                @dragover.prevent="isDragging = true"
                @dragleave.prevent="isDragging = false"
                @drop.prevent="handleDropCsvFile"
                @click="triggerCsvFileInput"
              >
                <input ref="csvFileInputRef" type="file" accept=".csv,text/csv" style="display: none;" @change="handleCsvFileSelected" />
                <div style="font-size: 24px; margin-bottom: 4px;">📄</div>
                <div v-if="csvFile" class="font-bold text-success font-mono" style="font-size: 12px;">
                  已选中文件: {{ csvFile.name }} ({{ (csvFile.size / 1024).toFixed(1) }} KB)
                </div>
                <div v-else class="text-secondary" style="font-size: 12px;">
                  拖拽 <span class="font-bold">.csv</span> 文件到此处，或 <span class="text-primary font-bold">点击选择文件</span>
                </div>
              </div>

              <!-- 或直接粘贴 CSV 文本 -->
              <div>
                <label class="form-label" style="display: flex; justify-content: space-between; font-size: 11px;">
                  <span>或直接在此粘贴 CSV 文本内容:</span>
                  <span v-if="csvText.trim()" class="font-mono text-muted">{{ csvText.split('\n').filter(r => r.trim()).length }} 行</span>
                </label>
                <textarea 
                  v-model="csvText" 
                  class="input-text font-mono" 
                  style="height: 80px; width: 100%; font-size: 11px;"
                  placeholder="numeric_phone,label,call_action,call_category,sms_action,sms_sub_action&#10;8695338,顺丰速运,0,delivery,4,10002"
                ></textarea>
              </div>

              <div style="display: flex; gap: 8px; justify-content: flex-end;">
                <button v-if="csvFile || csvText.trim()" class="btn btn-sm" @click="resetCsvImport">清空</button>
                <button 
                  class="btn btn-sm btn-success" 
                  :disabled="isImportingCsv || (!csvFile && !csvText.trim())" 
                  @click="handleExecuteCsvImport"
                >
                  {{ isImportingCsv ? '正在导入中...' : (csvForm.mode === 'full' ? '确认执行全量覆盖导入' : '确认执行增量合并导入') }}
                </button>
              </div>
            </div>
          </div>
        </div>
      </section>

      <!-- 面板 4：用户标记审核看板 -->
      <section v-if="currentTab === 'reports'" class="tab-panel">
        <div class="panel-header-section">
          <div>
            <h2 class="panel-title">用户标记审核</h2>
            <p class="panel-desc">审核来自客户端提交的陌生来电与短信标记信息，审核通过后汇入号码规则库。</p>
          </div>
          <div class="header-actions">
            <select v-model="reportFilterStatus" class="input-text" @change="fetchReports(1)">
              <option value="">全部状态</option>
              <option value="pending">待审核</option>
              <option value="approved">已采纳</option>
              <option value="rejected">已驳回</option>
            </select>
          </div>
        </div>

        <div class="table-container">
          <table class="report-table">
            <thead>
              <tr>
                <th style="width: 70px;">编号</th>
                <th style="width: 150px;">标记号码</th>
                <th style="width: 70px;">渠道</th>
                <th style="width: 100px;">提议分类</th>
                <th style="width: 150px;">建议标签</th>
                <th>内容摘要</th>
                <th style="width: 80px;">状态</th>
                <th style="width: 140px;">上报时间</th>
                <th style="width: 160px; text-align: right;">审核决策</th>
              </tr>
            </thead>
            <tbody>
              <tr v-if="reportTable.loading">
                <td colspan="9" class="table-empty">正在加载标记流水...</td>
              </tr>
              <tr v-else-if="reportTable.items.length === 0">
                <td colspan="9" class="table-empty">暂无待审核标记流水</td>
              </tr>
              <tr v-for="item in reportTable.items" :key="item.id">
                <td class="font-mono text-secondary">#{{ item.id }}</td>
                <td class="font-mono font-bold">{{ item.raw_phone || item.numeric_phone }}</td>
                <td>
                  <span class="badge badge-gray">{{ item.channel === 'sms' ? '短信' : '电话' }}</span>
                </td>
                <td>
                  <span class="badge" :class="isRiskCategory(item.category) ? 'badge-red' : 'badge-blue'">
                    {{ categoryMap[item.category] || item.category }}
                  </span>
                </td>
                <td>{{ item.suggested_label || '-' }}</td>
                <td class="text-secondary" style="max-width: 260px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
                  {{ item.content_snippet || '-' }}
                </td>
                <td>
                  <span class="badge" :class="statusBadgeClass(item.status)">
                    {{ statusText(item.status) }}
                  </span>
                </td>
                <td class="font-mono text-secondary">{{ formatTimestamp(item.created_at) }}</td>
                <td style="text-align: right;">
                  <template v-if="item.status === 'pending'">
                    <button class="btn btn-xs btn-success" @click="handleApproveReport(item.id)">采纳</button>
                    <button class="btn btn-xs btn-danger" @click="handleRejectReport(item.id)">驳回</button>
                  </template>
                  <span v-else class="text-muted font-mono" style="font-size: 11px;">已处理</span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="pagination-bar">
          <button class="btn btn-sm" :disabled="reportTable.page <= 1" @click="fetchReports(reportTable.page - 1)">上一页</button>
          <span class="page-indicator font-mono">
            第 {{ reportTable.page }} / {{ Math.max(1, Math.ceil(reportTable.total / reportTable.limit)) }} 页
          </span>
          <button class="btn btn-sm" :disabled="reportTable.page >= Math.ceil(reportTable.total / reportTable.limit)" @click="fetchReports(reportTable.page + 1)">下一页</button>
        </div>
      </section>

      <!-- 面板 5：纠错申诉处理看板 -->
      <section v-if="currentTab === 'appeals'" class="tab-panel">
        <div class="panel-header-section">
          <div>
            <h2 class="panel-title">纠错申诉处理</h2>
            <p class="panel-desc">处理来自机构或用户的号码纠错与误标申诉。采纳申诉将自动解除拦截并生成增量日志下发客户端。</p>
          </div>
          <div class="header-actions">
            <select v-model="appealFilterStatus" class="input-text" @change="fetchAppeals(1)">
              <option value="">全部状态</option>
              <option value="pending">待审核</option>
              <option value="approved">已采纳</option>
              <option value="rejected">已驳回</option>
            </select>
          </div>
        </div>

        <div class="table-container">
          <table class="report-table">
            <thead>
              <tr>
                <th style="width: 70px;">编号</th>
                <th style="width: 150px;">申诉号码</th>
                <th style="width: 130px;">申诉类型</th>
                <th>申诉事由与说明</th>
                <th style="width: 180px;">证明/资质摘要</th>
                <th style="width: 150px;">联系人信息</th>
                <th style="width: 90px;">状态</th>
                <th style="width: 140px;">提交时间</th>
                <th style="width: 160px; text-align: right;">纠错决策</th>
              </tr>
            </thead>
            <tbody>
              <tr v-if="appealTable.loading">
                <td colspan="9" class="table-empty">正在加载申诉列表...</td>
              </tr>
              <tr v-else-if="appealTable.items.length === 0">
                <td colspan="9" class="table-empty">暂无相关申诉记录</td>
              </tr>
              <tr v-for="item in appealTable.items" :key="item.id">
                <td class="font-mono text-secondary">#{{ item.id }}</td>
                <td class="font-mono font-bold">{{ item.raw_phone || item.numeric_phone }}</td>
                <td>
                  <span class="badge" :class="item.appeal_type === 'false_spam' ? 'badge-orange' : 'badge-blue'">
                    {{ appealTypeMap[item.appeal_type] || item.appeal_type }}
                  </span>
                </td>
                <td class="text-secondary" style="max-width: 240px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
                  {{ item.reason }}
                </td>
                <td class="text-secondary" style="max-width: 180px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
                  {{ item.proof_snippet || '-' }}
                </td>
                <td class="font-mono text-secondary" style="font-size: 11px;">
                  <div v-if="item.contact_phone">📞 {{ item.contact_phone }}</div>
                  <div v-if="item.contact_email">✉️ {{ item.contact_email }}</div>
                  <div v-if="!item.contact_phone && !item.contact_email">{{ item.contact_info }}</div>
                </td>
                <td>
                  <span class="badge" :class="statusBadgeClass(item.status)">
                    {{ statusText(item.status) }}
                  </span>
                </td>
                <td class="font-mono text-secondary">{{ formatTimestamp(item.created_at) }}</td>
                <td style="text-align: right;">
                  <template v-if="item.status === 'pending'">
                    <button class="btn btn-xs btn-success" @click="handleApproveAppeal(item.id)">采纳纠错</button>
                    <button class="btn btn-xs btn-danger" @click="handleRejectAppeal(item.id)">驳回</button>
                  </template>
                  <span v-else class="text-muted font-mono" style="font-size: 11px;">{{ item.review_notes || '已处理' }}</span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="pagination-bar">
          <button class="btn btn-sm" :disabled="appealTable.page <= 1" @click="fetchAppeals(appealTable.page - 1)">上一页</button>
          <span class="page-indicator font-mono">
            第 {{ appealTable.page }} / {{ Math.max(1, Math.ceil(appealTable.total / appealTable.limit)) }} 页
          </span>
          <button class="btn btn-sm" :disabled="appealTable.page >= Math.ceil(appealTable.total / appealTable.limit)" @click="fetchAppeals(appealTable.page + 1)">下一页</button>
        </div>
      </section>

      <!-- 面板 6：设备接入审计看板 -->
      <section v-if="currentTab === 'devices'" class="tab-panel">
        <div class="panel-header-section">
          <div>
            <h2 class="panel-title">设备接入审计</h2>
            <p class="panel-desc">审计接入客户端匿名设备信誉画像，监控标记质量与异常频次。</p>
          </div>
          <div class="header-actions">
            <button class="btn btn-sm" @click="fetchDevices(deviceTable.page)">刷新设备</button>
          </div>
        </div>

        <!-- 关键信誉指标 -->
        <div class="kpi-grid">
          <div class="kpi-card">
            <div class="kpi-title">已登记活跃设备</div>
            <div class="kpi-value font-mono">{{ deviceTable.total }} 台</div>
            <div class="kpi-sub">接入客户端匿名设备</div>
          </div>
          <div class="kpi-card">
            <div class="kpi-title">良好及以上设备</div>
            <div class="kpi-value font-mono text-success">
              {{ deviceTable.items.filter(d => ['excellent', 'good'].includes(d.credit_level)).length }} 台
            </div>
            <div class="kpi-sub">高权重信誉设备</div>
          </div>
          <div class="kpi-card">
            <div class="kpi-title">黑名单封禁设备</div>
            <div class="kpi-value font-mono text-danger">
              {{ deviceTable.items.filter(d => d.is_blocked).length }} 台
            </div>
            <div class="kpi-sub">异常刷单已拦截</div>
          </div>
          <div class="kpi-card">
            <div class="kpi-title">设备累计标记流水</div>
            <div class="kpi-value font-mono">
              {{ deviceTable.items.reduce((acc, d) => acc + (d.total_reports || 0), 0) }} 次
            </div>
            <div class="kpi-sub">客户端上报贡献量</div>
          </div>
        </div>

        <!-- 过滤栏 -->
        <div class="filter-toolbar">
          <div class="toolbar-group">
            <input 
              v-model="deviceFilter.keyword" 
              type="text" 
              class="input-text" 
              placeholder="搜索设备匿名指纹或设备名称..."
              style="width: 260px;" 
              @keyup.enter="fetchDevices(1)"
            />
            <select v-model="deviceFilter.credit_level" class="input-text" @change="fetchDevices(1)">
              <option value="">全部信用评级</option>
              <option value="excellent">极佳 (信誉分 ≥ 90)</option>
              <option value="good">良好 (信誉分 70~89)</option>
              <option value="fair">中等 (信誉分 50~69)</option>
              <option value="poor">高风险 (信誉分 &lt; 50)</option>
            </select>
            <select v-model="deviceFilter.is_blocked" class="input-text" @change="fetchDevices(1)">
              <option value="">全部状态</option>
              <option value="0">正常活跃</option>
              <option value="1">已封禁拦截</option>
            </select>
            <button class="btn" @click="fetchDevices(1)">查询</button>
            <button class="btn" @click="resetDeviceFilter">重置</button>
          </div>
          <div class="toolbar-stats">
            共 <span class="font-mono">{{ deviceTable.total }}</span> 台设备
          </div>
        </div>

        <!-- 设备列表 -->
        <div class="table-container">
          <table class="report-table">
            <thead>
              <tr>
                <th style="width: 220px;">设备匿名指纹</th>
                <th style="width: 140px;">设备名称</th>
                <th style="width: 80px;">平台</th>
                <th style="width: 100px;">信用评级</th>
                <th style="width: 90px;">信誉积分</th>
                <th style="width: 130px;">上报记录 (总计/已采纳/已驳回)</th>
                <th style="width: 80px;">申诉数</th>
                <th style="width: 140px;">首次接入时间</th>
                <th style="width: 140px;">最后活跃时间</th>
                <th style="width: 100px; text-align: right;">管控操作</th>
              </tr>
            </thead>
            <tbody>
              <tr v-if="deviceTable.loading">
                <td colspan="10" class="table-empty">正在加载设备画像数据...</td>
              </tr>
              <tr v-else-if="deviceTable.items.length === 0">
                <td colspan="10" class="table-empty">暂无登记的客户端设备 (可在客户端接入后点击刷新)</td>
              </tr>
              <tr v-for="d in deviceTable.items" :key="d.device_fingerprint">
                <td class="font-mono" style="font-size: 11px;">
                  <span :title="d.device_fingerprint">{{ d.device_fingerprint.substring(0, 16) }}...</span>
                </td>
                <td class="font-bold">{{ d.device_name || 'iPhone 客户端' }}</td>
                <td>
                  <span class="badge badge-gray font-mono">{{ d.platform }}</span>
                </td>
                <td>
                  <span 
                    class="badge" 
                    :class="{
                      'badge-green': d.credit_level === 'excellent',
                      'badge-blue': d.credit_level === 'good',
                      'badge-orange': d.credit_level === 'fair',
                      'badge-red': d.credit_level === 'poor'
                    }"
                  >
                    {{ d.credit_level === 'excellent' ? '极佳' : (d.credit_level === 'good' ? '良好' : (d.credit_level === 'fair' ? '中等' : '高风险')) }}
                  </span>
                </td>
                <td class="font-mono font-bold" :class="d.reputation_score >= 80 ? 'text-success' : (d.reputation_score >= 50 ? 'text-warning' : 'text-danger')">
                  {{ d.reputation_score.toFixed(1) }} 分
                </td>
                <td class="font-mono text-secondary" style="font-size: 12px;">
                  {{ d.total_reports }} / <span class="text-success">{{ d.approved_reports }}</span> / <span class="text-danger">{{ d.rejected_reports }}</span>
                </td>
                <td class="font-mono text-secondary">{{ d.total_appeals }}</td>
                <td class="font-mono text-secondary" style="font-size: 11px;">{{ formatTimestamp(d.first_seen_at) }}</td>
                <td class="font-mono text-secondary" style="font-size: 11px;">{{ formatTimestamp(d.last_active_at) }}</td>
                <td style="text-align: right; white-space: nowrap;">
                  <button 
                    class="btn btn-xs" 
                    title="重置信誉为 100 分"
                    @click="handleResetDeviceReputation(d)"
                  >
                    重置
                  </button>
                  <button 
                    v-if="!d.is_blocked" 
                    class="btn btn-xs btn-danger" 
                    style="margin-left: 4px;"
                    @click="handleBlockDevice(d)"
                  >
                    封禁
                  </button>
                  <button 
                    v-else 
                    class="btn btn-xs btn-success" 
                    style="margin-left: 4px;"
                    @click="handleUnblockDevice(d)"
                  >
                    解封
                  </button>
                  <button 
                    class="btn btn-xs btn-danger" 
                    style="margin-left: 4px;"
                    title="彻底删除解绑设备"
                    @click="handleDeleteDevice(d)"
                  >
                    删除
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <!-- 分页 -->
        <div class="pagination-bar">
          <button class="btn btn-sm" :disabled="deviceTable.page <= 1" @click="fetchDevices(deviceTable.page - 1)">上一页</button>
          <span class="page-indicator font-mono">
            第 {{ deviceTable.page }} / {{ Math.max(1, Math.ceil(deviceTable.total / deviceTable.limit)) }} 页
          </span>
          <button class="btn btn-sm" :disabled="deviceTable.page >= Math.ceil(deviceTable.total / deviceTable.limit)" @click="fetchDevices(deviceTable.page + 1)">下一页</button>
        </div>
      </section>

      <!-- 面板 7：分流与风控配置 -->
      <section v-if="currentTab === 'configs'" class="tab-panel">
        <div class="panel-header-section">
          <div>
            <h2 class="panel-title">分流与风控配置</h2>
            <p class="panel-desc">配置防骚扰分流阈值与上报收敛风控参数，参数保存后服务端立即生效。</p>
          </div>
          <div class="header-actions">
            <button class="btn btn-primary" :disabled="isSavingConfig" @click="handleSaveConfig">
              {{ isSavingConfig ? '保存中...' : '保存风控参数' }}
            </button>
          </div>
        </div>

        <div class="kpi-grid">
          <div class="kpi-card">
            <div class="kpi-title">标记衰减半衰期</div>
            <div class="kpi-value font-mono">{{ algorithmConfigs.decay_half_life_days }} 天</div>
            <div class="kpi-sub">默认 365 天 (平稳长效)</div>
          </div>
          <div class="kpi-card">
            <div class="kpi-title">规则入库生效门限</div>
            <div class="kpi-value font-mono">{{ algorithmConfigs.min_active_confidence }}</div>
            <div class="kpi-sub">达到此置信度自动下发离线库</div>
          </div>
          <div class="kpi-card">
            <div class="kpi-title">系统主动拦截门限</div>
            <div class="kpi-value font-mono">{{ algorithmConfigs.min_block_confidence }}</div>
            <div class="kpi-sub">达到此置信度自动执行拦截</div>
          </div>
          <div class="kpi-card">
            <div class="kpi-title">防刷单最少设备数</div>
            <div class="kpi-value font-mono">{{ algorithmConfigs.min_distinct_devices }} 台</div>
            <div class="kpi-sub">规则收敛所需最少独立设备</div>
          </div>
        </div>

        <div class="content-box" style="margin-top: 16px;">
          <div class="box-header">
            <h3>分流决策与风控核心参数</h3>
          </div>
          <div class="box-body" style="display: flex; flex-direction: column; gap: 16px;">
            <div class="form-group">
              <label>时间衰减半衰期 (天，默认 365 天，建议 180~730 天):</label>
              <div style="display: flex; gap: 12px; align-items: center;">
                <input v-model="algorithmConfigs.decay_half_life_days" type="number" min="30" max="1000" class="input-text" style="width: 140px;" />
                <span class="text-secondary" style="font-size: 13px;">{{ algorithmDescriptions.decay_half_life_days }}</span>
              </div>
            </div>

            <div class="form-group">
              <label>入库生效最低置信度门限 (0.00 ~ 1.00，默认 0.85):</label>
              <div style="display: flex; gap: 12px; align-items: center;">
                <input v-model="algorithmConfigs.min_active_confidence" type="text" class="input-text" style="width: 140px;" />
                <span class="text-secondary" style="font-size: 13px;">{{ algorithmDescriptions.min_active_confidence }}</span>
              </div>
            </div>

            <div class="form-group">
              <label>自动执行系统拦截最低置信度门限 (0.00 ~ 1.00，默认 0.90):</label>
              <div style="display: flex; gap: 12px; align-items: center;">
                <input v-model="algorithmConfigs.min_block_confidence" type="text" class="input-text" style="width: 140px;" />
                <span class="text-secondary" style="font-size: 13px;">{{ algorithmDescriptions.min_block_confidence }}</span>
              </div>
            </div>

            <div class="form-group">
              <label>触发规则聚合并发最低独立设备数 (默认 3):</label>
              <div style="display: flex; gap: 12px; align-items: center;">
                <input v-model="algorithmConfigs.min_distinct_devices" type="number" min="1" max="20" class="input-text" style="width: 140px;" />
                <span class="text-secondary" style="font-size: 13px;">{{ algorithmDescriptions.min_distinct_devices }}</span>
              </div>
            </div>

            <div class="form-group">
              <label>单一分类多数裁定占比阈值 (0.50 ~ 1.00，默认 0.70):</label>
              <div style="display: flex; gap: 12px; align-items: center;">
                <input v-model="algorithmConfigs.category_dominant_ratio" type="text" class="input-text" style="width: 140px;" />
                <span class="text-secondary" style="font-size: 13px;">{{ algorithmDescriptions.category_dominant_ratio }}</span>
              </div>
            </div>

            <div class="form-group">
              <label>号码发生申诉争议时的置信度抑制系数 (0.10 ~ 0.90，默认 0.50):</label>
              <div style="display: flex; gap: 12px; align-items: center;">
                <input v-model="algorithmConfigs.dispute_penalty_factor" type="text" class="input-text" style="width: 140px;" />
                <span class="text-secondary" style="font-size: 13px;">{{ algorithmDescriptions.dispute_penalty_factor }}</span>
              </div>
            </div>
          </div>
        </div>
      </section>

      <!-- 面板 8：号码反查测试终端 -->
      <section v-if="currentTab === 'terminal'" class="tab-panel">
        <div class="panel-header-section">
          <div>
            <h2 class="panel-title">号码反查测试终端</h2>
            <p class="panel-desc">在线测试单号码反查接口，模拟客户端检索流程并校验来电与短信分类动作。</p>
          </div>
        </div>

        <div class="terminal-grid">
          <!-- 查询输入区 -->
          <div class="content-box">
            <div class="box-header">
              <h3>单号码查询探测</h3>
            </div>
            <div class="box-body">
              <div class="form-group">
                <label class="form-label">输入电话号码 (支持 11 位手机、固话、400 热线):</label>
                <div style="display: flex; gap: 8px;">
                  <input 
                    v-model="terminalInput" 
                    type="text" 
                    class="input-text" 
                    style="flex: 1;" 
                    placeholder="例如 95338 或 10086"
                    @keyup.enter="handleTestLookup"
                  />
                  <button class="btn btn-primary" :disabled="isTesting" @click="handleTestLookup">
                    {{ isTesting ? '查询中...' : '测试反查' }}
                  </button>
                </div>
              </div>

              <!-- 快捷预置测试 (真实收录的官方权威号码) -->
              <div class="quick-chips">
                <span class="chip-label">快捷填充:</span>
                <button class="chip-btn" @click="terminalInput = '95338'; handleTestLookup()">顺丰速运 95338</button>
                <button class="chip-btn" @click="terminalInput = '95555'; handleTestLookup()">招商银行 95555</button>
                <button class="chip-btn" @click="terminalInput = '10086'; handleTestLookup()">中国移动 10086</button>
                <button class="chip-btn" @click="terminalInput = '4008205555'; handleTestLookup()">招行信用卡 4008205555</button>
              </div>
            </div>
          </div>

          <!-- 结果展示区 -->
          <div class="content-box">
            <div class="box-header">
              <h3>查询响应报文</h3>
            </div>
            <div class="box-body">
              <pre v-if="terminalResult" class="json-viewer font-mono">{{ JSON.stringify(terminalResult, null, 2) }}</pre>
              <div v-else class="table-empty">在左侧输入号码并发起测试</div>
            </div>
          </div>
        </div>
      </section>
    </main>

    <!-- 新增 / 编辑号码模态框 -->
    <div v-if="showModal" class="modal-layer" @click.self="closeModal">
      <div class="modal-card">
        <div class="box-header" style="justify-content: space-between; display: flex;">
          <h3>{{ isEditing ? '编辑号码规则' : '新增号码规则' }}</h3>
          <button class="btn btn-xs" @click="closeModal">关闭</button>
        </div>
        <div class="box-body" style="display: flex; flex-direction: column; gap: 12px;">
          <div class="form-group">
            <label class="form-label">电话号码 (纯数字):</label>
            <input 
              v-model="modalForm.numeric_phone" 
              type="number" 
              class="input-text" 
              :disabled="isEditing" 
              placeholder="如 8695338 或 8610086"
            />
          </div>

          <div class="form-group">
            <label class="form-label">原始显示号码:</label>
            <input v-model="modalForm.raw_phone" type="text" class="input-text" placeholder="如 95338 或 10086" />
          </div>

          <div class="form-group">
            <label class="form-label">机构或显示名称:</label>
            <input v-model="modalForm.label" type="text" class="input-text" placeholder="如 顺丰速运 官方热线" />
          </div>

          <div class="form-group">
            <label class="form-label">分类标签:</label>
            <select v-model="modalForm.category" class="input-text">
              <option v-for="(name, key) in categoryMap" :key="key" :value="key">{{ name }}</option>
            </select>
          </div>

          <div class="form-group">
            <label class="form-label">处置动作:</label>
            <select v-model="modalForm.action" class="input-text">
              <option value="identify">来电与信息识别</option>
              <option value="block">静默拦截阻止</option>
            </select>
          </div>

          <div class="form-group">
            <label class="form-label">置信度 (0.1 ~ 1.0):</label>
            <input v-model.number="modalForm.confidence" type="number" step="0.05" min="0.1" max="1.0" class="input-text" />
          </div>

          <div style="display: flex; justify-content: flex-end; gap: 8px; margin-top: 8px;">
            <button class="btn" @click="closeModal">取消</button>
            <button class="btn btn-primary" @click="handleSaveModal">保存提交</button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, onMounted } from 'vue'

const currentTab = ref('overview')
const tabs = reactive([
  { id: 'overview', name: '版本与同步' },
  { id: 'numbers', name: '号码规则库' },
  { id: 'data_io', name: '数据导入与导出 (CSV)' },
  { id: 'reports', name: '用户标记审核' },
  { id: 'appeals', name: '纠错申诉处理' },
  { id: 'devices', name: '设备接入审计' },
  { id: 'configs', name: '分流与风控配置' },
  { id: 'terminal', name: '号码反查测试终端' }
])

const categoryMap = {
  // 电话 8 核心分类 + 1 自定义
  delivery: '快递外卖',
  official: '官方政企',
  enterprise: '机构服务',
  real_estate: '房产中介',
  finance_loan: '贷款理财',
  marketing: '广告推销',
  harassment: '恶意骚扰',
  fraud: '疑似诈骗',
  // 短信专属 10 原生细分 + 1 自定义
  junk: '垃圾拦截',
  allow: '验证码放行',
  offers: '优惠营销',
  coupons: '打折卡券',
  promotion_others: '其他推广',
  orders: '订单与物流',
  finance: '金融银行',
  public_services: '公共政务',
  reminders: '行程预订',
  transaction_others: '其他交易',
  custom: '自定义标记'
}

const filterActionMap = {
  delivery: { prim: '交易与服务 (4)', sub: '订单与物流 (10002)' },
  official: { prim: '交易与服务 (4)', sub: '公共政务服务 (10008)' },
  enterprise: { prim: '交易与服务 (4)', sub: '金融银行服务 (10001)' },
  real_estate: { prim: '商业推广 (3)', sub: '其他商业推广 (20000)' },
  finance_loan: { prim: '商业推广 (3)', sub: '商业优惠与营销 (20001)' },
  marketing: { prim: '商业推广 (3)', sub: '商业优惠与营销 (20001)' },
  harassment: { prim: '垃圾短信拦截 (2)', sub: '无 (0)' },
  fraud: { prim: '垃圾短信拦截 (2)', sub: '无 (0)' },
  junk: { prim: '垃圾短信拦截 (2)', sub: '无 (0)' },
  allow: { prim: '允许放行 (1)', sub: '无 (0)' },
  offers: { prim: '商业推广 (3)', sub: '商业优惠与营销 (20001)' },
  coupons: { prim: '商业推广 (3)', sub: '优惠券与折扣 (20002)' },
  promotion_others: { prim: '商业推广 (3)', sub: '其他商业推广 (20000)' },
  orders: { prim: '交易与服务 (4)', sub: '订单与物流 (10002)' },
  finance: { prim: '交易与服务 (4)', sub: '金融银行服务 (10001)' },
  public_services: { prim: '交易与服务 (4)', sub: '公共政务服务 (10008)' },
  reminders: { prim: '交易与服务 (4)', sub: '行程与预订 (10003)' },
  transaction_others: { prim: '交易与服务 (4)', sub: '其他交易通知 (10000)' },
  custom: { prim: '用户自定 (0)', sub: '自主匹配 (0)' }
}

const smsPrimaryNames = {
  0: '普通放行 (0)',
  1: '验证码放行 (1)',
  2: '垃圾拦截 (2)',
  3: '商业推广 (3)',
  4: '交易服务 (4)'
}

const smsSubNames = {
  10000: '其他交易 (10000)',
  10001: '金融银行 (10001)',
  10002: '订单物流 (10002)',
  10003: '行程预订 (10003)',
  10004: '医疗健康 (10004)',
  10005: '气象预警 (10005)',
  10006: '运营商 (10006)',
  10007: '会员奖励 (10007)',
  10008: '公共政务 (10008)',
  20000: '其他推广 (20000)',
  20001: '优惠营销 (20001)',
  20002: '打折卡券 (20002)'
}

const formatSmsAction = (prim, sub) => {
  if (prim === undefined || prim === null) return '-'
  const pName = smsPrimaryNames[prim] || `Action ${prim}`
  if (!sub || sub === 0) return pName
  const sName = smsSubNames[sub] || `Sub ${sub}`
  return `${pName} · ${sName}`
}

const appealTypeMap = {
  false_spam: '误标为骚扰/推销/诈骗',
  wrong_name: '机构名称信息有误',
  whitelist_request: '官方服务号白名单申请',
  other: '其他纠错申诉'
}

// MARK: - 面板 1 状态
const metadata = ref({})
const isPublishing = ref(false)

const fetchMetadata = async () => {
  try {
    const res = await fetch('/api/v1/sync/metadata')
    const json = await res.json()
    if (json.code === 0) {
      metadata.value = json.data
    }
  } catch (err) {
    console.error('Fetch metadata failed', err)
  }
}

const handlePublishVersion = async () => {
  if (!confirm('确认发布新版本？这将原子递增数据库版本号，触发客户端同步。')) return
  isPublishing.value = true
  try {
    const res = await fetch('/api/v1/admin/publish-version', { method: 'POST' })
    const json = await res.json()
    if (json.code === 0) {
      await fetchMetadata()
      alert(`新版本 v${json.data.new_version} 已成功发布！`)
    } else {
      alert(`发布失败: ${json.message}`)
    }
  } catch (err) {
    alert(`网络错误: ${err.message}`)
  } finally {
    isPublishing.value = false
  }
}

// MARK: - 面板 2 状态
const numberFilter = reactive({
  keyword: '',
  category: '',
  action: '',
  status_filter: 'active'
})

const numberTable = reactive({
  loading: false,
  page: 1,
  limit: 20,
  total: 0,
  items: []
})

const fetchNumbers = async (page = 1) => {
  numberTable.loading = true
  numberTable.page = page
  try {
    const params = new URLSearchParams({
      page: String(page),
      limit: String(numberTable.limit)
    })
    if (numberFilter.keyword) params.append('keyword', numberFilter.keyword)
    if (numberFilter.category) params.append('category', numberFilter.category)
    if (numberFilter.action) params.append('action', numberFilter.action)
    if (numberFilter.status_filter) params.append('status_filter', numberFilter.status_filter)

    const res = await fetch(`/api/v1/admin/numbers?${params.toString()}`)
    const json = await res.json()
    if (json.code === 0) {
      numberTable.items = json.data.items
      numberTable.total = json.data.total
    }
  } catch (err) {
    console.error('Fetch numbers failed', err)
  } finally {
    numberTable.loading = false
  }
}

const resetNumberFilter = () => {
  numberFilter.keyword = ''
  numberFilter.category = ''
  numberFilter.action = ''
  numberFilter.status_filter = 'active'
  fetchNumbers(1)
}

// 模态框
const showModal = ref(false)
const isEditing = ref(false)
const modalForm = reactive({
  numeric_phone: '',
  raw_phone: '',
  label: '',
  category: 'delivery',
  action: 'identify',
  confidence: 1.0
})

const openCreateNumberModal = () => {
  isEditing.value = false
  modalForm.numeric_phone = ''
  modalForm.raw_phone = ''
  modalForm.label = ''
  modalForm.category = 'delivery'
  modalForm.action = 'identify'
  modalForm.confidence = 1.0
  showModal.value = true
}

const openEditNumberModal = (item) => {
  isEditing.value = true
  modalForm.numeric_phone = item.numeric_phone
  modalForm.raw_phone = item.raw_phone || ''
  modalForm.label = item.label
  modalForm.category = item.category
  modalForm.action = item.action
  modalForm.confidence = item.confidence
  showModal.value = true
}

const closeModal = () => {
  showModal.value = false
}

const handleSaveModal = async () => {
  if (!modalForm.numeric_phone || !modalForm.label) {
    alert('请填写纯数字号码及机构名称')
    return
  }

  try {
    if (isEditing.value) {
      const res = await fetch(`/api/v1/admin/numbers/${modalForm.numeric_phone}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          label: modalForm.label,
          category: modalForm.category,
          action: modalForm.action,
          confidence: modalForm.confidence
        })
      })
      const json = await res.json()
      if (json.code === 0) {
        closeModal()
        fetchNumbers(numberTable.page)
      } else {
        alert(json.message)
      }
    } else {
      const res = await fetch('/api/v1/admin/numbers', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          numeric_phone: Number(modalForm.numeric_phone),
          raw_phone: modalForm.raw_phone || String(modalForm.numeric_phone),
          label: modalForm.label,
          category: modalForm.category,
          action: modalForm.action,
          confidence: modalForm.confidence
        })
      })
      const json = await res.json()
      if (json.code === 0) {
        closeModal()
        fetchNumbers(1)
        fetchMetadata()
      } else {
        alert(json.message)
      }
    }
  } catch (err) {
    alert(`保存失败: ${err.message}`)
  }
}

const handleDeleteNumber = async (item) => {
  if (!confirm(`确定软删除号码 ${item.numeric_phone} (${item.label})？该号码将移出有效规则库。`)) return
  try {
    const res = await fetch(`/api/v1/admin/numbers/${item.numeric_phone}`, { method: 'DELETE' })
    const json = await res.json()
    if (json.code === 0) {
      fetchNumbers(numberTable.page)
      fetchMetadata()
      alert('号码已成功软删除移出有效库！')
    } else {
      alert(json.message)
    }
  } catch (err) {
    alert(`删除失败: ${err.message}`)
  }
}

const handleRestoreNumber = async (item) => {
  if (!confirm(`确定恢复上架号码 ${item.numeric_phone} (${item.label})？`)) return
  try {
    const res = await fetch(`/api/v1/admin/numbers/${item.numeric_phone}/restore`, { method: 'POST' })
    const json = await res.json()
    if (json.code === 0) {
      fetchNumbers(numberTable.page)
      fetchMetadata()
      alert('号码已成功恢复上架！')
    } else {
      alert(json.message)
    }
  } catch (err) {
    alert(`恢复失败: ${err.message}`)
  }
}

// MARK: - 面板 3 状态：CSV 数据导入与导出
const csvFileInputRef = ref(null)
const csvFile = ref(null)
const csvText = ref('')
const isDragging = ref(false)
const isImportingCsv = ref(false)

const csvForm = reactive({
  mode: 'incremental'
})

const triggerCsvFileInput = () => {
  if (csvFileInputRef.value) {
    csvFileInputRef.value.click()
  }
}

const handleCsvFileSelected = (e) => {
  const files = e.target.files
  if (files && files.length > 0) {
    csvFile.value = files[0]
  }
}

const handleDropCsvFile = (e) => {
  isDragging.value = false
  const files = e.dataTransfer.files
  if (files && files.length > 0) {
    csvFile.value = files[0]
  }
}

const resetCsvImport = () => {
  csvFile.value = null
  csvText.value = ''
  if (csvFileInputRef.value) {
    csvFileInputRef.value.value = ''
  }
}

const handleExportCsv = () => {
  window.location.href = '/api/v1/admin/export/csv'
}

const handleExecuteCsvImport = async () => {
  const modeText = csvForm.mode === 'full' 
    ? '【全量覆盖导入】将清空现有数据库中的全部号码！确认重建基准库？' 
    : '【增量合并导入】将保留既有号码，更新已有号码并追加新号码，确认执行？'
  
  if (!confirm(modeText)) return

  isImportingCsv.value = true
  try {
    const formData = new FormData()
    if (csvFile.value) {
      formData.append('file', csvFile.value)
    }
    if (csvText.value.trim()) {
      formData.append('csv_text', csvText.value.trim())
    }
    formData.append('mode', csvForm.mode)

    const res = await fetch('/api/v1/admin/import/csv', {
      method: 'POST',
      body: formData
    })
    const json = await res.json()
    if (json.code === 0) {
      const data = json.data
      alert(`导入成功！\n总解析行数: ${data.total_rows} 行\n实际新增: ${data.imported_count} 条\n实际更新: ${data.updated_count} 条\n跳过无效: ${data.skipped_count} 条\n已发布新版本: v${data.new_version}`)
      resetCsvImport()
      fetchMetadata()
      fetchNumbers(1)
      currentTab.value = 'numbers'
    } else {
      alert(`导入失败: ${json.message}`)
    }
  } catch (err) {
    alert(`网络异常: ${err.message}`)
  } finally {
    isImportingCsv.value = false
  }
}

// MARK: - 面板 3 状态
const reportFilterStatus = ref('')
const reportTable = reactive({
  loading: false,
  page: 1,
  limit: 20,
  total: 0,
  items: []
})

const fetchReports = async (page = 1) => {
  reportTable.loading = true
  reportTable.page = page
  try {
    const params = new URLSearchParams({
      page: String(page),
      limit: String(reportTable.limit)
    })
    if (reportFilterStatus.value) params.append('status', reportFilterStatus.value)

    const res = await fetch(`/api/v1/admin/reports?${params.toString()}`)
    const json = await res.json()
    if (json.code === 0) {
      reportTable.items = json.data.items
      reportTable.total = json.data.total
    }
  } catch (err) {
    console.error('Fetch reports failed', err)
  } finally {
    reportTable.loading = false
  }
}

const handleApproveReport = async (reportId) => {
  try {
    const res = await fetch(`/api/v1/admin/reports/${reportId}/approve`, { method: 'POST' })
    const json = await res.json()
    if (json.code === 0) {
      fetchReports(reportTable.page)
      fetchMetadata()
    } else {
      alert(json.message)
    }
  } catch (err) {
    alert(`采纳失败: ${err.message}`)
  }
}

const handleRejectReport = async (reportId) => {
  try {
    const res = await fetch(`/api/v1/admin/reports/${reportId}/reject`, { method: 'POST' })
    const json = await res.json()
    if (json.code === 0) {
      fetchReports(reportTable.page)
    } else {
      alert(json.message)
    }
  } catch (err) {
    alert(`驳回失败: ${err.message}`)
  }
}

const isRiskCategory = (cat) => ['fraud', 'harassment', 'real_estate', 'marketing', 'finance_loan', 'junk', 'offers', 'coupons', 'promotion_others', 'finance_telemarketing', 'telemarketing'].includes(cat)

const statusBadgeClass = (status) => {
  switch (status) {
    case 'approved': return 'badge-green'
    case 'rejected': return 'badge-red'
    default: return 'badge-orange'
  }
}

const statusText = (status) => {
  switch (status) {
    case 'approved': return '已采纳'
    case 'rejected': return '已驳回'
    default: return '待审核'
  }
}

// MARK: - 面板 4 状态：申诉管理
const appealFilterStatus = ref('')
const appealTable = reactive({
  loading: false,
  page: 1,
  limit: 20,
  total: 0,
  items: []
})

const fetchAppeals = async (page = 1) => {
  appealTable.loading = true
  appealTable.page = page
  try {
    const params = new URLSearchParams({
      page: String(page),
      limit: String(appealTable.limit)
    })
    if (appealFilterStatus.value) params.append('status', appealFilterStatus.value)

    const res = await fetch(`/api/v1/admin/appeals?${params.toString()}`)
    const json = await res.json()
    if (json.code === 0) {
      appealTable.items = json.data.items
      appealTable.total = json.data.total
    }
  } catch (err) {
    console.error('Fetch appeals failed', err)
  } finally {
    appealTable.loading = false
  }
}

const handleApproveAppeal = async (appealId) => {
  if (!confirm('确认采纳该申诉？若号码在拦截库中，将自动解除拦截并记录变更差量。')) return
  try {
    const res = await fetch(`/api/v1/admin/appeals/${appealId}/approve`, { method: 'POST' })
    const json = await res.json()
    if (json.code === 0) {
      fetchAppeals(appealTable.page)
      fetchMetadata()
      alert('申诉已采纳，已解除拦截状态并下发更新！')
    } else {
      alert(json.message)
    }
  } catch (err) {
    alert(`采纳失败: ${err.message}`)
  }
}

const handleRejectAppeal = async (appealId) => {
  const note = prompt('请输入驳回原因/审核批注:', '经核查维持原判')
  if (note === null) return
  try {
    const res = await fetch(`/api/v1/admin/appeals/${appealId}/reject?review_notes=${encodeURIComponent(note)}`, { method: 'POST' })
    const json = await res.json()
    if (json.code === 0) {
      fetchAppeals(appealTable.page)
    } else {
      alert(json.message)
    }
  } catch (err) {
    alert(`驳回失败: ${err.message}`)
  }
}

// MARK: - 面板 6 状态：匿名设备信用与画像管理
const deviceFilter = reactive({
  keyword: '',
  credit_level: '',
  is_blocked: ''
})

const deviceTable = reactive({
  loading: false,
  page: 1,
  limit: 20,
  total: 0,
  items: []
})

const fetchDevices = async (page = 1) => {
  deviceTable.loading = true
  deviceTable.page = page
  try {
    const params = new URLSearchParams({
      page: String(page),
      limit: String(deviceTable.limit)
    })
    if (deviceFilter.keyword) params.append('keyword', deviceFilter.keyword)
    if (deviceFilter.credit_level) params.append('credit_level', deviceFilter.credit_level)
    if (deviceFilter.is_blocked !== '') params.append('is_blocked', deviceFilter.is_blocked)

    const res = await fetch(`/api/v1/admin/devices?${params.toString()}`)
    const json = await res.json()
    if (json.code === 0) {
      deviceTable.items = json.data.items
      deviceTable.total = json.data.total
    }
  } catch (err) {
    console.error('Fetch devices failed', err)
  } finally {
    deviceTable.loading = false
  }
}

const resetDeviceFilter = () => {
  deviceFilter.keyword = ''
  deviceFilter.credit_level = ''
  deviceFilter.is_blocked = ''
  fetchDevices(1)
}

const handleBlockDevice = async (item) => {
  if (!confirm(`确定将设备 ${item.device_fingerprint.substring(0, 16)}... 列入黑名单封禁？该设备后续上报将被系统忽略！`)) return
  try {
    const res = await fetch(`/api/v1/admin/devices/${item.device_fingerprint}/block`, { method: 'POST' })
    const json = await res.json()
    if (json.code === 0) {
      fetchDevices(deviceTable.page)
      alert('设备已列入黑名单封禁！')
    } else {
      alert(json.message)
    }
  } catch (err) {
    alert(`操作失败: ${err.message}`)
  }
}

const handleUnblockDevice = async (item) => {
  if (!confirm(`确定解除设备 ${item.device_fingerprint.substring(0, 16)}... 的封禁并恢复信誉？`)) return
  try {
    const res = await fetch(`/api/v1/admin/devices/${item.device_fingerprint}/unblock`, { method: 'POST' })
    const json = await res.json()
    if (json.code === 0) {
      fetchDevices(deviceTable.page)
      alert('设备已成功解封并恢复良好信誉！')
    } else {
      alert(json.message)
    }
  } catch (err) {
    alert(`操作失败: ${err.message}`)
  }
}

const handleResetDeviceReputation = async (d) => {
  if (!confirm(`确定将设备 ${d.device_fingerprint.substring(0, 16)}... 的信誉评分重置为 100 分（极佳）？`)) return
  try {
    const res = await fetch(`/api/v1/admin/devices/${d.device_fingerprint}/reset-reputation`, { method: 'POST' })
    const json = await res.json()
    if (json.code === 0) {
      fetchDevices(deviceTable.page)
      alert('已成功重置该设备信誉评级为 100 分（极佳）！')
    } else {
      alert(json.message)
    }
  } catch (err) {
    alert(`重置失败: ${err.message}`)
  }
}

const handleDeleteDevice = async (d) => {
  if (!confirm(`确定彻底删除并解绑设备 ${d.device_fingerprint.substring(0, 16)}... 吗？删除后该设备的历史统计将被彻底清除。`)) return
  try {
    const res = await fetch(`/api/v1/admin/devices/${d.device_fingerprint}`, { method: 'DELETE' })
    const json = await res.json()
    if (json.code === 0) {
      fetchDevices(deviceTable.page)
      alert('设备记录已彻底删除解绑！')
    } else {
      alert(json.message)
    }
  } catch (err) {
    alert(`删除失败: ${err.message}`)
  }
}

// MARK: - 面板 5 状态：反查测试终端
const terminalInput = ref('95338')
const isTesting = ref(false)
const terminalResult = ref(null)

const handleTestLookup = async () => {
  const query = terminalInput.value.trim()
  if (!query) return
  isTesting.value = true
  try {
    const res = await fetch(`/api/v1/numbers/lookup?phone=${encodeURIComponent(query)}`)
    const json = await res.json()
    terminalResult.value = json
  } catch (err) {
    terminalResult.value = { error: err.message }
  } finally {
    isTesting.value = false
  }
}

const formatVersion = (v) => {
  if (!v) return '1'
  const s = String(v)
  if (s.length === 12) {
    return `${s.substring(0, 4)}.${s.substring(4, 6)}.${s.substring(6, 8)} ${s.substring(8, 10)}:${s.substring(10, 12)}`
  }
  return s
}

// MARK: - 面板 5 状态：算法与风控动态配置
const isSavingConfig = ref(false)
const algorithmConfigs = reactive({
  decay_half_life_days: 365,
  min_active_confidence: '0.85',
  min_block_confidence: '0.90',
  min_distinct_devices: 3,
  category_dominant_ratio: '0.70',
  dispute_penalty_factor: '0.50'
})
const algorithmDescriptions = reactive({
  decay_half_life_days: '社区标记时间衰减半衰期 (天)',
  min_active_confidence: '入库生效最低置信度门限',
  min_block_confidence: '自动执行系统拦截最低置信度门限',
  min_distinct_devices: '触发规则聚合并发最低独立设备数',
  category_dominant_ratio: '单一分类多数裁定占比阈值',
  dispute_penalty_factor: '号码发生申诉争议时的置信度抑制系数'
})

const fetchAlgorithmConfig = async () => {
  try {
    const res = await fetch('/api/v1/admin/algorithm-config')
    const json = await res.json()
    if (json.code === 0 && json.data) {
      Object.assign(algorithmConfigs, json.data.configs)
      Object.assign(algorithmDescriptions, json.data.descriptions)
    }
  } catch (err) {
    console.error('Fetch algorithm configs failed', err)
  }
}

const handleSaveConfig = async () => {
  isSavingConfig.value = true
  try {
    const res = await fetch('/api/v1/admin/algorithm-config', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ configs: algorithmConfigs })
    })
    const json = await res.json()
    if (json.code === 0) {
      alert('风控与置信度算法参数已成功保存并立即生效！')
      fetchAlgorithmConfig()
    } else {
      alert(`保存失败: ${json.message}`)
    }
  } catch (err) {
    alert(`网络错误: ${err.message}`)
  } finally {
    isSavingConfig.value = false
  }
}

const refreshCurrentTab = () => {
  if (currentTab.value === 'overview') fetchMetadata()
  if (currentTab.value === 'numbers') fetchNumbers(numberTable.page)
  if (currentTab.value === 'reports') fetchReports(reportTable.page)
  if (currentTab.value === 'appeals') fetchAppeals(appealTable.page)
  if (currentTab.value === 'devices') fetchDevices(deviceTable.page)
  if (currentTab.value === 'configs') fetchAlgorithmConfig()
  if (currentTab.value === 'terminal') handleTestLookup()
}

const formatTimestamp = (ts) => {
  if (!ts) return '-'
  const num = Number(ts)
  const d = new Date(num > 1e11 ? num : num * 1000)
  if (isNaN(d.getTime())) return String(ts)
  const pad = (n) => String(n).padStart(2, '0')
  const Y = d.getFullYear()
  const M = pad(d.getMonth() + 1)
  const D = pad(d.getDate())
  const h = pad(d.getHours())
  const m = pad(d.getMinutes())
  const s = pad(d.getSeconds())
  return `${Y}-${M}-${D} ${h}:${m}:${s}`
}

onMounted(() => {
  fetchMetadata()
  fetchNumbers(1)
  fetchReports(1)
  fetchAppeals(1)
  fetchDevices(1)
  fetchAlgorithmConfig()
  handleTestLookup()
})
</script>

<style scoped>
.console-root {
  min-height: 100vh;
  display: flex;
  flex-direction: column;
  background-color: var(--bg-primary);
}

.console-header {
  height: 48px;
  background-color: var(--bg-surface);
  border-bottom: 1px solid var(--border-color);
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 16px;
  position: sticky;
  top: 0;
  z-index: 50;
}

.header-left {
  display: flex;
  align-items: center;
  gap: 10px;
}

.brand-logo {
  color: var(--accent-blue);
  display: flex;
  align-items: center;
}

.brand-info {
  display: flex;
  align-items: baseline;
  gap: 6px;
}

.brand-title {
  font-weight: 700;
  font-size: 14px;
  color: var(--text-primary);
  letter-spacing: -0.2px;
}

.brand-subtitle {
  font-size: 11px;
  color: var(--text-muted);
}

.nav-tabs {
  display: flex;
  gap: 2px;
  background: var(--bg-subtle);
  padding: 3px;
  border-radius: var(--radius-md);
  border: 1px solid var(--border-subtle);
}

.nav-tab-btn {
  padding: 4px 12px;
  font-size: 12px;
  font-weight: 500;
  border: none;
  background: transparent;
  color: var(--text-secondary);
  border-radius: var(--radius-sm);
  cursor: pointer;
  transition: all 0.15s ease;
  display: flex;
  align-items: center;
  gap: 6px;
}

.nav-tab-btn:hover {
  color: var(--text-primary);
}

.nav-tab-btn.active {
  background: var(--bg-surface);
  color: var(--text-primary);
  box-shadow: var(--shadow-sm);
}

.header-right {
  display: flex;
  align-items: center;
  gap: 12px;
}

.system-indicator {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 11px;
  color: var(--text-secondary);
  font-family: var(--font-mono);
}

.pulse-dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background-color: var(--accent-green);
  box-shadow: 0 0 0 2px rgba(35, 134, 54, 0.2);
}

.console-main {
  flex: 1;
  padding: 20px 24px;
  max-width: 1400px;
  margin: 0 auto;
  width: 100%;
}

.panel-header-section {
  display: flex;
  justify-content: space-between;
  align-items: flex-end;
  margin-bottom: 16px;
  padding-bottom: 12px;
  border-bottom: 1px solid var(--border-subtle);
}

.panel-title {
  font-size: 18px;
  font-weight: 600;
  color: var(--text-primary);
  letter-spacing: -0.3px;
}

.panel-desc {
  font-size: 12px;
  color: var(--text-secondary);
  margin-top: 2px;
}

.header-actions {
  display: flex;
  align-items: center;
  gap: 8px;
}

/* KPI 指标卡片与指标矩阵 */
.kpi-grid,
.metrics-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
  gap: 14px;
  margin-bottom: 16px;
}

.kpi-card,
.metric-card {
  background: var(--bg-surface);
  border: 1px solid var(--border-color);
  border-radius: var(--radius-lg);
  padding: 16px;
  display: flex;
  flex-direction: column;
  transition: all 0.2s cubic-bezier(0.16, 1, 0.3, 1);
  box-shadow: var(--shadow-sm);
  position: relative;
  overflow: hidden;
}

.kpi-card:hover,
.metric-card:hover {
  transform: translateY(-2px);
  border-color: rgba(47, 129, 247, 0.45);
  box-shadow: 0 6px 20px rgba(0, 0, 0, 0.18);
}

.kpi-title,
.metric-label {
  font-size: 12px;
  font-weight: 500;
  color: var(--text-secondary);
  line-height: 1.4;
  letter-spacing: -0.1px;
}

.kpi-value,
.metric-value {
  font-size: 24px;
  font-weight: 700;
  font-family: var(--font-mono);
  color: var(--text-primary);
  margin-top: 4px;
  margin-bottom: 2px;
  letter-spacing: -0.5px;
  line-height: 1.25;
}

.kpi-sub,
.metric-footnote {
  font-size: 11px;
  color: var(--text-muted);
  line-height: 1.4;
}

/* 内容盒子 */
.content-box {
  background: var(--bg-surface);
  border: 1px solid var(--border-color);
  border-radius: var(--radius-md);
  margin-bottom: 16px;
  overflow: hidden;
}

.box-header {
  padding: 10px 14px;
  background: var(--bg-subtle);
  border-bottom: 1px solid var(--border-color);
}

.box-header h3 {
  font-size: 13px;
  font-weight: 600;
  color: var(--text-primary);
}

.box-body {
  padding: 14px;
}

.font-mono-desc {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.desc-row {
  display: flex;
  font-size: 12px;
  gap: 10px;
}

.desc-k {
  width: 140px;
  color: var(--text-secondary);
}

.desc-v {
  color: var(--text-primary);
}

/* 筛选工具栏 */
.filter-toolbar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 12px;
  margin-bottom: 12px;
}

.toolbar-group {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
}

.toolbar-stats {
  font-size: 12px;
  color: var(--text-secondary);
}

/* 报表表格 */
.table-container {
  background: var(--bg-surface);
  border: 1px solid var(--border-color);
  border-radius: var(--radius-md);
  overflow-x: auto;
}

.report-table {
  width: 100%;
  border-collapse: collapse;
  text-align: left;
  font-size: 12px;
}

.report-table th {
  background: var(--bg-subtle);
  color: var(--text-secondary);
  font-weight: 600;
  padding: 8px 12px;
  border-bottom: 1px solid var(--border-color);
  white-space: nowrap;
}

.report-table td {
  padding: 8px 12px;
  border-bottom: 1px solid var(--border-subtle);
  color: var(--text-primary);
  white-space: nowrap;
}

.report-table tr:last-child td {
  border-bottom: none;
}

.report-table tr:hover td {
  background-color: rgba(255, 255, 255, 0.02);
}

.table-empty {
  text-align: center;
  padding: 36px 0;
  color: var(--text-muted);
}

.btn-xs {
  padding: 2px 7px;
  height: 22px;
  font-size: 11px;
}

.pagination-bar {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 12px;
  margin-top: 12px;
}

.page-indicator {
  font-size: 12px;
  color: var(--text-secondary);
}

/* 终端测试区 */
.terminal-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 16px;
}

@media (max-width: 900px) {
  .terminal-grid {
    grid-template-columns: 1fr;
  }
}

.form-group {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.form-label {
  font-size: 11px;
  font-weight: 500;
  color: var(--text-secondary);
}

.quick-chips {
  display: flex;
  align-items: center;
  gap: 6px;
  margin-top: 12px;
  flex-wrap: wrap;
}

.chip-label {
  font-size: 11px;
  color: var(--text-muted);
}

.chip-btn {
  background: var(--bg-subtle);
  border: 1px solid var(--border-color);
  color: var(--text-primary);
  border-radius: 12px;
  padding: 2px 8px;
  font-size: 11px;
  cursor: pointer;
  transition: all 0.15s ease;
}

.chip-btn:hover {
  background: var(--border-color);
}

.json-viewer {
  background: var(--bg-primary);
  border: 1px solid var(--border-color);
  border-radius: var(--radius-sm);
  padding: 12px;
  max-height: 400px;
  overflow: auto;
  font-size: 11px;
  color: #7ee787;
  line-height: 1.4;
}

.text-success { color: var(--accent-green); }
.text-danger { color: var(--accent-red); }
.text-primary { color: var(--accent-blue); }
.text-warning { color: var(--accent-orange); }
.text-secondary { color: var(--text-secondary); }
.text-muted { color: var(--text-muted); }
.font-bold { font-weight: 600; }
.font-medium { font-weight: 500; }
</style>
