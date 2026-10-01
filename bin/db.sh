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
    local my_db="$DB_CONTAINER_NAME"
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
    local default_img="$DEFAULT_PG_IMAGE"
    if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
        echo "$default_img"
        return 0
    fi
    local local_imgs
    local_imgs=$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null || true)

    # 1. 优先检查本地是否存在内置默认镜像 (postgres:15-alpine)
    if echo "$local_imgs" | grep -qx "$default_img"; then
        echo "$default_img"
        return 0
    fi

    # 2. 检查本地是否有兼容的官方 PG15 镜像 (postgres:15*)
    local pg15_img
    pg15_img=$(echo "$local_imgs" | grep -E "^postgres:15" | grep -v "<none>" | head -n 1)
    if [ -n "$pg15_img" ]; then
        echo "$pg15_img"
        return 0
    fi

    # 3. 检查本地是否有官方轻量 alpine 镜像 (postgres:*alpine)
    local alpine_img
    alpine_img=$(echo "$local_imgs" | grep -E "^postgres:.*alpine" | grep -v "<none>" | head -n 1)
    if [ -n "$alpine_img" ]; then
        echo "$alpine_img"
        return 0
    fi

    # 4. 兜底返回内置默认镜像 (postgres:15-alpine)
    echo "$default_img"
}

image_exists() {
    local img="$1"
    if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
        return 1
    fi
    docker image inspect "$img" >/dev/null 2>&1
}

choose_db_image() {
    local default_img="$DEFAULT_PG_IMAGE"
    if ! docker info >/dev/null 2>&1; then
        DB_IMAGE="${CUSTOM_DB_IMAGE:-$default_img}"
        DB_PULL_POLICY="${DB_PULL_POLICY:-if_not_present}"
        DB_DATA_DIR="/var/lib/postgresql/data"
        export DB_IMAGE DB_PULL_POLICY DB_DATA_DIR
        if [ -n "$CUSTOM_DB_IMAGE" ]; then
            update_env_var "DB_IMAGE" "$DB_IMAGE"
        else
            update_env_var "DB_IMAGE" ""
        fi
        update_env_var "DB_PULL_POLICY" "$DB_PULL_POLICY"
        update_env_var "DB_DATA_DIR" "$DB_DATA_DIR"
        return 0
    fi

    # 1. 判断是否属于用户显式命令行自定义镜像 (--db-image / -i)
    local is_user_custom=0
    if [ -n "$CUSTOM_DB_IMAGE" ]; then
        DB_IMAGE="$CUSTOM_DB_IMAGE"
        is_user_custom=1
    else
        # 自动纠偏：若 .env 残留历史误判的 pg18 / pgvector 镜像且用户未显式指定，自动重置清除
        if [ -n "$DB_IMAGE" ] && echo "$DB_IMAGE" | grep -qiE "18|pgvector"; then
            echo -e "\033[1;33m[配置纠偏] 检测到历史残留误判镜像 [$DB_IMAGE]，自动重置为内置默认 [$default_img]\033[0m"
            DB_IMAGE=""
            update_env_var "DB_IMAGE" ""
        fi
        # 若非历史误判且环境变量/配置文件显式定义了非默认镜像（用户手动在 .env 指定）
        if [ -n "$DB_IMAGE" ] && [ "$DB_IMAGE" != "$default_img" ]; then
            is_user_custom=1
        fi
    fi

    # 2. 用户显式自定义分支：100% 尊崇用户自定义版本，绝对禁止被其他本地旧镜像篡改覆盖
    if [ "$is_user_custom" = "1" ]; then
        if image_exists "$DB_IMAGE"; then
            echo -e "\033[0;32m[镜像复用] 检测到本地已存在用户指定的自定义镜像 [$DB_IMAGE]，直接就地复用（pull_policy: never）\033[0m"
            DB_PULL_POLICY="never"
        else
            echo -e "\033[1;33m[镜像下载] 本地未检测到用户指定的自定义镜像 [$DB_IMAGE]，启动时将自动下载该版本（pull_policy: if_not_present）\033[0m"
            DB_PULL_POLICY="if_not_present"
        fi
        update_env_var "DB_IMAGE" "$DB_IMAGE"
    else
        # 3. 默认分支：优先检测本地兼容的官方 PG15 / alpine 镜像，无则自动拉取内置默认镜像
        local detected_img
        detected_img=$(detect_best_pg_image)

        if image_exists "$detected_img"; then
            DB_IMAGE="$detected_img"
            DB_PULL_POLICY="never"
            echo -e "\033[0;32m[镜像复用] 本地已存在兼容的 PG 镜像 [$DB_IMAGE]，直接就地复用（pull_policy: never）\033[0m"
        else
            DB_IMAGE="$default_img"
            DB_PULL_POLICY="if_not_present"
            echo -e "\033[1;33m[镜像下载] 本地未检测到兼容 PG 镜像，选用内置默认版本 [$DB_IMAGE] 并自动下载（pull_policy: if_not_present）\033[0m"
        fi
        # 默认模式下保持 .env 中 DB_IMAGE 为空，确保始终跟随系统内置默认
        update_env_var "DB_IMAGE" ""
    fi

    # 4. 数据卷挂载点标准化：PostgreSQL 官方及 pgvector 镜像数据目录统一规范为 /var/lib/postgresql/data
    DB_DATA_DIR="/var/lib/postgresql/data"

    export DB_IMAGE DB_PULL_POLICY DB_DATA_DIR
    update_env_var "DB_PULL_POLICY" "$DB_PULL_POLICY"
    update_env_var "DB_DATA_DIR" "$DB_DATA_DIR"
}

