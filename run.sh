#!/usr/bin/env bash
# ============================================================
# 萌芽（mengya）平台 - 本地传统模式管理脚本 (mengya-local)
#
# 架构模型：
#   - 外部访问：直连 FRONTEND_PORT（默认 5173），或通过 Nginx 统一反代（HTTPS SNI 443 唯一安全入口）
#   - 服务模型：Django 单体一体化服务，监听 0.0.0.0:$FRONTEND_PORT（统一托管前端 SPA 页面、静态资源与后端 API）
#   - 前端架构：前端生产静态产物已合并入 Django (templates/ & static/)，彻底移除 Node.js 常驻运行时，解决内存高占用
#   - 数据库：本地 SQLite (db.sqlite3)，轻量独立
#
# 支持命令：
#   ./run.sh start      启动本地前后端服务
#   ./run.sh stop       停止本地前后端服务
#   ./run.sh restart    重启本地前后端服务
#   ./run.sh status     查看运行状态与端口占用
#   ./run.sh add_nginx  生成基于 SNI 443 端口的 Nginx SSL 反代配置及证书
#   ./run.sh help       查看帮助信息
#
# 环境变量配置项（均有默认值，可按需覆盖）：
#   PORT              外部访问端口（默认 443，等同于 EXTERNAL_PORT）
#   EXTERNAL_PORT     外部 HTTPS 访问端口（默认 443）
#   SERVER_NAME       SNI 匹配域名（默认 mengya.local localhost）
#   FRONTEND_PORT     前端内部服务端口（默认 5173，仅供内部反代）
#   FRONTEND_PORT     一体化服务访问端口（默认 5173，托管前端静态与后端 API）
#   ADMIN_USERNAME    管理员账号（默认 admin）
#   ADMIN_PASSWORD    管理员密码（默认 admin123）
#   ADMIN_NICKNAME    管理员昵称（默认 管理员）
#   NGINX_CONF_DIR    Nginx 额外配置目录（默认 /opt/service/nginx/conf.d）
#   NGINX_CERT_DIR    Nginx SSL 证书目录（默认当前项目 ssl 目录）
#   ENABLE_HTTP_REDIRECT 是否生成 80 转 443 重定向规则（1=开启，0=关闭，默认 1）
# ============================================================

set -e

export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"
# 若当前通过 sh / dash 启动，且系统存在 bash，自动无缝重入为 bash
if [ -z "$BASH_VERSION" ]; then
    if command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    fi
fi

SCRIPT_SOURCE="${BASH_SOURCE:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE" 2>/dev/null || echo ".")" && pwd)"
cd "$SCRIPT_DIR"

