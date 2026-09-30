#!/usr/bin/env bash
# ============================================================
# 萌芽平台 (mengya-local) - 跨平台端口探针与进程管理模块
# ============================================================

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
            for cp in $pattern_pids; do
                # 排除属于 Docker 容器内的进程（容器内工作目录通常为 /app，或 cgroup 包含 docker/containerd）
                if [ -d "/proc/$cp" ]; then
                    local proc_cwd
                    proc_cwd=$(readlink -f "/proc/$cp/cwd" 2>/dev/null || true)
                    if [ "$proc_cwd" = "/app" ] || [[ "$proc_cwd" =~ ^/var/lib/docker ]]; then
                        continue
                    fi
                    local proc_cgroup
                    proc_cgroup=$(cat "/proc/$cp/cgroup" 2>/dev/null || true)
                    if [[ "$proc_cgroup" =~ docker|containerd ]]; then
                        continue
                    fi
                fi
                target_pids="$target_pids $cp"
            done
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
    stop_service "$(get_backend_pid)" "Django 一体化服务" "$BACKEND_PID_FILE" "$FRONTEND_PORT" "manage.py runserver 0.0.0.0:$FRONTEND_PORT"
    rm -f "$FRONTEND_PID_FILE"
    stop_db_container
    echo "  本地服务停止操作完成"
}

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

start_service() {
    cleanup_cache
    setup_db_for_mode
    # 安全补充：补全缺失的 SSL 证书与 Nginx 配置创建函数调用
    gen_ssl_cert
    gen_nginx_config
    start_backend
    echo ""
    echo "============================================"
    echo "  萌芽（mengya-local）本地一体化服务已启动"
    echo "  统一访问入口: $EXTERNAL_PORT (SNI 域名: $SERVER_NAME)"
    if [ -f "$NGINX_CONF" ]; then
        print_access_urls "统一访问入口" "$EXTERNAL_PORT"
    fi
    echo "  本地直连地址: http://127.0.0.1:$FRONTEND_PORT/"
    echo "  管理员账号:   $ADMIN_USERNAME"
    echo "  一体化架构:   前端静态资源已合并至 Django，彻底消除 Node.js 常驻内存开销"
    echo "============================================"
}

restart_service() {
    cleanup_cache
    stop_all
    sleep 1
    setup_db_for_mode
    gen_ssl_cert
    gen_nginx_config
    start_backend
    invalidate_all_sessions
    echo ""
    echo "============================================"
    echo "  萌芽（mengya-local）本地一体化服务已重启"
    echo "  统一访问入口: $EXTERNAL_PORT (SNI 域名: $SERVER_NAME)"
    if [ -f "$NGINX_CONF" ]; then
        print_access_urls "统一访问入口" "$EXTERNAL_PORT"
    fi
    echo "  本地直连地址: http://127.0.0.1:$FRONTEND_PORT/"
    echo "  管理员账号:   $ADMIN_USERNAME"
    echo "  一体化架构:   前端静态资源已合并至 Django，彻底消除 Node.js 常驻内存开销"
    echo "============================================"
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
    echo "  数据库存储模式   : $DB_MODE"
    if [ "$DB_MODE" = "sqlite" ]; then
        echo "  数据库物理文件   : $SCRIPT_DIR/db.sqlite3 [与 Docker 版 100% 物理隔离]"
    elif [ "$DB_MODE" = "shared" ]; then
        echo "  共享 PG 容器     : $SHARED_PG_CONTAINER (专属库: $POSTGRES_DB)"
        echo "  数据库连接       : $DATABASE_URL"
    else
        echo "  独立 PG 容器     : ${APP_NAME:-mengya_local}-pg"
        echo "  数据库连接       : $DATABASE_URL"
    fi
    echo "  架构安全设计     : Django 单体一体化全栈托管，彻底移除 Node 常驻服务与内存开销"
    echo "  日志目录         : $LOG_DIR"
    echo "============================================"
}

