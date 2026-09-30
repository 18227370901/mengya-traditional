# 萌芽（Mengya）母婴全周期平台 —— PSD 系统设计与重构决策文档

>
作者角色：资深系统架构师 & 代码审计专家 (Senior Solutions Architect)  |
文档性质：生产级权威系统设计规范 (PSD) & 重构决策基准  |
代码真相对齐：Git commit d8c2042 (v1.34)

---

## 阶段 0：历史设计资产自发现与执行基准

通过全盘扫描项目根目录，系统现存的历史设计资产、技术规格书与核心构建文件探测结果如下：

| 文件路径 | 预估用途与核心内容 | 时效性与状态判定 | 采纳与吸收决策 |
| --- | --- | --- | --- |
| `Project_Survey_Document.md` (190.6 KB / 1,986 行) | 全系统综合调研文档，记录了从 v1.0 至 v1.34 (REQ-01 ~ REQ-36) 的全量演进历史、29 个前端页面清单、数据字典与部署运维细节。 | 核心基准 (最新) 最后更新 2026-09-23。属于调研文档 (Survey)，缺乏顶层重构决策。 | **全量吸收**：作为业务领域意图、历史演进及事实底座的核心输入。 |
| `agent.md` (29.3 KB / 847 行) | AI 助手模块专用开发指南，包含 AI 架构设计、Prompt 编排、安全边界、数据模型与 API 规格。 | 局部专业规格 (次新) 更新于 2026-09-08。需针对联网搜索双引擎容灾进行校准。 | **定向采纳**：作为第 6 部分 AI 模块详尽规格的直接设计依据。 |
| `README.md` (40.4 KB / 425 行) | 本地传统部署版工程白皮书与运维说明，包含单体一体化托管拓扑、单端口 5173 策略与 `run.sh` 操作规范。 | 工程基准 (最新) 2026-09-23。准确反映了前端脱离 Node.js、合并入 Django 的最新物理拓扑。 | **全量吸收**：作为部署拓扑与网络边界的事实依据。 |
| `run.sh` / `run.ps1` (33.8 KB / 11.1 KB) | 服务治理与构建编排代码化脚本，实现端口探针、依赖检测、静态合并、Nginx SNI 生成与双版本隔离。 | 运行态实现真相 | **提取规则**：用于网络拓扑、自愈机制与部署流水线设计。 |

⚠️ 资产排除清单与依据

- `apps/core/fixtures/initial_data.json` (2.58 MB) 及 `fetal_stories_data.json` (704 KB)：纯业务数据种子与百科备份，非架构设计资产，予以排除。
- `frontend/package-lock.json`：包管理器锁定文件，予以排除。
- `.venv/` 及 Python `__pycache__/`：虚拟环境与编译缓存，全量排除。

## 第 1 部分：项目全局概览与拓扑

### 1.1 业务定位与核心价值

萌芽（Mengya）母婴平台是一套面向新一代母婴家庭的**全生命周期（备孕期、孕产期、0~6岁育儿期）健康陪伴、知识百科、消费决策与智能顾问一体化服务平台**。

- **孕育生命周期跟踪与智能阶段跃迁**：基于预产期与出生日期，自动计算孕周（1~40周）、孕三期（早/中/晚）及大龄宝宝复合月龄（如“2岁3个月”），动态驱动全站内容、营养食谱、产检与疫苗计划个性化分发。
- **母婴商品优选与多维雷达比价体系**：围绕母婴用品高标准安全与参数繁杂痛点，提供分类检索、品牌库透视、多商品横向参数矩阵比对及 5 维能力雷达评分。
- **场景化待产与母婴用品清单引擎**：按孕早期、待产包、新生儿、婴儿期等场景自动生成准备清单，支持分类统计、购买渠道推荐、预算管理与一键状态流转。
- **混合智能顾问与多引擎容灾检索**：结合大语言模型与 DuckDuckGo/Bing 双引擎联网检索管道，提供育儿知识问答、商品智能深度评测及胎教故事检索。

### 1.2 真实技术栈全景清单

| 领域 | 核心技术组件 | 真实版本规范 | 架构角色与选型考量 |
| --- | --- | --- | --- |
| **后端运行时** | Python | `>= 3.10` | 平台核心后端开发语言。 |
| **Web 核心框架** | Django | `Django>=4.2,<5.0` (推荐 4.2 LTS) | 提供 ORM、中间件流水线、安全防护、静态托管及 Admin 基础设施。 |
| **API 架构层** | Django REST Framework (DRF) | `djangorestframework>=3.14,<3.16` | RESTful 接口规范、序列化与模型验证层。 |
| **身份与权限** | djangorestframework-simplejwt | `djangorestframework-simplejwt>=5.3,<5.6` | 基于 JWT 的无状态认证体系，配合自定义权限矩阵 (`apps/core/utils/permissions.py`)。 |
| **数据持久化** | SQLite3 / PostgreSQL | `SQLite 3.x` / `PG 14+ / 16+` | 本地传统版开箱即用 SQLite3 (`db.sqlite3`)；保留 `psycopg2-binary>=2.9` 生产驱动。 |
| **缓存与异步任务** | Redis / Celery | `Redis 5.0+` / `Celery 5.3+` | 异步任务调度与集中缓存；本地无中间件环境下自动降级为 `LocMemCache` 同步执行。 |
| **前端运行时** | React + TypeScript | `React 18.3+` / `TS 5.4+` | 现代化强类型组件化前端应用，由 Vite 5.3 编译。 |
| **前端状态管理** | Zustand | `4.5.x` | 轻量级 Hook 状态管理，分管身份令牌、宝宝档案、全局主题与比价栏。 |
| **交付与部署形态** | 一体化单体托管 | `0.0.0.0:5173` | 前端打包产物合并至 Django 后端，单进程对外统一暴露，彻底移除 Node.js 常驻服务。 |

### 1.3 端到端最新架构拓扑图 (Mermaid)

系统经过 v1.27 ~ v1.34 演进后，已彻底抛弃独立 Node.js 前端服务，转为 **Django 一体化单体托管 + 单端口安全边界架构**：

#### 图 1.1：端到端架构拓扑全景图 (End-to-End System Topology)
```mermaid

flowchart TB
subgraph ClientLayer ["客户端接入层 (Browser / Mobile Web)"]
UserBrowser["用户/管理员终端浏览器"]
end

subgraph BoundaryLayer ["网络入口与安全边界 (Port: 5173 / 443)"]
NginxProxy["Nginx 反向代理 (可选，SNI 多域名 + 权威 SSL)"]
DjangoHost["Django 一体化核心服务 (0.0.0.0:5173)"]
end

subgraph DjangoCore ["Django 单体核心架构 (apps/core & config)"]
URLRouter["URL 智能调度网关 (config/urls.py)"]

subgraph StaticPipeline ["静态托管与 SPA 渲染管道"]
SPARouter["SPA 页面通配捕获 (index.html)"]
StaticServe["静态资源直发 (/static/*, /assets/*)"]
FetalStoryFallback["胎教故事双路径自愈路由 (serve_fetal_story)"]
end

subgraph SecurityPipeline ["安全风控与中间件流水线"]
CORS["CORS 跨域过滤器"]
JWTAuth["SimpleJWT 认证"]
SingleSession["单端会话互踢 (SingleSessionJWTAuthentication)"]
AdminTimeout["管理员空闲超时引擎 (REQ-35)"]
PermCheck["细粒度权限管控矩阵 (utils/permissions.py)"]
end

subgraph ViewLayer ["控制器视图层 (apps/core/views.py - 3,363行 / 43个视图单元)"]
AuthViews["认证与风控视图 (login, register, forgot_pwd)"]
BabyViews["宝宝与孕育周期视图 (BabyViewSet, timeline)"]
ProductViews["商品中心与比价视图 (ProductViewSet, compare)"]
AIViews["AI 助手交互视图 (ai_chat, sessions)"]
AdminViews["系统管理与审计视图 (UserManage, audit_logs)"]
end

subgraph ServiceLayer ["业务领域服务层 (apps/core/services)"]
AIService["AI 编排引擎 (ai_service.py)"]
WebSearchService["多引擎容灾检索 (web_search.py)"]
ProductComparator["雷达打分比价器 (product_comparator.py)"]
ShoppingGenerator["清单智能生成器 (shopping_list_generator.py)"]
StageUtils["孕育周期计算引擎 (utils/stage_utils.py)"]
end

subgraph ModelLayer ["数据领域模型层 (apps/core/models - 20个实体模型+1抽象基类)"]
UserModels["用户与安全模型 (User, SystemSetting, AuditLog)"]
DomainModels["母婴业务模型 (BabyProfile, TimelineEvent, HealthRecord, Recipe, Encyclopedia)"]
ProductModels["电商知识模型 (Product, BrandProfile, ProductComparison, ShoppingList)"]
AIModels["AI 会话模型 (ChatSession, ChatMessage, AIQueryLog)"]
end
end

subgraph StorageLayer ["存储与外部服务"]
SQLiteDB[("本地数据库: SQLite3 (db.sqlite3)")]
LocalFiles[("本地持久化存储 (static/ & media/)")]
OpenAIGW["外部大模型网关 (OpenAI / DeepSeek / 通义千问)"]
SearchEngines["外网检索引擎 (Bing / DuckDuckGo API)"]
end

UserBrowser -->|HTTPS/HTTP 访问| NginxProxy
NginxProxy -->|反向代理| DjangoHost
UserBrowser -.->|直连模式: 5173| DjangoHost

DjangoHost --> URLRouter

URLRouter -->|静态文件请求| StaticServe
URLRouter -->|/fetal-stories/*| FetalStoryFallback
URLRouter -->|SPA 页面路由| SPARouter
URLRouter -->|/api/* API 路由| SecurityPipeline

SecurityPipeline --> ViewLayer
ViewLayer --> ServiceLayer
ServiceLayer --> ModelLayer
ViewLayer --> ModelLayer

ModelLayer --> SQLiteDB
StaticServe --> LocalFiles
FetalStoryFallback --> LocalFiles
AIService --> OpenAIGW
WebSearchService --> SearchEngines

```