# 1. 自动环境自愈检查：若 .env 不存在，优先从 .env.example 复制初始化
if [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
        echo -e "\033[1;33m[提示] 未找到 .env 配置文件，自动从 .env.example 复制初始化...\033[0m"
        cp ".env.example" ".env"
    else
        touch ".env"
    fi
fi

if [ -f ".env" ]; then
    # 自动修复 .env 中带空格但未加引号的值（避免 bash source .env 时报 command not found）
    sed -i.bak -E 's/^([A-Za-z0-9_]+)=([^"#][^#]*[[:space:]][^#]*)$/\1="\2"/' ".env" 2>/dev/null && rm -f ".env.bak"
    set -a
    # shellcheck disable=SC1091
    . ./.env 2>/dev/null || true
    set +a
fi

# 更新/持久化变量到 .env 文件的辅助函数

# 2. 依次动态载入 bin/ 目录下独立功能组件模块
for mod in env process python db nginx data; do
    mod_file="$SCRIPT_DIR/bin/${mod}.sh"
    if [ -f "$mod_file" ]; then
        # shellcheck disable=SC1090
        . "$mod_file"
    else
        echo -e "\033[1;31m[错误] 缺失核心组件: bin/${mod}.sh，请检查项目完整性！\033[0m" >&2
        exit 1
    fi
done




# 外部访问端口默认统一为 443
PORT="${PORT:-${EXTERNAL_PORT:-443}}"
EXTERNAL_PORT="$PORT"
SERVER_NAME=$(normalize_domains "${SERVER_NAME:-${DOMAIN:-mengya.local localhost}}")

# 一体化服务访问端口（默认 5173）
FRONTEND_PORT="${FRONTEND_PORT:-5173}"
BACKEND_PORT="${FRONTEND_PORT}"

ADMIN_USERNAME="${ADMIN_USERNAME:-${ADMIN_PHONE:-admin}}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin123}"
ADMIN_NICKNAME="${ADMIN_NICKNAME:-管理员}"

NGINX_CONF_DIR=$(resolve_abs_path "${NGINX_CONF_DIR:-/opt/service/nginx/conf.d}")
NGINX_CERT_DIR=$(resolve_abs_path "${NGINX_CERT_DIR:-$SCRIPT_DIR/ssl}")
if [ ! -d "$NGINX_CERT_DIR" ]; then
    mkdir -p "$NGINX_CERT_DIR"
fi
NGINX_CONF="$NGINX_CONF_DIR/mengya_ssl.conf"
ENABLE_HTTP_REDIRECT="${ENABLE_HTTP_REDIRECT:-1}"

# 自动探测后端代码目录（兼容当前根目录或 backend/ 子目录）
BACKEND_DIR="$SCRIPT_DIR"
if [ -d "$SCRIPT_DIR/backend" ] && [ -f "$SCRIPT_DIR/backend/manage.py" ]; then
    BACKEND_DIR="$SCRIPT_DIR/backend"
fi
FRONTEND_DIR="$SCRIPT_DIR/frontend"

LOG_DIR="$SCRIPT_DIR/logs"
PID_DIR="$SCRIPT_DIR/logs"
BACKEND_PID_FILE="$PID_DIR/backend.pid"
FRONTEND_PID_FILE="$PID_DIR/frontend.pid"

[ -d "$LOG_DIR" ] || mkdir -p "$LOG_DIR"
[ -d "$PID_DIR" ] || mkdir -p "$PID_DIR"


# ============================================================
# 核心生命周期管理函数（仅保留基础启停与状态展示）
# ============================================================

start_backend() {
    echo "==> 启动 Django 一体化服务（端口 $FRONTEND_PORT，托管前端静态与后端 API）"
    if port_in_use "$FRONTEND_PORT"; then
        echo "  [提示] 端口 $FRONTEND_PORT 已被占用，跳过服务启动。"
        echo "         如需重新启动，请先执行 ./run.sh stop"
        return 0
    fi

    local PY_CMD
    PY_CMD=$(detect_python)
    if [ -z "$PY_CMD" ]; then
        echo "  [错误] 未找到 python3 或 python，请先安装 Python 3.10+"
        return 1
    fi

    local PYTHON
    PYTHON=$(ensure_backend_deps "$PY_CMD")

    cd "$BACKEND_DIR"
    setup_db_for_mode
    # 使用文件互斥锁，避免双版本同时启动时并发执行数据库迁移导致死锁或冲突
    local LOCK_FILE="/tmp/mengya_db_migrate.lock"
    local have_lock=0
    if command -v flock >/dev/null 2>&1; then
        exec 9>"$LOCK_FILE" 2>/dev/null || true
        if flock -w 60 9 2>/dev/null; then
            have_lock=1
        fi
    fi

    # 静态资源自愈：检测 static/fetal-stories，缺失时自动从 frontend/public/fetal-stories 同步
    if [ ! -d "$PROJECT_ROOT/static/fetal-stories" ] && [ -d "$PROJECT_ROOT/frontend/public/fetal-stories" ]; then
        echo "  [自愈] 自动同步胎教故事静态产物至 static/fetal-stories..."
        mkdir -p "$PROJECT_ROOT/static"
        cp -r "$PROJECT_ROOT/frontend/public/fetal-stories" "$PROJECT_ROOT/static/"
    fi

    echo "  执行数据迁移..."
    "$PYTHON" manage.py migrate --noinput
    echo "  初始化种子数据（孕期周历/胎教故事/孕期食谱/幼儿百科/商品品牌/待产清单）..."
    "$PYTHON" manage.py init_data --skip-if-exists

    if [ "$have_lock" = "1" ]; then
        flock -u 9 2>/dev/null || true
    fi

    echo "  同步单一管理员账号 ($ADMIN_USERNAME)..."
    ADMIN_USERNAME="$ADMIN_USERNAME" \
    ADMIN_PASSWORD="$ADMIN_PASSWORD" \
    ADMIN_NICKNAME="$ADMIN_NICKNAME" \
    "$PYTHON" manage.py ensure_admin

    # 监听 0.0.0.0:$FRONTEND_PORT：允许本地直连与 Nginx 反向代理
    nohup "$PYTHON" manage.py runserver 0.0.0.0:"$FRONTEND_PORT" \
        >> "$LOG_DIR/backend.log" 2>&1 &
    echo $! > "$BACKEND_PID_FILE"
    echo "  服务 PID: $(cat "$BACKEND_PID_FILE")"
    echo "  日志: $LOG_DIR/backend.log"
    cd "$SCRIPT_DIR"
}

show_status() {
    echo "============================================"
    echo "  萌芽（mengya-local）运行状态"
    echo "============================================"
    local bp
    bp=$(get_backend_pid)

    echo "  Django 一体化服务: $([ -n "$bp" ] && echo "运行中 (PID $bp, 端口 $FRONTEND_PORT)" || (port_in_use "$FRONTEND_PORT" && echo "端口占用 (外部进程)" || echo "未运行"))"
    echo "  前端托管架构     : 前端生产静态产物已合并至 Django (templates/ & static/)，零 Node 进程"
    echo "  Nginx SNI        : $([ -f "$NGINX_CONF" ] && echo "已配置 ($NGINX_CONF)" || echo "未生成 (执行 ./run.sh add_nginx 生成)")"
    echo "  外部访问端口     : $EXTERNAL_PORT (SNI 域名: $SERVER_NAME)"
    print_access_urls "统一访问入口" "$EXTERNAL_PORT"
    echo "  本地直连入口     : http://127.0.0.1:$FRONTEND_PORT/"
    echo "  数据库存储模式   : ${DB_MODE:-sqlite}"
    if [ "${DB_MODE:-sqlite}" = "sqlite" ]; then
        echo "  数据库物理文件   : $SCRIPT_DIR/db.sqlite3 [与 Docker 版 100% 物理隔离]"
    elif [ "$DB_MODE" = "shared" ]; then
        echo "  共享 PG 容器     : ${SHARED_PG_CONTAINER:-pgvector-18} (专属库: ${POSTGRES_DB:-mengya_local})"
        echo "  数据库连接       : $DATABASE_URL"
    else
        echo "  独立 PG 容器     : ${APP_NAME:-mengya_local}-pg"
        echo "  数据库连接       : $DATABASE_URL"
    fi
    echo "  架构安全设计     : Django 单体一体化全栈托管，彻底移除 Node 常驻服务与内存开销"
    echo "  日志目录         : $LOG_DIR"
    echo "============================================"
}


# 解析命令行参数与自定义变量
CMD=""
CUSTOM_PORT=""
CUSTOM_ADMIN_USER=""
CUSTOM_ADMIN_PASS=""
CUSTOM_ADMIN_NICK=""
CUSTOM_DOMAIN=""
CUSTOM_DB_USER=""
CUSTOM_DB_PASS=""
CUSTOM_DB_NAME=""
CUSTOM_DB_PORT=""
CUSTOM_DB_HOST=""
CUSTOM_DATABASE_URL=""
EXTRA_ARGS=""

while [ $# -gt 0 ]; do
    case "$1" in
        start|stop|restart|status|add_nginx|init_data|seed|reconfig|reconfig_db|help)
            if [ -z "$CMD" ]; then
                CMD="$1"
            else
                EXTRA_ARGS="${EXTRA_ARGS:+$EXTRA_ARGS }$1"
            fi
            shift
            ;;
        -m|--mode|--db-mode)
            CUSTOM_DB_MODE="$2"
            shift 2
            ;;
        --shared-pg|--shared-container)
            CUSTOM_SHARED_PG="$2"
            shift 2
            ;;
        --db-user|--db-username)
            CUSTOM_DB_USER="$2"
            shift 2
            ;;
        --db-pass|--db-password)
            CUSTOM_DB_PASS="$2"
            shift 2
            ;;
        --db-name|--db-database)
            CUSTOM_DB_NAME="$2"
            shift 2
            ;;
        --db-port)
            CUSTOM_DB_PORT="$2"
            shift 2
            ;;
        --db-host)
            CUSTOM_DB_HOST="$2"
            shift 2
            ;;
        --database-url)
            CUSTOM_DATABASE_URL="$2"
            shift 2
            ;;
        --reconfig|--reconfig-db)
            RECONFIG_DB=1
            shift
            ;;
        -y|--yes|--non-interactive)
            NON_INTERACTIVE=1
            shift
            ;;
        -p|--port)
            CUSTOM_PORT="$2"
            shift 2
            ;;
        -u|--admin|--user|--username)
            CUSTOM_ADMIN_USER="$2"
            shift 2
            ;;
        -P|--password|--pass)
            CUSTOM_ADMIN_PASS="$2"
            shift 2
            ;;
        -n|--nickname)
            CUSTOM_ADMIN_NICK="$2"
            shift 2
            ;;
        -d|--domain|--server-name)
            CUSTOM_DOMAIN="$2"
            shift 2
            ;;
        -h|--help)
            CMD="help"
            shift
            ;;
        --)
            shift
            while [ $# -gt 0 ]; do EXTRA_ARGS="${EXTRA_ARGS:+$EXTRA_ARGS }$1"; shift; done
            break
            ;;
        *)
            echo -e "\033[1;33m[警告] 未知选项: $1\033[0m"
            shift
            ;;
    esac
