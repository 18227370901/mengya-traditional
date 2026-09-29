#!/usr/bin/env bash
# ============================================================
# 萌芽平台 (mengya-local) - 数据库探针、部署决策向导与模式配置模块
# ============================================================

detect_host_ram_mb() {
    local mem_kb=0
    if [ -f "/proc/meminfo" ]; then
        mem_kb=$(grep -i "^MemTotal:" /proc/meminfo 2>/dev/null | awk '{print $2}')
    elif command -v sysctl >/dev/null 2>&1; then
        local bytes
        bytes=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
        mem_kb=$((bytes / 1024))
    fi
    echo $((mem_kb / 1024))
}

detect_running_pg_containers() {
    if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
        return 0
    fi
    local my_db="${APP_NAME:-mengya_local}-pg"
    docker ps --format '{{.Names}}\t{{.Image}}' 2>/dev/null | while read -r c_name c_img; do
        [ -z "$c_name" ] && continue
        if [ "$c_name" = "$my_db" ]; then
            continue
        fi
        if echo "$c_img" | grep -qiE "postgres|pgvector"; then
            echo "$c_name"
        fi
    done
}

detect_best_pg_image() {
    if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
        echo "pgvector/pgvector:pg18"
        return 0
    fi
    local local_imgs
    local_imgs=$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null || true)

    # 1. 优先复用宿主机正在运行的 PG 容器所使用的镜像
    local running_c
    running_c=$(detect_running_pg_containers | head -n 1)
    if [ -n "$running_c" ]; then
        local c_img
        c_img=$(docker inspect --format='{{.Config.Image}}' "$running_c" 2>/dev/null || true)
        if [ -n "$c_img" ]; then
            echo "$c_img"
            return 0
        fi
    fi

    # 2. 检查本地是否存在 pgvector/pgvector:pg18
    if echo "$local_imgs" | grep -qx "pgvector/pgvector:pg18"; then
        echo "pgvector/pgvector:pg18"
        return 0
    fi

    # 3. 检查本地是否存在 postgres:15-alpine 或其他 alpine 镜像
    local alpine_img
    alpine_img=$(echo "$local_imgs" | grep -E "^postgres:.*alpine" | head -n 1)
    if [ -n "$alpine_img" ]; then
        echo "$alpine_img"
        return 0
    fi

    # 4. 检查本地任何包含 postgres 或 pgvector 的镜像
    local any_pg
    any_pg=$(echo "$local_imgs" | grep -E "(postgres|pgvector)" | grep -v "<none>" | head -n 1)
    if [ -n "$any_pg" ]; then
        echo "$any_pg"
        return 0
    fi

    echo "pgvector/pgvector:pg18"
}

image_exists() {
    local img="$1"
    if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
        return 1
    fi
    docker image inspect "$img" >/dev/null 2>&1
}

choose_db_image() {
    if ! docker info >/dev/null 2>&1; then
        DB_IMAGE="${DB_IMAGE:-pgvector/pgvector:pg18}"
        DB_PULL_POLICY="${DB_PULL_POLICY:-never}"
        export DB_IMAGE DB_PULL_POLICY
        return 0
    fi

    if [ -n "$CUSTOM_DB_IMAGE" ]; then
        DB_IMAGE="$CUSTOM_DB_IMAGE"
    elif [ -z "$DB_IMAGE" ]; then
        DB_IMAGE=$(detect_best_pg_image)
    fi

    if image_exists "$DB_IMAGE"; then
        echo -e "\033[0;32m[镜像复用] 检测到本地已存在镜像 [$DB_IMAGE]，直接复用本地镜像，绝不执行远程下载（pull_policy: never）\033[0m"
        DB_PULL_POLICY="never"
    else
        local alt_img
        alt_img=$(detect_best_pg_image)
        if [ "$alt_img" != "$DB_IMAGE" ] && image_exists "$alt_img"; then
            echo -e "\033[0;32m[镜像复用] 指定镜像 $DB_IMAGE 本地不存在，但检测到本地已存在镜像 [$alt_img]，自动复用本地镜像，杜绝网络拉取！（pull_policy: never）\033[0m"
            DB_IMAGE="$alt_img"
            DB_PULL_POLICY="never"
        else
            echo -e "\033[1;33m[数据库] 本地未检测到任何可用 PG 镜像，按需拉取镜像: $DB_IMAGE\033[0m"
            DB_PULL_POLICY="missing"
        fi
    fi
    export DB_IMAGE DB_PULL_POLICY
}

