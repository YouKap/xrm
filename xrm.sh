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
    # 確保 curl 已安裝
    if ! command -v curl &> /dev/null; then
        apt-get update && apt-get install -y curl
    fi
    # 從 GitHub 下載最新版本到系統目錄
    curl -sSL "$SCRIPT_URL" -o /usr/local/bin/xrm
    chmod +x /usr/local/bin/xrm
    echo -e "${GREEN}>>> 安裝成功！未來可隨時輸入 'xrm' 呼叫面板。${PLAIN}"
    sleep 1
    # 轉交控制權給全域腳本，正式啟動面板
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
        echo -e "${RED}錯誤: 找不到 Xray 核心，請先執行步驟 1 進行安裝。${PLAIN}"
        sleep 2 && return
    fi

    if [ ! -f "$XRAY_CONF" ]; then
        echo -e "${YELLOW}找不到設定檔，正在建立預設模板...${PLAIN}"
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
        echo -e "${GREEN}預設模板已寫入。${PLAIN}"
    fi

    echo -e "${CYAN}即將打開 nano 編輯器，您可以檢視或修改設定...${PLAIN}"
    echo -e "${YELLOW}提示: 編輯完成後請按 Ctrl+O 存檔，Enter 確認，Ctrl+X 離開。${PLAIN}"
    sleep 2
    nano "$XRAY_CONF" < /dev/tty
    
    echo -e "\n${GREEN}✅ 設定檔編輯完畢！建議執行步驟 4 重啟服務套用設定。${PLAIN}"
    read -rp "按 Enter 鍵返回主選單..." dummy < /dev/tty
}

update_geo() {
    clear
    echo -e "${BLUE}=== 🗺️ 3. 更新 GeoIP / GeoSite 規則檔 ===${PLAIN}"
    
    if [ ! -f "$XRAY_BIN" ]; then
        echo -e "${RED}錯誤: 尚未安裝 Xray。${PLAIN}"
        sleep 2 && return
    fi

    echo -e "${YELLOW}正在透過官方腳本更新 dat 檔案...${PLAIN}"
    bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) --only-dat-files
    
    echo -e "\n${GREEN}✅ 路由規則資料庫更新完成！${PLAIN}"
    read -rp "按 Enter 鍵返回主選單..." dummy < /dev/tty
}

manage_service() {
    clear
    echo -e "${BLUE}=== 🔄 4. Xray 服務管理 ===${PLAIN}"
    echo -e " 1. 啟動 Xray (Start)"
    echo -e " 2. 停止 Xray (Stop)"
    echo -e " 3. 重啟 Xray (Restart) - ${CYAN}修改設定後必做${PLAIN}"
    echo -e " 4. 設定開機自啟 (Enable)"
    echo -e " 0. 返回主選單"
    read -rp "請選擇操作 [0-4]: " srv_choice < /dev/tty
    
    case $srv_choice in
        1) systemctl start xray && echo -e "${GREEN}已啟動 Xray。${PLAIN}" ;;
        2) systemctl stop xray && echo -e "${YELLOW}已停止 Xray。${PLAIN}" ;;
        3) systemctl restart xray && echo -e "${GREEN}已重啟 Xray，新設定已套用。${PLAIN}" ;;
        4) systemctl enable xray && echo -e "${GREEN}已設定 Xray 開機自動啟動。${PLAIN}" ;;
        0) return ;;
        *) echo -e "${RED}無效選擇${PLAIN}" ;;
    esac
    
    read -rp "按 Enter 鍵返回..." dummy < /dev/tty
}

show_status() {
    clear
    echo -e "${BLUE}=== 📊 5. 運行狀態與日誌 ===${PLAIN}"
    
    if systemctl is-active --quiet xray; then
        echo -e "Xray 狀態: ${GREEN}執行中 (Running)${PLAIN}"
    else
        echo -e "Xray 狀態: ${RED}已停止 (Stopped)${PLAIN}"
    fi
    echo -e "-------------------------------------------------"
    
    echo -e "${YELLOW}最新系統服務狀態 (systemctl status):${PLAIN}"
    systemctl status xray --no-pager -l | head -n 10
    
    echo -e "-------------------------------------------------"
    echo -e "${YELLOW}最新存取日誌 (access.log):${PLAIN}"
    tail -n 10 "${XRAY_LOG_DIR}/access.log" 2>/dev/null || echo "無日誌或檔案不存在"
    
    echo -e "-------------------------------------------------"
    echo -e "${RED}最新錯誤日誌 (error.log):${PLAIN}"
    tail -n 10 "${XRAY_LOG_DIR}/error.log" 2>/dev/null || echo "無日誌或檔案不存在"
    
    echo -e "-------------------------------------------------"
    read -rp "按 Enter 鍵返回..." dummy < /dev/tty
}