done

if [ -z "$CMD" ]; then
    if [ "$RECONFIG_DB" = "1" ]; then
        CMD="reconfig"
    else
        CMD="help"
    fi
fi

# 应用自定义参数并持久化至 .env
if [ -n "$CUSTOM_DB_MODE" ]; then
    DB_MODE="$CUSTOM_DB_MODE"
    update_env_var "DB_MODE" "$CUSTOM_DB_MODE"
    echo -e "\033[0;32m[配置] 数据库部署模式已设置为: $CUSTOM_DB_MODE (已同步至 .env)\033[0m"
fi

if [ -n "$CUSTOM_SHARED_PG" ]; then
    SHARED_PG_CONTAINER="$CUSTOM_SHARED_PG"
    update_env_var "SHARED_PG_CONTAINER" "$CUSTOM_SHARED_PG"
    echo -e "\033[0;32m[配置] 共享 PostgreSQL 容器已指定为: $CUSTOM_SHARED_PG (已同步至 .env)\033[0m"
fi

if [ -n "$CUSTOM_DB_USER" ]; then
    POSTGRES_USER="$CUSTOM_DB_USER"
    update_env_var "POSTGRES_USER" "$CUSTOM_DB_USER"
    echo -e "\033[0;32m[配置] 数据库用户名已设置为: $CUSTOM_DB_USER (已同步至 .env)\033[0m"
