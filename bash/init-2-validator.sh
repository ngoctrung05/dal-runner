#!/usr/bin/env bash
set -e

CHAIN_ID="private"
APP_IMAGE="ghcr.io/celestiaorg/celestia-app:v6.4.4-mocha"

BASE_DIR="$(pwd)/consensus"
DIR_NODE1="$BASE_DIR/celestia-validator"
DIR_NODE2="$BASE_DIR/celestia-validator2"

function fix_perms() {
    echo "🔓 Docker is unlocking file permissions..."
    docker run --rm -v "$BASE_DIR:/work" alpine chmod -R 777 /work
}

echo "🧹 Cleaning up old data..."
docker-compose -f docker-compose.validator.yml down || true
docker run --rm -v "$(pwd):/work" alpine sh -c "rm -rf /work/consensus"

echo "📂 Creating directories..."
mkdir -p "$DIR_NODE1" "$DIR_NODE2"
chmod -R 777 "$BASE_DIR"

# --- 1. INIT NODE ---
echo "🚀 Init Nodes..."
docker run --rm -v "$DIR_NODE1:/home/celestia/.celestia-app" $APP_IMAGE init "Node1" --chain-id "$CHAIN_ID"
docker run --rm -i -v "$DIR_NODE1:/home/celestia/.celestia-app" $APP_IMAGE keys add "validator1" --keyring-backend test

docker run --rm -v "$DIR_NODE2:/home/celestia/.celestia-app" $APP_IMAGE init "Node2" --chain-id "$CHAIN_ID"
docker run --rm -i -v "$DIR_NODE2:/home/celestia/.celestia-app" $APP_IMAGE keys add "validator2" --keyring-backend test

# --- 2. LẤY ĐỊA CHỈ ---
echo "📝 Extracting Addresses..."
ADDR_NODE2=$(docker run --rm -v "$DIR_NODE2:/home/celestia/.celestia-app" $APP_IMAGE keys show validator2 -a --keyring-backend test | tail -n 1 | tr -d '\r')

# --- 3. ADD GENESIS ACCOUNTS ---
echo "💰 Adding Accounts..."
# Cấp nhiều tiền để thoải mái trả phí sau này
docker run --rm -v "$DIR_NODE1:/home/celestia/.celestia-app" $APP_IMAGE genesis add-genesis-account "validator1" "10000000000000utia" --keyring-backend test
docker run --rm -v "$DIR_NODE1:/home/celestia/.celestia-app" $APP_IMAGE genesis add-genesis-account "$ADDR_NODE2" "10000000000000utia"

fix_perms

# --- 4. CONFIG MẠNG (Chỉ chỉnh IP & P2P, KHÔNG chỉnh Gas) ---
echo "🔧 Configuring Network..."
for DIR in "$DIR_NODE1" "$DIR_NODE2"; do
  docker run --rm -v "$DIR:/home/celestia/.celestia-app" alpine sh -c \
  "sed -i 's/127.0.0.1:26657/0.0.0.0:26657/g' /home/celestia/.celestia-app/config/config.toml && \
   sed -i 's/localhost:9090/0.0.0.0:9090/g' /home/celestia/.celestia-app/config/app.toml && \
   sed -i 's/addr_book_strict = true/addr_book_strict = false/g' /home/celestia/.celestia-app/config/config.toml"
done
# addr_book_strict = false là bắt buộc để chạy private với IP docker

fix_perms

# --- 5. SYNC GENESIS ---
cp "$DIR_NODE1/config/genesis.json" "$DIR_NODE2/config/genesis.json"

# --- 6. GENTX (TRẢ PHÍ CHUẨN) ---
echo "✍️ Creating Gentxs..."
# Mặc định cần phí, ta trả 5000utia cho chắc chắn qua cửa
docker run --rm -v "$DIR_NODE1:/home/celestia/.celestia-app" $APP_IMAGE genesis gentx "validator1" "5000000000000utia" --chain-id "$CHAIN_ID" --keyring-backend test --fees 5000utia
docker run --rm -v "$DIR_NODE2:/home/celestia/.celestia-app" $APP_IMAGE genesis gentx "validator2" "5000000000000utia" --chain-id "$CHAIN_ID" --keyring-backend test --fees 5000utia

fix_perms

# --- 7. COLLECT ---
echo "📥 Collecting Gentxs..."
cp $DIR_NODE2/config/gentx/*.json $DIR_NODE1/config/gentx/

docker run --rm -v "$DIR_NODE1:/home/celestia/.celestia-app" $APP_IMAGE genesis collect-gentxs
docker run --rm -v "$DIR_NODE1:/home/celestia/.celestia-app" $APP_IMAGE genesis validate

fix_perms

# --- 8. DISTRIBUTE ---
cp "$DIR_NODE1/config/genesis.json" "$DIR_NODE2/config/genesis.json"
fix_perms

NODE1_ID=$(docker run --rm -v "$DIR_NODE1:/home/celestia/.celestia-app" $APP_IMAGE tendermint show-node-id | tail -n 1 | tr -d '\r')
echo "✅ Setup Default Done!"
echo "🆔 Node 1 ID: $NODE1_ID"