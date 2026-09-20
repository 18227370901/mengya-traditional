#!/usr/bin/env bash
# ============================================================
# 萌芽（mengya）平台 - 本地传统模式管理脚本 (mengya-local)
#
# 架构模型：
#   - 外部访问：Nginx 统一反代，监听 0.0.0.0:443（HTTPS SNI 唯一安全入口）
#   - 前端服务：Vite 开发服务器，绑定 127.0.0.1:5173（本地回环保护）
#   - 后端服务：Django 框架，绑定 127.0.0.1:8000（本地回环保护，禁止外部直连）
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
#   BACKEND_PORT      后端内部服务端口（默认 8000，仅供内部反代）
#   ADMIN_USERNAME    管理员账号（默认 admin）
#   ADMIN_PASSWORD    管理员密码（默认 admin123）
#   ADMIN_NICKNAME    管理员昵称（默认 管理员）
#   NGINX_CONF_DIR    Nginx 额外配置目录（默认 /opt/service/nginx/conf.d）
#   NGINX_CERT_DIR    Nginx SSL 证书目录（默认 /opt/service/nginx/ssl）
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
    set -a
    # shellcheck disable=SC1091
    . ./.env
    set +a
fi

# 更新/持久化变量到 .env 文件的辅助函数
update_env_var() {
    local key="$1"
    local val="$2"
    if [ -f ".env" ]; then
        if grep -q "^${key}=" ".env" 2>/dev/null; then
            sed -i.bak "s|^${key}=.*|${key}=${val}|" ".env" 2>/dev/null && rm -f ".env.bak"
        else
            echo "${key}=${val}" >> ".env"
        fi
    fi
}
# 智能规范化路径为绝对物理路径（避免相对路径导致 Nginx 基于 Prefix 错误寻址）
resolve_abs_path() {
    local target="$1"
    if [ -z "$target" ]; then
        echo ""
        return
    fi
    case "$target" in
        /*|[A-Za-z]:*)
            echo "$target"
            ;;
        *)
            mkdir -p "$SCRIPT_DIR/$target" 2>/dev/null || true
            local abs_dir
            abs_dir="$(cd "$SCRIPT_DIR/$target" 2>/dev/null && pwd)"
            echo "${abs_dir:-$SCRIPT_DIR/$target}"
            ;;
    esac
}


# 外部访问端口默认统一为 443
PORT="${PORT:-${EXTERNAL_PORT:-443}}"
EXTERNAL_PORT="$PORT"
SERVER_NAME="${SERVER_NAME:-${DOMAIN:-mengya.local localhost}}"

# 内部服务端口（仅监听 127.0.0.1 本地回环）
BACKEND_PORT="${BACKEND_PORT:-8000}"
FRONTEND_PORT="${FRONTEND_PORT:-5173}"

ADMIN_USERNAME="${ADMIN_USERNAME:-${ADMIN_PHONE:-admin}}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin123}"
ADMIN_NICKNAME="${ADMIN_NICKNAME:-管理员}"

NGINX_CONF_DIR=$(resolve_abs_path "${NGINX_CONF_DIR:-/opt/service/nginx/conf.d}")
NGINX_CERT_DIR=$(resolve_abs_path "${NGINX_CERT_DIR:-/opt/service/nginx/ssl}")
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

mkdir -p "$LOG_DIR" "$PID_DIR"

port_in_use() {
    local port="$1"
    if command -v lsof >/dev/null 2>&1; then
        lsof -i :"$port" -sTCP:LISTEN >/dev/null 2>&1
        return $?
    elif command -v ss >/dev/null 2>&1; then
        ss -ltn | grep -E "[:]$port[[:space:]]" >/dev/null 2>&1
        return $?
    elif command -v netstat >/dev/null 2>&1; then
        netstat -lnt 2>/dev/null | grep -E "[:]$port[[:space:]]" >/dev/null 2>&1
        return $?
    fi
    return 1
}

get_port_pids() {
    local port="$1"
    local pids=""
    if command -v lsof >/dev/null 2>&1; then
        pids=$(lsof -ti :"$port" 2>/dev/null || true)
    fi
    if [ -z "$pids" ] && command -v fuser >/dev/null 2>&1; then
        pids=$(fuser "$port/tcp" 2>/dev/null || true)
    fi
    if [ -z "$pids" ] && command -v ss >/dev/null 2>&1; then
        pids=$(ss -lptn "sport = :$port" 2>/dev/null | grep -o "pid=[0-9]*" | cut -d= -f2 || true)
    fi
    echo "$pids"
}

get_descendant_pids() {
    local parent_pid="$1"
    local descendants=""
    local children=""
    if command -v pgrep >/dev/null 2>&1; then
        children=$(pgrep -P "$parent_pid" 2>/dev/null || true)
    elif [ -d "/proc/$parent_pid/task" ]; then
        children=$(grep -l "^PPid:[[:space:]]*$parent_pid$" /proc/[0-9]*/status 2>/dev/null | cut -d/ -f3 || true)
    fi
    for child in $children; do
        descendants="$descendants $child $(get_descendant_pids "$child")"
    done
    echo "$descendants"
}