choose_db_mode() {
    export APP_NAME
    export DB_CONTAINER_NAME

    # 若通过命令行参数直传 -m / --db-mode
    if [ -n "$CUSTOM_DB_MODE" ]; then
        DB_MODE="$CUSTOM_DB_MODE"
        update_env_var "DB_MODE" "$DB_MODE"
        echo -e "\033[0;32m[数据库] 命令行显式指定数据库部署模式: $DB_MODE (已同步至 .env)\033[0m"
        return 0
    fi

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
    # 1. restart / stop / status / logs 等管理维护命令：若未显式指定 --reconfig，则天然免交互，绝不打扰定时任务
    if [ "$RECONFIG_DB" != "1" ]; then
        if [ "$CMD" = "restart" ] || [ "$CMD" = "stop" ] || [ "$CMD" = "status" ] || [ "$CMD" = "logs" ]; then
            DB_MODE="${DB_MODE:-$rec_mode}"
            return 0
        fi
    fi

    # 2. 已有配置且未显式指定 --reconfig：静默沿用已保存配置
    if [ -n "$DB_MODE" ] && [ "$RECONFIG_DB" != "1" ]; then
        return 0
    fi

    # 3. 显式指定 -y / --yes / --non-interactive：直接采用推荐模式并同步
    if [ "$NON_INTERACTIVE" = "1" ]; then
        DB_MODE="${DB_MODE:-$rec_mode}"
        update_env_var "DB_MODE" "$DB_MODE"
        echo -e "\033[0;36m[免交互自愈] 显式指定 -y/--non-interactive，已自动采用智能推荐模式: $DB_MODE ($rec_reason)\033[0m"
        return 0
    fi

    # 4. 定时任务 / 无TTY 环境（且未显式指定 --reconfig）：自动采用推荐模式，绝不挂起进程
    if [ "$RECONFIG_DB" != "1" ] && [ ! -t 0 ]; then
        DB_MODE="${DB_MODE:-$rec_mode}"
        update_env_var "DB_MODE" "$DB_MODE"
        echo -e "\033[0;36m[免交互自愈] 检测到处于非交互环境/定时任务，已自动采用智能推荐模式: $DB_MODE ($rec_reason)\033[0m"
        return 0
    fi

    # 5. 交互式终端菜单展示
    echo ""
    echo "========================================================================"
    echo "  萌芽（mengya-local）环境与数据库部署模式检测"
    echo "========================================================================"
    echo "  [硬件检测] 宿主机总内存: ${ram_mb:-未知} MB"
    echo "  [连接配置] 当前参数 -> 用户: $POSTGRES_USER | 库名: $POSTGRES_DB | 端口: $POSTGRES_PORT | 密码: ${POSTGRES_PASSWORD:+******}"
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
    echo "    [2] 共享已有 PostgreSQL 实例 (共用已运行容器，自动建库 $POSTGRES_DB，零多余容器)"
    echo "    [3] 独立 PostgreSQL 容器 (独占专属容器 $DB_CONTAINER_NAME，复用本地镜像)"
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
    RECONFIG_DB=0
    export RECONFIG_DB
    echo -e "\033[0;32m[配置已保存] 数据库模式已设置为: $DB_MODE (已同步写入 .env)\033[0m"
}

