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
    echo "  本地服务停止操作完成"
}
