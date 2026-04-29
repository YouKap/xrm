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

# 確保以 Root 權限執行
[[ $EUID -ne 0 ]] && echo -e "${RED}錯誤: 必須以 root 執行！${PLAIN}" && exit 1

# 自我安裝與執行環境校正 (完美支援 curl | bash)
if [[ "$0" != "/usr/local/bin/xrm" ]]; then
    echo -e "${BLUE}>>> 正在同步腳本至全域環境...${PLAIN}"
    if ! command -v curl &> /dev/null; then
        apt-get update && apt-get install -y curl
    fi
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
    echo -e "${BLUE}=== 📦 1. 安裝/更新 Xray-core ===${PLAIN}"
    echo -e "${YELLOW}正在使用官方腳本進行安裝...${PLAIN}"
    apt-get update && apt-get install -y curl unzip nano
    bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)
    echo -e "\n${GREEN}✅ Xray-core 安裝/更新流程結束！${PLAIN}"
    read -rp "按 Enter 鍵返回..." dummy < /dev/tty
}

edit_config() {
    clear
    echo -e "${BLUE}=== ⚙️ 2. 編輯 Xray 設定檔 (config.json) ===${PLAIN}"
    
    if [ ! -f "$XRAY_BIN" ]; then
        echo -e "${RED}錯誤: 找不到 Xray 核心，請先執行步驟 1。${PLAIN}"
        sleep 2 && return
    fi

    # 檢測檔案是否存在或是否為空
    if [ ! -f "$XRAY_CONF" ] || [ $(stat -c%s "$XRAY_CONF" 2>/dev/null || echo 0) -lt 10 ]; then
        echo -e "${YELLOW}檢測到設定檔為空或不存在，正在寫入預設模板...${PLAIN}"
        mkdir -p /usr/local/etc/xray
        cat <<EOF > "$XRAY_CONF"
{
  "log": {
    "loglevel": "none"
  },
  "dns": {
    "servers": [
      "https://1.1.1.1/dns-query",
      "https://8.8.8.8/dns-query"
    ],
    "queryStrategy": "UseIPv4",
    "tag": "dns-internal"
  },
  "inbounds": [
    {
      "port": 52880,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "1cb88fed-057a-40d0-9341-94e53f3c5371"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/2UdBFrva7BrM1zLxT"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIPv4"
      }
    },
    {
      "tag": "block",
      "protocol": "blackhole",
      "settings": {
        "response": {
          "type": "none"
        }
      }
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "protocol": [
          "dns"
        ],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "port": 443,
        "network": "udp",
        "outboundTag": "block"
      },
      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "network": "tcp,udp",
        "outboundTag": "direct"
      }
    ]
  }
}
EOF
        echo -e "${GREEN}預設模板已載入。${PLAIN}"
    fi

    # 調用編輯器
    echo -e "${CYAN}即將打開 nano 編輯器...${PLAIN}"
    sleep 1
    nano "$XRAY_CONF" < /dev/tty

    # --- 自動檢測與重啟邏輯 ---
    echo -e "\n${YELLOW}正在檢測設定檔語法...${PLAIN}"
    
    # 執行測試並將錯誤日誌存入變數
    TEST_RES=$("$XRAY_BIN" test -c "$XRAY_CONF" 2>&1)
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ 語法檢測通過！正在重啟 Xray 服務...${PLAIN}"
        systemctl restart xray
        sleep 1
        if systemctl is-active --quiet xray; then
            echo -e "${GREEN}🚀 Xray 重啟成功並已在背景運行。${PLAIN}"
        else
            echo -e "${RED}❌ 重啟失敗，請檢查系統日誌。${PLAIN}"
        fi
    else
        echo -e "${RED}❌ 語法檢測失敗！詳細報錯如下：${PLAIN}"
        echo -e "${CYAN}-------------------------------------------------${PLAIN}"
        echo "$TEST_RES"
        echo -e "${CYAN}-------------------------------------------------${PLAIN}"
        echo -e "${YELLOW}提示：剛才的修改未生效，服務仍保持原狀執行。${PLAIN}"
    fi
    
    read -rp "按 Enter 鍵返回主選單..." dummy < /dev/tty
}

update_geo() {
    clear
    echo -e "${BLUE}=== 🗺️ 3. 更新 GeoIP / GeoSite ===${PLAIN}"
    bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) --only-dat-files
    read -rp "按 Enter 鍵返回..." dummy < /dev/tty
}

manage_service() {
    clear
    echo -e "${BLUE}=== 🔄 4. Xray 服務管理 ===${PLAIN}"
    echo -e " 1. 啟動 | 2. 停止 | 3. 重啟 | 4. 開機自啟 | 0. 返回"
    read -rp "請選擇: " srv_choice < /dev/tty
    case $srv_choice in
        1) systemctl start xray ;;
        2) systemctl stop xray ;;
        3) systemctl restart xray ;;
        4) systemctl enable xray ;;
    esac
}

show_status() {
    clear
    echo -e "${BLUE}=== 📊 5. 運行狀態 ===${PLAIN}"
    systemctl is-active --quiet xray && echo -e "狀態: ${GREEN}執行中${PLAIN}" || echo -e "狀態: ${RED}已停止${PLAIN}"
    echo -e "-------------------------------------------------"
    tail -n 10 "${XRAY_LOG_DIR}/access.log" 2>/dev/null || echo "暫無日誌"
    read -rp "按 Enter 鍵返回..." dummy < /dev/tty
}

uninstall_xray() {
    clear
    echo -e "${RED}⚠️  確定要徹底解除安裝 Xray 嗎？ (y/N)${PLAIN}"
    read -rp "請輸入: " confirm < /dev/tty
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) --remove
        rm -rf /usr/local/etc/xray
        rm -rf /var/log/xray
        echo -e "${GREEN}✅ 已徹底移除。${PLAIN}"
    fi
    read -rp "按 Enter 鍵返回..." dummy < /dev/tty
}

while true; do
    clear
    [[ -f "$XRAY_BIN" ]] && STATUS_INST="${GREEN}(已安裝)${PLAIN}" || STATUS_INST="${RED}(未安裝)${PLAIN}"
    echo -e "${BLUE}=================================================${PLAIN}"
    echo -e "  🚀 ${CYAN}Xray-core 管理面板 (xrm)${PLAIN}"
    echo -e "  指令: xrm  |  核心: $STATUS_INST"
    echo -e "${BLUE}=================================================${PLAIN}"
    echo -e "${YELLOW} 1.${PLAIN} 安裝/更新 Xray"
    echo -e "${YELLOW} 2.${PLAIN} 編輯設定 (自動載入模板)"
    echo -e "${YELLOW} 3.${PLAIN} 更新 Geo 資料庫"
    echo -e "-------------------------------------------------"
    echo -e "${YELLOW} 4.${PLAIN} 服務管理 (啟動/停止/重啟)"
    echo -e "${YELLOW} 5.${PLAIN} 查看狀態與日誌"
    echo -e "-------------------------------------------------"
    echo -e "${RED} 6.${PLAIN} 徹底解除安裝"
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
