#!/usr/bin/env bash
# ==========================================
#   🚀 SAGAR GAMING 2X - ALL IN ONE TOOL
# ==========================================

set -u

# --- ANSI COLORS ---
C=$'\033[36m'  # Cyan
G=$'\033[32m'  # Green
R=$'\033[31m'  # Red
B=$'\033[34m'  # Blue
Y=$'\033[33m'  # Yellow
W=$'\033[97m'  # White
N=$'\033[0m'   # Reset

# --- HEADER FUNCTION ---
header() {
    clear
    echo -e "${B}  __  __       _         __  __                  ${N}"
    echo -e "${B} |  \/  | __ _(_)_ __   |  \/  | ___ _ __  _   _ ${N}"
    echo -e "${B} | |\/| |/ _\` | | '_ \  | |\/| |/ _ \ '_ \| | | |${N}"
    echo -e "${B} | |  | | (_| | | | | | | |  | |  __/ | | | |_| |${N}"
    echo -e "${B} |_|  |_|\__,_|_|_| |_| |_|  |_|\___|_| |_|\__,_|${N}"
    echo -e "${B}=====================================================${N}"
    echo -e "${Y}      🚀 Subscribe To Sagar Gaming 2X      ${N}"
    echo -e "${B}=====================================================${N}"
    echo ""
}

# --- PAUSE FUNCTION ---
pause() {
    echo ""
    read -p "${W}Press [Enter] to return to menu...${N}" dummy
}

# --- MAIN LOOP ---
while true; do
    header
    echo -e "${C} 1) ${W}Dependency Installer ${G}(Node + Mineflayer)${N}"
    echo -e "${C} 2) ${W}Bot Maker ${G}(Create app.js)${N}"
    echo -e "${C} 3) ${W}Auto Restarter Setup ${G}(Systemd Service)${N}"
    echo -e "${C} 4) ${W}Bot Remover ${G}(Manager)${N}"
    echo -e "${C} 5) ${W}Discord Server Link${N}"
    echo -e "${C} 6) ${W}YouTube Channel Link${N}"
    echo -e "${C} 7) ${W}VM Installer ${G}(IDX VPS)${N}"
    echo -e "${C} 8) ${W}RDP Installer ${G}(Desktop Environment)${N}"
    echo -e "${C} 9) ${W}Tailscale Installer ${G}(VPN)${N}"
    echo -e "${R} 10) Exit${N}"
    echo ""
    echo -e "${B}=====================================================${N}"
    read -p "${Y}👉 Select an option [1-10]: ${N}" choice

    case $choice in
        1)
            echo ""
            echo -e "${Y}🔄 Running Dependency Installer...${N}"
            curl -fsSL https://raw.githubusercontent.com/Sagargamin/INSTALLER-REPO/refs/heads/main/dependency.sh | sed 's/\r$//' | bash
            pause
            ;;
        2)
            echo ""
            echo -e "${Y}🛠️  Running Bot Maker...${N}"
            curl -fsSL https://raw.githubusercontent.com/Sagargamin/INSTALLER-REPO/refs/heads/main/bot_maker.sh | sed 's/\r$//' | bash
            pause
            ;;
        3)
            echo ""
            echo -e "${Y}⚙️  Setting up Auto Restarter...${N}"
            curl -fsSL https://raw.githubusercontent.com/Sagargamin/INSTALLER-REPO/refs/heads/main/autorestarter.sh | sed 's/\r$//' | bash
            pause
            ;;
        4)
            echo ""
            echo -e "${Y}🚀 Bot Remover...${N}"
            curl -fsSL https://raw.githubusercontent.com/Sagargamin/INSTALLER-REPO/refs/heads/main/bot_remover.sh | sed 's/\r$//' | bash
            pause
            ;;
        5)
            echo ""
            echo -e "${B}📢 Join our Discord Server:${N}"
            echo -e "${G}🔗 https://discord.gg/ZAAyrb4J6s${N}"
            echo ""
            pause
            ;;
        6)
            echo ""
            echo -e "${R}📺 Subscribe to YouTube:${N}"
            echo -e "${Y}🔗 https://www.youtube.com/@OfficialNotGamerPie${N}"
            echo ""
            pause
            ;;
        7)
            echo ""
            echo -e "${Y}💻 Installing VM (IDX VPS)...${N}"
            bash <(curl -fsSL https://raw.githubusercontent.com/tyuio302/idx-vps/refs/heads/main/vps.sh)
            pause
            ;;
        8)
            echo ""
            echo -e "${Y}🖥️  Installing RDP...${N}"
            curl -fsSL https://raw.githubusercontent.com/Sagargamin/INSTALLER-REPO/main/rdp_installer.sh | sed 's/\r$//' | bash
            pause
            ;;
        9)
            echo ""
            echo -e "${Y}🌐 Installing Tailscale VPN...${N}"
            curl -fsSL https://tailscale.com/install.sh | sh
            pause
            ;;
        10)
            echo ""
            echo -e "${G}👋 Exiting... Thanks for using!${N}"
            exit 0
            ;;
        *)
            echo ""
            echo -e "${R}❌ Invalid Option! Please select between 1-10.${N}"
            sleep 2
            ;;
    esac
done
EOF
