#!/bin/bash
set -euo pipefail

# =============================
# MAX PERFORMANCE Multi-VM Manager
# Optimized for IDX Google / High Performance VMs
# =============================

# Function to display header
display_header() {
    clear
    cat << "EOF"
========================================================================
MAX PERFORMANCE VM Manager
Sponsor By: HOPINGBOYZ, Jishnu, NotGamerPie
========================================================================
EOF
    echo
}

# Function to display colored output
print_status() {
    local type=$1
    local message=$2
    
    case $type in
        "INFO") echo -e "\033[1;34m[INFO]\033[0m $message" ;;
        "WARN") echo -e "\033[1;33m[WARN]\033[0m $message" ;;
        "ERROR") echo -e "\033[1;31m[ERROR]\033[0m $message" ;;
        "SUCCESS") echo -e "\033[1;32m[SUCCESS]\033[0m $message" ;;
        "INPUT") echo -e "\033[1;36m[INPUT]\033[0m $message" ;;
        *) echo "[$type] $message" ;;
    esac
}

# Function to validate input
validate_input() {
    local type=$1
    local value=$2
    
    case $type in
        "number")
            if ! [[ "$value" =~ ^[0-9]+$ ]]; then
                print_status "ERROR" "Must be a number"
                return 1
            fi
            ;;
        "size")
            if ! [[ "$value" =~ ^[0-9]+[GgMm]$ ]]; then
                print_status "ERROR" "Must be a size with unit (e.g., 100G, 512M)"
                return 1
            fi
            ;;
        "port")
            if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 23 ] || [ "$value" -gt 65535 ]; then
                print_status "ERROR" "Must be a valid port number (23-65535)"
                return 1
            fi
            ;;
        "name")
            if ! [[ "$value" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                print_status "ERROR" "VM name can only contain letters, numbers, hyphens, and underscores"
                return 1
            fi
            ;;
        "username")
            if ! [[ "$value" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
                print_status "ERROR" "Username must start with a letter or underscore"
                return 1
            fi
            ;;
    esac
    return 0
}

# Function to check system capabilities
check_system_capabilities() {
    # Check KVM
    if [ -e /dev/kvm ]; then
        KVM_AVAILABLE=true
        print_status "SUCCESS" "KVM acceleration available"
    else
        KVM_AVAILABLE=false
        print_status "WARN" "KVM not available (performance will be slower)"
    fi
    
    # Get CPU info
    CPU_CORES=$(nproc)
    TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
    
    # Check CPU features
    if grep -q avx2 /proc/cpuinfo; then
        CPU_FEATURES="-cpu host,+avx2"
        print_status "SUCCESS" "AVX2 support detected"
    else
        CPU_FEATURES="-cpu host"
    fi
    
    print_status "INFO" "System: $CPU_CORES CPUs, ${TOTAL_MEM}MB RAM"
}

# Function to check dependencies
check_dependencies() {
    local deps=("qemu-system-x86_64" "wget" "cloud-localds" "qemu-img")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_status "ERROR" "Missing dependencies: ${missing_deps[*]}"
        exit 1
    fi
}

# Function to cleanup temporary files
cleanup() {
    rm -f user-data meta-data 2>/dev/null
}

# Function to get all VM configurations
get_vm_list() {
    find "$VM_DIR" -name "*.conf" -exec basename {} .conf \; 2>/dev/null | sort
}

# Function to load VM configuration
load_vm_config() {
    local vm_name=$1
    local config_file="$VM_DIR/$vm_name.conf"
    
    if [[ -f "$config_file" ]]; then
        unset VM_NAME OS_TYPE CODENAME IMG_URL HOSTNAME USERNAME PASSWORD
        unset DISK_SIZE MEMORY CPUS SSH_PORT GUI_MODE PORT_FORWARDS IMG_FILE SEED_FILE CREATED
        unset DISK_CACHE IO_THREADS NETWORK_MODEL
        
        source "$config_file"
        
        # Set performance defaults if not present
        DISK_CACHE="${DISK_CACHE:-writeback}"
        IO_THREADS="${IO_THREADS:-true}"
        NETWORK_MODEL="${NETWORK_MODEL:-virtio-net-pci}"
        
        return 0
    else
        print_status "ERROR" "Configuration for VM '$vm_name' not found"
        return 1
    fi
}

# Function to save VM configuration
save_vm_config() {
    local config_file="$VM_DIR/$VM_NAME.conf"
    
    cat > "$config_file" <<EOF
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
GUI_MODE="$GUI_MODE"
PORT_FORWARDS="$PORT_FORWARDS"
IMG_FILE="$IMG_FILE"
SEED_FILE="$SEED_FILE"
CREATED="$CREATED"
DISK_CACHE="$DISK_CACHE"
IO_THREADS="$IO_THREADS"
NETWORK_MODEL="$NETWORK_MODEL"
EOF
    
    print_status "SUCCESS" "Configuration saved"
}

# Function to create new VM
create_new_vm() {
    print_status "INFO" "Creating new VM (MAX PERFORMANCE)"
    
    # OS Selection
    print_status "INFO" "Select OS:"
    local os_options=()
    local i=1
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
        else
            print_status "ERROR" "Invalid selection"
        fi
    done

    # VM name
    while true; do
        read -p "$(print_status "INPUT" "VM name (default: $DEFAULT_HOSTNAME): ")" VM_NAME
        VM_NAME="${VM_NAME:-$DEFAULT_HOSTNAME}"
        if validate_input "name" "$VM_NAME"; then
            if [[ -f "$VM_DIR/$VM_NAME.conf" ]]; then
                print_status "ERROR" "VM '$VM_NAME' already exists"
            else
                break
            fi
        fi
    done

    # Hostname
    while true; do
        read -p "$(print_status "INPUT" "Hostname (default: $VM_NAME): ")" HOSTNAME
        HOSTNAME="${HOSTNAME:-$VM_NAME}"
        if validate_input "name" "$HOSTNAME"; then
            break
        fi
    done

    # Username
    while true; do
        read -p "$(print_status "INPUT" "Username (default: $DEFAULT_USERNAME): ")" USERNAME
        USERNAME="${USERNAME:-$DEFAULT_USERNAME}"
        if validate_input "username" "$USERNAME"; then
            break
        fi
    done

    # Password
    while true; do
        read -s -p "$(print_status "INPUT" "Password (default: $DEFAULT_PASSWORD): ")" PASSWORD
        PASSWORD="${PASSWORD:-$DEFAULT_PASSWORD}"
        echo
        if [ -n "$PASSWORD" ]; then
            break
        fi
    done

    # MAX PERFORMANCE defaults
    while true; do
        read -p "$(print_status "INPUT" "Disk size (default: 30G): ")" DISK_SIZE
        DISK_SIZE="${DISK_SIZE:-30G}"
        if validate_input "size" "$DISK_SIZE"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Memory MB (default: 4096): ")" MEMORY
        MEMORY="${MEMORY:-4096}"
        if validate_input "number" "$MEMORY"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "CPUs (default: 4, max: $CPU_CORES): ")" CPUS
        CPUS="${CPUS:-4}"
        if validate_input "number" "$CPUS"; then
            [ "$CPUS" -gt "$CPU_CORES" ] && CPUS=$CPU_CORES
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "SSH Port (default: 2222): ")" SSH_PORT
        SSH_PORT="${SSH_PORT:-2222}"
        if validate_input "port" "$SSH_PORT"; then
            if ss -tln 2>/dev/null | grep -q ":$SSH_PORT "; then
                print_status "ERROR" "Port $SSH_PORT already in use"
            else
                break
            fi
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "GUI mode? (y/n, default: n): ")" gui_input
        GUI_MODE=false
        gui_input="${gui_input:-n}"
        if [[ "$gui_input" =~ ^[Yy]$ ]]; then 
            GUI_MODE=true
            break
        elif [[ "$gui_input" =~ ^[Nn]$ ]]; then
            break
        else
            print_status "ERROR" "Answer y or n"
        fi
    done

    read -p "$(print_status "INPUT" "Port forwards (e.g., 3389:3389, press Enter for none): ")" PORT_FORWARDS

    # MAX PERFORMANCE settings (hardcoded)
    DISK_CACHE="writeback"
    IO_THREADS=true
    NETWORK_MODEL="virtio-net-pci"

    IMG_FILE="$VM_DIR/$VM_NAME.img"
    SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"
    CREATED="$(date)"

    setup_vm_image
    save_vm_config
    
    echo ""
    print_status "SUCCESS" "VM created with MAX PERFORMANCE"
    echo "  - CPU: $CPUS cores"
    echo "  - Memory: ${MEMORY}MB"
    echo "  - Disk: $DISK_SIZE (cache=$DISK_CACHE)"
    echo "  - I/O threads: ENABLED"
    echo "  - Network: $NETWORK_MODEL"
    echo "  - GPU: virtio-vga"
}