choose_db_mode() {
    local ram_mb
    ram_mb=$(detect_host_ram_mb)

    local running_pg_list
    running_pg_list=$(detect_running_pg_containers | tr '\n' ' ' | sed 's/[[:space:]]*$//')

    local local_pg_img
    local_pg_img=$(detect_best_pg_image)
    local img_local_exists=0
    if image_exists "$local_pg_img"; then
        img_local_exists=1
    fi

    local rec_mode="sqlite"
    local rec_num=1
    local rec_reason="传统版默认严格采用本地单文件 SQLite (db.sqlite3)，极简独立且与 Docker 版数据 100% 物理隔离"

    # ===== 定时任务 / 免交互判定逻辑 =====
    # 1. restart / stop / status / logs 命令：100% 天然免交互，绝对不打扰定时任务
    if [ "$CMD" = "restart" ] || [ "$CMD" = "stop" ] || [ "$CMD" = "status" ] || [ "$CMD" = "logs" ]; then
        DB_MODE="${DB_MODE:-$rec_mode}"
        return 0
    fi

    # 2. 已有配置且未显式指定 --reconfig：静默沿用已保存配置
    if [ -n "$DB_MODE" ] && [ "$RECONFIG_DB" != "1" ]; then
        return 0
    fi

    # 3. 非交互式终端环境 (如 Cron、Systemd、CI/CD、无 TTY)：自动采用推荐模式，绝不挂起进程
    if [ "$NON_INTERACTIVE" = "1" ] || [ ! -t 0 ]; then
        DB_MODE="${DB_MODE:-$rec_mode}"
        update_env_var "DB_MODE" "$DB_MODE"
        echo -e "\033[0;36m[免交互自愈] 检测到处于非交互环境/定时任务，已自动采用智能推荐模式: $DB_MODE ($rec_reason)\033[0m"
        return 0
    fi

    # 4. 交互式终端菜单展示
    echo ""
    echo "========================================================================"
    echo "  萌芽（mengya-local）环境与数据库部署模式检测"
    echo "========================================================================"
    echo "  [硬件检测] 宿主机总内存: ${ram_mb:-未知} MB"
    if [ -n "$running_pg_list" ]; then
        echo -e "  [运行实例] \033[0;32m检测到正在运行的 PostgreSQL 容器: [$running_pg_list]\033[0m"
    else
        echo "  [运行实例] 未检测到其他运行中的 PostgreSQL 容器"
    fi
    if [ "$img_local_exists" -eq 1 ]; then
        echo -e "  [本地镜像] \033[0;32m检测到本地已有 PG 镜像: [$local_pg_img] (可直接复用，免网络下载)\033[0m"
    else
        echo "  [本地镜像] 本地未检测到现存 PG 镜像"
    fi
    echo "------------------------------------------------------------------------"
    echo "  系统智能推荐建议:"
    echo -e "  \033[1;33m⭐ 推荐选择 [$rec_num] $rec_reason\033[0m"
    echo "------------------------------------------------------------------------"
    echo "  请选择您希望使用的数据库部署模式 (回车默认使用推荐选项 [$rec_num]):"
    echo "    [1] SQLite 本地化单文件 (默认推荐，db.sqlite3，极简轻量且 100% 物理隔离)"
    echo "    [2] 共享已有 PostgreSQL 实例 (共用已运行容器，自动建库 mengya_local，零多余容器)"
    echo "    [3] 独立 PostgreSQL 容器 (独占专属容器 ${APP_NAME:-mengya_local}-pg，复用本地镜像)"
    echo ""

    local choice=""
    read -t 30 -p "请输入选项编号 [1/2/3] (默认: $rec_num): " choice || true
    echo ""
    choice=$(echo "$choice" | tr -d '[:space:]')
    [ -z "$choice" ] && choice="$rec_num"

    case "$choice" in
        1|sqlite|SQLite)
            DB_MODE="sqlite"
            ;;
        2|shared|Shared)
            DB_MODE="shared"
            ;;
        3|dedicated|Dedicated)
            DB_MODE="dedicated"
            ;;
        *)
            echo "输入无效，自动采用推荐选项 [$rec_num]"
            DB_MODE="$rec_mode"
            ;;
    esac

    update_env_var "DB_MODE" "$DB_MODE"
    echo -e "\033[0;32m[配置已保存] 数据库模式已设置为: $DB_MODE (已同步写入 .env)\033[0m"
}