## 第 2 部分：文档-代码差异与漂移矩阵 (Drift Matrix)

将历史设计资产（`Project_Survey_Document.md`、`agent.md`、`README.md`）与当前代码库（Git commit `d8c2042`）进行逐行交叉核验，审计出的核心漂移矩阵如下：

| 模块/功能 | 历史文档记载 (Survey/Agent) | 代码真实实现与证据位置 | 状态判定 | 架构影响与风险评估 |
| --- | --- | --- | --- | --- |
| **前端交付与服务形态** | `Project_Survey_Document.md:2.5` 记载前端为独立 Vite 常驻进程，监听 `5173`，反代后端 `8000` 端口。 | `config/urls.py:25-33` `run.sh:180-220` (commit `a70a65c`)：前端生产编译产物直接合并至 Django `static/` 与 `templates/index.html`，统一由 Django 在 `0.0.0.0:5173` 托管。 | 已重大重构 | **正面收益**：彻底消除 Node.js 内存驻留（开销降低 70%），根除了跨进程 502/500 代理故障。但开发态需注意静态产物同步。 |
| **胎教故事静态寻址** | `Project_Survey_Document.md:5.1` 将 343 张封面大图（32.32MB）由 Git 直接索引管理在 `static/fetal-stories`。 | `config/urls.py:6-17` `.gitignore` (commit `d8c2042`)：物理移出 Git 跟踪。Django 实现 `serve_fetal_story` 双路径自愈（优先检查 `static/`，缺失则透明回退至 `frontend/public/`）。 | 已重构并自愈 | **正面收益**：精简 Git 仓库体积 32MB，解决新克隆环境与 Docker 卷挂载导致的 404 破图。 |
| **管理员会话空闲超时** | `Project_Survey_Document.md:3.1` 仅记录登录失败锁定与图形验证码，未设计无操作超时机制。 | `apps/core/models/system.py:32` `apps/core/views.py:2400-2450` `frontend/src/layouts/RequireAuth.tsx:45-68` (commit `89fb11b`)：新增 `admin_session_timeout_minutes`，前端 3s 节流写入 localStorage，跨 Tab 协同检测，超时踢出跳转 `/login?timeout=1`。 | 新增安全落地 | **正面收益**：满足等保 2.0/3.0 特权账户安全基线，消除离开操作台引发的特权会话劫持风险。 |
| **管理员免死金牌机制** | `Project_Survey_Document.md:3.3` 记载账号达到阈值后一律冻结 `is_active=False`。 | `apps/core/views.py:298-301, 2637-2639`：硬编码特权逻辑：若用户为 Admin，检测到 `is_active=False` 则强行自愈为 `True`，仅实施 `locked_until` 强制冷却，绝不永久冻结。 | 已定向加固 | **边界影响**：防止恶意攻击者通过暴力尝试管理员账号导致系统管理员永久锁定（DoS 瘫痪）。属于系统特许硬编码逻辑。 |
| **预置演示账户体系** | `Project_Survey_Document.md:3.1` 记录系统内嵌默认 `admin/admin123` 及演示用户种子。 | `apps/core/management/commands/ensure_admin.py` `run.sh:388` (commit `0588270`)：全量清理 demo、test 等内置账号；启动强制从 `.env` 派生唯一自定义管理员，历史残留管理员降级或移除。 | 已废除并收敛 | **正面收益**：消除默认弱口令被公网爆破隐患，确立“单一自定义管理员”架构准则。 |
| **AI 联网搜索容灾链路** | `agent.md:2.2` 仅声明集成单一 DuckDuckGo 搜索端点。 | `apps/core/services/web_search.py:45-120` `apps/core/services/ai_service.py:140-180`：重构为 Bing + DuckDuckGo 双引擎自适应流水线，注入系统 CA 证书链，增加 3s 严格超时与静默兜底。 | 已加固重构 | **正面收益**：彻底解决国内沙箱网络下 DuckDuckGo 偶发握手失败导致 AI 问答整体卡死的问题。 |
| **外部网络端口暴露基线** | `Project_Survey_Document.md:2.5` 早期拓扑曾暴露 8000、5433、6380 等端口。 | `README.md:20-40` `config/settings.py:ALLOWED_HOSTS`：除可选 Nginx 监听 443 外，Django 仅监听 `5173`，后端与数据库端口完全回环收敛。 | 已收敛加固 | **正面收益**：外部暴露攻击面缩小为单端口，杜绝后端未鉴权端口被旁路直连。 |

## 第 3 部分：架构模式识别与判定依据

📌 架构模式判定结论：一体化模块化单体 (Unified Modular Monolith)

系统在运行时为一个独立的操作系统进程（Python/Django），所有业务模块（认证、周期、商品、AI、系统管理）均在同一上下文内同步调度，共享单一物理数据库（SQLite/PostgreSQL）。

### 3.1 核心判定依据

- **单一物理入口与无分布式 RPC**：全站流量经由 `config/urls.py` 路由调度，各业务组件（`views.py` 与 `services/`）之间完全通过 Python 进程内标准内存导入与同步函数调用执行，无 gRPC/REST 内部微服务调用开销。
- **集中式路由装配总线**：`apps/core/urls.py` 集中注册 12 个 `ModelViewSet` 资源路由与 32 个显式 `path()` 路由；配合 `config/urls.py:32` 负向预警正则捕获全站 SPA 路由并返回 `index.html`。
- **单数据库上下文与本地 ACID 事务**：全平台共享单一数据库连接配置（`config/settings.py:DATABASES['default']`），跨表状态流转直接依托 Django `transaction.atomic()` 本地事务，无分布式一致性（2PC/SAGA）协调。

## 第 4 部分：架构耦合度诊断与坏味道分析

### 4.1 纯业务代码资产盘点 (框架无关，可直接跨技术栈复用)

系统内部沉淀了部分与 Django 框架完全解耦的高价值母婴领域资产：

- **孕育生命周期与年龄推导算法** (`apps/core/utils/stage_utils.py#L5-L110`)：纯 Python 函数，仅依赖内置 `datetime.date`。严密封装了 40 周倒推、孕三期边界及大龄宝宝“X岁X个月”格式化规则。
- **多维商品雷达比价算法** (`apps/core/services/product_comparator.py#L12-L135`)：封装了同类商品参数矩阵归一化打分与五维雷达图极差映射纯算法。
- **分阶段待产与物资清单规则库** (`apps/core/services/shopping_list_generator.py#L15-L140`)：纯规则字典驱动，按周期阶段标签自动映射物资清单。
- **多引擎检索与文本清洗管道** (`apps/core/services/web_search.py#L25-L115`)：封装了针对搜索结果的 HTML 剥离与正文摘要提取逻辑。

### 4.2 强侵入代码剖析 (强依赖 Django 生态，替换成本高)

- **Django ORM 细粒度模型群** (`apps/core/models/*.py`)：19 个模型深度绑定 `models.Model`、外键级联、Choices 枚举与 `update_fields` 机制。
- **DRF 序列化与校验管道** (`apps/core/serializers/__init__.py`)：深度绑定 `ModelSerializer` 与 `validate_*` 钩子。
- **SimpleJWT 鉴权与单端互踢** (`apps/core/utils/single_session_auth.py`)：深度依赖 SimpleJWT 的 Token 声明生成与 PBKDF2 密码校验。

### 4.3 分层退化坏味道深度剖析 (典型反模式与证据链)

🚨 坏味道 1：上帝视图文件与胖控制器 (Fat Controller / God View)

**代码事实**：`apps/core/views.py` **单文件高达 3,363 行，聚集了 50 个视图类和函数**！一个文件同时管理用户认证、风控熔断、宝宝档案、商品比价、雷达图计算、操作审计、管理后台权限配置与 AI 会话分发。严重违背单一职责原则 (SRP)，造成极高的维护心智负担与合并冲突风险。

🚨 坏味道 2：业务逻辑未下沉 Service，在 View 中过程化堆砌

