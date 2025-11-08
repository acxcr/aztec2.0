#!/bin/bash

# Aztec 节点部署脚本 - 完全基于官方资料
# 参考项目方文档和GitHub社区资料
# 保留用户脚本的菜单逻辑结构

set -euo pipefail

# 基础配置
AZTEC_DIR="/root/aztec"
DATA_DIR="/root/.aztec/testnet/data"
AZTEC_IMAGE_VERSION="2.1.2"
AZTEC_IMAGE="aztecprotocol/aztec:${AZTEC_IMAGE_VERSION}"
ROLLUP_CONTRACT="0xebd99ff0ff6677205509ae73f93d0ca52ac85d67"
STAKE_TOKEN_CONTRACT="0x139d2a7a0881e16332d7D1F8DB383A4507E1Ea7A"
STAKE_REQUIRED_AMOUNT="200000ether"

# 额外 CLI 路径
if [ -d "$HOME/.aztec/bin" ]; then
    export PATH="$HOME/.aztec/bin:$PATH"
fi
if [ -d "$HOME/.foundry/bin" ]; then
    export PATH="$HOME/.foundry/bin:$PATH"
fi

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 打印函数
print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

safe_source() {
    local file=$1
    if [ -f "$file" ]; then
        set +u
        # shellcheck disable=SC1090
        source "$file"
        set -u
    fi
}

ensure_command() {
    local cmd=$1
    local install_hint=${2:-}
    if ! command -v "$cmd" >/dev/null 2>&1; then
        print_error "未检测到命令：$cmd"
        if [ -n "$install_hint" ]; then
            print_info "安装提示：$install_hint"
        fi
        return 1
    fi
    return 0
}

ensure_or_install_jq() {
    if command -v jq >/dev/null 2>&1; then
        return 0
    fi

    print_warning "未检测到 jq。"
    if command -v apt >/dev/null 2>&1; then
        read -p "是否现在自动安装 jq？(y/N): " install_jq
        if [[ "$install_jq" == "y" || "$install_jq" == "Y" ]]; then
            print_info "开始安装 jq..."
            if apt-get update && apt-get install -y jq; then
                print_info "jq 安装完成。"
                return 0
            else
                print_error "自动安装 jq 失败，请手动运行：apt install jq"
            fi
        else
            print_info "已取消自动安装，请手动运行：apt install jq"
        fi
    else
        print_info "无法自动安装 jq，请手动安装：apt install jq"
    fi
    return 1
}

