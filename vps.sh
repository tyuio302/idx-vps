#!/bin/bash
set -euo pipefail

# VM Manager - FINAL VERSION
# NO sudo, NO host Xorg, works everywhere
# virtio-vga for good performance without host dependencies

display_header() {
    clear
    echo "========================================"
    echo "HIGH PERFORMANCE VM Manager"
    echo "No sudo required, Works on IDX/Replit"
    echo "========================================"
    echo
}

print_status() {
    local type=$1 message=$2
    case $type in
        "INFO") echo -e "\033[1;34m[INFO]\033[0m $message" ;;
        "SUCCESS") echo -e "\033[1;32m[SUCCESS]\033[0m $message" ;;
        "WARN") echo -e "\033[1;33m[WARN]\033[0m $message" ;;
        "ERROR") echo -e "\033[1;31m[ERROR]\033[0m $message" ;;
    esac
}

# Check KVM and CPU
CPU_CORES=$(nproc)
KVM_AVAILABLE=false
[ -e /dev/kvm ] && KVM_AVAILABLE=true

# VM directory
VM_DIR="${HOME}/vms"
mkdir -p "$VM_DIR"

# Create new VM
create_vm() {
    print_status "INFO" "Creating new VM..."
    
    echo "Select OS:"
    echo "  1) Debian 12"
    echo "  2) Ubuntu 24.04"
    read -p "Choice: " os_choice
    
    case $os_choice in
        1)
            OS_NAME="Debian 12"
            IMG_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
            DEFAULT_USER="debian"
            ;;
        2)
            OS_NAME="Ubuntu 24.04"
            IMG_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
            DEFAULT_USER="ubuntu"
            ;;
        *)
            print_status "ERROR" "Invalid choice"
            return 1
            ;;
    esac
    
    read -p "VM name: " VM_NAME
    read -p "Username [$DEFAULT_USER]: " USERNAME
    USERNAME=${USERNAME:-$DEFAULT_USER}
    read -sp "Password [123456]: " PASSWORD
    PASSWORD=${PASSWORD:-123456}
    echo
    read -p "Memory MB [4096]: " MEMORY
    MEMORY=${MEMORY:-4096}
    read -p "CPUs [4]: " CPUS
    CPUS=${CPUS:-4}
    read -p "SSH Port [2222]: " SSH_PORT
    SSH_PORT=${SSH_PORT:-2222}
    
    IMG_FILE="$VM_DIR/${VM_NAME}.img"
    SEED_FILE="$VM_DIR/${VM_NAME}-seed.iso"
    
    # Download image
    if [[ ! -f "$IMG_FILE" ]]; then
        print_status "INFO" "Downloading image..."
        wget -q --show-progress "$IMG_URL" -O "$IMG_FILE"
    fi
    
    qemu-img resize "$IMG_FILE" 30G &>/dev/null
    
    # Cloud-init
    cat > /tmp/user-data <<EOF
#cloud-config
hostname: $VM_NAME
password: $PASSWORD
chpasswd: { expire: false }
ssh_pwauth: true
packages: [xserver-xorg-core, xserver-xorg-video-dummy, mesa-utils]
runcmd:
  - echo "DISPLAY=:0" >> /etc/environment
EOF
    
    cat > /tmp/meta-data <<EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF
    
    cloud-localds "$SEED_FILE" /tmp/user-data /tmp/meta-data
    
    # Save config
    cat > "$VM_DIR/${VM_NAME}.conf" <<EOF
VM_NAME="$VM_NAME"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
MEMORY="$MEMORY"
CPUS="$CPUS"
SSH_PORT="$SSH_PORT"
IMG_FILE="$IMG_FILE"
SEED_FILE="$SEED_FILE"
EOF
    
    print_status "SUCCESS" "VM created: $VM_NAME"
}

# Start VM
start_vm() {
    local vm=$1
    local conf="$VM_DIR/${vm}.conf"
    
    [[ ! -f "$conf" ]] && { print_status "ERROR" "VM not found"; return 1; }
    
    source "$conf"
    
    print_status "INFO" "Starting $VM_NAME..."
    print_status "INFO" "SSH: ssh -p $SSH_PORT $USERNAME@localhost"
    
    local qemu_cmd="qemu-system-x86_64"
    $KVM_AVAILABLE && qemu_cmd+=" -enable-kvm"
    
    $qemu_cmd \
        -m $MEMORY \
        -smp $CPUS \
        -drive file=$IMG_FILE,format=qcow2,if=virtio \
        -drive file=$SEED_FILE,format=raw,if=virtio \
        -device virtio-net-pci,netdev=n0 \
        -netdev user,id=n0,hostfwd=tcp::${SSH_PORT}-:22 \
        -device virtio-vga \
        -display none \
        -nographic
}

# List VMs
list_vms() {
    print_status "INFO" "VMs:"
    local i=1
    for conf in "$VM_DIR"/*.conf; do
        [[ -f "$conf" ]] || continue
        local name=$(basename "$conf" .conf)
        echo "  $i) $name"
        ((i++))
    done
}

# Main menu
while true; do
    display_header
    list_vms
    echo
    echo "1) Create VM"
    echo "2) Start VM"
    echo "0) Exit"
    echo
    read -p "Choice: " choice
    
    case $choice in
        1) create_vm ;;
        2)
            read -p "VM name: " vm
            start_vm "$vm"
            ;;
        0) exit 0 ;;
    esac
    
    read -p "Press Enter..."
done