**典型证据**：`ForgotPasswordView` (单类 438 行，`apps/core/views.py:2616-3053`) 与 `login` (单函数 141 行，`apps/core/views.py:290-430`)。

视图层直接处理账号查找、特权账号免死金牌解冻、锁定倒计时计算、密码散列比对、失败计数累加、强制等待熔断、审计日志记录及响应字典组装。核心风控逻辑完全无法被单元测试独立覆盖，亦无法被后台脚本或 CLI 复用。

⚠️ 坏味道 3：ORM 查询与聚合外露在 View 层

**典型证据**：`ProductViewSet` (`apps/core/views.py:1185-1350`) 与 `BabyShoppingItemViewSet` (`apps/core/views.py:1612-1850`) 中充斥着大段跨表查询、关联预加载与内存循环组装，缺乏统一的 Repository 或 QueryService 抽象。

## 第 5 部分：架构替换与轻量化可行性决策

### 5.1 评估动机：当前框架是否过重？真有性能/维护瓶颈？

- **内存实测现实**：移除独立 Node.js 进程并将前端静态产物合并至 Django 后，整站运行内存稳定在 **80MB ~ 130MB**（SQLite 模式）。对于本地化运行和边缘轻量主机，内存已十分轻量。
- **并发与性能现实**：系统核心场景为家庭/单机构本地使用，日常 TPS 在 50~200 之间。SQLite 开启 WAL 模式结合 Django 能轻松支撑该吞吐，**性能并非系统当前的主要矛盾**。
- **真正核心瓶颈**：不是 Django 运行慢，而是 `views.py` 内部的分层退化导致的代码可维护性与测试困境。

### 5.2 替换代价 vs 收益矩阵 (ROI 分析)

| 重构方案 | 重构成本 (代价) | 预期技术收益 | 潜在工程风险 | ROI 综合判定 |
| --- | --- | --- | --- | --- |
| **方案 A：全面推倒，重写为 FastAPI / Go** | **极高** (需重写 20 个数据实体模型、ORM 迁移、SimpleJWT 认证、全套管理后台逻辑，耗时约 3~4 人周)。 | 并发性能提升 3~5 倍，原生类型提示更强。 | 历史业务规则（免死金牌、倒计时算法、阶段状态机）遗漏风险极高；破坏稳定运行的启动自愈脚本。 | 极低 (负收益) 对母婴低频交互场景属于过度工程。 |
| **方案 B：全栈 Next.js / Node 重构** | **高** (需将 Python AI 服务与数据模型全量重写为 TS/Prisma，耗时约 2~3 人周)。 | 前后端语言全栈统一为 TypeScript。 | Python 生态强大的 AI/数据清洗能力在 Node 端适配复杂。 | 低 (收益有限) |
| **方案 C：维持 Django 框架，实施局部防腐与服务层下沉** | **低~中** (不变更底层框架与表结构，仅拆解 `views.py` 并下沉 Service，耗时约 3~5 工日)。 | 彻底根除胖控制器坏味道，业务逻辑 100% 可单测，保持 100% 现有 API 契约与运维脚本兼容。 | 无架构级破坏性风险，具备灰度分步演进条件。 | 极高 (最佳选择) 以最小代价换取最高工程健康度。 |

### 5.3 模块可替换性资产分级表

| 资产等级 | 包含模块与代码依据 | 框架耦合度 | 替换与重构策略 |
| --- | --- | --- | --- |
| Level 1：纯业务资产 | 阶段算法 (`apps/core/utils/stage_utils.py`)、比价算法 (`apps/core/services/product_comparator.py`)、清单生成 (`apps/core/services/shopping_list_generator.py`)。 | **零耦合** (框架无关) | **资产保护级**：无论技术栈如何变迁，此部分代码原样保留或直接跨语言移植。 |
| Level 2：轻度封装服务 | AI 会话编排 (`ai_service.py`)、多引擎联网搜索 (`web_search.py`)。 | **低耦合** (依赖外部 SDK) | **接口规范化**：提取标准抽象接口，作为独立领域服务支撑。 |
| Level 3：分层重构重灾区 | 登录与密保风控 (`views.py:290-430, 2616-3053`)、商品与清单控制、系统权限管理。 | **中高耦合** (混杂 HTTP 与业务) | **核心手术区**：拆分为独立 `views/` 目录；将业务下沉为独立 `services/`。 |
| Level 4：框架持久层 | 数据模型 (`models/*.py`)、数据库迁移文件、序列化器。 | **极高耦合** (强绑定 ORM) | **维持现状基线**：保留现存成熟表结构与迁移链路，严禁无收益的推倒重写。 |

<h3>架构师权威决策：【不建议推倒替换框架，强烈建议实施架构局部治理与视图分层解耦】</h3>

以最小工程代价换取最高系统可靠性，避免盲目重写带来的业务中断与隐性回归缺陷。

## 第 6 部分：前后端详尽规格 (校准整合版)

### 6.1 前端架构设计与通信体系

系统前端基于 **React 18.3 + TypeScript 5.4 + Vite 5.3** 构建，以 **Zustand** 作为轻量级全局状态总线，通过 **Axios 拦截器流水线** 建立严密的认证与容错通信网。

- **路由体系与无闪烁守卫 (`frontend/src/layouts/RequireAuth.tsx`)**：所有核心业务页面均受 `RequireAuth` 包裹，在未认证时输出骨架占位，杜绝未鉴权内容的视觉频闪。
- **跨 Tab 空闲活跃监听引擎 (`RequireAuth.tsx#L45-L68`)**：监听用户在浏览器内的多源交互事件，采用 3 秒节流将活跃时间戳写入 `localStorage("mengya_last_active")`。每 10 秒巡检一次，超过 `admin_session_timeout_minutes`（默认 30 分钟）主动触发 `authStore.logout()` 并踢出跳转至 `/login?timeout=1`。

**API 通信与拦截器流水线 (`frontend/src/api/client.ts`)**：

- **请求拦截**：自动在 HTTP 请求头中注入 `Authorization: Bearer <Token>`，并刷新活跃时间戳。
- **响应拦截与单端互踢解包**：捕获 HTTP 401 且 `code === 1003` 时，立即清除本地存储并重定向 `/login?kicked=1`，展示“账号已在其他设备登录”警示。

#### 3. 黑夜/白天双主题切换与自适应渲染体系 (`frontend/src/store/themeStore.ts`, `tailwind.config.js`)
- **双主题架构规范**：开启 Tailwind CSS `darkMode: 'class'`，通过根节点 `<html>` 的 `.dark` 类驱动全站样式自适应。
- **状态原子化与持久化**：采用 Zustand `useThemeStore` 状态机管理 `theme` 与 `isDark`，自动双向同步持久化至 `localStorage('mengya_theme')`，实现毫秒级平滑响应。
- **FOUT 白屏闪烁消除机制**：在 `index.html` 首部注入微型原生 IIFE 脚本，在首屏 DOM 树初次渲染前先行读取偏好并挂载 `dark` 类，彻底杜绝冷启动与页面刷新时的视觉跳变。
- **全表单控件与输入框双层深色兜底**：
  - 覆盖全站 22 个文件、138+ 处 `<input>`, `<textarea>`, `<select>` 表单元素；
  - 在 `src/index.css` 为 `.input` 类与原生表单标签提供系统级深色兜底（`dark:bg-gray-800`, `dark:text-gray-100`, `dark:border-gray-700`，`color-scheme: dark`）；
  - 针对原生 `<select>` 下拉菜单，强制设定暗色 option 背景，消除移动端与桌面端原生下拉弹层的白底冲突。
- **动态图表深浅自适应**：ECharts 生长曲线图（`GrowthChart`）与多品对比雷达图（`ComparisonRadar`）监听 `useThemeStore`，实时平滑适配背景分割区、坐标轴与 Tooltip 配色。
- **三维切换入口覆盖**：全局主布局顶栏（`MainLayout`）Sun/Moon 切换按钮、独立认证页（`LoginPage` / `RegisterPage`）右上角悬浮按钮、个人中心（`ProfilePage`）“界面外观”设置卡片。

---

### 6.2 后端核心服务分层与中间件流水线

请求进入系统后的处理流水线与单端互踢时序如下：

#### 图 6.1：请求处理流水线与单端会话校验时序图 (Request Pipeline & Single Session)
```mermaid

sequenceDiagram
autonumber
actor Client as 客户端 (Browser)
participant Sec as Security & CORS
participant Session as Session & Common
participant Auth as SingleSessionJWT
participant View as View / Controller
participant DB as SQLite3 数据库

Client->>Sec: 发送 HTTP 请求 (带 Bearer Token)
Sec->>Sec: 安全标头注入 / 跨域源校验
Sec->>Session: 建立会话上下文
Session->>Auth: 提取 Bearer Token
Auth->>Auth: 校验 Token 签名 & JTI 活跃度
alt JTI 不匹配 (异地设备登录被顶下线)
Auth-->>Client: 401 Unauthorized (code=1003)
Client->>Client: 捕获 1003 清理存储并跳转 /login?kicked=1
else 认证合法
Auth->>View: 绑定 request.user 进入业务分发
View->>DB: ORM 查询/事务提交
DB-->>View: 返回数据实体
View-->>Client: 200 OK 业务 JSON 响应
end

```