kill_pid_tree() {
    local root_pid="$1"
    [ -z "$root_pid" ] && return 0
    if ! kill -0 "$root_pid" 2>/dev/null; then
        return 0
    fi
    local all_pids
    all_pids="$(get_descendant_pids "$root_pid") $root_pid"
    for p in $all_pids; do
        kill -15 "$p" 2>/dev/null || true
    done
    sleep 0.5
    for p in $all_pids; do
        if kill -0 "$p" 2>/dev/null; then
            kill -9 "$p" 2>/dev/null || true
        fi
    done
}

pid_alive() {
    local pid="$1"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

read_pid() {
    local pidfile="$1"
    if [ -f "$pidfile" ]; then
        local pid
        pid=$(cat "$pidfile" 2>/dev/null | tr -d "[:space:]")
        if [ -n "$pid" ] && pid_alive "$pid"; then
            echo "$pid"
            return 0
        fi
    fi
    return 1
}

get_backend_pid() { read_pid "$BACKEND_PID_FILE" || true; }
get_frontend_pid() { read_pid "$FRONTEND_PID_FILE" || true; }

detect_python() {
    if command -v python3 >/dev/null 2>&1; then
        echo "python3"
    elif command -v python >/dev/null 2>&1; then
        echo "python"
    else
        echo ""
    fi
}

ensure_backend_deps() {
    local SYS_PY="$1"
    local VENV_DIR="$BACKEND_DIR/.venv"
    local VENV_PY="$VENV_DIR/bin/python"

    if [ ! -f "$VENV_PY" ] && [ -f "$VENV_DIR/Scripts/python.exe" ]; then
        VENV_PY="$VENV_DIR/Scripts/python.exe"
    fi

    if [ ! -f "$VENV_PY" ]; then
        echo "  [环境] 未检测到后端虚拟环境，正在创建 ($VENV_DIR)..." >&2
        "$SYS_PY" -m venv "$VENV_DIR" >&2
        if [ ! -f "$VENV_PY" ] && [ -f "$VENV_DIR/Scripts/python.exe" ]; then
            VENV_PY="$VENV_DIR/Scripts/python.exe"
        fi
    fi

    local need_install=0
    local HASH_FILE="$VENV_DIR/.req_hash"
    local REQ_FILE="$BACKEND_DIR/requirements.txt"
    local CURR_HASH=""

    if command -v md5sum >/dev/null 2>&1; then
        CURR_HASH=$(md5sum "$REQ_FILE" 2>/dev/null | cut -d" " -f1)
    elif command -v md5 >/dev/null 2>&1; then
        CURR_HASH=$(md5 -q "$REQ_FILE" 2>/dev/null)
    fi

    if [ ! -f "$HASH_FILE" ] || [ "$CURR_HASH" != "$(cat "$HASH_FILE" 2>/dev/null)" ]; then
        need_install=1
    fi

    if [ "$need_install" = "1" ]; then
        echo "  [依赖] 正在同步后端依赖 (pip install -r requirements.txt)..." >&2
        (cd "$BACKEND_DIR" && "$VENV_PY" -m pip install -r requirements.txt >&2)
        [ -n "$CURR_HASH" ] && echo "$CURR_HASH" > "$HASH_FILE"
    fi

    echo "$VENV_PY"
}


cleanup_cache() {
    echo -e "\x1b[32m正在清理本地缓存与 .git 冗余垃圾...\x1b[0m"
    cd "$SCRIPT_DIR" || return
    if [ -d ".git" ] && command -v git > /dev/null 2>&1; then
        git reflog expire --expire=now --all 2>/dev/null || true
        git gc --prune=now 2>/dev/null || true
        echo -e "\x1b[32m✅ .git 冗余垃圾清理完成! 当前 .git 体积: $(du -sh .git 2>/dev/null | cut -f1)\x1b[0m"
    fi
    find "$SCRIPT_DIR" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
    find "$SCRIPT_DIR" -type f -name "*.pyc" -delete 2>/dev/null || true
    rm -rf /tmp/gift-backup 2>/dev/null || true
}

start_backend() {
    echo "==> 启动后端服务（端口 $BACKEND_PORT，本地回环保护模式）"
    if port_in_use "$BACKEND_PORT"; then
        echo "  [提示] 端口 $BACKEND_PORT 已被占用，跳过后端启动。"
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
    echo "  执行数据迁移..."
    "$PYTHON" manage.py migrate --noinput
    echo "  初始化种子数据..."
    "$PYTHON" manage.py init_data --skip-if-exists
    "$PYTHON" manage.py init_fetal_stories --skip-if-exists

    echo "  同步单一管理员账号 ($ADMIN_USERNAME)..."
    ADMIN_USERNAME="$ADMIN_USERNAME" \
    ADMIN_PASSWORD="$ADMIN_PASSWORD" \
    ADMIN_NICKNAME="$ADMIN_NICKNAME" \
    "$PYTHON" manage.py ensure_admin

    # 绑定 127.0.0.1 回环地址：仅允许本机反代访问，禁止外部直接连 8000
    nohup "$PYTHON" manage.py runserver 127.0.0.1:"$BACKEND_PORT" \
        >> "$LOG_DIR/backend.log" 2>&1 &
    echo $! > "$BACKEND_PID_FILE"
    echo "  后端 PID: $(cat "$BACKEND_PID_FILE")"
    echo "  日志: $LOG_DIR/backend.log"
    cd "$SCRIPT_DIR"
}

ensure_frontend_deps() {
    echo "  ==> 检查前端依赖..."
    cd "$FRONTEND_DIR"
    if [ ! -d "node_modules" ]; then
        echo "  [依赖] 未找到 node_modules，执行 npm install..."
        npm install
    fi
}

start_frontend() {
    echo "==> 启动前端服务（内部端口 $FRONTEND_PORT，本地回环保护模式）"
    if port_in_use "$FRONTEND_PORT"; then
        echo "  [提示] 内部端口 $FRONTEND_PORT 已被占用，跳过前端启动。"
        return 0
    fi

    ensure_frontend_deps

    cd "$FRONTEND_DIR"
    local VITE_BIN="./node_modules/.bin/vite"
    # 绑定 127.0.0.1 回环保护，外部流量必须经过 Nginx 443 反代
    if [ -f "$VITE_BIN" ]; then
        nohup "$VITE_BIN" --port "$FRONTEND_PORT" --host 127.0.0.1 \
            >> "$LOG_DIR/frontend.log" 2>&1 &
    else
        nohup npm run dev -- --port "$FRONTEND_PORT" --host 127.0.0.1 \
            >> "$LOG_DIR/frontend.log" 2>&1 &
    fi
    echo $! > "$FRONTEND_PID_FILE"
    echo "  前端 PID: $(cat "$FRONTEND_PID_FILE")"
    echo "  日志: $LOG_DIR/frontend.log"
    cd "$SCRIPT_DIR"
}

# ===== 生成 Nginx SNI 443 SSL 反向代理配置 =====
# ===== SSL 证书创建函数（带交互式防误覆盖确认） =====
gen_ssl_cert() {
    echo "==> 检查/配置 SSL 证书 (传统部署版)"

    NGINX_CERT_DIR=$(resolve_abs_path "$NGINX_CERT_DIR")
    mkdir -p "$NGINX_CERT_DIR"

    local MAIN_DOMAIN
    MAIN_DOMAIN=$(echo "$SERVER_NAME" | awk '{print $1}')
    [ -z "$MAIN_DOMAIN" ] && MAIN_DOMAIN="localhost"

    local SAN_LIST="DNS:localhost,IP:127.0.0.1"
    for d in $SERVER_NAME; do
        SAN_LIST="$SAN_LIST,DNS:$d"
    done

    local CERT_FILE="$NGINX_CERT_DIR/mengya.crt"
    local KEY_FILE="$NGINX_CERT_DIR/mengya.key"

    echo "  操作证书对象: $CERT_FILE"
    echo "  操作私钥对象: $KEY_FILE"

    local do_update="n"
    if [ -f "$CERT_FILE" ] || [ -f "$KEY_FILE" ]; then
        echo -e "\033[1;33m[提示] 检测到已存在 SSL 证书或私钥文件。\033[0m"
        echo -e "\033[1;31m[注意] 若选择更新，将重新生成自签名证书并覆盖现有文件内容（已有正式证书将被替换）！\033[0m"
        printf "是否需要更新 SSL 证书文件内容？(y/N): "
        read choice
    else
        echo -e "\033[1;33m[提示] 检测到目标 SSL 证书文件尚不存在。\033[0m"
        echo "  - 选择更新(y): 将调用 OpenSSL 自动生成适用于域名 [$MAIN_DOMAIN] 的自签名证书并写入；"
        echo "  - 选择否(n): 仅保证文件存在（创建空占位文件，避免 Nginx 启动报错），不写入自签名内容。"
        printf "是否需要生成并写入 SSL 证书内容？(y/N): "
        read choice
    fi

    case "$choice" in
        [yY]|[yY][eE][sS])
            do_update="y"
            ;;
        *)
            do_update="n"
            ;;
    esac

    if [ "$do_update" = "y" ]; then
        echo "  正在生成并更新自签名 SSL 证书（主域名: $MAIN_DOMAIN，SAN: $SAN_LIST）..."
        if command -v openssl >/dev/null 2>&1; then
            openssl req -x509 -newkey rsa:2048 -keyout "$KEY_FILE" \
                -out "$CERT_FILE" -days 365 -nodes \
                -subj "/C=CN/O=mengya/CN=$MAIN_DOMAIN" \
                -addext "subjectAltName=$SAN_LIST" 2>/dev/null || \
            openssl req -x509 -newkey rsa:2048 -keyout "$KEY_FILE" \
                -out "$CERT_FILE" -days 365 -nodes \
                -subj "/C=CN/O=mengya/CN=$MAIN_DOMAIN" 2>/dev/null || true
            echo "  ✅ SSL 证书与私钥已更新成功: $CERT_FILE"
        else
            echo "  [警告] 未找到 openssl 命令，无法生成证书内容，将仅保证文件存在。"
            [ ! -f "$CERT_FILE" ] && touch "$CERT_FILE" 2>/dev/null || true
            [ ! -f "$KEY_FILE" ] && touch "$KEY_FILE" 2>/dev/null || true
        fi
    else
        echo "  保持现有证书内容不变，跳过证书更新。"
        [ ! -f "$CERT_FILE" ] && touch "$CERT_FILE" 2>/dev/null || true
        [ ! -f "$KEY_FILE" ] && touch "$KEY_FILE" 2>/dev/null || true
        echo "  ✅ 证书文件状态确认: 保留已有内容（或已保证空占位文件存在）"
    fi
}