fi

if [ -n "$CUSTOM_DB_PASS" ]; then
    POSTGRES_PASSWORD="$CUSTOM_DB_PASS"
    update_env_var "POSTGRES_PASSWORD" "$CUSTOM_DB_PASS"
    echo -e "\033[0;32m[配置] 数据库连接密码已更新 (已同步至 .env)\033[0m"
fi

if [ -n "$CUSTOM_DB_NAME" ]; then
    POSTGRES_DB="$CUSTOM_DB_NAME"
    update_env_var "POSTGRES_DB" "$CUSTOM_DB_NAME"
    echo -e "\033[0;32m[配置] 数据库名/实例名已设置为: $CUSTOM_DB_NAME (已同步至 .env)\033[0m"
fi

if [ -n "$CUSTOM_DB_PORT" ]; then
    POSTGRES_PORT="$CUSTOM_DB_PORT"
    update_env_var "POSTGRES_PORT" "$CUSTOM_DB_PORT"
    echo -e "\033[0;32m[配置] 数据库连接端口已设置为: $CUSTOM_DB_PORT (已同步至 .env)\033[0m"
fi

if [ -n "$CUSTOM_DB_HOST" ]; then
    POSTGRES_HOST="$CUSTOM_DB_HOST"
    update_env_var "POSTGRES_HOST" "$CUSTOM_DB_HOST"
    echo -e "\033[0;32m[配置] 数据库主机地址已设置为: $CUSTOM_DB_HOST (已同步至 .env)\033[0m"
fi

if [ -n "$CUSTOM_DATABASE_URL" ]; then
    DATABASE_URL="$CUSTOM_DATABASE_URL"
    update_env_var "DATABASE_URL" "$CUSTOM_DATABASE_URL"
    echo -e "\033[0;32m[配置] 数据库连接串 DATABASE_URL 已直接指定 (已同步至 .env)\033[0m"
fi