### 6.3 核心 API 规范清单 (代表性 8 大接口)

| 接口路径与方法 | 鉴权级别 | 核心请求参数 (Payload) | 核心校验与风控逻辑 | 成功返回示例 (200 OK / 201 Created) |
| --- | --- | --- | --- | --- |
| `POST /api/auth/login/` | 公开 (`AllowAny`) | `phone` (支持手机号/用户名), `password`, `captcha` (超限必填) | 校验是否冻结（管理员免死金牌自动自愈）；检查 `locked_until` 强制等待冷却；密码失败累加计数；登录成功更新 `active_token_jti`（单端互踢），重置失败计数。 | `{"code": 0, "message": "登录成功", "data": {"user": {"id": 1, "username": "admin", "phone": "admin", "role": "mother"}, "access": "...", "refresh": "...", "admin_session_timeout_minutes": 30}}` |
| `GET /api/users/me/` | JWT Bearer | 无 (Query/Header) | 返回当前用户信息、关联的当前激活宝宝档案、计算出的母婴周期阶段信息（孕周、月龄）、权限字典与超时配置。 | `{"code": 0, "message": "success", "data": {"user": {"id": 1, "username": "admin", "role": "mother"}, "stage": {"type": "pregnancy", "label": "孕28周", "value": 28}, "permissions": {"ai_chat": true}, "admin_session_timeout_minutes": 30}}` |
| `POST /api/babies/` | JWT Bearer | `name`, `gender`, `birthday` (出生日期或预产期), `is_born`, `is_primary` | 支持未出生/已出生建档；`is_primary=True` 时在同一事务中同步重置主账户 `User.due_date`/`baby_birthday` 与 `is_pregnant`，实现生命周期跨模块双向联动；提供 `@action set_primary` 切换激活状态。 | `{"code": 0, "data": {"id": 2, "name": "悠悠", "birthday": "2026-11-20", "is_born": false, "is_primary": true}}` |
| `POST /api/products/compare/` | JWT Bearer | `{"product_ids": [101, 102]}` | 后端校验至少选择 2 款在售商品（`len < 2` 报错 2001）；前端建议 2~4 款；调用 `product_comparator.py` 计算基础参数对比表、多维雷达图得分与综合推荐标签。 | `{"code": 0, "message": "success", "data": {"comparison_id": 1, "products": [...], "radar": {"indicators": [...], "series": [...]}, "recommendation": {...}, "price_comparison": {...}, "dimensions": {...}}}` |
| `POST /api/ai/chat/` | JWT Bearer | `{"query": "孕妇能吃大闸蟹吗", "session_id": 1}` | 检查 `ai_chat` 权限；后端调用 `web_search.needs_search()` 自动启发式判定是否触发 Bing/DuckDuckGo 联网搜索；注入当前孕周/月龄知识库上下文；调用模型或降级到本地专家库。 | `{"code": 0, "message": "success", "data": {"query": "孕妇能吃大闸蟹吗", "response": "...", "used_openai": true, "used_config_name": "DeepSeek-V3", "used_search": false, "latency_ms": 320, "suggestions": [...], "session_id": 1, "session_title": "孕妇能吃大闸蟹吗"}}` |
| `POST /api/shopping-lists/generate/` | JWT Bearer | `{"name": "我的待产包", "season": "all", "delivery_method": "both"}` | 接收季节（all/spring_autumn/summer/winter）与分娩方式（both/vaginal/c_section），调用规则引擎自动生成待产包与新生儿分类清单，计算初始进度。 | **201 Created**<br>`{"code": 0, "message": "生成成功", "data": {"id": 5, "name": "我的待产包", "list_type": "hospital_bag", "season": "all", "delivery_method": "both", "progress": 0, "total_items": 18, "checked_items": 0, "items": [...]}}` |
| `PUT /api/admin/users/` | 超级管理员特权 (`IsAdminUser`) | 修改用户：`user_id, nickname, role, is_staff, is_active, reset_security_lock`；<br>修改系统安全参数(不传 user_id)：`login_freeze_threshold, admin_session_timeout_minutes` 等 | 修改指定用户状态、解冻锁定、管理员免死金牌自动自愈；或修改全局安全参数。写入 `SystemSetting` 并全量落盘操作审计日志（注：权限矩阵覆写由 `PUT /api/admin/permissions/` 处理）。 | `{"code": 0, "message": "用户信息已更新", "data": {...}}` 或 `{"code": 0, "message": "安全配置参数已更新", "data": {...}}` |
| `PUT /api/users/forgot-password/` | 公开 (`AllowAny`) | `phone, security_answer, new_password, captcha` | **两步重置流程**：① `POST` 验证密保答案（返回 `verified=true`）；② `PUT` 校验密保并重置新密码；失败累加 `security_fail_count`；超阈值触发熔断，返回 HTTP 400 (`code=1012`) 并带冷却等待倒计时。 | `{"code": 0, "message": "密码重置成功，请重新登录"}` |

## 第 7 部分：数据持久化设计

### 7.1 核心实体关系模型 (Mermaid ER Diagram)

系统核心实体关系与业务外键映射结构如下：

#### 图 7.1：数据模型实体关系图 (Entity-Relationship Diagram)
```mermaid

erDiagram
User ||--o{ BabyProfile : "owns"
User ||--o{ TimelineEvent : "records"
User ||--o{ HealthRecord : "measures"
User ||--o{ ShoppingList : "creates"
User ||--o{ UserFavorite : "favorites"
User ||--o{ ChatSession : "chats"
User ||--o{ AuditLog : "triggers"

Product ||--o{ UserFavorite : "is_favorited"
Product ||--o{ ShoppingListItem : "contains_item"
BrandProfile ||--o{ Product : "manufactures"

ChatSession ||--o{ ChatMessage : "has_messages"
ShoppingList ||--o{ ShoppingListItem : "has_items"

User {
    int id PK
    string phone UK
    string role
    date due_date
    date baby_birthday
    boolean is_pregnant
    string active_token_jti
    int login_fail_count
    int security_fail_count
    datetime locked_until
    string security_question
    string security_answer
}

BabyProfile {
    int id PK
    int user_id FK
    string name
    string gender
    date birthday
    boolean is_born
    boolean is_primary
    float birth_weight
    float birth_height
    float birth_head_circumference
}

Product {
    int id PK
    int brand_profile_id FK
    string name
    string brand
    string first_category
    string second_category
    json price_info
    json specifications
    json ratings
    float overall_rating
    boolean has_ccc_certification
    boolean is_essential
}

SystemSetting {
int id PK
string registration_mode
int login_freeze_threshold
int login_lock_seconds
int admin_session_timeout_minutes
}

AuditLog {
    int id PK
    int user_id FK
    string username
    string action
    string action_label
    string target_type
    string target_id
    string target_name
    text detail
    string ip
    datetime created_at
}

```

### 7.2 核心数据表约束与字段字典

| 表名 (Model) | 核心字段 | 数据类型 | 约束条件 | 业务定义与架构作用 |
| --- | --- | --- | --- | --- |
| `core_user` (`User`) | `phone`<br>`role`<br>`active_token_jti`<br>`locked_until` | VARCHAR(50)<br>VARCHAR(20)<br>VARCHAR(64)<br>DATETIME | UNIQUE, NOT NULL<br>DEFAULT 'mother'<br>BLANK=True<br>NULL=True | 平台主账号实体（继承 AbstractUser）；基于 JTI 的单端互踢与风控冷却时间戳。 |
| `core_babyprofile` (`BabyProfile`) | `user_id`<br>`birthday`<br>`is_born`<br>`is_primary` | INTEGER (FK)<br>DATE<br>BOOLEAN<br>BOOLEAN | CASCADE, INDEX<br>NOT NULL<br>DEFAULT True<br>DEFAULT False | 宝宝与胎儿统一档案实体；`birthday` 承载预产期或出生日期，`is_primary` 驱动全站阶段跃迁。 |
| `core_product` (`Product`) | `name`<br>`first_category`<br>`price_info`<br>`specifications`<br>`ratings` | VARCHAR(200)<br>VARCHAR(30)<br>JSONField<br>JSONField<br>JSONField | NOT NULL, INDEX<br>CHOICES, INDEX<br>DEFAULT dict<br>DEFAULT dict<br>DEFAULT dict | 母婴商品实体；JSON 格式弹性存储价格区间、专业技术参数与 5 维雷达图得分。 |
| `core_systemsetting` (`SystemSetting`) | `registration_mode`<br>`admin_session_timeout_minutes`<br>`login_freeze_threshold` | VARCHAR(20)<br>INTEGER<br>INTEGER | DEFAULT 'open'<br>DEFAULT 30<br>DEFAULT 10 | 单例配置表（ID=1）；控制开放/邀请注册、无操作超时与密码爆破风控阈值。 |
| `core_auditlog` (`AuditLog`) | `action`<br>`target_type`<br>`ip`<br>`created_at` | VARCHAR(50)<br>VARCHAR(50)<br>VARCHAR(64)<br>DATETIME | INDEX<br>BLANK=True<br>BLANK=True<br>AUTO_NOW_ADD, INDEX | 全站不可篡改操作合规审计日志，保留责任人、目标对象、变更明细与 IP 地址。 |

