#!/bin/bash

# 🚀 Auto Setup Sepolia Geth + Beacon (Prysm or Lighthouse) for Aztec Sequencer
# Assumes system has at least 1TB NVMe, 16GB RAM
# Updated for Fusaka upgrade compatibility

set -e

# === CONFIG ===
DATA_DIR="$HOME/sepolia-node"
GETH_DIR="$DATA_DIR/geth"
JWT_FILE="$DATA_DIR/jwt.hex"
COMPOSE_FILE="$DATA_DIR/docker-compose.yml"

# === CLEANUP FUNCTION ===
cleanup_all() {
  echo ">>> 正在停止并删除容器..."
  docker rm -f lighthouse prysm geth 2>/dev/null || true

  echo ">>> 正在删除相关镜像 (若不存在请忽略报错)..."
  docker rmi -f ethereum/client-go:v1.16.5 sigp/lighthouse:v8.0.0 sigp/lighthouse:v8.0.0-rc.2 gcr.io/prysmaticlabs/prysm/beacon-chain:v6.1.2 2>/dev/null || true

  echo ">>> 正在清理数据目录..."
  rm -rf "$GETH_DIR" "$DATA_DIR/lighthouse" "$DATA_DIR/prysm"
  rm -f "$JWT_FILE" "$COMPOSE_FILE"
  rmdir "$DATA_DIR" 2>/dev/null || true

  echo ">>> 清理完成，脚本文件已保留。"
}

show_sync_status() {
  echo "============ 执行层（Geth）============"
  if ! docker ps --format '{{.Names}}' | grep -q '^geth$'; then
    echo "状态: 未运行"
  else
    sync_result=$(curl -s -X POST http://localhost:8545 \
      -H "Content-Type: application/json" \
      -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}')
    if [ -z "$sync_result" ]; then
      echo "状态: 无法访问 RPC（请检查 8545 端口）"
    elif echo "$sync_result" | jq -e '.result == false' >/dev/null 2>&1; then
      echo "状态: 已同步 ✅"
    elif echo "$sync_result" | jq -e '.result.currentBlock' >/dev/null 2>&1; then
      current_block=$(echo "$sync_result" | jq -r '.result.currentBlock')
      highest_block=$(echo "$sync_result" | jq -r '.result.highestBlock')
      echo "状态: 正在同步 🔄"
      echo "当前区块: $current_block"
      echo "目标区块: $highest_block"
    else
      echo "状态: 正在同步（详细信息获取失败）"
    fi
  fi

  echo ""
  echo "============ 共识层（Lighthouse）============"
  if ! docker ps --format '{{.Names}}' | grep -q '^lighthouse$'; then
    echo "状态: 未运行"
  else
    beacon_result=$(curl -s http://localhost:5052/eth/v1/node/syncing)
    if [ -z "$beacon_result" ]; then
      echo "状态: 无法访问 Beacon API（请检查 5052 端口）"
    elif echo "$beacon_result" | jq -e '.data.is_syncing == false' >/dev/null 2>&1; then
      head_slot=$(echo "$beacon_result" | jq -r '.data.head_slot // "0"')
      echo "状态: 已同步 ✅"
      echo "当前 Slot: $head_slot"
    else
      current_slot=$(echo "$beacon_result" | jq -r '.data.current_slot // "0"')
      head_slot=$(echo "$beacon_result" | jq -r '.data.head_slot // "0"')
      echo "状态: 正在同步 🔄"
      echo "当前 Slot: $current_slot"
      echo "目标 Slot: $head_slot"
      if [ "$head_slot" != "0" ] && [ "$head_slot" != "null" ]; then
        progress=$(( current_slot * 100 / head_slot ))
        echo "同步进度: ${progress}%"
      fi
    fi
  fi
}

# === ACTION SELECTION ===
echo ">>> 请选择操作:"
echo "1) 部署 Sepolia 节点（Geth + Lighthouse）"
echo "2) 退出"
echo "3) 清理所有节点容器与数据 (保留脚本)"
echo "4) 查看同步进度"
read -rp "请输入选项 [1-4]: " ACTION_CHOICE

case "$ACTION_CHOICE" in
  1|"")
    echo ">>> 开始部署/升级..."
    ;;
  3)
    cleanup_all
    exit 0
    ;;
  4)
    show_sync_status
    exit 0
    ;;
  2)
    echo ">>> 已退出。"
    exit 0
    ;;
  *)
    echo "❌ 无效选项，程序结束。"
    exit 1
    ;;
esac

# Check if node is already running and get current beacon client
CURRENT_BEACON=""
if [ -f "$COMPOSE_FILE" ]; then
    if grep -q "prysm:" "$COMPOSE_FILE"; then
        CURRENT_BEACON="prysm"
    elif grep -q "lighthouse:" "$COMPOSE_FILE"; then
        CURRENT_BEACON="lighthouse"
    fi
fi

# === TARGET CLIENT ===
NEW_BEACON="lighthouse"
BEACON_VOLUME="$DATA_DIR/lighthouse"

