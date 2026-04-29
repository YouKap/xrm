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
    echo -e "${YELLOW}1. 正在安裝 Xray 核心...${PLAIN}"
    bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)
    
    echo -e "\n${YELLOW}2. 正在下載 Geo 數據文件...${PLAIN}"
    bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) --only-dat-files
    
    mkdir -p "$XRAY_LOG_DIR"
    chown -R nobody:nogroup "$XRAY_LOG_DIR"
    
    echo -e "\n${GREEN}✅ 安裝成功！${PLAIN}"
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
    fi

    nano "$XRAY_CONF" < /dev/tty
    echo -e "\n${YELLOW}正在檢測設定檔語法...${PLAIN}"
    
    # 改用更具相容性的舊式測試指令格式
    TEST_RES=$(XRAY_LOCATION_ASSET=$XRAY_ASSETS "$XRAY_BIN" -test -config "$XRAY_CONF" 2>&1)
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ 語法正確！正在重啟服務...${PLAIN}"
        systemctl restart xray
        sleep 0.5
        systemctl is-active --quiet xray && echo -e "${GREEN}🚀 重啟成功。${PLAIN}"
    else
        echo -e "${RED}❌ 語法檢測失敗！詳細報錯如下：${PLAIN}"
        echo -e "${CYAN}-------------------------------------------------${PLAIN}"
        echo "$TEST_RES"
        echo -e "${CYAN}-------------------------------------------------${PLAIN}"
        echo -e "${YELLOW}提示：若報錯為 'unknown flag -test'，請手動確認 Xray 版本。${PLAIN}"
    fi
    read -rp "按 Enter 鍵返回主選單..." dummy < /dev/tty
}

show_status() {
    while true; do
        clear
        echo -e "${BLUE}=== 📊 5. 查看狀態與日誌 ===${PLAIN}"
        systemctl is-active --quiet xray && echo -e "狀態: ${GREEN}▶ 執行中${PLAIN}" || echo -e "狀態: ${RED}■ 已停止${PLAIN}"
        echo -e "-------------------------------------------------"
        echo -e " 1. 系統服務詳情 | 2. 存取日誌 (20條) | 3. ${YELLOW}實時監控 (Ctrl+C退出)${PLAIN} | 0. 返回"
        read -rp "請選擇: " l_choice < /dev/tty
        case $l_choice in
            1) clear; systemctl status xray --no-pager -l; read -rp "按 Enter..." ;;
            2) clear; tail -n 20 "$XRAY_LOG_DIR/access.log" 2>/dev/null || echo "無日誌"; read -rp "按 Enter..." ;;
            3) clear; tail -f "$XRAY_LOG_DIR/access.log" 2>/dev/null || echo "無日誌"; sleep 1 ;;
            0) break ;;
        esac
    done
}

# (其餘 manage_service, update_geo, uninstall_xray 保持不變)
update_geo() {
    clear; bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) --only-dat-files; read -rp "返回..." dummy < /dev/tty
}

manage_service() {
    clear; echo -e "1.啟動 2.停止 3.重啟"; read -rp "選: " s;
    case $s in 1) systemctl start xray ;; 2) systemctl stop xray ;; 3) systemctl restart xray ;; esac
}

uninstall_xray() {
    clear; read -rp "刪除？(y/N): " c;
    if [[ "$c" == "y" ]]; then
        bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) --remove
        rm -rf /usr/local/etc/xray /var/log/xray
    fi
}

while true; do
    clear
    [[ -f "$XRAY_BIN" ]] && STATUS="${GREEN}(已安裝)${PLAIN}" || STATUS="${RED}(未安裝)${PLAIN}"
    echo -e "${BLUE}=================================================${PLAIN}"
    echo -e "  🚀 ${CYAN}Xray 管理面板 (xrm)${PLAIN}  $STATUS"
    echo -e "${BLUE}=================================================${PLAIN}"
    echo -e "${YELLOW} 1.${PLAIN} 安裝/更新 Xray | ${YELLOW} 2.${PLAIN} 編輯設定"
    echo -e "${YELLOW} 3.${PLAIN} 更新數據文件   | ${YELLOW} 4.${PLAIN} 服務管理"
    echo -e "${YELLOW} 5.${PLAIN} 狀態與即時日誌 | ${RED} 6.${PLAIN} 徹底解除安裝"
    echo -e "-------------------------------------------------"
    echo -e "${YELLOW} 0.${PLAIN} 退出"
    read -rp "請選擇: " choice < /dev/tty
    case $choice in
        1) install_xray ;; 2) edit_config ;; 3) update_geo ;; 4) manage_service ;; 5) show_status ;; 6) uninstall_xray ;; 0) exit 0 ;;
    esac
done
