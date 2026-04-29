#!/bin/bash

# --- 顏色定義 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# --- 全域變數 ---
SCRIPT_URL="https://raw.githubusercontent.com/YouKap/xrm/main/xrm.sh"
XRAY_BIN="/usr/local/bin/xray"
XRAY_CONF="/usr/local/etc/xray/config.json"
XRAY_LOG_DIR="/var/log/xray"
XRAY_ASSETS="/usr/local/share/xray"

# 確保以 Root 權限執行
[[ $EUID -ne 0 ]] && echo -e "${RED}錯誤: 必須以 root 執行！${PLAIN}" && exit 1

# 自我安裝與執行環境校正
if [[ "$0" != "/usr/local/bin/xrm" ]]; then
    echo -e "${BLUE}>>> 正在同步腳本至全域環境...${PLAIN}"
    apt-get update && apt-get install -y curl unzip nano
    curl -sSL "$SCRIPT_URL" -o /usr/local/bin/xrm
    chmod +x /usr/local/bin/xrm
    echo -e "${GREEN}>>> 安裝成功！未來可隨時輸入 'xrm' 呼叫面板。${PLAIN}"
    sleep 1
    exec /usr/local/bin/xrm
fi

# ==========================================
# 核心功能模組
# ==========================================

install_xray() {
    clear
    echo -e "${BLUE}=== 📦 安裝/更新 Xray-core (含數據文件) ===${PLAIN}"
    echo -e "${YELLOW}1. 正在安裝 Xray 核心二進制文件...${PLAIN}"
    bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)
    
    echo -e "\n${YELLOW}2. 正在下載 GeoIP 與 GeoSite 數據文件...${PLAIN}"
    bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) --only-dat-files
    
    echo -e "\n${YELLOW}3. 正在初始化日誌與目錄權限...${PLAIN}"
    mkdir -p "$XRAY_LOG_DIR"
    chown -R nobody:nogroup "$XRAY_LOG_DIR"
    
    echo -e "\n${GREEN}✅ Xray 完整安裝成功！${PLAIN}"
    read -rp "按 Enter 鍵返回..." dummy < /dev/tty
}

edit_config() {
    clear
    echo -e "${BLUE}=== ⚙️ 2. 編輯 Xray 設定檔 ===${PLAIN}"
    if [ ! -f "$XRAY_BIN" ]; then echo -e "${RED}尚未安裝 Xray。${PLAIN}"; sleep 2; return; fi

    if [ ! -f "$XRAY_CONF" ] || [ $(stat -c%s "$XRAY_CONF" 2>/dev/null || echo 0) -lt 10 ]; then
        mkdir -p /usr/local/etc/xray
        cat <<EOF > "$XRAY_CONF"
{
  "log": { "access": "$XRAY_LOG_DIR/access.log", "error": "$XRAY_LOG_DIR/error.log", "loglevel": "warning" },
  "dns": { "servers": ["1.1.1.1", "8.8.8.8"], "queryStrategy": "UseIPv4" },
  "inbounds": [
    {
      "port": 52880, "listen": "127.0.0.1", "protocol": "vless",
      "settings": { "clients": [{ "id": "1cb88fed-057a-40d0-9341-94e53f3c5371" }], "decryption": "none" },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "/2UdBFrva7BrM1zLxT" } },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "block" }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      { "type": "field", "ip": ["geoip:private"], "outboundTag": "direct" },
      { "type": "field", "protocol": ["dns"], "outboundTag": "direct" }
    ]
  }
}
EOF
    fi

    nano "$XRAY_CONF" < /dev/tty
    echo -e "\n${YELLOW}正在檢測設定檔語法...${PLAIN}"
    TEST_RES=$(XRAY_LOCATION_ASSET=$XRAY_ASSETS "$XRAY_BIN" test -c "$XRAY_CONF" 2>&1)
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ 語法正確！正在重啟服務...${PLAIN}"
        systemctl restart xray
        sleep 0.5
        systemctl is-active --quiet xray && echo -e "${GREEN}🚀 重啟成功。${PLAIN}"
    else
        echo -e "${RED}❌ 語法檢測失敗！${PLAIN}\n$TEST_RES"
    fi
    read -rp "按 Enter 鍵返回..." dummy < /dev/tty
}

update_geo() {
    clear
    echo -e "${BLUE}=== 🗺️ 3. 更新 Geo 數據文件 ===${PLAIN}"
    bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) --only-dat-files
    read -rp "按 Enter 鍵返回..." dummy < /dev/tty
}