ensure_or_install_aztec_cli() {
    if command -v aztec >/dev/null 2>&1; then
        return 0
    fi

    print_warning "未检测到 Aztec CLI。"
    read -p "是否立即自动安装 Aztec CLI？(y/N): " install_cli
    if [[ "$install_cli" == "y" || "$install_cli" == "Y" ]]; then
        print_warning "安装过程会启动新的登录 Shell，完成后请输入 exit 返回本脚本。"
        echo
        print_info "开始安装 Aztec CLI..."
        if bash -i <(curl -s https://install.aztec.network); then
            print_info "Aztec CLI 安装完成。"
            safe_source "$HOME/.bashrc"
            safe_source "$HOME/.bash_profile"
            export PATH="$HOME/.aztec/bin:$PATH"
        else
            print_error "Aztec CLI 安装失败，请稍后重试或手动安装。"
        fi
    else
        print_info "已取消自动安装，请手动运行：bash -i <(curl -s https://install.aztec.network)"
    fi

    if command -v aztec >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

ensure_or_install_foundry() {
    if command -v cast >/dev/null 2>&1 && command -v forge >/dev/null 2>&1; then
        return 0
    fi

    print_warning "未检测到 Foundry (cast/forge)。"
    read -p "是否立即自动安装 Foundry？(y/N): " install_foundry
    if [[ "$install_foundry" == "y" || "$install_foundry" == "Y" ]]; then
        print_info "开始安装 Foundry..."
        if curl -L https://foundry.paradigm.xyz | bash; then
            print_info "Foundry 安装脚本执行完成，正在初始化..."
            safe_source "$HOME/.bashrc"
            safe_source "$HOME/.bash_profile"
            export PATH="$HOME/.foundry/bin:$PATH"
            if command -v foundryup >/dev/null 2>&1; then
                if foundryup; then
                    print_info "Foundry 初始化完成。"
                    export PATH="$HOME/.foundry/bin:$PATH"
                    return 0
                else
                    print_error "foundryup 执行失败，请手动运行 foundryup。"
                fi
            else
                print_error "未找到 foundryup，请确认安装脚本是否成功执行。"
            fi
        else
            print_error "Foundry 安装脚本执行失败，请稍后重试或手动安装。"
        fi
    else
        print_info "已取消自动安装，请手动运行：curl -L https://foundry.paradigm.xyz | bash && source ~/.bashrc && foundryup"
    fi

    if command -v cast >/dev/null 2>&1 && command -v forge >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

update_env_var() {
    local key=$1
    local value=$2
    local file="$AZTEC_DIR/.env"

    if [ ! -f "$file" ]; then
        mkdir -p "$AZTEC_DIR"
        touch "$file"
        print_info "已创建新的环境文件 $file。"
    fi

    if grep -q "^$key=" "$file"; then
        sed -i "s|^$key=.*|$key=$value|" "$file"
    else
        echo "$key=$value" >> "$file"
    fi
}

# 智能加载环境变量（可选，不强制要求）
if [ -f "$AZTEC_DIR/.env" ]; then
    print_info "从配置文件加载环境变量..."
    safe_source "$AZTEC_DIR/.env"
    print_info "环境变量加载完成"
fi

# 智能加载环境变量（可选，不强制要求）
if [ -f "$AZTEC_DIR/.env" ]; then
    print_info "从配置文件加载环境变量..."
    source "$AZTEC_DIR/.env"
    print_info "环境变量加载完成"
fi

# 检查 root 权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_error "本脚本必须以 root 权限运行。"
        exit 1
    fi
}

# 安装 Docker
install_docker() {
    if command -v docker &> /dev/null; then
        local version
        version=$(docker --version | grep -oP '\d+\.\d+\.\d+' || echo "0.0.0")
        print_info "Docker 已安装，版本 $version"
        return 0
    fi
    
    print_info "正在安装 Docker..."
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl start docker
    systemctl enable docker
    print_info "Docker 安装完成"
}

# 安装 Docker Compose
install_docker_compose() {
    if command -v docker-compose &> /dev/null || docker compose version &> /dev/null; then
        print_info "Docker Compose 已安装"
        return 0
    fi
    
    print_info "正在安装 Docker Compose..."
    apt-get update
    apt-get install -y docker-compose-plugin
    print_info "Docker Compose 安装完成"
}

# 获取用户输入
get_user_input() {
    if [ -f "$AZTEC_DIR/.env" ]; then
        print_info "检测到现有配置，将加载默认值。"
        set -a
        safe_source "$AZTEC_DIR/.env"
        set +a
    fi

    print_step "请输入 Aztec 节点配置信息 / Enter Aztec node configuration"
    echo
    
    local default_eth="${ETHEREUM_HOSTS:-}"
    while true; do
        echo "L1 执行客户端（EL）RPC URL / Execution layer RPC (http/https)"
        echo "  建议使用 Alchemy、Infura、DRPC 等 Sepolia EL 节点。"
        print_info "当前默认值：${default_eth:-未配置}"
        read -p "请输入 EL RPC URL (默认: ${default_eth:-无})：" input
        if [ -z "$input" ] && [ -n "$default_eth" ]; then
            ETHEREUM_HOSTS="$default_eth"
            break
        elif [[ "$input" =~ ^https?:// ]]; then
            ETHEREUM_HOSTS="$input"
            break
        else
            print_error "URL 格式无效，必须以 http:// 或 https:// 开头。"
        fi
    done
    
    echo
    
    local default_cl="${L1_CONSENSUS_HOST_URLS:-}"
    while true; do
        echo "L1 共识客户端（CL）RPC URL / Consensus layer Beacon RPC"
        echo "  建议使用自建 Lighthouse/Prsym 或公共 Beacon RPC。"
        print_info "当前默认值：${default_cl:-未配置}"
        read -p "请输入 CL RPC URL (默认: ${default_cl:-无})：" input
        if [ -z "$input" ] && [ -n "$default_cl" ]; then
            L1_CONSENSUS_HOST_URLS="$default_cl"
            break
        elif [[ "$input" =~ ^https?:// ]]; then
            L1_CONSENSUS_HOST_URLS="$input"
            break
        else
            print_error "URL 格式无效，必须以 http:// 或 https:// 开头。"
        fi
    done
    
    echo
    
    local default_attester="${VALIDATOR_PRIVATE_KEY:-}"
    while true; do
        echo "验证者私钥（证明者） / Attester private key"
        echo "  - 0x 开头的 64 位十六进制字符串"
        echo "  - 需持有足够 Sepolia ETH 与 STAKE"
        print_info "当前默认值：${default_attester:-未配置}"
        read -p "请输入验证者私钥 (默认保留原值): " input
        if [ -z "$input" ] && [ -n "$default_attester" ]; then
            VALIDATOR_PRIVATE_KEY="$default_attester"
            break
        elif [[ "$input" =~ ^0x[a-fA-F0-9]{64}$ ]]; then
            VALIDATOR_PRIVATE_KEY="$input"
            break
        else
            print_error "私钥格式无效，必须是 0x 开头的 64 位十六进制。"
        fi
    done
    
    echo
    
    local default_coinbase="${COINBASE:-}"
    while true; do
        echo "奖励地址 / Coinbase address"
        echo "  - 接收 L2 区块奖励与费用"
        print_info "当前默认值：${default_coinbase:-未配置}"
        read -p "请输入 Coinbase 地址 (默认保留原值): " input
        if [ -z "$input" ] && [ -n "$default_coinbase" ]; then
            COINBASE="$default_coinbase"
            break
        elif [[ "$input" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
            COINBASE="$input"
            break
        else
            print_error "地址格式无效，必须是 0x 开头的 40 位十六进制。"
        fi
    done
    
    echo
    
    local default_withdrawer="${WITHDRAWER_ADDRESS:-$COINBASE}"
    print_info "当前默认值：${default_withdrawer:-未配置}"
    read -p "提取地址 / Withdrawer address (默认使用 ${default_withdrawer}): " input
    if [ -z "$input" ]; then
        WITHDRAWER_ADDRESS="$default_withdrawer"
    elif [[ "$input" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        WITHDRAWER_ADDRESS="$input"
    else
        print_warning "输入格式无效，继续使用默认提取地址 $default_withdrawer"
        WITHDRAWER_ADDRESS="$default_withdrawer"
    fi

    echo

    local default_bls="${BLS_SECRET_KEY:-}"
    print_info "当前默认值：${default_bls:-未配置}"
    read -p "如已拥有 BLS 私钥，请输入（可留空稍后生成） / Existing BLS secret (optional): " input
    if [ -n "$input" ]; then
        BLS_SECRET_KEY="$input"
    else
        BLS_SECRET_KEY="${default_bls:-}"
    fi

    echo

    local default_snapshot="${SNAPSHOT_URLS:-}"
    print_info "当前默认值：${default_snapshot:-未配置}"
    read -p "如需指定快照源 (SNAPSHOT_URLS)，请输入（可留空，默认从 L1 同步）: " input
    if [ -n "$input" ]; then
        SNAPSHOT_URLS="$input"
    else
        SNAPSHOT_URLS="${default_snapshot:-}"
    fi

    echo

    local detected_ip=""
    local detected_ipv6=""
    for endpoint in \
        "https://ipv4.icanhazip.com" \
        "https://ifconfig.me/ip" \
        "https://ipinfo.io/ip" \
        "https://checkip.amazonaws.com"; do
        resp=$(curl -s --connect-timeout 5 --max-time 10 "$endpoint" 2>/dev/null || echo "")
        if [[ "$resp" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            detected_ip="$resp"
            break
        elif [[ -z "$detected_ipv6" && "$resp" =~ : ]]; then
            detected_ipv6="$resp"
        fi
    done
    if [ -z "$detected_ip" ]; then
        detected_ip="$detected_ipv6"
    fi
    local default_ip="${P2P_IP:-$detected_ip}"
    print_info "检测到的公共 IP: ${detected_ip:-未获取}"
    print_info "当前默认值：${default_ip:-未配置}"
    read -p "请输入 P2P 公网 IP (默认: ${default_ip:-127.0.0.1}): " input
    if [ -n "$input" ]; then
        P2P_IP="$input"
    elif [ -n "$default_ip" ]; then
        P2P_IP="$default_ip"
    else
        P2P_IP="127.0.0.1"
    fi
    
    echo
}

# 创建配置文件 - 严格按照官方资料
create_config_files() {
    print_step "创建配置文件..."
    
    mkdir -p "$AZTEC_DIR"
    mkdir -p "$DATA_DIR"
    
    local bls_value="${BLS_SECRET_KEY:-}"
    local snapshot_value="${SNAPSHOT_URLS:-}"

    print_info "创建 .env 文件..."
    cat > "$AZTEC_DIR/.env" <<EOF
ETHEREUM_HOSTS=$ETHEREUM_HOSTS
L1_CONSENSUS_HOST_URLS=$L1_CONSENSUS_HOST_URLS
P2P_IP=$P2P_IP
VALIDATOR_PRIVATE_KEY=$VALIDATOR_PRIVATE_KEY
COINBASE=$COINBASE
WITHDRAWER_ADDRESS=$WITHDRAWER_ADDRESS
BLS_SECRET_KEY=$bls_value
DATA_DIRECTORY=/data
LOG_LEVEL=info
GOVERNANCE_PROPOSER_PAYLOAD_ADDRESS=0xDCd9DdeAbEF70108cE02576df1eB333c4244C666
ROLLUP_CONTRACT=$ROLLUP_CONTRACT
STAKE_TOKEN_CONTRACT=$STAKE_TOKEN_CONTRACT
STAKE_REQUIRED_AMOUNT=$STAKE_REQUIRED_AMOUNT
SNAPSHOT_URLS=$snapshot_value
EOF
    chmod 600 "$AZTEC_DIR/.env"
    
    print_info "创建 docker-compose.yml 文件..."
    cat > "$AZTEC_DIR/docker-compose.yml" <<EOF
services:
  aztec-sequencer:
    container_name: aztec-sequencer
    network_mode: host
    image: $AZTEC_IMAGE
    restart: unless-stopped
    logging:
      driver: "json-file"
      options:
        max-size: "100m"
        max-file: "3"
    environment:
      ETHEREUM_HOSTS: \${ETHEREUM_HOSTS}
      L1_CONSENSUS_HOST_URLS: \${L1_CONSENSUS_HOST_URLS}
      P2P_IP: \${P2P_IP}
      VALIDATOR_PRIVATE_KEY: \${VALIDATOR_PRIVATE_KEY}
      COINBASE: \${COINBASE}
      WITHDRAWER_ADDRESS: \${WITHDRAWER_ADDRESS}
      DATA_DIRECTORY: \${DATA_DIRECTORY}
      LOG_LEVEL: \${LOG_LEVEL}
      GOVERNANCE_PROPOSER_PAYLOAD_ADDRESS: \${GOVERNANCE_PROPOSER_PAYLOAD_ADDRESS}
      ROLLUP_CONTRACT: \${ROLLUP_CONTRACT}
      STAKE_TOKEN_CONTRACT: \${STAKE_TOKEN_CONTRACT}
      STAKE_REQUIRED_AMOUNT: \${STAKE_REQUIRED_AMOUNT}
    entrypoint: >
      sh -c "EXTRA_ARGS=\"\"; \
             if [ -n \"\${SNAPSHOT_URLS:-}\" ]; then EXTRA_ARGS=\"--snapshots-urls \${SNAPSHOT_URLS}\"; fi; \
             exec node --no-warnings /usr/src/yarn-project/aztec/dest/bin/index.js start --network testnet --node --archiver --sequencer \${EXTRA_ARGS}"
    volumes:
      - $DATA_DIR:/data
EOF
    chmod 644 "$AZTEC_DIR/docker-compose.yml"
    
    print_info "配置文件创建完成"
}

# 防火墙配置提示
show_firewall_info() {
    print_step "防火墙配置说明..."
    
    print_info "请手动配置防火墙开放以下端口："
    print_info "  - 22/tcp   (SSH 访问)"
    print_info "  - 40400/tcp (P2P 网络)"
    print_info "  - 40400/udp (P2P 网络)"
    print_info "  - 8080/tcp  (HTTP API)"
    echo
    print_info "如果使用 ufw，可以运行以下命令："
    print_info "  ufw allow 22/tcp"
    print_info "  ufw allow 40400/tcp"
    print_info "  ufw allow 40400/udp"
    print_info "  ufw allow 8080/tcp"
    echo
    print_warning "注意：防火墙配置失败可能导致节点无法正常工作"
}

# 拉取最新镜像
pull_latest_image() {
    print_step "拉取最新 Aztec 镜像..."
    print_info "正在拉取 $AZTEC_IMAGE..."
    docker pull "$AZTEC_IMAGE"
    local image_id
    image_id=$(docker images --format "{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.CreatedAt}}" | grep "$AZTEC_IMAGE" | head -1 | awk '{print $2}')
    [ -n "$image_id" ] && print_info "镜像拉取完成，镜像 ID: $image_id"
}

# 启动节点
start_node() {
    print_step "启动 Aztec 节点..."
    cd "$AZTEC_DIR"
    print_info "停止当前容器（如有）..."
    docker compose down
    print_info "启动新容器..."
    if docker compose up -d; then
        print_info "Aztec 节点启动成功！"
        print_info "容器名称: aztec-sequencer"
        print_info "数据目录: $DATA_DIR"
        print_info "配置目录: $AZTEC_DIR"
    else
        print_error "启动失败，请检查配置和日志"
        exit 1
    fi
}

# 轻量删除节点 - 保留配置和P2P身份
delete_node() {
    print_step "轻量删除 Aztec 节点..."
    
    print_warning "此操作将删除以下内容："
    print_warning "  - Docker 容器和镜像"
    print_warning "  - 同步数据（archiver, world_state, cache）"
    print_warning "  - Docker系统缓存"
    echo
    print_info "将保留以下内容："
    print_info "  - 配置文件（.env, docker-compose.yml）"
    print_info "  - P2P身份文件（节点ID保持不变）"
    print_info "  - 脚本文件"
    echo
    
    read -p "确认要执行轻量删除吗？(y/N): " confirm_delete
    if [[ "$confirm_delete" != "y" && "$confirm_delete" != "Y" ]]; then
        print_info "操作已取消"
        echo "按任意键返回主菜单..."
        read -n 1
        return
    fi
    
    echo
    print_info "开始轻量删除节点..."
    
    # 1. 停止并删除容器
    print_info "1/5: 停止并删除容器..."
    docker stop aztec-sequencer 2>/dev/null || true
    docker rm aztec-sequencer 2>/dev/null || true
    
    # 2. 删除所有Aztec镜像
    print_info "2/5: 删除所有 Aztec 镜像..."
    docker images --format "{{.Repository}} {{.ID}}" | awk '/aztecprotocol\/aztec/{print $2}' | xargs -r docker rmi -f 2>/dev/null || true
    
    # 3. 删除同步数据（保留P2P身份和配置）
    print_info "3/5: 删除同步数据..."
    rm -rf "/root/.aztec/testnet/data/archiver" 2>/dev/null || true
    rm -rf "/root/.aztec/testnet/data/world_state" 2>/dev/null || true  
    rm -rf "/root/.aztec/testnet/data/cache" 2>/dev/null || true
    rm -rf "/root/.aztec/testnet/data/sentinel" 2>/dev/null || true
    rm -rf "/root/.aztec/testnet/data/slasher" 2>/dev/null || true
    print_info "同步数据已清理，P2P身份文件已保留"
    
    # 4. 清理Docker系统
    print_info "4/5: 清理Docker系统..."
    docker system prune -f --volumes 2>/dev/null || true
    
    # 5. 验证保留的文件
    print_info "5/5: 验证保留的文件..."
    if [ -f "/root/.aztec/testnet/data/p2p-private-key" ]; then
        print_info "✅ P2P私钥已保留"
    fi
    if [ -f "$AZTEC_DIR/.env" ]; then
        print_info "✅ 配置文件已保留"  
    fi
    
    print_info "✅ 轻量删除完成！"
    echo
    print_info "已删除的内容："
    print_info "  - Docker 容器: aztec-sequencer"
    print_info "  - Aztec 镜像 (aztecprotocol/aztec:*)"
    print_info "  - 同步数据: archiver, world_state, cache"
    print_info "  - Docker系统缓存"
    echo
    print_info "✅ 已保留的内容："
    print_info "  - 配置文件: $AZTEC_DIR/.env, docker-compose.yml"
    print_info "  - P2P身份: p2p-private-key, p2p/, p2p-peers/"
    print_info "  - 脚本文件: aztec2.0.sh"
    echo
    print_info "📝 现在可以直接选择选项1或4重新部署，配置和节点ID将保持不变"
    
    echo "按任意键返回主菜单..."
    read -n 1
}

generate_bls_secret_key() {
    ensure_command "aztec" "请先安装 Aztec CLI：bash -i <(curl -s https://install.aztec.network)"
    ensure_command "jq" "请运行 apt install jq"
    ensure_command "cast" "请先安装 Foundry：curl -L https://foundry.paradigm.xyz | bash && source ~/.bashrc && foundryup"

    local bls_dir="$AZTEC_DIR/bls_keys"
    mkdir -p "$bls_dir"
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    local raw_file="$bls_dir/${timestamp}_raw.txt"
    local json_file="$bls_dir/${timestamp}.json"
    local latest_raw="$bls_dir/last_output_raw.txt"
    local latest_json="$bls_dir/last_output.json"

    print_info "正在使用 aztec CLI 生成临时密钥..."
    local cmd_output
    if ! cmd_output=$(aztec validator-keys new \
        --json \
        --fee-recipient 0x0000000000000000000000000000000000000000000000000000000000000000 2>&1 | tee "$raw_file"); then
        print_error "调用 aztec validator-keys new 失败，请检查 CLI 安装及网络。"
        echo "$cmd_output"
        return 1
    fi

    local cmd_clean
    cmd_clean=$(printf '%s\n' "$cmd_output" | tr -d '\r')
    printf '%s\n' "$cmd_clean" > "$raw_file"
    cp "$raw_file" "$latest_raw" >/dev/null 2>&1 || ln -sf "$raw_file" "$latest_raw"

    local json_payload
    json_payload=$(printf '%s\n' "$cmd_clean" | sed '/^acc1:/,$d' | sed '/^[[:space:]]*$/d')
    if [ -n "$json_payload" ]; then
        printf '%s\n' "$json_payload" > "$json_file"
        cp "$json_file" "$latest_json" >/dev/null 2>&1 || ln -sf "$json_file" "$latest_json"
    fi

    local attester_eth=""
    local attester_bls=""
    local attester_address=""
    if [ -s "$json_file" ]; then
        attester_eth=$(jq -r '.validators[0].attester.eth // empty' "$json_file" 2>/dev/null || echo "")
        attester_bls=$(jq -r '.validators[0].attester.bls // empty' "$json_file" 2>/dev/null || echo "")
    fi

    if [[ -z "$attester_bls" || "$attester_bls" == "null" ]]; then
        attester_bls=$(printf '%s\n' "$cmd_clean" | awk '/bls:/ {gsub(/.*bls:[[:space:]]*/, ""); print; exit}' | tr -d '"' | xargs)
    fi

    if [ -n "$attester_eth" ]; then
        attester_address=$(cast wallet address "$attester_eth" 2>/dev/null || echo "")
    fi

    if [[ -z "$attester_bls" || "$attester_bls" == "null" ]]; then
        print_error "未能解析到 BLS 私钥，请手动执行 aztec validator-keys new 并记录输出。"
        cat "$raw_file"
        return 1
    fi

    print_info "原始输出已保存：$latest_raw"
    [ -s "$json_file" ] && print_info "JSON 结果已保存：$latest_json"
    if [ -n "$attester_eth" ]; then
        print_info "新的以太坊私钥 (attester.eth)：$attester_eth"
    fi
    if [ -n "$attester_address" ]; then
        print_info "新的以太坊地址：$attester_address"
    fi
    print_info "新的 BLS 私钥 (attester.bls)：$attester_bls"
    if [ -n "$attester_address" ]; then
        print_warning "请向上述新地址转入 0.2 - 0.5 Sepolia ETH 后再继续注册。"
    fi

    echo "$attester_eth|$attester_bls|$attester_address"
    return 0
}

register_validator() {
    print_step "通过 CLI 注册序列器 / CLI Register Sequencer"

    local has_env=false
    if [ -f "$AZTEC_DIR/.env" ]; then
        has_env=true
        set -a
        safe_source "$AZTEC_DIR/.env"
        set +a
        print_info "已从 $AZTEC_DIR/.env 读取默认参数，如需覆盖可手动输入。"
    else
        print_warning "未找到 $AZTEC_DIR/.env，将通过交互方式填写所需配置。"
    fi

    ensure_or_install_aztec_cli
    if ! ensure_command "aztec" "请先安装 Aztec CLI：bash -i <(curl -s https://install.aztec.network)"; then
        echo "按任意键返回主菜单..."
        read -n 1
        return
    fi
    
    ensure_or_install_foundry
    if ! ensure_command "cast" "请先安装 Foundry：curl -L https://foundry.paradigm.xyz | bash && source ~/.bashrc && foundryup"; then
        echo "按任意键返回主菜单..."
        read -n 1
        return
    fi
    
    ensure_or_install_jq
    if ! ensure_command "jq" "请运行 apt install jq"; then
        echo "按任意键返回主菜单..."
        read -n 1
        return
    fi

    local old_priv="${VALIDATOR_PRIVATE_KEY:-}"
    if [ -z "$old_priv" ]; then
        print_warning "注意：此处输入的旧私钥将直接回显，请确认环境安全。"
        read -rp "请输入旧验证者私钥（Attester Private Key，当前节点正在使用的旧地址私钥）： " old_priv
    fi
    old_priv=$(echo "$old_priv" | xargs)

    local default_rpc=""
    if [ -n "${ETHEREUM_HOSTS:-}" ]; then
        default_rpc=$(echo "$ETHEREUM_HOSTS" | cut -d',' -f1 | xargs)
    fi
    read -p "请输入 L1 执行层 RPC（Execution Layer RPC，留空使用 ${default_rpc:-需手动输入}）： " rpc_url
    if [ -z "$rpc_url" ]; then
        rpc_url="$default_rpc"
    fi
    if [ -z "$rpc_url" ]; then
        read -p "请再次输入 L1 执行层 RPC（不可为空）： " rpc_url
        if [ -z "$rpc_url" ]; then
            print_error "未提供 L1 RPC 地址，无法继续。"
            echo "按任意键返回主菜单..."
            read -n 1
            return
        fi
    fi

    local old_address
    old_address=$(cast wallet address "$old_priv" 2>/dev/null || echo "")
    if [ -z "$old_address" ]; then
        while true; do
            read -p "请输入旧节点的证明者地址（Attester Address，旧地址，0x 开头的 40 位十六进制）： " old_address
            if [[ "$old_address" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
                break
            else
                print_error "地址格式无效，请重新输入。"
            fi
        done
    else
        print_info "使用旧证明者地址：$old_address"
    fi

    local new_eth_priv=""
    local new_bls_priv="${BLS_SECRET_KEY:-}"
    local new_address=""

    read -p "请输入新的验证者以太坊私钥（留空表示自动生成）： " new_eth_priv
    new_eth_priv=$(echo "$new_eth_priv" | xargs)

    read -p "请输入新的 BLS 私钥（留空表示自动生成）： " manual_bls
    manual_bls=$(echo "$manual_bls" | xargs)
    if [ -n "$manual_bls" ]; then
        new_bls_priv="$manual_bls"
    fi

    if [ -z "$new_eth_priv" ] || [ -z "$new_bls_priv" ]; then
        local generated_output
        generated_output=$(generate_bls_secret_key) || {
            print_error "生成密钥失败，请手动生成后重试。"
            echo "按任意键返回主菜单..."
            read -n 1
            return
        }
        local generated_line
        generated_line=$(printf '%s\n' "$generated_output" | tail -n 1)
        new_eth_priv=$(printf '%s' "$generated_line" | cut -d'|' -f1 | xargs)
        new_bls_priv=$(printf '%s' "$generated_line" | cut -d'|' -f2 | xargs)
        new_address=$(printf '%s' "$generated_line" | cut -d'|' -f3 | xargs)
    else
        if [ -n "$new_eth_priv" ]; then
            new_address=$(cast wallet address "$new_eth_priv" 2>/dev/null || echo "")
        fi
        if [ -z "$new_bls_priv" ]; then
            print_error "BLS 私钥为空，请重新运行。"
            echo "按任意键返回主菜单..."
            read -n 1
            return
        fi
    fi

    if [ -z "$new_eth_priv" ]; then
        print_error "未能确定新的以太坊私钥，请重新运行。"
        echo "按任意键返回主菜单..."
        read -n 1
        return
    fi

    if [ -z "$new_address" ]; then
        new_address=$(cast wallet address "$new_eth_priv" 2>/dev/null || echo "")
    fi
    if [ -z "$new_address" ]; then
        print_error "未能根据新的以太坊私钥推导出地址，请检查输入。"
        echo "按任意键返回主菜单..."
        read -n 1
        return
    fi

    new_bls_priv=$(echo "$new_bls_priv" | xargs)
    if [ -z "$new_bls_priv" ]; then
        print_error "BLS 私钥生成失败，请手动执行 aztec validator-keys new 并重试。"
        echo "按任意键返回主菜单..."
        read -n 1
        return
    fi
    if [[ ! "$new_bls_priv" =~ ^0x[0-9a-fA-F]+$ ]]; then
        print_error "BLS 私钥格式无效，必须是 0x 开头的十六进制字符串。"
        echo "按任意键返回主菜单..."
        read -n 1
        return
    fi

    print_info "新的以太坊私钥 (attester.eth)：$new_eth_priv"
    print_info "新的 BLS 私钥 (attester.bls)：$new_bls_priv"
    print_info "新的验证者地址：$new_address"
    if [ -n "$new_address" ]; then
        print_warning "请确保已向 $new_address 转入 0.2 - 0.5 Sepolia ETH（覆盖注册与 Gas 成本）。"
    fi

    local withdrawer="${WITHDRAWER_ADDRESS:-${COINBASE:-}}"
    if [ -z "$withdrawer" ]; then
        read -p "是否使用新地址 $new_address 作为提取地址？(Y/n): " withdrawer_use_new
        if [[ "$withdrawer_use_new" =~ ^[nN]$ ]]; then
            read -p "请输入提取地址（0x 开头的 40 位十六进制）： " withdrawer
            withdrawer=$(echo "$withdrawer" | xargs)
        else
            withdrawer="$new_address"
        fi
    else
        read -p "当前提取地址为 $withdrawer，是否保持不变？(Y/n): " withdrawer_choice
        if [[ "$withdrawer_choice" =~ ^[nN]$ ]]; then
            read -p "请输入新的提取地址（0x 开头的 40 位十六进制，可留空使用 $new_address）： " withdrawer
            withdrawer=$(echo "$withdrawer" | xargs)
            if [ -z "$withdrawer" ]; then
                withdrawer="$new_address"
            fi
        fi
    fi
    while [[ -z "$withdrawer" || ! "$withdrawer" =~ ^0x[a-fA-F0-9]{40}$ ]]; do
        print_error "地址格式无效，请重新输入。"
        read -p "请输入提取地址（0x 开头的 40 位十六进制）： " withdrawer
        withdrawer=$(echo "$withdrawer" | xargs)
    done

    print_info "选择的提取地址：$withdrawer"

    if [ -n "$new_address" ]; then
        read -p "确认资金已到位后按 Enter 继续..." _
    fi
    
    echo
    print_info "旧验证者地址：$old_address"
    print_info "新验证者地址：$new_address"
    print_warning "请确保证明者旧地址 $old_address 已持有 200000 STAKE（保持质押状态），同时新地址 $new_address 拥有足够的 Sepolia ETH 支付注册 Gas。"
    read -p "确认继续执行授权与注册操作吗？(y/N): " confirm_all
    if [[ "$confirm_all" != "y" && "$confirm_all" != "Y" ]]; then
        print_info "操作已取消。"
        echo "按任意键返回主菜单..."
        read -n 1
        return
    fi

    echo
    print_info "执行 STAKE 授权..."
    if ! cast send "$STAKE_TOKEN_CONTRACT" "approve(address,uint256)" "$ROLLUP_CONTRACT" "$STAKE_REQUIRED_AMOUNT" --private-key "$old_priv" --rpc-url "$rpc_url"; then
        print_error "授权交易失败，请检查账户余额与 RPC 配置。"
        echo "按任意键返回主菜单..."
        read -n 1
        return
    fi

    echo
    print_info "提交注册交易..."
    if ! aztec add-l1-validator \
        --l1-rpc-urls "$rpc_url" \
        --network testnet \
        --private-key "$old_priv" \
        --attester "$new_address" \
        --withdrawer "$withdrawer" \
        --bls-secret-key "$new_bls_priv" \
        --rollup "$ROLLUP_CONTRACT"; then
        print_error "注册命令执行失败，请检查 CLI 输出。"
        echo "按任意键返回主菜单..."
        read -n 1
        return
    fi

    update_env_var "WITHDRAWER_ADDRESS" "$withdrawer"
    update_env_var "BLS_SECRET_KEY" "$new_bls_priv"
    update_env_var "VALIDATOR_PRIVATE_KEY" "$new_eth_priv"

    print_info "✅ 序列器已成功注册，环境变量已更新。"
    echo "按任意键返回主菜单..."
    read -n 1
}

reload_p2p_identity() {
    print_step "重新加载 P2P 身份 / Reload P2P Identity"

    if [ ! -f "$AZTEC_DIR/docker-compose.yml" ]; then
        print_error "未找到 docker-compose.yml，请先安装节点。"
        echo "按任意键返回主菜单..."
        read -n 1
        return
    fi

    if [ ! -f "$DATA_DIR/p2p-private-key" ]; then
        print_error "未检测到 $DATA_DIR/p2p-private-key，请先替换 P2P 身份文件。"
        echo "按任意键返回主菜单..."
        read -n 1
        return
    fi

    read -p "确认已经完成身份文件替换，是否重启容器生效？(y/N): " confirm_reload
    if [[ "$confirm_reload" != "y" && "$confirm_reload" != "Y" ]]; then
        print_info "操作已取消。"
        echo "按任意键返回主菜单..."
        read -n 1
        return
    fi

    cd "$AZTEC_DIR"
    print_info "停止容器..."
    docker compose down
    print_info "重新启动容器..."
    if docker compose up -d; then
        sleep 3
        local new_peer
        new_peer=$(docker logs aztec-sequencer 2>&1 | grep -i '"peerId"' | tail -1 | sed -n 's/.*"peerId":"\([^"]*\)".*/\1/p')
        if [ -n "$new_peer" ]; then
            print_info "新的节点 ID: $new_peer"
        else
            print_warning "未能立即获取新的节点 ID，可稍后通过选项 5 查看。"
        fi
        print_info "P2P 身份已重新加载。"
    else
        print_error "容器启动失败，请检查 docker compose 输出。"
    fi

    echo "按任意键返回主菜单..."
    read -n 1
}

# 升级节点容器
upgrade_node() {
    print_step "升级节点容器..."

    if [ ! -f "$AZTEC_DIR/docker-compose.yml" ]; then
        print_error "未找到配置文件，请先安装节点。"
        echo "按任意键返回主菜单..."
        read -n 1
        return
    fi

    if ! docker ps -a -q -f name=aztec-sequencer | grep -q .; then
        print_error "未检测到现有容器，请先安装并启动节点。"
        echo "按任意键返回主菜单..."
        read -n 1
        return
    fi

    cd "$AZTEC_DIR"
    print_info "1/4: 停止容器..."
    docker compose down

    echo
    print_warning "是否需要清空同步数据？"
    print_info "  y: 清空 archiver/world_state/cache 等数据（重新同步）"
    print_info "  n: 保留现有同步进度（推荐）"
    read -p "是否清空同步数据？(y/N): " wipe_choice
    if [[ "$wipe_choice" == "y" || "$wipe_choice" == "Y" ]]; then
        print_info "清空同步数据..."
        rm -rf "$DATA_DIR/archiver" "$DATA_DIR/world_state" "$DATA_DIR/cache" \
               "$DATA_DIR/sentinel" "$DATA_DIR/slasher" "$DATA_DIR/l1-tx-utils" 2>/dev/null || true
        print_info "同步数据已清理，P2P 身份与配置已保留。"
    else
        print_info "保留现有同步数据。"
    fi

    print_info "2/4: 拉取最新镜像 $AZTEC_IMAGE..."
    docker pull "$AZTEC_IMAGE"

    print_info "3/4: 启动新容器..."
    docker compose up -d
    
    print_info "4/4: 验证启动状态..."
    sleep 5
    if docker ps -q -f name=aztec-sequencer | grep -q .; then
        print_info "✅ 升级完成！节点已运行在版本 $AZTEC_IMAGE_VERSION"
    else
        print_error "❌ 升级后容器未运行，请检查 docker logs aztec-sequencer"
    fi
    
    echo "按任意键返回主菜单..."
    read -n 1
}

# 调整日志级别
adjust_log_level() {
    print_step "调整日志级别..."
    
    if [ ! -f "$AZTEC_DIR/.env" ]; then
        print_error "未找到配置文件，请先安装节点"
        echo "按任意键返回主菜单..."
        read -n 1
        return
    fi
    
    echo "当前日志级别选项："
    echo "1. error   - 只显示错误信息（最少日志）"
    echo "2. warn    - 显示警告和错误"
    echo "3. info    - 显示信息、警告、错误（推荐）"
    echo "4. debug   - 显示所有信息（最多日志）"
    echo
    read -p "请选择日志级别 (1-4): " log_choice
    
    case $log_choice in
        1) LOG_LEVEL="error" ;;
        2) LOG_LEVEL="warn" ;;
        3) LOG_LEVEL="info" ;;
        4) LOG_LEVEL="debug" ;;
        *)
            print_error "无效选择"
            echo "按任意键返回主菜单..."
            read -n 1
            return
            ;;
    esac
    
    # 更新 .env 文件
    sed -i "s/LOG_LEVEL=.*/LOG_LEVEL=$LOG_LEVEL/" "$AZTEC_DIR/.env"
    
    # 更新 docker-compose.yml
    sed -i "s/LOG_LEVEL: .*/LOG_LEVEL: \${LOG_LEVEL}/" "$AZTEC_DIR/docker-compose.yml"
    
    print_info "日志级别已更新为: $LOG_LEVEL"
    
    # 询问是否重启节点
    read -p "需要重启节点使配置生效吗？(y/N): " restart_choice
    if [[ "$restart_choice" == "y" || "$restart_choice" == "Y" ]]; then
        print_info "重启节点..."
        cd "$AZTEC_DIR"
        docker compose restart
        print_info "节点已重启，新日志级别生效"
    else
        print_info "配置已保存，下次重启节点时生效"
    fi
    
    echo "按任意键返回主菜单..."
    read -n 1
}

# 主安装流程
install_and_start_node() {
    print_step "开始安装 Aztec 节点..."
    
    # 检查依赖
    install_docker
    install_docker_compose
    
    # 获取用户输入
    get_user_input
    
    # 创建配置文件
    create_config_files
    
    # 显示防火墙配置说明
    show_firewall_info
    
    # 拉取最新镜像
    pull_latest_image
    
    # 启动节点
    start_node
    
    # 完成
    echo
    print_info "安装和启动完成！"
    print_info "  - 查看日志：docker logs -f aztec-sequencer"
    print_info "  - 配置目录：$AZTEC_DIR"
    print_info "  - 数据目录：$DATA_DIR"
    print_info "  - CLI 注册：可通过菜单选项 7 完成序列器注册"
    echo
    print_warning "重要提醒：请确保防火墙已开放必要端口！"
    print_info "  - 22/tcp   (SSH 访问)"
    print_info "  - 40400/tcp (P2P 网络)"
    print_info "  - 40400/udp (P2P 网络)"
    print_info "  - 8080/tcp  (HTTP API)"
}

# 主菜单函数 - 保留用户脚本的逻辑结构
main_menu() {
    while true; do
        clear
        
        # 定义颜色 - 调整为更暗色系
        BORDER_COLOR="\033[38;5;24m"      # 深蓝色边框
        TITLE_COLOR="\033[1;38;5;45m"     # 亮青色标题，加粗
        SUBTITLE_COLOR="\033[38;5;87m"    # 深青色副标题
        OPTION_COLOR="\033[38;5;195m"     # 浅青色选项
        SEPARATOR_COLOR="\033[38;5;31m"   # 深青色分隔线
        HINT_COLOR="\033[38;5;120m"       # 深绿色提示
        RESET="\033[0m"
        
        # 显示美化界面
        echo -e "${BORDER_COLOR}┌─────────────────────────────────────────────────────────┐${RESET}"
        echo -e "${BORDER_COLOR}│                                                         │${RESET}"
        echo -e "${BORDER_COLOR}│              ${TITLE_COLOR}🚀 Aztec 2.0 节点部署脚本 🚀${RESET}${BORDER_COLOR}                 │${RESET}"
        echo -e "${BORDER_COLOR}│                                                         │${RESET}"
        echo -e "${BORDER_COLOR}│           ${SUBTITLE_COLOR}基于官方资料，由 acxcr 与 Claude 共同设计${RESET}${BORDER_COLOR}      │${RESET}"
        echo -e "${BORDER_COLOR}│                                                         │${RESET}"
        echo -e "${BORDER_COLOR}└─────────────────────────────────────────────────────────┘${RESET}"
        echo
        echo "                    请选择要执行的操作:"
        echo
        echo -e "${OPTION_COLOR}    1. 安装并启动 Aztec 节点${RESET}"
        echo -e "${OPTION_COLOR}    2. 查看节点日志${RESET}"
        echo -e "${OPTION_COLOR}    3. 调整日志级别${RESET}"
        echo -e "${OPTION_COLOR}    4. 升级节点容器${RESET}"
        echo -e "${OPTION_COLOR}    5. 查看节点状态${RESET}"
        echo -e "${OPTION_COLOR}    6. 彻底删除节点${RESET}"
        echo -e "${OPTION_COLOR}    7. CLI 注册序列器 / CLI Register Sequencer${RESET}"
        echo -e "${OPTION_COLOR}    8. 重新加载 P2P 身份 / Reload P2P Identity${RESET}"
        echo -e "${OPTION_COLOR}    9. 退出 / Exit${RESET}"
        echo
        echo -e "${SEPARATOR_COLOR}    ────────────────────────────────────────────────${RESET}"
        echo
        echo -e "${HINT_COLOR}    q. 退出脚本${RESET}"
        echo
        read -p "    请输入选项 [1-9, q]: " choice

        case $choice in
            1)
                install_and_start_node
                echo "按任意键返回主菜单..."
                read -n 1
                ;;
            2)
                if [ -f "$AZTEC_DIR/docker-compose.yml" ]; then
                    print_info "查看节点日志..."
                    print_info "显示最后100条日志并实时跟随..."
                    echo "按 Ctrl+C 退出日志查看"
                    echo "─────────────────────────────────────────"
                    docker logs --tail 100 -f aztec-sequencer
                else
                    print_info "错误：未找到 $AZTEC_DIR/docker-compose.yml 文件，请先安装并启动节点。"
                fi
                echo "按任意键返回主菜单..."
                read -n 1
                ;;
            3)
                adjust_log_level
                ;;
            4)
                upgrade_node
                ;;
            5)
                check_node_status
                ;;
            6)
                delete_node
                ;;
            7)
                register_validator
                ;;
            8)
                reload_p2p_identity
                ;;
            9|q|Q)
                print_info "感谢使用，再见！"
                exit 0
                ;;
            *)
                print_info "无效选项，请输入 1-9 或 q。"
                echo "按任意键返回主菜单..."
                read -n 1
                ;;
        esac
    done
}

