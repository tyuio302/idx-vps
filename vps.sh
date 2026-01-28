#!/bin/bash
set -euo pipefail

# =============================
# MAX PERFORMANCE VM Manager
# virtio-vga-gl MANDATORY for all VMs
# Xorg dummy in VM ONLY (not on host)
# Host needs: QEMU + cloud-init only
# =============================

display_header() {
    clear
    cat << "EOF"
========================================================================
MAX PERFORMANCE VM Manager - virtio-vga-gl DEFAULT
Sponsor By: HOPINGBOYZ, Jishnu, NotGamerPie
========================================================================
EOF
    echo
}

print_status() {
    local type=$1 message=$2
    case $type in
        "INFO") echo -e "\033[1;34m[INFO]\033[0m $message" ;;
        "WARN") echo -e "\033[1;33m[WARN]\033[0m $message" ;;
        "ERROR") echo -e "\033[1;31m[ERROR]\033[0m $message" ;;
        "SUCCESS") echo -e "\033[1;32m[SUCCESS]\033[0m $message" ;;
        "INPUT") echo -e "\033[1;36m[INPUT]\033[0m $message" ;;
    esac
}

validate_input() {
    local type=$1 value=$2
    case $type in
        "number") [[ "$value" =~ ^[0-9]+$ ]] || { print_status "ERROR" "Must be a number"; return 1; } ;;
        "size") [[ "$value" =~ ^[0-9]+[GgMm]$ ]] || { print_status "ERROR" "Must be size (e.g., 100G)"; return 1; } ;;
        "port") [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -ge 23 ] && [ "$value" -le 65535 ] || { print_status "ERROR" "Invalid port (23-65535)"; return 1; } ;;
        "name") [[ "$value" =~ ^[a-zA-Z0-9_-]+$ ]] || { print_status "ERROR" "Invalid name"; return 1; } ;;
        "username") [[ "$value" =~ ^[a-z_][a-z0-9_-]*$ ]] || { print_status "ERROR" "Invalid username"; return 1; } ;;
    esac
}

check_system_capabilities() {
    print_status "INFO" "Checking system capabilities..."
    
    # KVM
    if [ -e /dev/kvm ]; then
        KVM_AVAILABLE=true
        print_status "SUCCESS" "KVM acceleration available"
    else
        KVM_AVAILABLE=false
        print_status "WARN" "KVM not available (slower performance)"
    fi
    
    # CPU
    CPU_CORES=$(nproc)
    TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
    if grep -q avx2 /proc/cpuinfo; then
        CPU_FEATURES="-cpu host,+avx2"
        print_status "SUCCESS" "AVX2 support detected"
    else
        CPU_FEATURES="-cpu host"
    fi
    print_status "INFO" "CPU: $CPU_CORES cores, RAM: ${TOTAL_MEM}MB"
    
    # virtio-vga-gl check
    if qemu-system-x86_64 -device help 2>/dev/null | grep -q "virtio-vga-gl"; then
        print_status "SUCCESS" "virtio-vga-gl available - will be used for ALL VMs"
    else
        print_status "ERROR" "virtio-vga-gl NOT available!"
        print_status "ERROR" "This script requires QEMU with virglrenderer support"
        print_status "INFO" "Make sure dev.nix has: pkgs.qemu (with virgl enabled)"
        exit 1
    fi
    
    print_status "INFO" "Note: Xorg dummy will be auto-installed in VMs (not on host)"
}