manage_service() {
    clear
    echo -e "${BLUE}=== 🔄 4. 服務管理 ===${PLAIN}"
    echo -e " 1. 啟動 | 2. 停止 | 3. 重啟 | 4. 開機啟動"
    read -rp "請選擇: " s_choice < /dev/tty
    case $s_choice in
        1) systemctl start xray ;;
        2) systemctl stop xray ;;
        3) systemctl restart xray ;;
        4) systemctl enable xray ;;
    esac
}

show_status() {
    while true; do
        clear
        echo -e "${BLUE}=== 📊 5. 查看狀態與日誌 ===${PLAIN}"
        if systemctl is-active --quiet xray; then
            echo -e "目前狀態: ${GREEN}▶ 執行中 (Running)${PLAIN}"
        else
            echo -e "目前狀態: ${RED}■ 已停止 (Stopped)${PLAIN}"
        fi
        echo -e "-------------------------------------------------"
        echo -e " 1. 查看系統服務詳情 (systemctl status)"
        echo -e " 2. 查看最新存取日誌 (access.log - 最近 20 條)"
        echo -e " 3. ${YELLOW}實時監控存取日誌 (tail -f)${PLAIN}"
        echo -e " 4. 查看錯誤日誌 (error.log)"
        echo -e " 0. 返回主選單"
        echo -e "-------------------------------------------------"
        read -rp "請選擇操作 [0-4]: " log_choice < /dev/tty

        case $log_choice in
            1) clear; systemctl status xray --no-pager -l; read -rp "按 Enter 返回..." ;;
            2) clear; echo -e "${CYAN}最新存取日誌：${PLAIN}"; tail -n 20 "$XRAY_LOG_DIR/access.log" 2>/dev/null || echo "尚無日誌紀錄"; read -rp "按 Enter 返回..." ;;
            3) clear; echo -e "${YELLOW}正在實時監控存取日誌 (按 Ctrl+C 退出監控)...${PLAIN}"; tail -f "$XRAY_LOG_DIR/access.log" 2>/dev/null || echo "尚無日誌紀錄"; sleep 2 ;;
            4) clear; echo -e "${RED}最新錯誤日誌：${PLAIN}"; tail -n 20 "$XRAY_LOG_DIR/error.log" 2>/dev/null || echo "尚無日誌紀錄"; read -rp "按 Enter 返回..." ;;
            0) break ;;
            *) echo "無效選擇"; sleep 1 ;;
        esac
    done
}

uninstall_xray() {
    clear
    read -rp "確定要刪除 Xray 嗎？(y/N): " confirm < /dev/tty
    if [[ "$confirm" == "y" ]]; then
        bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) --remove
        rm -rf /usr/local/etc/xray /var/log/xray
        echo -e "${GREEN}✅ 已解除安裝。${PLAIN}"
    fi
    read -rp "按 Enter 鍵返回..." dummy < /dev/tty
}

# ==========================================
# 主介面循環
# ==========================================
while true; do
    clear
    [[ -f "$XRAY_BIN" ]] && STATUS="${GREEN}(已安裝)${PLAIN}" || STATUS="${RED}(未安裝)${PLAIN}"
    echo -e "${BLUE}=================================================${PLAIN}"
    echo -e "  🚀 ${CYAN}Xray 管理面板 (xrm)${PLAIN}  $STATUS"
    echo -e "${BLUE}=================================================${PLAIN}"
    echo -e "${YELLOW} 1.${PLAIN} 📦 安裝 / 更新 Xray (一鍵到位)"
    echo -e "${YELLOW} 2.${PLAIN} ⚙️ 編輯設定 (自動檢測與重啟)"
    echo -e "${YELLOW} 3.${PLAIN} 🗺️ 手動更新 Geo 數據文件"
    echo -e "-------------------------------------------------"
    echo -e "${YELLOW} 4.${PLAIN} 🔄 服務管理 (啟動/停止/重啟)"
    echo -e "${YELLOW} 5.${PLAIN} 📊 查看狀態與即時日誌"
    echo -e "-------------------------------------------------"
    echo -e "${RED} 6.${PLAIN} 💥 徹底解除安裝"
    echo -e "${YELLOW} 0.${PLAIN} 退出"
    read -rp "請選擇 [0-6]: " choice < /dev/tty
    case $choice in
        1) install_xray ;;
        2) edit_config ;;
        3) update_geo ;;
        4) manage_service ;;
        5) show_status ;;
        6) uninstall_xray ;;
        0) exit 0 ;;
    esac
done
