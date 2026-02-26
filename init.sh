#!/usr/bin/env bash
set -e

CHAIN_ID="private"
MONIKER="nodeV1"
DENOM="utia"
STAKE="300000000000utia"
BALANCE="1000000000000utia"
APP_IMAGE="ghcr.io/celestiaorg/celestia-app:v6.4.3-mocha"

CONS_DIR="$(pwd)/consensus/celestia-validator"
GENESIS="$CONS_DIR/config/genesis.json"

rm -rf "$CONS_DIR"
mkdir -p "$CONS_DIR"
chmod -R 777 "$CONS_DIR"

docker run --rm -v "$CONS_DIR:/home/celestia/.celestia-app" \
  "$APP_IMAGE" init "$MONIKER" --chain-id "$CHAIN_ID"

docker run --rm -i -v "$CONS_DIR:/home/celestia/.celestia-app" \
  "$APP_IMAGE" keys add "$MONIKER" --keyring-backend test

docker run --rm -v "$CONS_DIR:/home/celestia/.celestia-app" \
  "$APP_IMAGE" genesis add-genesis-account "$MONIKER" "$BALANCE" \
  --keyring-backend test

# ✅ FIX: Dùng đúng tên trường network_min_gas_price
jq '.app_state.minfee.params.network_min_gas_price = "0.0"' \
  "$GENESIS" > tmp.json && mv tmp.json "$GENESIS"

echo "🔧 Updating listeners to 0.0.0.0..."

docker run --rm -v "$CONS_DIR:/home/celestia/.celestia-app" alpine:latest sh -c \
  "sed -i 's/minimum-gas-prices = \"\"/minimum-gas-prices = \"0utia\"/g' /home/celestia/.celestia-app/config/app.toml && \
   sed -i 's/127.0.0.1:26657/0.0.0.0:26657/g' /home/celestia/.celestia-app/config/config.toml && \
   sed -i 's/localhost:9090/0.0.0.0:9090/g' /home/celestia/.celestia-app/config/app.toml && \
   sed -i 's/enable = false/enable = true/g' /home/celestia/.celestia-app/config/app.toml"
   
docker run --rm -v "$CONS_DIR:/home/celestia/.celestia-app" \
  "$APP_IMAGE" genesis gentx "$MONIKER" "$STAKE" \
  --chain-id "$CHAIN_ID" \
  --keyring-backend test \
  --fees 1utia

docker run --rm -v "$CONS_DIR:/home/celestia/.celestia-app" \
  "$APP_IMAGE" genesis collect-gentxs

docker run --rm -v "$CONS_DIR:/home/celestia/.celestia-app" \
  "$APP_IMAGE" genesis validate

echo "✅ GENESIS OK"


# docker exec celestia-light cel-key list \
#   --node.type light \
#   --p2p.network private \
#   --keyring-backend test \


# docker run --rm -it \                                                                              
#   -v "$(pwd)/celes-light3:/home/celestia" \
#   --entrypoint "" \
#   ghcr.io/celestiaorg/celestia-node:v0.28.4-mocha \
#   celestia light init --p2p.network private
