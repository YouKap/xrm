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
XRAY_ASSETS="/usr/local/share/xray"

# 確保以 Root 權限執行
[[ $EUID -ne 0 ]] && echo -e "${RED}錯誤: 必須以 root 執行！${PLAIN}" && exit 1

# 自我安裝與執行環境校正
if [[ "$0" != "/usr/local/bin/xrm" ]]; then
    echo -e "${BLUE}>>> 正在同步腳本至全域環境...${PLAIN}"
    apt-get update && apt-get install -y curl unzip nano procps
    curl -sSL "$SCRIPT_URL" -o /usr/local/bin/xrm
    chmod +x /usr/local/bin/xrm
    echo -e "${GREEN}>>> 安裝成功！未來可隨時輸入 'xrm' 呼叫面板。${PLAIN}"
    sleep 1
    exec /usr/local/bin/xrm
fi

# ==========================================
# 核心功能模組
# ==========================================

install_update_xray() {
    clear
    echo -e "${BLUE}=== 📦 安裝/更新 Xray-core (含數據文件) ===${PLAIN}"
    echo -e "${YELLOW}正在執行官方安裝程序...${PLAIN}"
    bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)
    echo -e "\n${GREEN}✅ 安裝/更新成功！${PLAIN}"
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
      "tag": "dns-in",
      "port": 5300,
      "listen": "127.0.0.1",
      "protocol": "dokodemo-door",
      "settings": {
        "address": "1.1.1.1",
        "port": 53,
        "network": "udp"
      }
    },
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
      "tag": "dns-out",
      "protocol": "dns"
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
        "inboundTag": ["dns-in"],
        "outboundTag": "dns-out"
      },
      {
        "type": "field",
        "protocol": ["dns"],
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
        "ip": ["geoip:private"],
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

    # 確保 nano 編輯器也能抓到實體鍵盤輸入
    nano "$XRAY_CONF" < /dev/tty
    echo -e "\n${YELLOW}正在檢測設定檔語法...${PLAIN}"
    
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
    fi
    read -rp "按 Enter 鍵返回主選單..." dummy < /dev/tty
}

manage_service() {
    clear
    echo -e "${BLUE}=== ⚡ 3. 服務管理 ===${PLAIN}"
    echo -e " 1. ${GREEN}啟動${PLAIN} | 2. ${RED}停止${PLAIN} | 3. ${YELLOW}重啟${PLAIN} | 0. 返回"
    echo -e "-------------------------------------------------"
    read -rp "請選擇: " s < /dev/tty
    case $s in 
        1) systemctl start xray && echo -e "${GREEN}已啟動${PLAIN}" ;; 
        2) systemctl stop xray && echo -e "${RED}已停止${PLAIN}" ;; 
        3) systemctl restart xray && echo -e "${YELLOW}已重啟${PLAIN}" ;; 
        0) return ;;
        *) echo -e "${RED}無效選擇${PLAIN}" ;;
    esac
    sleep 1
}

show_status() {
    while true; do
        clear
        echo -e "${BLUE}=== 📊 4. 運行狀態監控 ===${PLAIN}"
        
        if systemctl is-active --quiet xray; then
            XRAY_PID=$(pidof xray)
            UPTIME=$(ps -p "$XRAY_PID" -o etime= | tr -d ' ')
            echo -e "狀態: ${GREEN}▶ 執行中${PLAIN} (PID: $XRAY_PID)"
            echo -e "時長: ${GREEN}$UPTIME${PLAIN}"
        else
            echo -e "狀態: ${RED}■ 已停止${PLAIN}"
            echo -e "時長: ${RED}N/A${PLAIN}"
        fi
        
        echo -e "-------------------------------------------------"
        echo -e " 1. 查看系統日誌 (排錯用)"
        echo -e " 0. 返回"
        read -rp "請選擇: " l_choice < /dev/tty
        case $l_choice in
            1) clear; journalctl -u xray -n 30 --no-pager; read -rp "按 Enter 返回..." dummy < /dev/tty ;;
            0) break ;;
        esac
    done
}

uninstall_xray() {
    clear
    echo -e "${RED}=== ⚠️ 解除安裝 Xray ===${PLAIN}"
    read -rp "確定要徹底刪除 Xray 嗎？(y/N): " c < /dev/tty
    if [[ "$c" == "y" || "$c" == "Y" ]]; then
        echo -e "${YELLOW}正在移除 Xray 核心服務...${PLAIN}"
        # 1. 執行官方卸載 (purge 會連帶清理系統服務連結)
        bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) remove --purge
        
        echo -e "${YELLOW}正在清理殘留文件與日誌...${PLAIN}"
        # 2. 強制刪除配置目錄
        rm -rf /usr/local/etc/xray
        # 3. 強制刪除日誌目錄 (這是最常被遺忘的)
        rm -rf /var/log/xray
        # 4. 清理數據文件目錄
        rm -rf /usr/local/share/xray
        
        echo -e "${GREEN}✅ 所有組件已徹底清除！${PLAIN}"
        echo -e "${CYAN}腳本即將退出，'xrm' 指令打開。${PLAIN}"
        sleep 2
        exit 0
    fi
}

while true; do
    clear
    [[ -f "$XRAY_BIN" ]] && STATUS="${GREEN}(已安裝)${PLAIN}" || STATUS="${RED}(未安裝)${PLAIN}"
    echo -e "${BLUE}=================================================${PLAIN}"
    echo -e "  🚀 ${CYAN}Xray 管理面板 (xrm)${PLAIN}  $STATUS"
    echo -e "${BLUE}=================================================${PLAIN}"
    echo -e "${YELLOW} 1.${PLAIN} 安裝/更新" 
    echo -e "${YELLOW} 2.${PLAIN} 編輯設定"
    echo -e "${YELLOW} 3.${PLAIN} 服務管理" 
    echo -e "${YELLOW} 4.${PLAIN} 狀態監控"
    echo -e "${RED} 5.${PLAIN} 徹底卸載"
    echo -e "-------------------------------------------------"
    echo -e "${YELLOW} 0.${PLAIN} 退出"
    
    # 這裡是最關鍵的修復點，確保選單不會因為讀不到輸入而死迴圈
    read -rp "請選擇: " choice < /dev/tty
    
    case $choice in
        1) install_update_xray ;; 
        2) edit_config ;; 
        3) manage_service ;; 
        4) show_status ;; 
        5) uninstall_xray ;; 
        0) clear; exit 0 ;;
    esac
done
