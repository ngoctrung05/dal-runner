#!/usr/bin/env bash
set -e

# 1. CẤU HÌNH CƠ BẢN
NODE_IMAGE="ghcr.io/celestiaorg/celestia-node:v0.28.5-mocha"
VALIDATOR="celestia-validator-astar"

# 2. LẤY TRUSTED HASH & HEIGHT TỪ VALIDATOR
echo "🔍 Đang lấy thông tin Trust từ Validator..."

# Lấy output JSON (Lưu ý: Output của bạn không có .result)
STATUS=$(docker exec $VALIDATOR celestia-appd status --output json 2>/dev/null)

# --- SỬA LỖI TẠI ĐÂY (Bỏ .result đi) ---
TRUST_HASH=$(echo "$STATUS" | jq -r '.sync_info.latest_block_hash')
TRUST_HEIGHT=$(echo "$STATUS" | jq -r '.sync_info.latest_block_height')

# Kiểm tra lại lần nữa
if [ "$TRUST_HASH" == "null" ] || [ -z "$TRUST_HASH" ]; then
  echo "❌ Lỗi: Vẫn không lấy được Hash. Hãy kiểm tra lại jq."
  echo "Output: $STATUS"
  exit 1
fi

echo "✅ Trusted Hash:   $TRUST_HASH"
echo "✅ Trusted Height: $TRUST_HEIGHT"

# 3. DỌN DẸP DATA CŨ
echo "🧹 Cleaning old data..."
docker run --rm -v "$(pwd):/work" alpine sh -c "rm -rf /work/celes-light1 /work/celes-light2"
mkdir -p ./celes-light1 ./celes-light2
chmod -R 777 ./celes-light1 ./celes-light2

# 4. INIT (TẠO CONFIG MẶC ĐỊNH)
echo "🚀 Initializing Nodes..."
docker run --rm -v "$(pwd)/celes-light1:/home/celestia" $NODE_IMAGE celestia light init --p2p.network private --node.store /home/celestia --keyring.backend test
docker run --rm -v "$(pwd)/celes-light2:/home/celestia" $NODE_IMAGE celestia light init --p2p.network private --node.store /home/celestia --keyring.backend test

# 5. INJECT TRUSTED HASH VÀO FILE CONFIG
echo "✍️ Injecting Trust Params into config.toml..."

inject_config() {
  local DIR=$1
  
  # Dùng sed để tìm và thay thế trong config.toml
  # Tìm TrustedHash = "" thay bằng Hash thật
  # Tìm TrustedHeight = 0 thay bằng Height thật
  docker run --rm -v "$DIR:/home/celestia" alpine sh -c \
    "sed -i 's/SyncFromHash = \"\"/SyncFromHash = \"$TRUST_HASH\"/g' /home/celestia/config.toml && \
     sed -i 's/SyncFromHeight = 0/SyncFromHeight = $TRUST_HEIGHT/g' /home/celestia/config.toml"
}

inject_config "$(pwd)/celes-light1"
inject_config "$(pwd)/celes-light2"

# 6. FIX QUYỀN
echo "🔓 Fixing permissions..."
docker run --rm -v "$(pwd):/work" alpine chmod -R 777 /work/celes-light1 /work/celes-light2

echo "✅ Setup Complete! Hash $TRUST_HASH injected."