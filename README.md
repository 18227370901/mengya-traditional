# 萌芽（Mengya）母婴健康与育儿平台 - 本地传统部署版 (mengya-local)

<p align="left">
  <img src="https://img.shields.io/badge/Python-3.10%2B-blue.svg" alt="Python Version">
  <img src="https://img.shields.io/badge/Django-4.2%20LTS-brightgreen.svg" alt="Django Version">
  <img src="https://img.shields.io/badge/Frontend-React%2018%20%7C%20TS%20%7C%20TailwindCSS-purple.svg" alt="Frontend">
  <img src="https://img.shields.io/badge/Database-SQLite3%20%7C%20PostgreSQL-orange.svg" alt="Database">
  <img src="https://img.shields.io/badge/Architecture-Single%20Process%20Monolith-success.svg" alt="Architecture">
  <img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License">
</p>

> **面向新一代母婴家庭的全生命周期（备孕、孕期、育儿）健康陪伴、知识百科、消费决策与智能顾问一体化平台**。专为开发者日常本地调试、源码热重载开发及无 Docker 环境的轻量化主机部署深度定制。
>
> 📌 **当前版本**：`v1.84` | 📖 **[查看全量版本演化与发布历史 (docs/CHANGELOG.md)](docs/CHANGELOG.md)**

<!-- 
  【AI 协作与维护规范 - 严禁违背】
  本项目严格遵循模块化文档分层治理架构（详见根目录 AGENTS.md）：
  1. 严禁在本 README.md 中追加版本更新公告、历史变更流水账或长篇技术细节！README.md 必须严格保持在 150-180 行以内的极简自述形态。
  2. 新版本发布与全量更新日志：请一律追加至 docs/CHANGELOG.md。
  3. 架构设计与重构决策记录：请一律追加至 docs/PSD_System_Design_and_Refactoring.md 并同步更新 docs/PSD_System_Design_and_Refactoring.html。
  4. 本地开发构建脚本一律收纳在 tools/ 目录下。
-->

---

## 🔑 默认管理员账号与安全凭据

初次部署启动后，系统将自动执行 `ensure_admin` 流程并初始化安全凭证：
- **登录账号**：`admin`
- **初始密码**：`admin123`
- **管理员昵称**：`管理员`
- **安全自定义**：支持在根目录 `.env` 文件中通过 `ADMIN_USERNAME`、`ADMIN_PASSWORD`、`ADMIN_NICKNAME` 自定义覆盖；系统内置单管理员生命周期保障，启动时自动清理历史残留管理员并保护普通用户数据完整。

---

## 🌟 核心业务架构与技术特性

1. 🚀 **单体一体化极简托管 (0.0.0.0:5173)**
   - 前端 React SPA 生产构建产物已完整合并至 Django `templates/` 与 `static/` 目录；
   - 生产环境默认集成 WhiteNoise 零拷贝静态托管与 1 年强缓存，彻底消除 StatReloader 扫描进程与 Debug 内存泄漏；
   - 单 Python 进程同时托管 Web 前端页面、静态资产与后端 API，**彻底移除 Node.js 常驻服务**，常驻内存降低 70% 以上，杜绝 OOM 隐患。
2. 🛡️ **本地轻量存储与并发性能优化**
   - 默认严格采用本地独立 SQLite3（`db.sqlite3`），开箱即用，自动迁移；与 Docker 容器版数据保持 100% 物理硬隔离。
3. 👶 **全生命周期健康与育儿陪伴**
   - 涵盖备孕、孕期 1~40 周胎儿发育、妈妈体重/BMI 监测、血压/血糖生命体征智能分析、幼儿生长曲线（WHO 标准）、产检与疫苗智能日历；
   - 结合大语言模型与 SearXNG / 公网多引擎容灾管线，提供智能育儿顾问、胎教故事及母婴商品多维对比雷达。

---

## 🚀 快速启动与运维管理

### 运行环境要求
- **操作系统**：Linux / macOS / Windows (PowerShell / WSL)
- **Python 环境**：Python 3.10+（系统内置 `venv` 模块）
- **Node.js**：**运行无需 Node.js**（仅在二次开发修改前端源码时需要 Node.js 18+）

### 常用运维命令

```bash
# === Windows 环境 (PowerShell) ===
powershell -ExecutionPolicy Bypass -File .\run.ps1 start    # 启动一体化服务 (默认端口 5173)
powershell -ExecutionPolicy Bypass -File .\run.ps1 status   # 查看服务运行状态与端口占用
powershell -ExecutionPolicy Bypass -File .\run.ps1 restart  # 重启服务 (自动清理临时缓存)
powershell -ExecutionPolicy Bypass -File .\run.ps1 stop     # 彻底停止服务并释放端口

# === Linux / macOS 环境 (Bash) ===
./run.sh start      # 启动服务
./run.sh status     # 查看状态
./run.sh restart    # 重启服务
./run.sh stop       # 停止服务
./run.sh add_nginx  # 自动签发 SAN 多域名证书并生成 Nginx 反代配置
./run.sh init_data  # 检查并补齐全量百科、食谱与样例数据
```

