#!/usr/bin/env bash
set -e

APP_IMAGE="ghcr.io/celestiaorg/celestia-app:v6.4.4-mocha"
CHAIN_ID="private"

# Đường dẫn tuyệt đối
BASE_DIR="$(pwd)/consensus"
DIR_NODE1="$BASE_DIR/celestia-validator"
DIR_NODE3="$BASE_DIR/celestia-validator3"

# --- HÀM FIX QUYỀN (CHỈ NODE 3) ---
function fix_perms_node3() {
    echo "🔓 Fixing permissions for Node 3..."
    # Chỉ chmod thư mục của Node 3, KHÔNG chạm vào Node 1, 2
    docker run --rm -v "$DIR_NODE3:/work" alpine chmod -R 777 /work
}

# 1. Xóa data cũ của Node 3 (nếu có)
echo "🧹 Cleaning Node 3 data..."
docker run --rm -v "$BASE_DIR:/work" alpine sh -c "rm -rf /work/celestia-validator3"

echo "📂 Creating directories..."
mkdir -p "$DIR_NODE3"
# Set quyền 777 cho thư mục cha trước để tí nữa container ghi được
chmod 777 "$DIR_NODE3"

# 2. Init Node 3
echo "🚀 Init Node 3..."
docker run --rm -v "$DIR_NODE3:/home/celestia/.celestia-app" $APP_IMAGE init "Node3" --chain-id "$CHAIN_ID"
docker run --rm -i -v "$DIR_NODE3:/home/celestia/.celestia-app" $APP_IMAGE keys add "validator3" --keyring-backend test

# 3. COPY GENESIS (DÙNG DOCKER ĐỂ COPY)
# Cách này giúp copy từ Node 1 (Root) sang Node 3 mà không cần chmod Node 1
echo "📦 Copying Genesis from Node 1..."
docker run --rm \
  -v "$DIR_NODE1/config:/source" \
  -v "$DIR_NODE3/config:/dest" \
  alpine cp /source/genesis.json /dest/genesis.json

# 4. Config Network cho Node 3
echo "🔧 Configuring Node 3..."
docker run --rm -v "$DIR_NODE3:/home/celestia/.celestia-app" alpine sh -c \
  "sed -i 's/127.0.0.1:26657/0.0.0.0:26657/g' /home/celestia/.celestia-app/config/config.toml && \
   sed -i 's/localhost:9090/0.0.0.0:9090/g' /home/celestia/.celestia-app/config/app.toml && \
   sed -i 's/addr_book_strict = true/addr_book_strict = false/g' /home/celestia/.celestia-app/config/config.toml"

# 5. FIX QUYỀN CUỐI CÙNG (CHỈ NODE 3)
fix_perms_node3

# 6. Lấy Node ID của Node 1
NODE1_ID=$(docker run --rm -v "$DIR_NODE1:/home/celestia/.celestia-app" $APP_IMAGE tendermint show-node-id | tail -n 1 | tr -d '\r')

echo "✅ Node 3 Setup Done!"
echo "👉 Hãy copy ID này vào dòng '--p2p.persistent_peers' của Node 3 trong docker-compose:"
echo "$NODE1_ID"