### 7.3 索引设计与事务机制

- **索引有效性与查询加速**：`User.phone` 与 `InviteLink.token` 设有唯一索引保障一致性；`AuditLog.created_at`（降序索引）支撑高频分页审计；`Product.category` 与 `BabyProfile.user_id` 均建有外键/B-Tree 索引。
- **事务机制与 ACID 边界**：全站跨表一致性（如修改宝宝激活状态同时联动用户主档案预产期、修改系统安全设置同时记录审计日志）严格封装于 `transaction.atomic()` 事务块内。
- **SQLite 高并发保护**：默认开启 **WAL (Write-Ahead Logging)** 预写日志模式，实现“读写并发不阻塞”，杜绝数据库死锁。

## 第 8 部分：工程与安全保障

### 8.1 环境变量与配置分离规范

系统严格遵循 **12-Factor App** 标准：配置通过根目录 `.env` 文件与代码彻底解耦，提供 `.env.example` 作为基准模板。

`run.sh#update_env_var` 与 `run.sh#normalize_domains` 针对多 SNI 域名配置（支持空格、逗号、分号及引号混配，如 `SERVER_NAME="mengya.local, baby.local"`）增加了自动语法清洗、双引号包裹与读取前正则自愈，防止分隔符异常导致 Bash 语法解析崩溃或域名无法识别。

- **Nginx 反代配置智能差分比对与静默自愈引擎 (`run.sh#gen_nginx_config`)**：
  - **智能差分比对**：预计算目标反代配置并与现有磁盘配置比对（自动忽略时间戳注释差异），配置完全一致时静默保留，杜绝冗余快照文件堆积并确保日常启动（`start`/`restart`）零干扰；
  - **参数漂移自动安全自愈**：当检测到前端端口或 SNI 域名变更时，自动备份时间戳快照并同步重写 Nginx 反代配置，彻底消除端口不一致导致的 502 Bad Gateway 隐患；
  - **免打扰锁定机制**：首行带 `# MANAGED_BY_ADMIN_DO_NOT_OVERWRITE` 标记时绝对跳过覆盖，在专属命令（`add_nginx`）下提供交互式覆盖确认，为个性化定制提供多层次防护。
- **SSL 证书目录默认本地化与自愈创建 (`run.sh#NGINX_CERT_DIR`)**：
  - **默认路径本地化**：证书默认路径由宿主机全局目录 `/opt/service/nginx/ssl` 重构为当前项目目录下的 `ssl/`（`$SCRIPT_DIR/ssl`），消除对外部全局目录的强制依赖；
  - **目录缺失静默自愈**：在脚本环境初始化阶段，增加 `[ ! -d "$NGINX_CERT_DIR" ] && mkdir -p "$NGINX_CERT_DIR"` 自愈逻辑，保障生成或读取证书前目录绝对就绪；
  - **兼容性与优先级保障**：全面兼容 `.env` 与环境变量中显式配置的自定义路径，并由 `resolve_abs_path` 自动转为物理绝对路径。

### 8.2 认证与安全防御纵深

- **网络边界收敛**：生产仅暴露 5173/443 端口，后端 8000 与数据库端口完全回环隔离。
- **暴力破解防御**：IP/账号双重防抖计数，阈值熔断冷却 (`code=1012`)。
- **单端会话互踢**：基于 JWT JTI 强校验，异地登录立即注销 (`code=1003`)。
- **管理员特权免死金牌**：管理员账号永不永久冻结，仅实施强制等待，防 DoS 锁死。
- **管理员空闲超时踢出**：30 分钟无操作自动注销 (`RequireAuth` 跨 Tab 协同引擎)。
- **全站操作审计**：全量管理行为、权限变更、状态重置物理落盘至 `AuditLog`。

### 8.3 部署构建流水线与双路径自愈保障

- **前端打包编译流水线**：
  - 执行 `npm run build` 生成生产 SPA 静态包。
  - 将产物 `dist/index.html` 复制至 Django `templates/index.html`；`dist/assets/*` 复制至 `static/assets/`。
- **本地单体运行态**：
  - `run.sh` / `run.ps1` 启动直接依赖 `config/urls.py` 静态直发，开箱即用免调 `collectstatic`。
- **生产级 Nginx 分离部署**：
  - 若配置独立 Nginx 拦截 `/static/`，则需执行 `python manage.py collectstatic --noinput` 进行静态聚合。

**胎教故事双路径自愈路由 (`config/urls.py#L6-L17`)**：
```
def serve_fetal_story(request, path):
primary_dir = settings.BASE_DIR / "static" / "fetal-stories"
fallback_dir = settings.BASE_DIR / "frontend" / "public" / "fetal-stories"
if (primary_dir / path).is_file():
return serve(request, path, document_root=primary_dir)
return serve(request, path, document_root=fallback_dir)
```
移出 Git 仓库中 32MB 重复大图的同时，通过动态双路径路由保障本地裸机与容器环境下 100% 杜绝 404 破图。

## 第 9 部分：综合问题排查与渐进演进路线图

### 9.1 五维技术债清单

| 维度 | 现存技术债与代码坏味道 | 风险等级 | 治理手段与目标 |
| --- | --- | --- | --- |
| **1. 代码质量** | `apps/core/views.py` **单文件 3,363 行**，聚集 43 个视图单元；业务逻辑严重堆砌在 Controller 中，缺乏独立的 Service 抽象与单元测试。 | P0 (极高) | 实施**绞杀者重构**：将 `views.py` 拆解为 `views/` 领域目录，将风控与认证逻辑下沉至 `services/`。 |
| **2. 高并发性能** | 全站静态文件（含胎教故事、图片、React assets）由 Django 同步进程直发，高并发下消耗 Python 工作线程。 | P1 (高) | 生产环境通过 Nginx 拦截静态资源路径（`/static/`, `/assets/`, `/fetal-stories/`），实施零拷贝直发。 |
| **3. 架构扩展性** | 单一 Django App（`apps/core`）承载全平台 20 个业务实体模型与全部接口，模块边界模糊。 | P2 (中) | 渐进式拆分子 App：`apps/authentication`、`apps/baby`、`apps/catalog`、`apps/ai_assistant`。 |
| **4. 安全边界** | 密保答案采用简单散列对比，缺少基于 PBKDF2 的加盐散列保护；未实施严格的上传文件 MIME 类型白名单防御。 | P1 (高) | 强化安全工具库，密保与敏感数据统一接入 Django `make_password` 标准加密体系。 |
| **5. 自动化运维** | 缺少端到端自动化测试流水线（CI/CD），代码提交依赖人工脚本验证。 | P2 (中) | 配置 GitHub Actions / 本地自动化回归测试（pytest + Playwright），实现代码提交自动质量门禁。 |

### 9.2 渐进式演进路线图 (Mermaid Gantt 甘特图)

#### 图 9.1：系统架构治理与渐进演进路线图 (Architecture Evolution Gantt)
```mermaid

gantt
title 萌芽平台架构治理与渐进演进路线图
dateFormat  YYYY-MM-DD
section P0 核心代码解耦与稳态治理 (第1至2周)
views.py 绞杀者模式目录与防腐层建立 :active, p0_1, 2026-10-01, 4d
核心风控与认证逻辑下沉 Service 层   :p0_2, after p0_1, 5d
核心接口单元测试覆盖 (覆盖率达标80%) :p0_3, after p0_2, 5d
section P1 性能优化与生产加固 (第3至4周)
Nginx 静态资源零拷贝直发配置优化   :p1_1, 2026-10-18, 4d
SQLite WAL 模式与并发锁优化      :p1_2, after p1_1, 3d
密保安全算法升级与敏感数据加盐    :p1_3, after p1_2, 4d
section P2 领域多App拆分与扩展 (第5至8周)
apps_core 拆分为 4 个高内聚子App  :p2_1, 2026-11-01, 14d
CI_CD 自动化回归流水线搭建       :p2_2, after p2_1, 7d
多家庭与多角色多租户能力探索      :p2_3, after p2_2, 10d

```

### 9.3 针对 views.py 的“绞杀者模式 (Strangler Pattern)”重构实施方案

为避免“大爆炸式重构”引发业务中断，针对 3,363 行的 `views.py` 采用绞杀者模式分步演进：