setup_db_for_mode() {
    choose_db_mode
    export DB_MODE

    export APP_NAME
    export DB_CONTAINER_NAME

    case "$DB_MODE" in
        sqlite)
            echo "==> 数据库部署模式: [1] SQLite 本地化单文件存储"
            echo "  [模式特性] 零额外 PG 容器，极简轻量，数据持久化于 $SQLITE_PATH (与 Docker 版 100% 物理隔离)"
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
                SHARED_PG_CONTAINER="$running_pg"
            fi

            # 若未找到运行中的 PG 容器，尝试检查已停止的 PG 容器并尝试唤醒自愈
            if [ -z "$SHARED_PG_CONTAINER" ]; then
                local stopped_c
                stopped_c=$(docker ps -a --filter "status=exited" --format '{{.Names}}\t{{.Image}}' 2>/dev/null | grep -E "postgres|pgvector" | head -n 1 | awk '{print $1}')
                if [ -n "$stopped_c" ]; then
                    echo -e "\033[1;33m[共享模式自愈] 检测到已停止的 PG 容器 [$stopped_c]，正在自动启动...\033[0m"
                    docker start "$stopped_c" >/dev/null 2>&1 || true
                    SHARED_PG_CONTAINER="$stopped_c"
                fi
            fi

            if [ -z "$SHARED_PG_CONTAINER" ]; then
                echo -e "\033[1;31m[错误] 宿主机未检测到任何正在运行的 PostgreSQL 容器，无法进行共享连接！\033[0m"
                echo "       请先启动宿主机 PG 容器或通过 --shared-pg <容器名> 显式指定；"
                echo -e "\033[1;33m[智能降级] 系统已自动安全切换为传统版推荐的 [1] SQLite 本地单文件模式...\033[0m"
                DB_MODE="sqlite"
                update_env_var "DB_MODE" "sqlite"
                setup_db_for_mode
                return 0
            fi

            export SHARED_PG_CONTAINER
            update_env_var "SHARED_PG_CONTAINER" "$SHARED_PG_CONTAINER"

            local pg_db="$POSTGRES_DB"
            local pg_user="$POSTGRES_USER"
            local pg_pass="$POSTGRES_PASSWORD"

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
            local pg_port="$POSTGRES_PORT"
            local pg_host="$POSTGRES_HOST"
            if [ -n "$CUSTOM_DATABASE_URL" ]; then
                DATABASE_URL="$CUSTOM_DATABASE_URL"
            elif [ -z "$DATABASE_URL" ]; then
                DATABASE_URL="postgresql://${pg_user}:${pg_pass}@${pg_host}:${pg_port}/${pg_db}"
            fi
            export USE_POSTGRES DATABASE_URL
            update_env_var "USE_POSTGRES" "True"
            update_env_var "DATABASE_URL" "$DATABASE_URL"
            ;;
        dedicated|*)
            echo "==> 数据库部署模式: [3] 独立专属 PostgreSQL 容器 ($DB_CONTAINER_NAME)"
            choose_db_image
            local pg_db="$POSTGRES_DB"
            local pg_user="$POSTGRES_USER"
            local pg_pass="$POSTGRES_PASSWORD"
            local host_port="5433"
            if ! port_in_use 5432; then
                host_port="5432"
            fi
            local pg_port="${POSTGRES_PORT:-$host_port}"
            if [ "$POSTGRES_PORT" = "5432" ] && port_in_use 5432; then
                pg_port="$host_port"
            fi

            if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
                if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$DB_CONTAINER_NAME"; then
                    local existing_img
                    existing_img=$(docker inspect --format='{{.Config.Image}}' "$DB_CONTAINER_NAME" 2>/dev/null || true)
                    if [ -n "$existing_img" ] && [ "$existing_img" != "$DB_IMAGE" ]; then
                        echo "  [镜像自愈] 检测到已有专属 PG 容器 $DB_CONTAINER_NAME 镜像 ($existing_img) 与目标镜像 ($DB_IMAGE) 不一致，正在重建容器..."
                        docker stop "$DB_CONTAINER_NAME" >/dev/null 2>&1 || true
                        docker rm "$DB_CONTAINER_NAME" >/dev/null 2>&1 || true
                        if echo "$existing_img" | grep -qiE "18|pgvector" && echo "$DB_IMAGE" | grep -qv "18"; then
                            echo "  [存储卷自愈] 检测到历史残留容器使用了 PG18，其数据文件无法被 PG15 加载，重置存储卷 ${APP_NAME}_pgdata 以确保全新初始化..."
                            docker volume rm "${APP_NAME}_pgdata" >/dev/null 2>&1 || true
                        fi
                    fi
                fi

                if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$DB_CONTAINER_NAME"; then
                    docker update --restart unless-stopped "$DB_CONTAINER_NAME" >/dev/null 2>&1 || true
                    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$DB_CONTAINER_NAME"; then
                        echo "  启动已有独立 PG 容器 $DB_CONTAINER_NAME..."
                        docker start "$DB_CONTAINER_NAME" >/dev/null 2>&1 || true
                    fi
                else
                    echo "  创建并启动独立专属 PG 容器 $DB_CONTAINER_NAME (选用镜像: $DB_IMAGE, 宿主机端口: $pg_port)..."
                    docker run -d \
                        --name "$DB_CONTAINER_NAME" \
                        -p "${pg_port}:5432" \
                        -e POSTGRES_DB="$pg_db" \
                        -e POSTGRES_USER="$pg_user" \
                        -e POSTGRES_PASSWORD="$pg_pass" \
                        -v "${APP_NAME}_pgdata:${DB_DATA_DIR:-/var/lib/postgresql/data}" \
                        --restart unless-stopped \
                        "$DB_IMAGE" \
                        postgres -c shared_buffers=24MB -c work_mem=1MB -c max_connections=20 >/dev/null 2>&1 || true
                fi
            fi

            USE_POSTGRES="True"
            local pg_host="$POSTGRES_HOST"
            if [ -n "$CUSTOM_DATABASE_URL" ]; then
                DATABASE_URL="$CUSTOM_DATABASE_URL"
            elif [ -z "$DATABASE_URL" ]; then
                DATABASE_URL="postgresql://${pg_user}:${pg_pass}@${pg_host}:${pg_port}/${pg_db}"
            fi
            export USE_POSTGRES DATABASE_URL
            update_env_var "USE_POSTGRES" "True"
            update_env_var "DATABASE_URL" "$DATABASE_URL"
            ;;
    esac
}