> 服务启动后，打开浏览器访问：**[http://localhost:5173/](http://localhost:5173/)**

### 常用命令行自定义参数
| 选项 | 长参数 | 默认值 | 作用说明 |
| :--- | :--- | :--- | :--- |
| `-p` | `--port` | `5173` | 自定义内部运行端口（自动同步持久化写入 `.env`） |
| `-u` | `--admin` | `admin` | 自定义管理员登录账号（同步写入 `.env`） |
| `-P` | `--password` | `admin123` | 自定义管理员登录密码（同步写入 `.env`） |
| `-n` | `--nickname` | `管理员` | 自定义管理员前台展示昵称 |
| `-d` | `--domain` | `mengya.local localhost` | 自定义 Nginx 反代 SNI 域名 |
| `-m` | `--mode` | `sqlite` | 显式指定数据库模式（`sqlite` / `shared` / `dedicated`） |
| - | `--reconfig` | - | 重新唤起数据库部署模式交互向导 |
| `-y` | `--non-interactive` | - | 免交互静默模式（自动化脚本/CI 环境适用） |

---

## 📂 系统文件架构概览

```text
mengya-local/
├── manage.py                          # [核心] Django 主应用标准 CLI 调度入口
├── requirements.txt                   # [核心] 后端 Python 依赖清单
├── run.sh                             # [核心] Linux/macOS 专职后台运维管理脚本
├── run.ps1                            # [核心] Windows PowerShell 一键运维管理脚本
├── README.md                          # [自述] 极简自述与快速导航（< 180 行）
├── AGENTS.md                          # [规范] 跨 AI 协作与维护指南
├── .env.example                       # [配置] 环境变量初始化模板
├── .gitignore                         # [规则] Git 忽略规则
│
├── docs/                              # 📁 [文档中心] 统一管理架构设计、HTML视图与发布日志
│   ├── PSD_System_Design_and_Refactoring.md   # 系统设计与重构权威决策规范
│   ├── PSD_System_Design_and_Refactoring.html # 架构设计离线 HTML 交互视图 (Mermaid)
│   └── CHANGELOG.md                           # 全量版本演化与历史变更日志 (v1.13~v1.84+)
│
├── tools/                             # 📁 [工具中心] 归集非线上常驻的本地开发调试脚本
│   ├── build_frontend.py              # 前端一键构建与静态产物同步脚本 (Path两级回退)
│   └── check_admin_status.py          # 管理员账号状态与锁定诊断脚本 (sys.path动态注入)
│
├── apps/                              # 业务应用包 (Django Apps：core, models, views, services)
├── config/                            # Django 全局配置中心 (settings, urls, wsgi, asgi)
├── frontend/                          # React 18 + TS 前端源码工程 (Vite 5 构建)
├── bin/                               # 运维子模块 (env, process, db, nginx, python, data 等)
├── static/                            # Django 生产静态产物合并目录
├── templates/                         # Django SPA 页面入口模板 (index.html)
└── data/                              # 本地运行时持久化缓存 (holiday_cache.json 等)
```

---

## 📚 详细文档导航

深入了解系统架构决策、全版本演化或运维深度定制，请参阅 `docs/` 目录下的专有文档：

- 📐 **[PSD 架构设计与重构决策文档 (docs/PSD_System_Design_and_Refactoring.md)](docs/PSD_System_Design_and_Refactoring.md)**：包含系统全景技术栈审计、三大数据库部署模式自适应与 6 种物理隔离矩阵、前后台完整设计规格及 ADR-01~36 全部重构决策（另备有含完整图表的 [HTML 交互版](docs/PSD_System_Design_and_Refactoring.html)）；
- 📜 **[全量版本演化与更新日志 (docs/CHANGELOG.md)](docs/CHANGELOG.md)**：记录自 v1.13 至 v1.84 全部迭代历史、缺陷修复与详细技术升级公告；
- 🤖 **[AI 协作与跨工具维护规范 (AGENTS.md)](AGENTS.md)**：约束 Codex、Cursor、Claude Code、Windsurf 等各类 AI 工具严守极简自述与文档分流铁律。

---

## 📄 开源许可证

本项目基于 [MIT License](LICENSE) 开源许可协议发布。