# Function to setup VM image
setup_vm_image() {
    print_status "INFO" "Preparing image..."
    
    mkdir -p "$VM_DIR"
    
    if [[ -f "$IMG_FILE" ]]; then
        print_status "INFO" "Image exists, skipping download"
    else
        print_status "INFO" "Downloading from $IMG_URL..."
        if ! wget --progress=bar:force "$IMG_URL" -O "$IMG_FILE.tmp"; then
            print_status "ERROR" "Download failed"
            exit 1
        fi
        mv "$IMG_FILE.tmp" "$IMG_FILE"
    fi
    
    qemu-img resize "$IMG_FILE" "$DISK_SIZE" 2>/dev/null || \
    qemu-img create -f qcow2 "$IMG_FILE" "$DISK_SIZE"

    # Cloud-init
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
EOF

    cat > meta-data <<EOF
instance-id: iid-$VM_NAME
local-hostname: $HOSTNAME
EOF

    if ! cloud-localds "$SEED_FILE" user-data meta-data; then
        print_status "ERROR" "Failed to create cloud-init seed"
        exit 1
    fi
    
    print_status "SUCCESS" "VM image ready"
}

# Function to start VM with MAX PERFORMANCE
start_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Starting VM: $vm_name (MAX PERFORMANCE)"
        print_status "INFO" "SSH: ssh -p $SSH_PORT $USERNAME@localhost"
        print_status "INFO" "Password: $PASSWORD"
        
        [[ ! -f "$IMG_FILE" ]] && { print_status "ERROR" "Image not found"; return 1; }
        [[ ! -f "$SEED_FILE" ]] && setup_vm_image
        
        # Build QEMU command with MAX PERFORMANCE
        local qemu_cmd=(qemu-system-x86_64)
        
        # KVM acceleration
        if [ "$KVM_AVAILABLE" = true ]; then
            qemu_cmd+=(-enable-kvm)
        fi
        
        # CPU and memory
        qemu_cmd+=(
            -m "$MEMORY"
            -smp "cpus=$CPUS,cores=$CPUS,threads=1,sockets=1"
            $CPU_FEATURES
        )
        
        # Machine type (Q35 for modern features)
        local machine_opts="q35,hpet=off"
        [ "$KVM_AVAILABLE" = true ] && machine_opts+=",accel=kvm"
        qemu_cmd+=(-machine "$machine_opts")
        
        # Storage with I/O threads (MAX PERFORMANCE)
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
        
        # Port forwards
        if [[ -n "$PORT_FORWARDS" ]]; then
            IFS=',' read -ra forwards <<< "$PORT_FORWARDS"
            for forward in "${forwards[@]}"; do
                IFS=':' read -r host_port guest_port <<< "$forward"
                qemu_cmd+=(",hostfwd=tcp::$host_port-:$guest_port")
            done
        fi
        
        # GPU and display
        if [[ "$GUI_MODE" == true ]]; then
            qemu_cmd+=(-device virtio-vga -display gtk,gl=on)
        else
            qemu_cmd+=(-device virtio-vga -display none -nographic -serial mon:stdio)
        fi
        
        # Performance optimizations
        qemu_cmd+=(
            -object "rng-random,filename=/dev/urandom,id=rng0"
            -device "virtio-rng-pci,rng=rng0"
            -device "virtio-balloon-pci"
            -global "ICH9-LPC.disable_s3=1"
            -global "ICH9-LPC.disable_s4=1"
            -rtc "base=utc,clock=host,driftfix=slew"
        )
        
        print_status "INFO" "Performance Profile:"
        [ "$KVM_AVAILABLE" = true ] && echo "  - KVM: ENABLED"
        echo "  - CPU: $CPUS cores"
        echo "  - Memory: ${MEMORY}MB"
        echo "  - Disk cache: $DISK_CACHE (fastest)"
        [ "$IO_THREADS" = true ] && echo "  - I/O threads: ENABLED"
        echo "  - Network: $NETWORK_MODEL"
        echo "  - GPU: virtio-vga"
        
        print_status "INFO" "Starting QEMU..."
        "${qemu_cmd[@]}"
        
        print_status "INFO" "VM stopped"
    fi
}