uninstall_xray() {
    clear
    echo -e "${RED}=================================================${PLAIN}"
    echo -e "      ⚠️  警告：徹底解除安裝 Xray-core"
    echo -e "${RED}=================================================${PLAIN}"
    echo -e "這將會："
    echo -e " 1. 停止 Xray 服務並移除二進制檔案"
    echo -e " 2. 刪除所有設定檔與日誌 (/usr/local/etc/xray 等)\n"
    
    read -rp "您確定要解除安裝嗎？請輸入 'y' 確認: " confirm < /dev/tty
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        # 1. 執行官方卸載
        bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) --remove
        
        # 2. 【新增】強制刪除殘留的配置目錄與日誌目錄，確保下次安裝是「全新」的
        rm -rf /usr/local/etc/xray
        rm -rf /var/log/xray
        
        echo -e "\n${GREEN}✅ Xray 已從此伺服器徹底移除（含配置檔）！${PLAIN}"
        echo -e "${YELLOW}註：此管理面板 (xrm) 仍保留，若要刪除請執行: rm -f /usr/local/bin/xrm${PLAIN}"
    else
        echo -e "\n${BLUE}已取消操作。${PLAIN}"
    fi
    read -rp "按 Enter 鍵返回主選單..." dummy < /dev/tty
}

# ==========================================
# 主介面循環
# ==========================================
while true; do
    clear
    [[ -f "$XRAY_BIN" ]] && ICON1="${GREEN}(已安裝)${PLAIN}" || ICON1="${RED}(未安裝)${PLAIN}"
    [[ -f "$XRAY_CONF" ]] && ICON2="${GREEN}(已配置)${PLAIN}" || ICON2=""
    
    if systemctl is-active --quiet xray; then
        ICON_STATUS="${GREEN}▶ 執行中${PLAIN}"
    else
        ICON_STATUS="${RED}■ 已停止${PLAIN}"
    fi
    
    echo -e "${BLUE}=================================================${PLAIN}"
    echo -e "  🚀 ${CYAN}Xray-core 部署與管理面板${PLAIN}"
    echo -e "      快捷指令: xrm  |  狀態: $ICON_STATUS"
    echo -e "${BLUE}=================================================${PLAIN}"
    echo -e "${YELLOW} 1.${PLAIN} 📦 安裝 / 更新 Xray-core $ICON1"
    echo -e "${YELLOW} 2.${PLAIN} ⚙️ 編輯 Xray 設定檔 (config.json) $ICON2"
    echo -e "${YELLOW} 3.${PLAIN} 🗺️ 更新 GeoIP & GeoSite 規則檔"
    echo -e "-------------------------------------------------"
    echo -e "${YELLOW} 4.${PLAIN} 🔄 Xray 服務管理 (啟動/停止/重啟)"
    echo -e "${YELLOW} 5.${PLAIN} 📊 查看運行狀態與即時日誌"
    echo -e "-------------------------------------------------"
    echo -e "${RED} 6.${PLAIN} 💥 徹底解除安裝 Xray-core"
    echo -e "-------------------------------------------------"
    echo -e "${YELLOW} 0.${PLAIN} 退出腳本"
    echo -e "${BLUE}=================================================${PLAIN}"
    
    read -rp "請選擇數字 [0-6]: " choice < /dev/tty
    [[ -z "$choice" ]] && continue

    case $choice in
        1) install_xray ;;
        2) edit_config ;;
        3) update_geo ;;
        4) manage_service ;;
        5) show_status ;;
        6) uninstall_xray ;;
        0) clear; exit 0 ;;
        *) echo -e "${RED}無效選擇${PLAIN}"; sleep 1 ;;
    esac
done