if [ -n "$CUSTOM_PORT" ]; then
    FRONTEND_PORT="$CUSTOM_PORT"
    update_env_var "FRONTEND_PORT" "$CUSTOM_PORT"
    echo -e "\033[0;32m[配置] 前端访问端口已设置为: $CUSTOM_PORT (已同步至 .env)\033[0m"
fi

if [ -n "$CUSTOM_ADMIN_USER" ]; then
    ADMIN_USERNAME="$CUSTOM_ADMIN_USER"
    ADMIN_PHONE="$CUSTOM_ADMIN_USER"
    update_env_var "ADMIN_USERNAME" "$CUSTOM_ADMIN_USER"
    update_env_var "ADMIN_PHONE" "$CUSTOM_ADMIN_USER"
    echo -e "\033[0;32m[配置] 管理员账号已设置为: $CUSTOM_ADMIN_USER (已同步至 .env)\033[0m"
fi

if [ -n "$CUSTOM_ADMIN_PASS" ]; then
    ADMIN_PASSWORD="$CUSTOM_ADMIN_PASS"
    update_env_var "ADMIN_PASSWORD" "$CUSTOM_ADMIN_PASS"
    echo -e "\033[0;32m[配置] 管理员密码已更新 (已同步至 .env)\033[0m"
fi

if [ -n "$CUSTOM_ADMIN_NICK" ]; then
    ADMIN_NICKNAME="$CUSTOM_ADMIN_NICK"
    update_env_var "ADMIN_NICKNAME" "$CUSTOM_ADMIN_NICK"
fi

if [ -n "$CUSTOM_DOMAIN" ]; then
    SERVER_NAME=$(normalize_domains "$CUSTOM_DOMAIN")
    update_env_var "SERVER_NAME" "$SERVER_NAME"
    echo -e "\033[0;32m[配置] SNI 匹配域名已设置为: $SERVER_NAME (已同步至 .env)\033[0m"
fi

export FRONTEND_PORT
export ADMIN_USERNAME
export ADMIN_PHONE
export ADMIN_PASSWORD
export ADMIN_NICKNAME
export SERVER_NAME
export EXTERNAL_PORT
export DB_MODE
export APP_NAME
export SHARED_PG_CONTAINER
export RECONFIG_DB
export NON_INTERACTIVE
export POSTGRES_USER
export POSTGRES_PASSWORD
export POSTGRES_DB
export POSTGRES_PORT
export POSTGRES_HOST
export DATABASE_URL
export CUSTOM_DB_USER
export CUSTOM_DB_PASS
export CUSTOM_DB_NAME
export CUSTOM_DB_PORT
export CUSTOM_DB_HOST
export CUSTOM_DATABASE_URL