# 查看节点状态
check_node_status() {
    print_step "查看节点状态..."
    
    echo "=== 节点健康检查 ==="
    
    # 1. 容器状态
    if docker ps | grep -q aztec-sequencer; then
        echo "1. 容器状态: ✅ 运行中"
    else
        echo "1. 容器状态: ❌ 已停止"
        echo "按任意键返回主菜单..."
        read -n 1
        return
    fi
    

    
    # 2. 同步状态
    local current_block
    local latest_block
    
    if ! command -v jq >/dev/null 2>&1; then
        print_warning "未检测到 jq，无法解析节点高度。请运行 apt install jq 后重试。"
    else
    current_block=$(curl -s -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":1}' http://localhost:8080 | jq -r ".result.proven.number" 2>/dev/null || echo "")
    latest_block=$(curl -s -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":1}' http://localhost:8080 | jq -r ".result.latest.number" 2>/dev/null || echo "")
    
    if [ -n "$current_block" ] && [ "$current_block" != "null" ]; then
        if [ -n "$latest_block" ] && [ "$latest_block" != "null" ]; then
            local diff=$((latest_block - current_block))
            if [ $diff -le 5 ]; then
                echo "2. 同步状态: ✅ 已同步 (当前: $current_block, 最新: $latest_block)"
            elif [ $diff -le 20 ]; then
                echo "2. 同步状态: ⚠️  基本同步 (当前: $current_block, 最新: $latest_block, 差异: $diff)"
            else
                echo "2. 同步状态: 🚀 同步中 (当前: $current_block, 最新: $latest_block, 差异: $diff)"
            fi
        else
            echo "2. 同步状态: ✅ 已同步 (区块: $current_block)"
        fi
    else
        echo "2. 同步状态: ❌ 异常"
        fi
    fi
    
    # 3. P2P网络连接数
    local peer_count
    
    # 从日志中提取最新的peer数量
    peer_count=$(docker logs aztec-sequencer 2>&1 | grep "Connected to.*peers" | tail -1 | sed 's/.*Connected to \([0-9]*\) peers.*/\1/' || echo "0")
    
    echo "3. P2P连接数: 🔗 $peer_count"
    
    # 4. P2P服务状态
    local port_check=false
    local node_process_check=false
    
    # 检查端口是否被监听
    if nc -z localhost 40400 2>/dev/null; then
        port_check=true
    fi
    
    # 检查端口是否被node进程占用
    if ss -tlnp | grep ":40400" | grep -q "node"; then
        node_process_check=true
    fi
    
    if [ "$port_check" = true ] && [ "$node_process_check" = true ]; then
            echo "4. P2P服务: ✅ 正常 (Aztec序列器)"
elif [ "$port_check" = true ]; then
    echo "4. P2P服务: ⚠️  端口被占用 (非Aztec服务)"
else
    echo "4. P2P服务: ❌ 异常"
fi

# 5. 节点ID
local node_id
node_id=$(docker logs aztec-sequencer 2>&1 | grep -i "peerId" | grep -o '"peerId":"[^"]*"' | cut -d'"' -f4 | head -n 1 || echo "未知")

echo "5. 节点ID: 🆔 $node_id"

echo "=================="
echo "按任意键返回主菜单..."
read -n 1
}

# 执行主菜单
main_menu