gen_nginx_config() {
    echo "==> 生成 Nginx SSL (SNI 443) 反向代理配置"

    # 确保证书目录与配置目录均为物理绝对路径（彻底避免相对路径导致 Nginx 寻址失败）
    NGINX_CONF_DIR=$(resolve_abs_path "$NGINX_CONF_DIR")
    NGINX_CERT_DIR=$(resolve_abs_path "$NGINX_CERT_DIR")
    NGINX_CONF="$NGINX_CONF_DIR/mengya_ssl.conf"

    mkdir -p "$NGINX_CONF_DIR" "$NGINX_CERT_DIR"

    # 主域名用于 OpenSSL 证书 CN 与控制台访问链接展示（以 SERVER_NAME 配置为准）
    local MAIN_DOMAIN
    MAIN_DOMAIN=$(echo "$SERVER_NAME" | awk '{print $1}')
    [ -z "$MAIN_DOMAIN" ] && MAIN_DOMAIN="localhost"

    local CERT_FILE="$NGINX_CERT_DIR/mengya.crt"
    local KEY_FILE="$NGINX_CERT_DIR/mengya.key"

    local REDIRECT_BLOCK=""
    if [ "$ENABLE_HTTP_REDIRECT" = "1" ] && [ "$EXTERNAL_PORT" = "443" ]; then
        REDIRECT_BLOCK="
# HTTP 80 自动重定向到 HTTPS 443（SNI 标准规范）
server {
    listen 80;
    listen [::]:80;
    server_name $SERVER_NAME;

    return 301 https://\$host\$request_uri;
}
"
    fi

    cat > "$NGINX_CONF" << EOF
# ============================================================
# 萌芽（mengya）平台 - Nginx HTTPS (SNI 443) 反向代理配置
# 配置文件：$NGINX_CONF
# 访问端口：$EXTERNAL_PORT (HTTPS 标准端口)
# 匹配域名：$SERVER_NAME (以 SERVER_NAME 配置为准)
# SNI 特性：基于 server_name 匹配 TLS 握手域名，支持多站点共用 443 端口
# 自动生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# ============================================================
${REDIRECT_BLOCK}
server {
    listen $EXTERNAL_PORT ssl;
    listen [::]:$EXTERNAL_PORT ssl;
    server_name $SERVER_NAME;

    # SSL 证书与私钥（基于物理绝对路径，保障 Nginx 稳定加载）
    ssl_certificate     $CERT_FILE;
    ssl_certificate_key $KEY_FILE;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    # 安全响应头
    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # 文件上传限制（支持孕检报告、商品素材等大文件上传）
    client_max_body_size 20M;

    # 前端 Vite 代理（支持 SPA 路由与 WebSocket HMR）
    location / {
        proxy_pass http://127.0.0.1:$FRONTEND_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_set_header X-Forwarded-Host \$host;

        # WebSocket 支持（Vite HMR 热重载）
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # 后端 Django API 反向代理
    location /api/ {
        proxy_pass http://127.0.0.1:$BACKEND_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_set_header X-Forwarded-Host \$host;
    }

    # Django Admin 管理后台反向代理
    location /admin/ {
        proxy_pass http://127.0.0.1:$BACKEND_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_set_header X-Forwarded-Host \$host;
    }
}
EOF

    echo "  Nginx 配置文件已生成: $NGINX_CONF"
    echo "  SSL 证书路径:         $CERT_FILE"
    echo "  SNI 监听域名:         $SERVER_NAME (以 SERVER_NAME 为准，主域名: $MAIN_DOMAIN)"
    echo "  外部访问端口:         $EXTERNAL_PORT"
    echo ""
    echo "  启用配置请执行:"
    echo "    1. 确保 nginx.conf 已包含: include $NGINX_CONF_DIR/*.conf;"
    echo "    2. 检查配置并重载: nginx -t && nginx -s reload"
}

stop_service() {
    local pid="$1"
    local name="$2"
    local pidfile="$3"
    local port="$4"
    local pattern="$5"
    local stopped=0
    local target_pids=""

    if [ -n "$pid" ] && pid_alive "$pid"; then
        target_pids="$target_pids $pid"
    fi

    if [ -n "$port" ]; then
        local port_pids
        port_pids=$(get_port_pids "$port")
        if [ -n "$port_pids" ]; then
            target_pids="$target_pids $port_pids"
        fi
    fi

    if [ -n "$pattern" ] && command -v pgrep >/dev/null 2>&1; then
        local pattern_pids
        pattern_pids=$(pgrep -f "$pattern" 2>/dev/null || true)
        if [ -n "$pattern_pids" ]; then
            target_pids="$target_pids $pattern_pids"
        fi
    fi

    local unique_pids
    unique_pids=$(echo "$target_pids" | tr " " "\n" | grep -E "^[0-9]+$" | sort -u || true)

    if [ -n "$unique_pids" ]; then
        echo "  ==> 停止 $name (PID: $unique_pids)"
        for p in $unique_pids; do
            kill_pid_tree "$p"
        done
        stopped=1
    fi
    rm -f "$pidfile"

    if [ -n "$port" ]; then
        for _ in $(seq 1 6); do
            local remaining_pids
            remaining_pids=$(get_port_pids "$port")
            if [ -z "$remaining_pids" ]; then
                break
            fi
            for rp in $remaining_pids; do
                kill -9 "$rp" 2>/dev/null || true
            done
            sleep 0.5
        done
    fi

    if [ "$stopped" = "1" ]; then
        echo "  $name 已停止"
    else
        echo "  $name 未在运行"
    fi
}

stop_all() {
    echo "==> 停止本地服务"
    stop_service "$(get_backend_pid)" "后端 Django" "$BACKEND_PID_FILE" "$BACKEND_PORT" "manage.py runserver"
    stop_service "$(get_frontend_pid)" "前端 Vite" "$FRONTEND_PID_FILE" "$FRONTEND_PORT" "vite"
    echo "  本地服务停止操作完成"
}

show_status() {
    echo "============================================"
    echo "  萌芽（mengya-local）运行状态"
    echo "============================================"
    local bp fp
    bp=$(get_backend_pid)
    fp=$(get_frontend_pid)

    echo "  后端 Django  : $([ -n "$bp" ] && echo "运行中 (PID $bp, 回环端口 $BACKEND_PORT)" || (port_in_use "$BACKEND_PORT" && echo "端口占用 (外部进程)" || echo "未运行"))"
    echo "  前端 Vite    : $([ -n "$fp" ] && echo "运行中 (PID $fp, 回环端口 $FRONTEND_PORT)" || (port_in_use "$FRONTEND_PORT" && echo "端口占用 (外部进程)" || echo "未运行"))"
    echo "  Nginx SNI    : $([ -f "$NGINX_CONF" ] && echo "已配置 ($NGINX_CONF)" || echo "未生成 (执行 ./run.sh add_nginx 生成)")"
    echo "  外部访问端口 : $EXTERNAL_PORT (SNI 域名: $SERVER_NAME)"
    local MAIN_DOMAIN
    MAIN_DOMAIN=$(echo "$SERVER_NAME" | awk '{print $1}')
    [ -z "$MAIN_DOMAIN" ] && MAIN_DOMAIN="localhost"
    if [ "$EXTERNAL_PORT" = "443" ]; then
        echo "  统一访问入口 : https://$MAIN_DOMAIN/ (HTTPS SNI 443)"
    else
        echo "  统一访问入口 : https://$MAIN_DOMAIN:$EXTERNAL_PORT/ (HTTPS SNI)"
    fi
    echo "  架构安全设计 : 前后端绑定 127.0.0.1 保护中，全站流量走 443 统一反代"
    echo "  日志目录     : $LOG_DIR"
    echo "============================================"
}

# 解析命令行参数与自定义变量
CMD=""
CUSTOM_PORT=""
CUSTOM_ADMIN_USER=""
CUSTOM_ADMIN_PASS=""
CUSTOM_ADMIN_NICK=""
CUSTOM_DOMAIN=""
EXTRA_ARGS=""

while [ $# -gt 0 ]; do
    case "$1" in
        start|stop|restart|status|add_nginx|help)
            if [ -z "$CMD" ]; then
                CMD="$1"
            else
                EXTRA_ARGS="${EXTRA_ARGS:+$EXTRA_ARGS }$1"
            fi
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

[ -z "$CMD" ] && CMD="help"

# 应用自定义参数并持久化至 .env
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
    SERVER_NAME="$CUSTOM_DOMAIN"
    update_env_var "SERVER_NAME" "$CUSTOM_DOMAIN"
    echo -e "\033[0;32m[配置] SNI 匹配域名已设置为: $CUSTOM_DOMAIN (已同步至 .env)\033[0m"
fi

export FRONTEND_PORT
export ADMIN_USERNAME
export ADMIN_PHONE
export ADMIN_PASSWORD
export ADMIN_NICKNAME
export SERVER_NAME
export EXTERNAL_PORT

case "$CMD" in
    start)
        cleanup_cache
        # 补全主流程中缺失的 SSL 证书与 Nginx 配置创建函数调用
        gen_ssl_cert
        gen_nginx_config
        start_backend
        start_frontend
        echo ""
        echo "============================================"
        echo "  萌芽（mengya-local）启动完成！"
        PRIMARY_DOMAIN=$(echo "$SERVER_NAME" | awk '{print $1}')
        [ -z "$PRIMARY_DOMAIN" ] && PRIMARY_DOMAIN="localhost"
        if [ "$EXTERNAL_PORT" = "443" ]; then
            echo "  统一访问地址: https://$PRIMARY_DOMAIN/ (HTTPS 443 SNI 唯一入口)"
        else
            echo "  统一访问地址: https://$PRIMARY_DOMAIN:$EXTERNAL_PORT/ (HTTPS SNI)"
        fi
        echo "  管理员账号:   $ADMIN_USERNAME"
        echo "  安全架构:     前端(:$FRONTEND_PORT)与后端(:$BACKEND_PORT)已收敛至 127.0.0.1 回环保护"
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
        # 补全主流程中缺失的 SSL 证书与 Nginx 配置创建函数调用
        gen_ssl_cert
        gen_nginx_config
        start_backend
        start_frontend
        echo ""
        echo "============================================"
        echo "  萌芽（mengya-local）重启完成！"
        PRIMARY_DOMAIN=$(echo "$SERVER_NAME" | awk '{print $1}')
        [ -z "$PRIMARY_DOMAIN" ] && PRIMARY_DOMAIN="localhost"
        if [ "$EXTERNAL_PORT" = "443" ]; then
            echo "  统一访问地址: https://$PRIMARY_DOMAIN/ (HTTPS 443 SNI 唯一入口)"
        else
            echo "  统一访问地址: https://$PRIMARY_DOMAIN:$EXTERNAL_PORT/ (HTTPS SNI)"
        fi
        echo "============================================"
        ;;
    add_nginx)
        gen_ssl_cert
        gen_nginx_config
        ;;
    status)
        show_status
        ;;
    help)
        echo ""
        echo "萌芽（mengya-local）本地模式管理命令："
        echo "  ./run.sh start [选项]        启动前后端本地服务（启动前自动清理垃圾与缓存）"
        echo "  ./run.sh stop                停止本地前后端服务"
        echo "  ./run.sh restart [选项]      重启本地前后端服务（重启前自动清理垃圾与缓存）"
        echo "  ./run.sh status              查看运行状态与端口占用"
        echo "  ./run.sh add_nginx [选项]    生成基于 SNI 443 端口的 Nginx SSL 反向代理配置"
        echo "  ./run.sh help                查看帮助"
        echo ""
        echo "常用自定义选项（支持在 start / restart / add_nginx 时追加，自动持久化至 .env）："
        echo "  -p, --port <PORT>            自定义前端内部访问端口（默认 5173）"
        echo "  -u, --admin <USER>           自定义超级管理员账号/手机号（默认 admin）"
        echo "  -P, --password <PASS>        自定义超级管理员登录密码（默认 admin123）"
        echo "  -n, --nickname <NAME>        自定义管理员昵称（默认 管理员）"
        echo "  -d, --domain <DOMAIN>        自定义绑定的 SNI 域名（默认 mengya.local localhost）"
        echo ""
        echo "实用启动示例："
        echo "  ./run.sh start                                 # 默认启动（端口 5173，管理员 admin / admin123）"
        echo "  ./run.sh start -p 5175                         # 自定义以 5175 端口启动"
        echo "  ./run.sh start -p 5173 -u superadmin -P Pass123 # 自定义端口与管理员账密启动"
        echo "  ./run.sh restart -p 5175                       # 重启并变更为 5175 端口"
        echo "  ./run.sh add_nginx -d mengya.myhost.com        # 为指定域名生成独立反代配置"
        echo ""
        ;;
    *)
        echo "未知命令: $CMD"
        echo "支持的子命令: start | stop | restart | status | add_nginx | help"
        exit 1
        ;;
esac