case "$CMD" in
    start)
        cleanup_cache
        setup_db_for_mode
        # 补全主流程中缺失的 SSL 证书与 Nginx 配置创建函数调用
        gen_ssl_cert
        gen_nginx_config
        start_backend
        echo ""
        echo "============================================"
        echo "  萌芽（mengya-local）启动完成！"
        print_access_urls "统一访问地址" "$EXTERNAL_PORT"
        echo "  本地直连地址: http://127.0.0.1:$FRONTEND_PORT/"
        echo "  管理员账号:   $ADMIN_USERNAME"
        echo "  一体化架构:   前端静态资源已合并至 Django，彻底消除 Node.js 常驻内存开销"
        echo "  Nginx 配置:   $([ -f "$NGINX_CONF" ] && echo "已就绪 ($NGINX_CONF)" || echo "尚未生成，可执行 ./run.sh add_nginx 生成")"
        echo "============================================"
        ;;
    stop)
        stop_all
        ;;
    restart)
        stop_all
        sleep 1
        cleanup_cache
        setup_db_for_mode
        # 会话强制注销，强制所有历史登录用户下线重新登录
        invalidate_all_sessions
        # 补全主流程中缺失的 SSL 证书与 Nginx 配置创建函数调用
        gen_ssl_cert
        gen_nginx_config
        start_backend
        echo ""
        echo "============================================"
        echo "  萌芽（mengya-local）重启完成！"
        print_access_urls "统一访问地址" "$EXTERNAL_PORT"
        echo "  本地直连地址: http://127.0.0.1:$FRONTEND_PORT/"
        echo "  管理员账号:   $ADMIN_USERNAME"
        echo "  一体化架构:   前端静态资源已合并至 Django，彻底消除 Node.js 常驻内存开销"
        echo "============================================"
        ;;
    add_nginx)
        gen_ssl_cert
        gen_nginx_config
        ;;
    status)
        show_status
        ;;
    init_data|seed)
        init_data_local $EXTRA_ARGS
        ;;
    reconfig|reconfig_db)
        RECONFIG_DB=1
        setup_db_for_mode
        echo -e "\033[0;32m[完成] 数据库模式已重新配置并保存至 .env (当前模式: $DB_MODE)\033[0m"
        ;;
    help)
        echo ""
        echo "萌芽（mengya-local）本地模式管理命令："
        echo "  ./run.sh start [选项]        启动本地一体化服务（前端合并至Django，零Node常驻）"
        echo "  ./run.sh stop                停止本地一体化服务"
        echo "  ./run.sh restart [选项]      重启本地一体化服务（前端合并至Django，零Node常驻）"
        echo "  ./run.sh status              查看运行状态与端口占用"
        echo "  ./run.sh add_nginx [选项]    生成基于 SNI 443 端口的 Nginx SSL 反向代理配置"
        echo "  ./run.sh init_data [选项]    检查并补齐全量样例数据（食谱/胎教/百科/周历/清单/商品/品牌）"
        echo "  ./run.sh reconfig            交互式重新配置数据库存储方式（并自动更新 .env）"
        echo "  ./run.sh help                查看帮助"
        echo ""
        echo "常用自定义选项（支持在 start / restart / add_nginx 时追加，自动持久化至 .env）："
        echo "  -p, --port <PORT>            自定义前端内部访问端口（默认 5173）"
        echo "  -u, --admin <USER>           自定义超级管理员账号/手机号（默认 admin）"
        echo "  -P, --password <PASS>        自定义超级管理员登录密码（默认 admin123）"
        echo "  -n, --nickname <NAME>        自定义管理员昵称（默认 管理员）"
        echo "  -d, --domain <DOMAIN>        自定义绑定的 SNI 域名（默认 mengya.local localhost）"
        echo "  -m, --mode <MODE>            显式指定数据库模式 (sqlite | shared | dedicated)"
        echo "  --reconfig, --reconfig-db    重新唤起数据库决策向导，交互式切换数据库存储模式
  --db-user <USER>             自定义 PostgreSQL 用户名（默认 mengya_local）
  --db-pass <PASS>             自定义 PostgreSQL 密码（默认 mengya123）
  --db-name <DB>               自定义 PostgreSQL 数据库名/实例名（默认 mengya_local）
  --db-port <PORT>             自定义 PostgreSQL 连接端口（默认 5432/5433）
  --db-host <HOST>             自定义 PostgreSQL 主机地址（默认 127.0.0.1）
  --database-url <URL>         直接指定完整 DATABASE_URL 连接串"
        echo "  --shared-pg <CONTAINER>      指定共享模式下的宿主机 PostgreSQL 容器名称"
        echo "  -y, --yes                    非交互式模式，免去任何等待（Cron / 重启自动采用推荐值）"
        echo ""
        echo "实用启动示例："
        echo "  ./run.sh start                                 # 默认启动（端口 5173，管理员 admin / admin123）"
        echo "  ./run.sh start -p 5175                         # 自定义以 5175 端口启动"
        echo "  ./run.sh --reconfig                            # 直接唤醒交互式数据库模式选择向导
  ./run.sh start --reconfig                      # 重新选择数据库模式（SQLite / 共享PG / 独立PG）
  ./run.sh start --db-user myuser --db-pass mypass # 自定义数据库连接账号与密码启动"
        echo "  ./run.sh start -m sqlite                       # 直接以 SQLite 本地单文件模式启动并保存至 .env"
        echo "  ./run.sh start -m shared                       # 直接以共享宿主机已有 PG 模式启动并保存至 .env"
        echo "  ./run.sh start -p 5173 -u superadmin -P Pass123 # 自定义端口与管理员账密启动"
        echo "  ./run.sh restart -p 5175                       # 重启并变更为 5175 端口"
        echo "  ./run.sh add_nginx -d mengya.myhost.com        # 为指定域名生成独立反代配置"
        echo ""
        show_db_reconfig_guide
        ;;
    *)
        echo "未知命令: $CMD"
        echo "支持的子命令: start | stop | restart | status | add_nginx | init_data | help"
        exit 1
        ;;
esac