```
[现有旧结构]                                  [重构后新结构]
apps/core/                                    apps/core/
└── views.py (3,363行 上帝文件)                ├── views/                     # 拆解后的纯 HTTP 视图目录
│   ├── __init__.py            # 向后兼容导出
│   ├── auth_views.py          # 登录/注册/验证码
│   ├── baby_views.py          # 宝宝与孕育阶段
│   ├── product_views.py       # 商品与比价
│   ├── ai_views.py            # AI 对话与会话
│   └── admin_views.py         # 用户管理与审计日志
├── services/                  # 下沉的核心领域服务
│   ├── auth_service.py        # 纯业务：认证/免死金牌/会话
│   ├── risk_service.py        # 纯业务：动态冷却/熔断计数
│   └── stage_service.py       # 纯业务：生命周期推导
└── urls.py                    # 无感平滑路由
```

- **第一步：建立目录防腐层**：创建 `apps/core/views/` 目录，在 `apps/core/views/__init__.py` 中通过 `from ..views_legacy import *` 保持所有旧视图导入符号完全不变，确保 `urls.py` 零修改。
- **第二步：剥离高内聚服务层**：将 `views.py#L290-L430` 中的密码校验、锁定等待计算、管理员免死金牌提取至 `services/auth_service.py`；将密保尝试熔断下沉至 `services/risk_service.py`。
- **第三步：逐个视图模块迁移**：依次切出 `auth_views.py`、`product_views.py`、`admin_views.py`，Controller 仅保留参数校验与 Service 调用。
- **第四步：物理销毁旧文件**：当 43 个视图全部迁移完毕并跑通测试后，彻底删除旧 `views.py`。

## 架构审计与重构裁决总结

🏆 交付成果与总结

本文档完整交付了 `mengya-local` 平台的**权威 PSD 系统设计与工程重构决策**：

- **事实真相严密对齐**：核准了前端合并托管于 Django、单端口暴露、管理员无操作超时、静态资源双路径自愈等最新架构事实。
- **架构模式与决策明确**：否定了推倒重写的非理性重构，确立了“维持 Django 一体化单体，实施视图层绞杀者解耦”的最高 ROI 治理路线。
- **端到端工程规格就绪**：提供了详尽的前后端通信规范、8 个核心 API 契约、数据持久化 ER 结构与分期治理实施方案，可作为后续研发与演进的基石指南。

---

## 第 10 部分：双版本数据库存储物理隔离规范 (v1.38)

### 10.1 隔离架构设计与现状基线
系统分为容器微服务版（`mengya-docker`）与本地传统部署版（`mengya-local`），为确保双版本在同一服务器或开发机并存时数据不发生交叉污染，架构确立了**数据层 100% 物理硬隔离规范**：

| 维度 | 传统本地模式 (`mengya-local`) | Docker 容器模式 (`mengya-docker`) |
| :--- | :--- | :--- |
| **存储介质与引擎** | **本地独立单文件 SQLite 3** | **PostgreSQL 18 (内置 pgvector)** |
| **物理存储路径** | `mengya-local/db.sqlite3` | Docker 命名存储卷 `pgdata` (`/var/lib/postgresql`) |
| **网络暴露策略** | 仅供宿主机 Python 进程直连本地文件，无网络端口 | 容器内暴露 5432 (`expose`)，**不对宿主机映射端口** |
| **默认加载逻辑** | `USE_POSTGRES` 未显式开启时强制使用 SQLite，忽略上级环境变量 | 严格连接 Compose 内部服务 `db:5432` |

### 10.2 核心安全机制
1. **切断父级目录环境污染**：传统版 `settings.py` 仅加载当前工程内部的 `.env`，杜绝上级公共目录环境变量渗透。
2. **显式开关保护 (`USE_POSTGRES`)**：即便宿主机系统环境中残留了 `DATABASE_URL`，未显式配置 `USE_POSTGRES=True` 时，系统坚决锁定使用本地 `db.sqlite3`。
3. **运维与启动状态自愈可视化**：`run.sh` 与 `run.ps1` 在启动和状态输出中明确标识数据库引擎类型与物理存储路径。


### 10.3 多数据库部署模式自适应架构与交互式向导规范 (v1.40)

为满足传统版用户在本地轻量化与外部生产级 PostgreSQL 之间的平滑切换，系统在 v1.40 实现了**多数据库部署模式自适应架构与智能向导机制**：

#### 10.3.1 三大多态数据库部署模式
1. **模式 1：SQLite 本地化单文件 (`sqlite`, 传统版严格默认推荐)**
   - **架构设计**：数据直接持久化在 `mengya-local/db.sqlite3`，`USE_POSTGRES=False`，`DATABASE_URL=""`。
   - **资源收益**：**零额外数据库容器**，整站常驻总内存仅约 **50MB**，与 Docker 版数据 **100% 物理硬隔离**。
2. **模式 2：共享已有 PostgreSQL 实例 (`shared`)**
   - **架构设计**：复用宿主机已在运行的 PG 容器（如 `pgvector-18`），启动时通过容器内管理接口幂等执行 `CREATE DATABASE mengya_local` 与 `CREATE USER mengya_local`。
   - **数据隔离保障**：即使与 Docker 版共享同一个 PG 容器，传统版使用专属数据库名 `mengya_local` 与专属账号，而 Docker 版使用 `mengya` 库，实现**库级和权限级物理隔离**，互不串扰。
3. **模式 3：独立专属 PostgreSQL 容器 (`dedicated`)**
   - **架构设计**：基于 Docker 启动专属容器 `${APP_NAME:-mengya_local}-pg`，宿主机端口映射 5433（避免与宿主机 5432 冲突），应用 80MB 内核微服务精简调优。
   - **镜像策略**：严格就地复用本地已有 PG 镜像，严禁联网拉取。

#### 10.3.2 严苛的本地镜像就地复用策略
扫描链依次检索：① 运行中 PG 容器镜像；② 本地 `pgvector/pgvector:pg18`；③ 本地 `postgres:15-alpine` 等轻量镜像；④ 本地任何包含 `postgres` 的镜像。命中即直接复用，杜绝网络重复下载。

#### 10.3.3 基于硬件探针与架构定位的智能推荐引擎
- **传统版核心规则**：由于传统版定位为宿主机轻量独立运行，向导**严格优先推荐 [1] SQLite 本地化单文件**，保障与 Docker 版数据 100% 物理隔离与零配置开箱即用；
- **共享检测**：若检测到宿主机已有运行中的 PostgreSQL 容器，列出推荐选项供高阶管理员按需切换；
- **防挂起兜底**：交互终端设定 30 秒超时自动兜底，超时未操作自动采用推荐项。

#### 10.3.4 定时任务 / Cron / 重启全静默免交互保护机制
1. **运维子命令白名单自愈**：当命令行传入 `restart`、`stop`、`status`、`logs` 时，系统 100% 自动跳过任何交互逻辑，静默沿用已有配置，绝不阻塞定时重启任务；
2. **状态记忆持久化**：首次向导配置成功后自动将 `DB_MODE`、`USE_POSTGRES`、`DATABASE_URL` 等变量持久化至 `.env`，后续常规启动直接读取；
3. **非交互环境自愈**：利用 `[ ! -t 0 ]` 探针检测无 TTY 环境（如 Cron、Systemd 守护进程、Jenkins/GitLab CI 流水线），或传入 `-y / --non-interactive` 时，自动静默应用推荐配置（SQLite）并自愈写入 `.env`；
4. **显式重配开关**：运维人员如需变更模式，支持追加 `--reconfig` 参数（例如 `./run.sh start --reconfig`），随时唤醒全流程向导。


### 10.4 运维管理脚本组件化解耦与 bin/ 目录模块化治理规范 (v1.41)

#### 10.4.1 演化背景与治理目标
传统版本运维脚本 `run.sh` 承载了跨平台端口探测、进程树终止、Python 虚拟环境自愈、三大数据库模式决策（严格默认 SQLite）、SSL 证书生成与 Nginx 反代写入等丰富功能，单文件代码量超过 1300 行。
为提高运维脚本的直观性、模块化程度和长期可维护性，系统实施了“**主入口微内核 + bin/ 垂直领域组件库**”解耦重构。

#### 10.4.2 模块化分层职责清单
- **微内核主入口 (`run.sh`)**：仅保留环境安全检测、`bin/*.sh` 组件装载守卫、核心生命周期调度 (`start_backend` / `show_status`)、统一参数解析与命令分发，代码结构高度清晰；
- **`bin/env.sh` (环境与配置域)**：负责 `.env` 读写持久化、物理绝对路径解析、SNI 域名归一化、URL 访问指引打印、临时缓存清理与重启会话全量吊销 (`invalidate_all_sessions`)；
- **`bin/process.sh` (进程与端口管理域)**：负责跨平台端口探针 (`lsof` / `ss` / `netstat` / `/dev/tcp`)、PID 记录读取与存活性检测、进程树递归强制回收 (`kill_pid_tree`)、服务停止编排 (`stop_service` / `stop_all`)；
- **`bin/python.sh` (Python 运行环境域)**：负责系统级 Python 解释器侦测、虚拟环境与基础依赖检查 (`ensure_backend_deps`)，保留老版前端空函数兼容旧接口；
- **`bin/db.sh` (数据持久化治理域)**：负责宿主机内存与运行中 PG 容器探针、本地镜像优先复用、三大数据库模式决策向导（传统版严格默认推荐 SQLite 保障 100% 物理硬隔离）、共享 PG 容器内 `mengya_local` 专属库与账号幂等创建；
- **`bin/nginx.sh` (网关与证书安全域)**：负责 OpenSSL SAN 扩展证书签发、Nginx 反代配置写入、带时间戳快照防误触机制；
- **`bin/data.sh` (业务数据域)**：负责本地全量脱敏样例数据 (971条) 检查与补齐 (`init_data_local`)。

