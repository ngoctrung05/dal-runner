#!/bin/bash

# --- CẤU HÌNH ---
NUM_USERS=50         
MIN_BALANCE=1000000 
STOP_FILE="/tmp/celestia_cross_stop"
rm -f "$STOP_FILE"

NODE1_CONTAINER="celestia-validator-astar"
NODE1_VAL_KEY="validator1" 
NODE2_CONTAINER="celestia-validator-astar2"

cleanup() {
    echo -e "\n🛑 Đang dừng..."
    touch "$STOP_FILE"
    pkill -P $$ 
    exit 1
}
trap cleanup SIGINT

# --- GIAI ĐOẠN 1: SETUP ---
echo "🛠️  ĐANG KHỞI TẠO VÀ BƠM TIỀN (CHẾ ĐỘ SMART RETRY)..."

SRC_ADDRS=()
DEST_ADDRS=()

for i in $(seq 1 $NUM_USERS); do
    SRC_NAME="user_src_$i"
    DEST_NAME="user_dest_$i"

    # 1. User Nguồn (Node 1)
    ADDR_1=$(docker exec $NODE1_CONTAINER celestia-appd keys show $SRC_NAME -a --keyring-backend test 2>/dev/null)
    if [ -z "$ADDR_1" ]; then
        ADDR_1=$(docker exec $NODE1_CONTAINER celestia-appd keys add $SRC_NAME --keyring-backend test --output json | jq -r '.address')
    fi
    SRC_ADDRS+=("$ADDR_1")

    # 2. Bơm tiền (CÓ LOGIC THỬ LẠI NẾU LỖI SEQUENCE)
    while true; do
        # Check số dư
        BAL=$(docker exec $NODE1_CONTAINER celestia-appd query bank balances $ADDR_1 --output json | jq -r '.balances[0].amount // "0"')
        
        if [ "$BAL" -ge "$MIN_BALANCE" ]; then
            # Đủ tiền thì qua user tiếp theo
            break 
        fi

        echo "   ⛽ Bơm tiền cho $SRC_NAME (Hiện tại: $BAL)..."
        
        # Gửi tiền và bắt lỗi vào biến OUTPUT
        OUTPUT=$(docker exec $NODE1_CONTAINER celestia-appd tx bank send \
            $NODE1_VAL_KEY $ADDR_1 10000000utia \
            --chain-id private --keyring-backend test \
            --fees 5000utia \
            --gas auto --gas-adjustment 1.5 \
            -y --broadcast-mode sync 2>&1)

        # Kiểm tra lỗi Sequence
        if [[ "$OUTPUT" == *"account sequence mismatch"* ]] || [[ "$OUTPUT" == *"incorrect account sequence"* ]]; then
            echo "      ⚠️  Lệch Sequence! (Node nhanh hơn Script). Đợi 3s rồi thử lại..."
            sleep 3
            continue # Quay lại đầu vòng lặp while để thử lại
        fi

        # Nếu lỗi khác (không phải sequence) -> In ra và dừng để sửa
        if [[ "$OUTPUT" == *"Error"* ]]; then
             echo "      ❌ Lỗi lạ: $OUTPUT"
             # Có thể break hoặc continue tùy bạn, ở đây tôi cho thử lại luôn
             sleep 3
             continue
        fi

        # Nếu thành công
        echo "      ✅ Đã gửi lệnh bơm tiền. TxHash: $(echo "$OUTPUT" | grep 'txhash' | awk '{print $2}')"
        echo "      ...Chờ 6s block confirm..."
        sleep 6
        break # Thoát vòng lặp while
    done

    # 3. User Đích (Node 2)
    ADDR_2=$(docker exec $NODE2_CONTAINER celestia-appd keys show $DEST_NAME -a --keyring-backend test 2>/dev/null)
    if [ -z "$ADDR_2" ]; then
        ADDR_2=$(docker exec $NODE2_CONTAINER celestia-appd keys add $DEST_NAME --keyring-backend test --output json | jq -r '.address')
    fi
    DEST_ADDRS+=("$ADDR_2")
    
    echo "   🆗 Xong cặp $i/$NUM_USERS"
done

echo "⏳ Chờ thêm 5s chốt hạ..."
sleep 5

echo "✅ SETUP XONG! BẮT ĐẦU TẤN CÔNG..."

# --- GIAI ĐOẠN 2: SPAM ---
spam_thread() {
    local id=$1
    local src_key="user_src_$id"
    local dest_addr=${DEST_ADDRS[$((id-1))]}
    
    while [ ! -f "$STOP_FILE" ]; do
        MEMO="cross_${id}_$(date +%N)"
        
        # Gửi từ Node 1 sang Node 2
        OUTPUT=$(docker exec $NODE1_CONTAINER celestia-appd tx bank send \
            $src_key $dest_addr 1utia \
            --from $src_key \
            --chain-id private \
            --fees 1000utia \
            --keyring-backend test \
            --note "$MEMO" \
            -y \
            --broadcast-mode async 2>&1)

        if [[ "$OUTPUT" == *"connection refused"* ]] || [[ "$OUTPUT" == *"EOF"* ]]; then
             echo "🔥 [Thread $id] Node chết!"
             touch "$STOP_FILE"
             break
        fi
    done
}

for i in $(seq 1 $NUM_USERS); do
    spam_thread $i &
done

while [ ! -f "$STOP_FILE" ]; do
    sleep 1
done
cleanup