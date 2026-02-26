#!/usr/bin/env bash
set -e

# --- CẤU HÌNH (Đã khớp với file YAML mới) ---
COMPOSE_FILE="docker-compose.validator.yml"
NODE1_NAME="celestia-validator-astar"
NODE2_NAME="celestia-validator-astar2"
NODE3_NAME="celestia-validator-astar3"
INTERNAL_PORT="26656" # Cổng P2P nội bộ container luôn là 26656

# Màu sắc
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}==================================================${NC}"
echo -e "${YELLOW}🤖 AUTO CONFIG P2P MESH (VALIDATOR CLUSTER)${NC}"
echo -e "${YELLOW}==================================================${NC}"

# 1. KHỞI ĐỘNG CÁC NODE (ĐỂ LẤY ID)
echo -e "${GREEN}1. Đang khởi động các node từ file $COMPOSE_FILE...${NC}"
# Dùng cờ --remove-orphans để dọn dẹp lỗi cổng cũ nếu có
docker compose -f $COMPOSE_FILE up -d --remove-orphans

echo "⏳ Đợi 10s để các node khởi tạo ID..."
sleep 10

# 2. LẤY NODE ID
echo -e "${GREEN}2. Đang lấy Node ID...${NC}"

get_id() {
    local container=$1
    local id=$(docker exec $container celestia-appd tendermint show-node-id 2>/dev/null)
    
    # Kiểm tra nếu ID rỗng (do node chưa chạy kịp hoặc lỗi)
    if [ -z "$id" ]; then
        echo -e "${RED}❌ Lỗi: Không lấy được ID của $container. Hãy kiểm tra log: docker logs $container${NC}"
        exit 1
    fi
    echo $id
}

ID1=$(get_id $NODE1_NAME)
ID2=$(get_id $NODE2_NAME)
ID3=$(get_id $NODE3_NAME)

echo -e "   ✅ Node 1 ($NODE1_NAME): $ID1"
echo -e "   ✅ Node 2 ($NODE2_NAME): $ID2"
echo -e "   ✅ Node 3 ($NODE3_NAME): $ID3"

# 3. TẠO CHUỖI KẾT NỐI (PEER STRING)
# Cấu trúc: ID@TÊN_CONTAINER:26656
# Docker sẽ tự giải quyết TÊN_CONTAINER thành IP trong mạng nội bộ
PEERS_FOR_NODE1="$ID2@$NODE2_NAME:$INTERNAL_PORT,$ID3@$NODE3_NAME:$INTERNAL_PORT"
PEERS_FOR_NODE2="$ID1@$NODE1_NAME:$INTERNAL_PORT,$ID3@$NODE3_NAME:$INTERNAL_PORT"
PEERS_FOR_NODE3="$ID1@$NODE1_NAME:$INTERNAL_PORT,$ID2@$NODE2_NAME:$INTERNAL_PORT"

# 4. TIÊM CONFIG VÀO CONTAINER
echo -e "${GREEN}3. Đang cập nhật config.toml và xóa addrbook cũ...${NC}"

inject_config() {
    local container=$1
    local peers=$2

    echo "   -> Xử lý $container..."
    
    # a. Thay thế dòng persistent_peers trong file config.toml
    # Dùng sed trực tiếp trong container
    docker exec $container sed -i \
        "s|^persistent_peers = .*|persistent_peers = \"$peers\"|g" \
        /home/celestia/.celestia-app/config/config.toml

    # b. Xóa addrbook.json để ép node tìm lại IP mới (Sửa lỗi i/o timeout)
    docker exec $container rm -f /home/celestia/.celestia-app/config/addrbook.json
}

inject_config $NODE1_NAME "$PEERS_FOR_NODE1"
inject_config $NODE2_NAME "$PEERS_FOR_NODE2"
inject_config $NODE3_NAME "$PEERS_FOR_NODE3"

# 5. KHỞI ĐỘNG LẠI ĐỂ ÁP DỤNG
echo -e "${GREEN}4. Đang khởi động lại toàn bộ mạng lưới...${NC}"
docker compose -f $COMPOSE_FILE restart

echo -e "${YELLOW}==================================================${NC}"
echo -e "${GREEN}🎉 CẤU HÌNH HOÀN TẤT! MẠNG LƯỚI ĐÃ THÔNG.${NC}"
echo -e "👉 Node 1 <--> Node 2"
echo -e "👉 Node 2 <--> Node 3"
echo -e "👉 Node 3 <--> Node 1"
echo -e "${YELLOW}==================================================${NC}"