#### 10.4.3 模块加载守卫机制
```bash
for mod in env process python db nginx data; do
    mod_file="$SCRIPT_DIR/bin/${mod}.sh"
    if [ -f "$mod_file" ]; then
        . "$mod_file"
    else
        echo -e "\033[1;31m[错误] 缺失核心组件: bin/${mod}.sh，请检查项目完整性！\033[0m" >&2
        exit 1
    fi
done
```
该设计从架构底层确保任何模块缺失均可即时被感知，杜绝半执行隐患，且 100% 保持了外部命令行交互与定时任务调度的兼容性。

### 10.5 孕育阶段全域自适应协同规范：胎教故事周数智能跳转与交互体验对齐 (v1.42)

#### 10.5.1 业务诉求与体验对齐现状
在平台的母婴孕育周期中，用户在个人档案中配置了孕周或预产期后，系统通过 `useAuthStore` 全局分发 `stage` 状态（包含 `is_pregnant` 判定及当前孕周 `value`）。此前孕期周历（`PregnancyWeeklyPage`）与孕期食谱（`PregnancyRecipePage`）均已实现基于用户真实孕周的自动化进入定位，而胎教故事（`FetalStoryPage`）此前未订阅阶段信息，硬编码默认定位于孕 17 周，造成用户在不同功能间跳转时的体验割裂。

#### 10.5.2 核心自适应协同逻辑架构
1. **智能边界截断（Clamp）与医学特性对齐**：
   - 胎儿听觉系统通常在孕 17 周（孕 5 月初）左右开始建立外界感知，系统胎教故事库的数据定义亦覆盖孕 17~40 周（共 24 周）。
   - **孕中晚期（17 ≤ `stage.value` ≤ 40）**：进入页面直接自适应定位到用户当前真实孕周，故事列表联动刷新。
   - **孕早期（1 ≤ `stage.value` < 17）**：智能吸附到最早胎教周（第 17 周），并弹出温情科普提示框：“您当前处于孕 X 周，胎儿听觉一般于孕17周左右开始发育，胎教故事从孕17周开启，已为您定位至第17周故事”。
   - **超期孕周（`stage.value` > 40）**：智能截断至第 40 周（足月故事）。
   - **非孕期或未配置阶段**：保持向后兼容的第 17 周默认推荐。
2. **多态视觉反馈与一键跳回交互**：
   - **周选择器按钮高亮**：
     - 当前正在浏览的周：采用主题色全填充 `bg-brand-500 font-medium text-white shadow-sm`；
     - 用户当前的真实孕周（当浏览其他周时）：采用浅色高对比度外环 `bg-brand-100 text-brand-700 font-medium ring-2 ring-brand-400 dark:bg-brand-950 dark:text-brand-300` 显著标记，便于快速识别与跳回；
     - 浏览当前孕周时：在周摘要旁附带「当前孕周」主题徽章。
   - **动态提示胶囊条**：在按周模式顶部展示阶段自适应提示横幅，并在用户切换至其他周时提供「返回我的孕周 (第X周)」一键直达操作。
3. **黑夜/白天模式全面协调**：
   - 提示条、月份快捷键、周数指示器、故事卡片与详情弹窗全面覆盖 Tailwind `dark:` 语义化类，保障双主题模式下良好的对比度与视觉体验。

### 10.6 .env 环境变量持久化与数据库存储模式动态重配机制规范 (v1.43)

#### 10.6.1 架构设计背景
系统在首次执行 `run.sh` 初始化后，会将用户的决策结果（硬件探针推荐或交互选择）以及系统密钥持久化写入 `.env` 文件。为了满足用户在后续运维过程中随时重新调整数据库存储架构（如从 SQLite 平滑升级至共享 PG，或从独立 PG 降级为 SQLite）的需求，同时避免用户因盲目删除 `.env` 导致 `SECRET_KEY`、端口等核心配置丢失，系统建立了规范化的重新配置标准流程与帮助内嵌机制。

#### 10.6.2 核心机制与实现逻辑
1. **显式重配子命令与参数解析**：
   - 增加 `./run.sh reconfig` 原生子命令；
   - 支持 `--reconfig` / `--reconfig-db` 命令行开关；
   - 支持 `-m, --mode <sqlite|shared|dedicated>` 参数直接切模；
   - 支持 `-y, --yes` 非交互兜底，保障 Cron/自动化运维流水线零阻塞。
2. **说明函数封装与帮助模块内嵌**：
   - 在组件模块 `bin/db.sh` 中抽象出 `show_db_reconfig_guide()` 专用展示函数；
   - 在 `run.sh` 的 `help` 模块末尾统一挂载调用，确保终端用户执行 `./run.sh help` 或直接输入 `./run.sh` 即可一览无余。
3. **配置文件容错与自愈策略**：
   - 推荐优先采用 `./run.sh reconfig` 或修改 `.env` 中的 `DB_MODE`；
   - 严正声明直接删除整个 `.env` 文件对 `SECRET_KEY` 与自定义参数的破坏性副作用，引导规范化运维。

### 10.7 PostgreSQL 镜像动态探针感知与零硬编码复用规范 (v1.44)

#### 10.7.1 架构设计背景与治理痛点
此前版本在容器化数据库部署中存在部分写死隐患：
1. `.env.example` 模板硬编码了 `DB_IMAGE=pgvector/pgvector:pg18` 与 `SHARED_PG_CONTAINER=pgvector-18`，导致新节点部署复制 `.env` 时提前赋死值，绕过了镜像探测；
2. 用户显式指定自定义版本时，若本地尚未下载，底层探针曾错误地强制回退至本地已有旧镜像，破坏了用户的自定义预期；
3. 宿主机无任何 PG 镜像时，硬编码拉取体积庞大的 `pgvector/pgvector:pg18`（约 500MB~1GB），未能选用更通用成熟轻量的官方版本；
4. 共享模式下硬编码兜底容器名 `pgvector-18`，在无该容器的异构节点上引发连接断开。

#### 10.7.2 核心机制与治理规范
1. **用户自定义优先原则（100% 遵从，决不篡改）**：
   - 用户通过命令行 `-i / --db-image <IMAGE>` 或在 `.env` 中配置 `DB_IMAGE` 时，系统将其视为绝对不可覆盖的决策输入；
   - 若本地已存在该镜像：标记 `DB_PULL_POLICY="never"`，就地复用，零网络开销；
   - 若本地尚无该镜像：标记 `DB_PULL_POLICY="if_not_present"`，启动时从 Registry 精准拉取用户指定版本，严禁回退到本地其他旧镜像。
2. **服务器本地已有镜像优先复用策略**：
   - 当用户未指定自定义镜像时，探针依次检索：
     - ① 宿主机正在运行的 PG 容器所使用的镜像；
     - ② 本地已存在的官方 Alpine / PostgreSQL 轻量镜像；
     - ③ 本地任何现存的可用 PG 镜像。
     命中任意本地镜像即就地复用并设为 `never`，彻底消除重复拉取。
3. **内置默认轻量镜像与按需拉取**：
   - 全新空服务器（本地无任何 PG 镜像）且选用 PG 存储模式时，自动采用内置轻量成熟镜像（`postgres:15-alpine`，支持 `DEFAULT_PG_IMAGE` 覆盖），仅在此场景下触发自动下载（`if_not_present`）。
4. **共享 PG 模式（shared）零硬编码与智能自愈**：
   - 彻底移除 `pgvector-18` 硬编码；
   - 动态嗅探宿主机运行中 PG 容器；若未运行但存在已停止容器则尝试拉起自愈；
   - 宿主机完全无 PG 容器时，给出明确诊断并智能平滑降级（Docker版降级为独立PG，传统版降级为SQLite），保障服务可用性。

### 10.8 数据库交互式重配链路修复与全参连接自定义规范 (v1.45)

