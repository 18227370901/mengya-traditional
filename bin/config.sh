#!/usr/bin/env bash
# ============================================================
# 萌芽平台 (mengya-local) - 自定义变量与配置解析模块
# ============================================================

init_default_configs() {
    PROJECT_ROOT="${PROJECT_ROOT:-$SCRIPT_DIR}"

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

    RECONFIG_DB=0
    NON_INTERACTIVE=0
}

parse_cli_args() {
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

}

apply_and_save_configs() {
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

}

export_runtime_vars() {
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

    export EXTRA_ARGS
    export CMD
}