check_dependencies() {
    local deps=("qemu-system-x86_64" "wget" "cloud-localds" "qemu-img")
    local missing=()
    for dep in "${deps[@]}"; do
        command -v "$dep" &>/dev/null || missing+=("$dep")
    done
    if [ ${#missing[@]} -ne 0 ]; then
        print_status "ERROR" "Missing dependencies: ${missing[*]}"
        print_status "INFO" "Install via dev.nix: pkgs.qemu, pkgs.cloud-utils, pkgs.wget"
        exit 1
    fi
}

cleanup() {
    rm -f user-data meta-data 2>/dev/null
}

get_vm_list() {
    find "$VM_DIR" -name "*.conf" -exec basename {} .conf \; 2>/dev/null | sort
}

load_vm_config() {
    local config_file="$VM_DIR/$1.conf"
    [[ -f "$config_file" ]] || { print_status "ERROR" "Config not found: $1"; return 1; }
    
    unset VM_NAME OS_TYPE CODENAME IMG_URL HOSTNAME USERNAME PASSWORD
    unset DISK_SIZE MEMORY CPUS SSH_PORT PORT_FORWARDS IMG_FILE SEED_FILE CREATED
    unset DISK_CACHE NETWORK_MODEL IO_THREADS
    
    source "$config_file"
    
    # MAX PERFORMANCE DEFAULTS
    DISK_CACHE="${DISK_CACHE:-writeback}"
    NETWORK_MODEL="${NETWORK_MODEL:-virtio-net-pci}"
    IO_THREADS="${IO_THREADS:-true}"
}

save_vm_config() {
    cat > "$VM_DIR/$VM_NAME.conf" <<EOF
VM_NAME="$VM_NAME"
OS_TYPE="$OS_TYPE"
CODENAME="$CODENAME"
IMG_URL="$IMG_URL"
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
DISK_SIZE="$DISK_SIZE"
MEMORY="$MEMORY"
CPUS="$CPUS"
SSH_PORT="$SSH_PORT"
PORT_FORWARDS="$PORT_FORWARDS"
IMG_FILE="$IMG_FILE"
SEED_FILE="$SEED_FILE"
CREATED="$CREATED"
DISK_CACHE="$DISK_CACHE"
NETWORK_MODEL="$NETWORK_MODEL"
IO_THREADS="$IO_THREADS"
EOF
    print_status "SUCCESS" "Configuration saved"
}

create_new_vm() {
    print_status "INFO" "Creating new VM (virtio-vga-gl + Xorg dummy in VM)"
    
    # OS Selection
    print_status "INFO" "Select OS:"
    local os_options=() i=1
    for os in "${!OS_OPTIONS[@]}"; do
        echo "  $i) $os"
        os_options[$i]="$os"
        ((i++))
    done
    
    while true; do
        read -p "$(print_status "INPUT" "Choice (1-${#OS_OPTIONS[@]}): ")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#OS_OPTIONS[@]} ]; then
            local os="${os_options[$choice]}"
            IFS='|' read -r OS_TYPE CODENAME IMG_URL DEFAULT_HOSTNAME DEFAULT_USERNAME DEFAULT_PASSWORD <<< "${OS_OPTIONS[$os]}"
            break
        fi
    done

    # Basic config
    while true; do
        read -p "$(print_status "INPUT" "VM name (default: $DEFAULT_HOSTNAME): ")" VM_NAME
        VM_NAME="${VM_NAME:-$DEFAULT_HOSTNAME}"
        validate_input "name" "$VM_NAME" && [[ ! -f "$VM_DIR/$VM_NAME.conf" ]] && break
        print_status "ERROR" "VM exists: $VM_NAME"
    done

    read -p "$(print_status "INPUT" "Hostname (default: $VM_NAME): ")" HOSTNAME
    HOSTNAME="${HOSTNAME:-$VM_NAME}"
    
    read -p "$(print_status "INPUT" "Username (default: $DEFAULT_USERNAME): ")" USERNAME
    USERNAME="${USERNAME:-$DEFAULT_USERNAME}"
    
    read -s -p "$(print_status "INPUT" "Password (default: $DEFAULT_PASSWORD): ")" PASSWORD
    PASSWORD="${PASSWORD:-$DEFAULT_PASSWORD}"
    echo

    # Performance config - DEFAULTS TO MAX
    read -p "$(print_status "INPUT" "Disk size (default: 30G): ")" DISK_SIZE
    DISK_SIZE="${DISK_SIZE:-30G}"
    
    read -p "$(print_status "INPUT" "Memory MB (default: 4096): ")" MEMORY
    MEMORY="${MEMORY:-4096}"
    
    read -p "$(print_status "INPUT" "CPUs (default: 4, max: $CPU_CORES): ")" CPUS
    CPUS="${CPUS:-4}"
    [ "$CPUS" -gt "$CPU_CORES" ] && CPUS=$CPU_CORES
    
    read -p "$(print_status "INPUT" "SSH Port (default: 2222): ")" SSH_PORT
    SSH_PORT="${SSH_PORT:-2222}"
    
    read -p "$(print_status "INPUT" "Port forwards (e.g., 8080:80,3389:3389 for RDP): ")" PORT_FORWARDS

    # Performance defaults
    DISK_CACHE="writeback"
    IO_THREADS=true
    NETWORK_MODEL="virtio-net-pci"

    IMG_FILE="$VM_DIR/$VM_NAME.img"
    SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"
    CREATED="$(date)"

    setup_vm_image
    save_vm_config
    
    echo ""
    print_status "SUCCESS" "VM Created with MAX PERFORMANCE"
    echo "  - CPU: $CPUS cores"
    echo "  - Memory: ${MEMORY}MB"
    echo "  - Disk: $DISK_SIZE (cache=$DISK_CACHE)"
    echo "  - I/O threads: ENABLED"
    echo "  - Network: virtio-net-pci"
    echo "  - GPU: virtio-vga-gl (ALWAYS)"
    echo "  - Display: Xorg dummy in VM (for RDP access)"
    echo ""
    print_status "INFO" "To use RDP: SSH in and run: sudo apt install xrdp -y"
}

setup_vm_image() {
    print_status "INFO" "Preparing image..."
    
    mkdir -p "$VM_DIR"
    
    if [[ ! -f "$IMG_FILE" ]]; then
        print_status "INFO" "Downloading from $IMG_URL..."
        wget --progress=bar:force "$IMG_URL" -O "$IMG_FILE.tmp" || {
            print_status "ERROR" "Download failed"
            exit 1
        }
        mv "$IMG_FILE.tmp" "$IMG_FILE"
    fi
    
    qemu-img resize "$IMG_FILE" "$DISK_SIZE" 2>/dev/null || qemu-img create -f qcow2 "$IMG_FILE" "$DISK_SIZE"

    # Cloud-init: Setup Xorg dummy in VM for GPU + RDP
    cat > user-data <<EOF
#cloud-config
hostname: $HOSTNAME
ssh_pwauth: true
disable_root: false
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    password: $(openssl passwd -6 "$PASSWORD" | tr -d '\n')
chpasswd:
  list: |
    root:$PASSWORD
    $USERNAME:$PASSWORD
  expire: false

packages:
  - xserver-xorg-core
  - xserver-xorg-video-dummy
  - x11-xserver-utils
  - mesa-utils
  - glmark2
  - desktop-file-utils

write_files:
  - path: /etc/X11/xorg.conf.d/20-dummy.conf
    content: |
      Section "Device"
          Identifier "dummy_videocard"
          Driver "dummy"
          VideoRam 256000
      EndSection
      
      Section "Monitor"
          Identifier "dummy_monitor"
          HorizSync 30.0-70.0
          VertRefresh 50.0-75.0
      EndSection
      
      Section "Screen"
          Identifier "dummy_screen"
          Device "dummy_videocard"
          Monitor "dummy_monitor"
          DefaultDepth 24
          SubSection "Display"
              Depth 24
              Modes "1920x1080"
          EndSubSection
      EndSection

  - path: /etc/systemd/system/xorg-dummy.service
    content: |
      [Unit]
      Description=Xorg Dummy Display for virtio-vga-gl
      After=network.target
      
      [Service]
      Type=simple
      ExecStart=/usr/bin/Xorg :0 -config /etc/X11/xorg.conf.d/20-dummy.conf
      Restart=always
      Environment="DISPLAY=:0"
      
      [Install]
      WantedBy=multi-user.target
  
  - path: /etc/profile.d/display.sh
    content: |
      export DISPLAY=:0

runcmd:
  - systemctl daemon-reload
  - systemctl enable xorg-dummy
  - systemctl start xorg-dummy
  - echo "export DISPLAY=:0" >> /etc/environment
  - echo "GPU: virtio-vga-gl with Xorg dummy display" > /etc/motd
  - echo "To install RDP: sudo apt install xrdp -y" >> /etc/motd
  - echo "Then connect via RDP to use desktop with GPU acceleration" >> /etc/motd
EOF

    cat > meta-data <<EOF
instance-id: iid-$VM_NAME
local-hostname: $HOSTNAME
EOF

    cloud-localds "$SEED_FILE" user-data meta-data || {
        print_status "ERROR" "Failed to create seed"
        exit 1
    }
    
    print_status "SUCCESS" "VM image ready (Xorg dummy will auto-start in VM)"
}

build_qemu_command() {
    local qemu_cmd=(qemu-system-x86_64)
    
    [ "$KVM_AVAILABLE" = true ] && qemu_cmd+=(-enable-kvm)
    
    qemu_cmd+=(
        -m "$MEMORY"
        -smp "cpus=$CPUS,cores=$CPUS,threads=1,sockets=1"
        $CPU_FEATURES
    )
    
    local machine_opts="q35,hpet=off"
    [ "$KVM_AVAILABLE" = true ] && machine_opts+=",accel=kvm"
    qemu_cmd+=(-machine "$machine_opts")
    
    # Disk with I/O threads
    if [ "$IO_THREADS" = true ]; then
        local aio_mode="threads"
        [ "$DISK_CACHE" = "none" ] && aio_mode="native"
        
        qemu_cmd+=(
            -object "iothread,id=io1"
            -device "virtio-scsi-pci,id=scsi0,iothread=io1"
            -drive "file=$IMG_FILE,if=none,id=drive0,format=qcow2,cache=$DISK_CACHE,aio=$aio_mode"
            -device "scsi-hd,drive=drive0,bus=scsi0.0"
            -drive "file=$SEED_FILE,if=none,id=drive1,format=raw,cache=none,aio=threads"
            -device "scsi-cd,drive=drive1,bus=scsi0.0"
        )
    else
        qemu_cmd+=(
            -drive "file=$IMG_FILE,format=qcow2,if=virtio,cache=$DISK_CACHE,aio=threads"
            -drive "file=$SEED_FILE,format=raw,if=virtio,cache=none"
        )
    fi
    
    qemu_cmd+=(-boot order=c)
    
    # Network
    qemu_cmd+=(
        -device "$NETWORK_MODEL,netdev=n0"
        -netdev "user,id=n0,hostfwd=tcp::$SSH_PORT-:22"
    )
    
    if [[ -n "$PORT_FORWARDS" ]]; then
        IFS=',' read -ra forwards <<< "$PORT_FORWARDS"
        for forward in "${forwards[@]}"; do
            IFS=':' read -r host_port guest_port <<< "$forward"
            qemu_cmd+=(",hostfwd=tcp::$host_port-:$guest_port")
        done
    fi
    
    # GPU - ALWAYS virtio-vga-gl (NO vga std)
    # Using -display none for headless operation (no X server needed on host)
    qemu_cmd+=(
        -device "virtio-vga-gl"
        -display "none"
    )
    
    # Serial console for SSH access (headless)
    qemu_cmd+=(-nographic -serial mon:stdio)
    
    # Performance optimizations
    qemu_cmd+=(
        -object "rng-random,filename=/dev/urandom,id=rng0"
        -device "virtio-rng-pci,rng=rng0"
        -device "virtio-balloon-pci"
        -global "ICH9-LPC.disable_s3=1"
        -global "ICH9-LPC.disable_s4=1"
        -rtc "base=utc,clock=host,driftfix=slew"
    )
    
    echo "${qemu_cmd[@]}"
}

start_vm() {
    local vm_name=$1
    load_vm_config "$vm_name" || return 1
    
    print_status "INFO" "Starting VM: $vm_name"
    print_status "INFO" "SSH: ssh -p $SSH_PORT $USERNAME@localhost"
    print_status "INFO" "Password: $PASSWORD"
    
    [[ ! -f "$IMG_FILE" ]] && { print_status "ERROR" "Image not found"; return 1; }
    [[ ! -f "$SEED_FILE" ]] && setup_vm_image
    
    local qemu_cmd=($(build_qemu_command))
    
    print_status "INFO" "Performance Profile:"
    [ "$KVM_AVAILABLE" = true ] && echo "  - KVM acceleration: ENABLED"
    echo "  - CPU: $CPUS cores"
    echo "  - Memory: ${MEMORY}MB"
    echo "  - Disk cache: $DISK_CACHE"
    [ "$IO_THREADS" = true ] && echo "  - I/O threads: ENABLED"
    echo "  - Network: $NETWORK_MODEL"
    echo "  - GPU: virtio-vga-gl (ALWAYS ENABLED)"
    echo "  - Display: Xorg dummy in VM (no X needed on host)"
    echo ""
    print_status "INFO" "After boot: SSH in and install RDP if needed"
    print_status "INFO" "  sudo apt install xrdp -y"
    print_status "INFO" "  sudo systemctl enable xrdp"
    print_status "INFO" "  sudo systemctl start xrdp"
    
    print_status "INFO" "Starting QEMU..."
    
    "${qemu_cmd[@]}"
    
    print_status "INFO" "VM stopped"
}

stop_vm() {
    load_vm_config "$1" || return 1
    if pgrep -f "qemu-system-x86_64.*$IMG_FILE" >/dev/null; then
        print_status "INFO" "Stopping VM: $1"
        pkill -f "qemu-system-x86_64.*$IMG_FILE"
        sleep 2
        pkill -9 -f "qemu-system-x86_64.*$IMG_FILE" 2>/dev/null
        print_status "SUCCESS" "VM stopped"
    else
        print_status "INFO" "VM not running"
    fi
}

delete_vm() {
    print_status "WARN" "Delete VM '$1'?"
    read -p "Confirm (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        load_vm_config "$1" && {
            rm -f "$IMG_FILE" "$SEED_FILE" "$VM_DIR/$1.conf"
            print_status "SUCCESS" "VM deleted"
        }
    fi
}

show_vm_info() {
    load_vm_config "$1" || return 1
    
    echo ""
    print_status "INFO" "VM: $1"
    echo "========================================"
    echo "OS: $OS_TYPE $CODENAME"
    echo "Hostname: $HOSTNAME"
    echo "User: $USERNAME / Password: $PASSWORD"
    echo "SSH: ssh -p $SSH_PORT $USERNAME@localhost"
    echo ""
    echo "Resources:"
    echo "  Memory: $MEMORY MB"
    echo "  CPUs: $CPUS"
    echo "  Disk: $DISK_SIZE"
    echo "  Port forwards: ${PORT_FORWARDS:-None}"
    echo ""
    echo "Performance:"
    echo "  Disk cache: $DISK_CACHE"
    echo "  I/O threads: $IO_THREADS"
    echo "  Network: $NETWORK_MODEL"
    echo "  GPU: virtio-vga-gl (ALWAYS)"
    echo "  Display: Xorg dummy in VM"
    echo ""
    echo "Created: $CREATED"
    echo "========================================"
    read -p "Press Enter..."
}

is_vm_running() {
    pgrep -f "qemu-system-x86_64.*$1" >/dev/null
}

main_menu() {
    while true; do
        display_header
        
        local vms=($(get_vm_list))
        local vm_count=${#vms[@]}
        
        if [ $vm_count -gt 0 ]; then
            print_status "INFO" "$vm_count VM(s):"
            for i in "${!vms[@]}"; do
                local status="Stopped"
                is_vm_running "${vms[$i]}" && status="Running"
                printf "  %2d) %-20s [%s]\n" $((i+1)) "${vms[$i]}" "$status"
            done
            echo
        fi
        
        echo "Menu:"
        echo "  1) Create VM (virtio-vga-gl + RDP ready)"
        [ $vm_count -gt 0 ] && cat <<EOF
  2) Start VM
  3) Stop VM
  4) VM Info
  5) Delete VM
EOF
        echo "  0) Exit"
        echo
        
        read -p "Choice: " choice
        
        case $choice in
            1) create_new_vm ;;
            2)
                if [ $vm_count -gt 0 ]; then
                    read -p "VM number: " vm_num
                    [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ] && \
                    start_vm "${vms[$((vm_num-1))]}"
                fi
                ;;
            3)
                if [ $vm_count -gt 0 ]; then
                    read -p "VM number: " vm_num
                    [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ] && \
                    stop_vm "${vms[$((vm_num-1))]}"
                fi
                ;;
            4)
                if [ $vm_count -gt 0 ]; then
                    read -p "VM number: " vm_num
                    [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ] && \
                    show_vm_info "${vms[$((vm_num-1))]}"
                fi
                ;;
            5)
                if [ $vm_count -gt 0 ]; then
                    read -p "VM number: " vm_num
                    [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ] && \
                    delete_vm "${vms[$((vm_num-1))]}"
                fi
                ;;
            0)
                print_status "INFO" "Goodbye!"
                exit 0
                ;;
        esac
        
        read -p "Press Enter to continue..."
    done
}

# Trap cleanup
trap cleanup EXIT

# Initialize
check_dependencies
check_system_capabilities

VM_DIR="${VM_DIR:-$HOME/vms}"
mkdir -p "$VM_DIR"

# OS options
declare -A OS_OPTIONS=(
    ["Ubuntu 22.04"]="ubuntu|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu22|ubuntu|ubuntu"
    ["Ubuntu 24.04"]="ubuntu|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu24|ubuntu|ubuntu"
    ["Debian 11"]="debian|bullseye|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2|debian11|debian|debian"
    ["Debian 12"]="debian|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian12|debian|debian"
    ["Fedora 40"]="fedora|40|https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2|fedora40|fedora|fedora"
    ["CentOS Stream 9"]="centos|stream9|https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2|centos9|centos|centos"
    ["AlmaLinux 9"]="almalinux|9|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2|almalinux9|alma|alma"
    ["Rocky Linux 9"]="rockylinux|9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2|rocky9|rocky|rocky"
)

# Start
main_menu