# Function to delete VM
delete_vm() {
    local vm_name=$1
    
    print_status "WARN" "Delete VM '$vm_name'?"
    read -p "Confirm (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if load_vm_config "$vm_name"; then
            rm -f "$IMG_FILE" "$SEED_FILE" "$VM_DIR/$vm_name.conf"
            print_status "SUCCESS" "VM deleted"
        fi
    fi
}

# Function to show VM info
show_vm_info() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        echo ""
        print_status "INFO" "VM: $vm_name"
        echo "=========================================="
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
        echo "  GPU: virtio-vga"
        echo ""
        echo "Created: $CREATED"
        echo "=========================================="
        read -p "Press Enter..."
    fi
}

# Function to check if VM is running
is_vm_running() {
    local vm_name=$1
    pgrep -f "qemu-system-x86_64.*$vm_name" >/dev/null
}

# Function to stop VM
stop_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        if is_vm_running "$vm_name"; then
            print_status "INFO" "Stopping VM: $vm_name"
            pkill -f "qemu-system-x86_64.*$IMG_FILE"
            sleep 2
            pkill -9 -f "qemu-system-x86_64.*$IMG_FILE" 2>/dev/null
            print_status "SUCCESS" "VM stopped"
        else
            print_status "INFO" "VM not running"
        fi
    fi
}

# Main menu
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
        echo "  1) Create VM (MAX PERFORMANCE)"
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
            *)
                print_status "ERROR" "Invalid option"
                ;;
        esac
        
        read -p "Press Enter..."
    done
}

# Initialize
trap cleanup EXIT
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

main_menu