# === CHECKPOINT SYNC ENDPOINT ===
CHECKPOINT_SYNC_URL="https://sepolia.beaconstate.info"
echo ">>> 使用以太坊社区维护的检查点同步：$CHECKPOINT_SYNC_URL"

# === DEPENDENCY CHECK ===
echo ">>> 正在检查依赖环境..."
install_if_missing() {
  local cmd="$1"
  local pkg="$2"

  if ! command -v $cmd &> /dev/null; then
    echo "⛔ 缺少 $cmd，正在安装软件包 $pkg..."
    sudo apt update
    sudo apt install -y $pkg
  else
    echo "✅ $cmd 已安装。"
  fi
}

# Docker check
if ! command -v docker &> /dev/null || ! command -v docker compose &> /dev/null; then
  echo "⛔ 未检测到 Docker 或 Docker Compose，开始安装..."

  for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
    sudo apt-get remove -y $pkg || true
  done

  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt update
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo docker run hello-world
  sudo systemctl enable docker && sudo systemctl restart docker
else
  echo "✅ Docker 与 Docker Compose 已安装。"
fi

install_if_missing curl curl
install_if_missing openssl openssl
install_if_missing jq jq

# Create directories
mkdir -p "$GETH_DIR"
mkdir -p "$BEACON_VOLUME"

# === GENERATE JWT SECRET ===
echo ">>> 正在生成 JWT 密钥..."
openssl rand -hex 32 > "$JWT_FILE"

# === WRITE docker-compose.yml ===
echo ">>> 正在写入 docker-compose.yml..."
cat > "$COMPOSE_FILE" <<EOF
services:
  geth:
    image: ethereum/client-go:v1.16.5
    container_name: geth
    restart: unless-stopped
    volumes:
      - $GETH_DIR:/root/.ethereum
      - $JWT_FILE:/root/jwt.hex
    ports:
      - "8545:8545"
      - "30303:30303"
      - "8551:8551"
    command: >
      --sepolia
      --http --http.addr 0.0.0.0 --http.api eth,web3,net,engine
      --authrpc.addr 0.0.0.0 --authrpc.port 8551
      --authrpc.jwtsecret /root/jwt.hex
      --authrpc.vhosts=*
      --http.corsdomain="*"
      --syncmode=snap
      --cache=8192
      --http.vhosts=*
EOF

cat >> "$COMPOSE_FILE" <<EOF

  lighthouse:
    image: sigp/lighthouse:v8.0.0
    container_name: lighthouse
    restart: unless-stopped
    volumes:
      - $BEACON_VOLUME:/root/.lighthouse
      - $JWT_FILE:/root/jwt.hex
    depends_on:
      - geth
    ports:
      - "5052:5052"
      - "9000:9000/tcp"
      - "9000:9000/udp"
    command: >
      lighthouse bn
      --network sepolia
      --execution-endpoint http://geth:8551
      --execution-jwt /root/jwt.hex
EOF

if [ -n "$CHECKPOINT_SYNC_URL" ]; then
  cat >> "$COMPOSE_FILE" <<EOF
      --checkpoint-sync-url=$CHECKPOINT_SYNC_URL
EOF
fi

cat >> "$COMPOSE_FILE" <<'EOF'
      --http
      --http-address 0.0.0.0
      --supernode
EOF

# === START DOCKER ===
echo ">>> 正在启动包含 Lighthouse 的 Sepolia 节点..."

# Pull latest images first
echo ">>> 拉取最新镜像..."
cd "$DATA_DIR"
docker compose pull

# Start Geth first and wait for it to be ready
echo ">>> 启动执行层 Geth..."
docker compose up -d geth

# Wait for Geth to be ready
echo ">>> 等待 Geth 就绪..."
while true; do
    if curl -s -X POST http://localhost:8545 \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' > /dev/null; then
        echo ">>> Geth 已就绪！"
        break
    fi
    echo ">>> Geth 启动中，稍候..."
    sleep 5
done

# Start beacon client
echo ">>> 启动共识层 Lighthouse..."
docker compose up -d lighthouse

# Wait for beacon client to be ready
echo ">>> 等待 Lighthouse 就绪..."
while true; do
    if curl -s http://localhost:5052/eth/v1/node/syncing > /dev/null; then
        echo ">>> Lighthouse 已就绪！"
        break
    fi
    echo ">>> Lighthouse 启动中，稍候..."
    sleep 5
done

echo ">>> 部署完成！"
echo ">>> 当前节点配置："
echo "    - 执行层：Geth v1.16.5 (Fusaka ready)"
echo "    - 共识层：Lighthouse v8.0.0 (已启用 Supernode)"
if [ -n "$CHECKPOINT_SYNC_URL" ]; then
  echo "    - 检查点同步：$CHECKPOINT_SYNC_URL"
else
  echo "    - 检查点同步：已关闭 (全量同步)"
fi
echo "    - RPC 接口：http://localhost:8545"
echo "    - Beacon API：http://localhost:5052"