stop_db_container() {
    local db_container="$DB_CONTAINER_NAME"
    [ -z "$db_container" ] && db_container="${APP_NAME:-mengya_local}-pg"

    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$db_container"; then
            echo "  ==> 停止专属 PostgreSQL 数据库容器 ($db_container)..."
            docker stop "$db_container" >/dev/null 2>&1 || true
            echo "  专属 PostgreSQL 数据库容器 ($db_container) 已停止"
        fi
    fi
}

show_db_reconfig_guide() {
    echo -e "\033[1;36m========================================================================\033[0m"
    echo -e "\033[1;36m  【.env 与数据库存储方式选择及重新配置操作说明】\033[0m"
    echo -e "\033[1;36m========================================================================\033[0m"
    echo "  1. 支持的 3 大数据库模式（通过 .env 中 DB_MODE 变量记录）："
    echo "     - sqlite    : [传统版默认推荐] 本地独立 SQLite 单文件 (db.sqlite3)，零多余容器，"
    echo "                   极简轻量 (内存常驻仅 ~50MB)，与 Docker 版数据 100% 物理硬隔离。"
    echo "     - shared    : [宿主机已运行 PG 容器时推荐] 共享宿主机已有的 PostgreSQL 容器，"
    echo "                   自动幂等创建当前应用专属数据库（$POSTGRES_DB）与账号，零多余容器，节约 80MB+ 内存。"
    echo "     - dedicated : 独立专属 PostgreSQL 容器（$DB_CONTAINER_NAME），宿主机端口映射 $POSTGRES_PORT，"
    echo "                   严格就地复用本地已有镜像，严禁网络拉取。"
    echo ""
    echo "  2. 数据库配置相关命令行参数："
    echo "     --reconfig | --reconfig-db           强制唤醒硬件感知探针与交互决策菜单（保留其他已有配置）"
    echo "     -m, --mode <sqlite|shared|dedicated> 命令行显式指定数据库模式并自动同步持久化至 .env"
    echo "     --db-image <镜像名:标签>             指定 PostgreSQL 镜像（默认优先复用本地已有镜像）"
    echo "     --shared-pg <容器名>                 指定共享的宿主机 PostgreSQL 容器名（shared 模式使用）"
    echo "     -y, --yes | --non-interactive        非交互/定时任务模式（若未配置自动采用智能推荐，绝不阻塞）"
    echo "     --db-user <用户名>                   自定义 PostgreSQL 用户名（默认: $POSTGRES_USER）"
    echo "     --db-pass <密码>                     自定义 PostgreSQL 密码（默认: $POSTGRES_PASSWORD）"
    echo "     --db-name <库名/实例名>              自定义 PostgreSQL 数据库名（默认: $POSTGRES_DB）"
    echo "     --db-port <端口>                     自定义 PostgreSQL 连接端口（默认: $POSTGRES_PORT）"
    echo "     --db-host <主机地址>                 自定义 PostgreSQL 主机地址（默认: $POSTGRES_HOST）"
    echo "     --database-url <完整URL>             直接指定完整 DATABASE_URL 连接串"
    echo ""
    echo "  3. 首次使用与再次重新选择方式："
    echo "     [方式一] 命令行显式重配（强烈推荐，最安全便捷）："
    echo "              ./run.sh start --reconfig"
    echo "              或在启动时直接指定目标模式："
    echo "              ./run.sh start -m sqlite (或 -m shared / -m dedicated)"
    echo "     [方式二] 修改 .env 文件中的 DB_MODE 变量："
    echo "              若需切换模式，直接编辑 .env 将 DB_MODE=... 改为目标模式（如 DB_MODE=shared），"
    echo "              或将 DB_MODE 这一行删除或留空，下次执行 ./run.sh start 即可自动重新唤起选择向导。"
    echo "     [方式三] 直接删除整个 .env 文件的影响说明："
    echo "              删除 .env 虽可重置向导，但会同时重置系统安全密钥 (SECRET_KEY)、自定义端口等参数，"
    echo "              因此强烈建议优先采用 [方式一] 或 [方式二]。"
    echo -e "\033[1;36m========================================================================\033[0m"
    echo ""
}