#### 10.8.1 架构设计背景与根因治理
针对执行 `./run.sh` 配合 `--reconfig` / `--reconfig-db` 时未弹出数据库选择向导的问题，经端到端全链路审计，治理了以下 4 项连锁缺陷：
1. **参数解析缺省回退缺陷**：当仅输入 `./run.sh --reconfig` 时，因未指定子命令触发 `[ -z "$CMD" ] && CMD="help"`，导致误入帮助输出而跳过向导。修复后自动识别 `--reconfig` 并赋予 `CMD="reconfig"`；
2. **restart 免交互过早拦截**：`choose_db_mode()` 的第 1 步免交互判定中 `if [ "$CMD" = "restart" ]` 优先于 `RECONFIG_DB` 判定，导致 `./run.sh restart --reconfig` 直接静默退出。修复为仅在 `[ "$RECONFIG_DB" != "1" ]` 时生效；
3. **无 TTY 环境检测误杀**：原 `if [ "$NON_INTERACTIVE" = "1" ] || [ ! -t 0 ]` 将子 shell、IDE 终端与管道误判为非交互定时任务。修复后将后台自愈与用户显式指令解耦，显式传入 `--reconfig` 时强制呈现交互式决策菜单；
4. **传统版端口占用提早退出**：`setup_db_for_mode` 调用时机前置到 `start)` 与 `restart)` 入口，杜绝因服务已占用端口导致的提早 return。

#### 10.8.2 全参数连接信息自定义与持久化规范
为满足传统部署环境下对独立 SQLite、本地或外部 PostgreSQL 账号权限、指定端口的高级需求，系统在 `run.sh` 与 `bin/db.sh` 中全面支持以下命令行选项与自动持久化配置：
- `--db-user <USER>`: 自定义 PostgreSQL 用户名（默认: `mengya_local`）；
- `--db-pass <PASS>`: 自定义 PostgreSQL 连接密码（默认: `mengya123`）；
- `--db-name <DB>`: 自定义 PostgreSQL 数据库名/实例名（默认: `mengya_local`）；
- `--db-port <PORT>`: 自定义 PostgreSQL 端口（默认: `5432` / `5433`）；
- `--db-host <HOST>`: 自定义 PostgreSQL 主机地址（默认: `127.0.0.1`）；
- `--database-url <URL>`: 直接覆盖指定完整的标准连接串（如 `postgresql://user:pass@127.0.0.1:port/dbname`）。

所有参数均自动幂等写入当前目录 `.env`，并在服务启动或重启时组装为标准 `DATABASE_URL`，同时保障传统版默认 SQLite 模式下与 Docker 版本的 100% 物理隔离。

### 10.9 run.sh 脚本模块化拆分与自定义变量独立解耦规范 (v1.46)

#### 10.9.1 微内核启动器重构
为提升传统版本运维脚本的可读性与工程维护性，系统将 `run.sh` 重构为**轻量级微内核调度器**：
1. **体积与行数极致瘦身**：`run.sh` 脚本由原来的 530+ 行精简至 120 行左右，只负责环境引导、模块动态遍历载入（`for mod in env config python process db nginx data help; do ...`）以及最终子命令的极简调度分发；
2. **生命周期高内聚下沉**：将 `start_backend()`, `start_service()`, `restart_service()`, `show_status()` 全部下沉归集至 `bin/process.sh`，使 `process.sh` 成为统一的本地多进程生命周期管理管家；
3. **帮助系统独立收口**：将长篇帮助说明文档、参数说明与典型启动示例迁移至独立模块 `bin/help.sh`（`show_cli_help()` 函数），彻底移除主脚本冗余代码。

#### 10.9.2 自定义变量与配置解析独立模块 (`bin/config.sh`)
将传统版本所有自定义变量、参数解析与持久化逻辑独立抽离并封装至 `bin/config.sh`：
- **`init_default_configs()`**：声明并统一初始化本地端口（`PORT`, `FRONTEND_PORT`，默认 5173）、超级管理员账密（`ADMIN_USERNAME`, `ADMIN_PASSWORD` 等）、SNI 匹配域名、Nginx 路径、PID 与日志文件路径以及全套数据库连接参数；
- **`parse_cli_args "$@"`**：专职承接所有命令行参数循环解析（包括 `-p`, `-u`, `-P`, `-d`, `-m`, `--db-*`, `--reconfig`, `-y` 等）；
- **`apply_and_save_configs()`**：对用户显式传入的自定义参数进行校验，并自动调用 `update_env_var` 持久化同步写入 `.env` 文件；
- **`export_runtime_vars()`**：统一向后置运行环境导出 Django 运行时所需的核心环境变量。

### 10.10 数据库全量变量集中归集于 config.sh 治理规范 (v1.47)

#### 10.10.1 治理背景与单点收拢设计
在传统版本中，此前数据库相关变量分散在 `bin/config.sh`、`bin/db.sh` 以及 `bin/process.sh` 中，并在多处使用了冗余后备默认值（如 `${POSTGRES_USER:-mengya_local}`、`${POSTGRES_DB:-mengya_local}` 等）。用户若希望一次性自定义修改所有数据库默认配置，需要跨多个文件逐一排查，存在维护心智负担与遗漏风险。

为此，系统在 v1.47 版本确立了**数据库全量变量统一集中归集规范**：
1. **单一事实来源（Single Source of Truth）**：所有与数据库、存储引擎相关的可自定义变量，全部一站式归集至 `bin/config.sh` 的 `init_default_configs()` 与 `export_runtime_vars()` 中声明与导出；
2. **严格三级配置优先级**：
   $$\text{CLI 命令行显式参数 (--db-*, -m, --db-image)} > \text{.env 本地持久化配置} > \text{config.sh 代码级默认定义}$$
3. **消除跨模块硬编码后备**：`bin/db.sh` 与 `bin/process.sh` 彻底移除多余的 `:-mengya_local`、`:-5432` 等内联 fallback，统一直接消费 `config.sh` 预先初始化并导出的规范变量。

#### 10.10.2 一站式归集变量矩阵清单
在 `mengya-local/bin/config.sh` 中统一声明并维护的核心数据库变量如下：
- `APP_NAME`：应用命名空间（默认 `mengya_local`）；
- `DB_MODE`：数据库部署模式（传统版默认严格采用 `sqlite`，保障与 Docker 版数据 100% 物理隔离）；
- `DEFAULT_PG_IMAGE`：内置默认 PG 镜像版本（默认 `postgres:15-alpine`）；
- `DB_IMAGE`：用户指定或探针自适应复用的目标 PG 镜像；
- `DB_PULL_POLICY`：镜像拉取策略（就地复用为 `never`，按需下载为 `if_not_present`）；
- `DB_DATA_DIR`：PG 容器挂载目录（默认 `/var/lib/postgresql/data`）；
- `DB_CONTAINER_NAME`：独立 PG 模式专属容器名（默认 `${APP_NAME}-pg`）；
- `SHARED_PG_CONTAINER`：共享模式目标 PG 容器名；
- `POSTGRES_USER`：PostgreSQL 用户名（默认 `mengya_local`）；
- `POSTGRES_PASSWORD`：PostgreSQL 连接密码（默认 `mengya123`）；
- `POSTGRES_DB`：PostgreSQL 数据库/实例名（默认 `mengya_local`）；
- `POSTGRES_PORT`：PostgreSQL 连接端口（默认 `5432`，独立模式遇冲突自适应 `5433`）；
- `POSTGRES_HOST`：PostgreSQL 访问主机（默认 `127.0.0.1`）；
- `DATABASE_URL`：标准数据库连接串（支持在此直接显式定义，或留空由系统自动按参数标准组装）；
- `SQLITE_PATH`：SQLite 模式数据持久化路径（默认 `$BACKEND_DIR/db.sqlite3`）；
- `USE_POSTGRES`：是否启用 PostgreSQL 引擎（默认 `False`，启用 PG 模式时自动置为 `True`）。

### 10.11 传统模式专属 PG 容器生命周期联动终止与 unless-stopped 重启策略规范 (v1.48)

#### 10.11.1 传统模式数据库容器未终止问题与生命周期联动
此前在传统部署版本（`mengya-local`）中，当用户选用独立专属 PostgreSQL 模式（`dedicated`）时，启动脚本会拉起容器 `${APP_NAME}-pg`（如 `mengya_local-pg`）。但在执行 `./run.sh stop` 时，由于仅查杀终止了本地 Django 后端 Python 进程，未触及 Docker 容器，导致数据库容器一直残留在后台运行。

为此，系统确立了**传统模式数据库容器生命周期联动机制**：
1. **新增容器下线感知函数 (`bin/db.sh` -> `stop_db_container`)**：
   通过 Docker 管理指令安全探查当前应用专属的独立 PG 容器是否运行。若存在，执行 `docker stop "$DB_CONTAINER_NAME"` 进行平滑停止；
2. **停止流全面打通 (`bin/process.sh` -> `stop_all`)**：
   在停止本地 Django 服务的同时，联动执行 `stop_db_container`，实现程序停止时本地进程与关联数据库容器的一键完全终止；
3. **共享模式安全隔离**：
   在 `shared` 模式下严格保持边界，不触碰宿主机其他系统共用的已有 PG 实例。

#### 10.11.2 重启策略纠偏至 unless-stopped
- **避免 `always` 策略失控**：初次创建专属 PG 容器时保持 `--restart unless-stopped`；
- **存量容器动态纠偏**：在唤醒已有专属 PG 容器前，自动调用 `docker update --restart unless-stopped "$DB_CONTAINER_NAME"`，将历史可能配置为 `always` 的存量容器无缝纠正为标准 `unless-stopped` 策略。