setup_db_for_mode() {
    choose_db_mode
    export DB_MODE

    local app_name="${APP_NAME:-mengya_local}"
    export APP_NAME="$app_name"
    local db_container="${app_name}-pg"

    case "$DB_MODE" in
        sqlite)
            echo "==> 数据库部署模式: [1] SQLite 本地化单文件存储"
            echo "  [模式特性] 零额外 PG 容器，极简轻量，数据持久化于 $BACKEND_DIR/db.sqlite3 (与 Docker 版 100% 物理隔离)"
            USE_POSTGRES="False"
            DATABASE_URL=""
            export USE_POSTGRES DATABASE_URL
            update_env_var "USE_POSTGRES" "False"
            update_env_var "DATABASE_URL" ""
            ;;
        shared)
            echo "==> 数据库部署模式: [2] 共享已有 PostgreSQL 实例"
            local running_pg
            running_pg=$(detect_running_pg_containers | head -n 1)
            if [ -z "$SHARED_PG_CONTAINER" ]; then
                SHARED_PG_CONTAINER="${running_pg:-pgvector-18}"
            fi
            export SHARED_PG_CONTAINER
            update_env_var "SHARED_PG_CONTAINER" "$SHARED_PG_CONTAINER"

            local pg_db="${POSTGRES_DB:-mengya_local}"
            local pg_user="${POSTGRES_USER:-mengya_local}"
            local pg_pass="${POSTGRES_PASSWORD:-mengya123}"

            echo "  [共享实例] 目标 PG 容器: $SHARED_PG_CONTAINER (应用专属库: $pg_db, 专属账号: $pg_user)"
            if docker inspect --format='{{.State.Running}}' "$SHARED_PG_CONTAINER" 2>/dev/null | grep -qx "true"; then
                echo "  正在通过容器内管理接口幂等初始化专属库 [$pg_db] 与账号 [$pg_user]..."
                local superuser="postgres"
                if docker exec "$SHARED_PG_CONTAINER" psql -U mengya -d postgres -c "SELECT 1;" >/dev/null 2>&1; then
                    superuser="mengya"
                fi
                docker exec "$SHARED_PG_CONTAINER" psql -U "$superuser" -d postgres -tc "SELECT 1 FROM pg_roles WHERE rolname = '$pg_user';" 2>/dev/null | grep -q 1 || \
                    docker exec "$SHARED_PG_CONTAINER" psql -U "$superuser" -d postgres -c "CREATE USER $pg_user WITH PASSWORD '$pg_pass';" 2>/dev/null || true
                docker exec "$SHARED_PG_CONTAINER" psql -U "$superuser" -d postgres -tc "SELECT 1 FROM pg_database WHERE datname = '$pg_db';" 2>/dev/null | grep -q 1 || \
                    docker exec "$SHARED_PG_CONTAINER" psql -U "$superuser" -d postgres -c "CREATE DATABASE $pg_db OWNER $pg_user;" 2>/dev/null || true
                docker exec "$SHARED_PG_CONTAINER" psql -U "$superuser" -d postgres -c "GRANT ALL PRIVILEGES ON DATABASE $pg_db TO $pg_user;" 2>/dev/null || true
                echo "  ✅ 已在容器 $SHARED_PG_CONTAINER 中就绪专属库 [$pg_db] 与用户 [$pg_user]！"
            else
                echo -e "\033[1;33m  [提示] 目标容器 $SHARED_PG_CONTAINER 当前未在运行中，请确保该容器可正常访问。\033[0m"
            fi

            USE_POSTGRES="True"
            DATABASE_URL="postgresql://${pg_user}:${pg_pass}@127.0.0.1:5432/${pg_db}"
            export USE_POSTGRES DATABASE_URL
            update_env_var "USE_POSTGRES" "True"
            update_env_var "DATABASE_URL" "$DATABASE_URL"
            ;;
        dedicated|*)
            echo "==> 数据库部署模式: [3] 独立专属 PostgreSQL 容器 ($db_container)"
            choose_db_image
            local pg_db="${POSTGRES_DB:-mengya_local}"
            local pg_user="${POSTGRES_USER:-mengya_local}"
            local pg_pass="${POSTGRES_PASSWORD:-mengya123}"
            local host_port="5433"
            if ! port_in_use 5432; then
                host_port="5432"
            fi

            if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
                if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$db_container"; then
                    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$db_container"; then
                        echo "  启动已有独立 PG 容器 $db_container..."
                        docker start "$db_container" >/dev/null 2>&1 || true
                    fi
                else
                    echo "  创建并启动独立专属 PG 容器 $db_container (复用镜像: $DB_IMAGE, 宿主机端口: $host_port)..."
                    docker run -d \
                        --name "$db_container" \
                        -p "${host_port}:5432" \
                        -e POSTGRES_DB="$pg_db" \
                        -e POSTGRES_USER="$pg_user" \
                        -e POSTGRES_PASSWORD="$pg_pass" \
                        -v "${app_name}_pgdata:/var/lib/postgresql" \
                        --restart unless-stopped \
                        "$DB_IMAGE" \
                        postgres -c shared_buffers=24MB -c work_mem=1MB -c max_connections=20 >/dev/null 2>&1 || true
                fi
            fi

            USE_POSTGRES="True"
            DATABASE_URL="postgresql://${pg_user}:${pg_pass}@127.0.0.1:${host_port}/${pg_db}"
            export USE_POSTGRES DATABASE_URL
            update_env_var "USE_POSTGRES" "True"
            update_env_var "DATABASE_URL" "$DATABASE_URL"
            ;;
    esac
}
