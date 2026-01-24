#!/bin/bash
set -euo pipefail

# =============================
# Enhanced Multi-VM Manager with Performance Optimizations
# NO APT/DPKG - Pure Nix packages
# =============================

# Function to display header
display_header() {
    clear
    cat << "EOF"
========================================================================
Sponsor By These Guys!                                                                  
HOPINGBOYZ
Jishnu
NotGamerPie
========================================================================
🚀 OPTIMIZED VERSION - High Performance VM Manager
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
    print_status "INFO" "Checking system capabilities..."
    
    # Check KVM support
    if [ -e /dev/kvm ]; then
        print_status "SUCCESS" "KVM acceleration available"
        KVM_AVAILABLE=true
    else
        print_status "WARN" "KVM not available, VMs will run slower"
        KVM_AVAILABLE=false
    fi
    
    # Check CPU capabilities
    CPU_CORES=$(nproc)
    print_status "INFO" "CPU cores: $CPU_CORES"
    
    # Check for AVX2 support
    if grep -q avx2 /proc/cpuinfo; then
        print_status "SUCCESS" "AVX2 support detected"
        CPU_FEATURES="-cpu host,+avx2"
    else
        CPU_FEATURES="-cpu host"
    fi
    
    # Check available memory
    TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
    print_status "INFO" "Total memory: ${TOTAL_MEM}MB"
    
    # Check virtio-gpu support
    if qemu-system-x86_64 -device help 2>/dev/null | grep -q "virtio-vga-gl"; then
        print_status "SUCCESS" "virtio-gpu with virgl available"
        VIRGL_AVAILABLE=true
    else
        print_status "WARN" "virtio-gpu-gl not available"
        VIRGL_AVAILABLE=false
    fi
    
    # Check Xorg availability
    if command -v Xorg &> /dev/null; then
        print_status "SUCCESS" "Xorg server available"
        XORG_AVAILABLE=true
    else
        if [ "$VIRGL_AVAILABLE" = true ]; then
            print_status "WARN" "Xorg not found - add to dev.nix"
        fi
        XORG_AVAILABLE=false
    fi
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
        print_status "ERROR" "Missing: ${missing_deps[*]}"
        print_status "INFO" "Add to dev.nix packages"
        exit 1
    fi
}

# Function to cleanup temporary files
cleanup() {
    if [ -f "user-data" ]; then rm -f "user-data"; fi
    if [ -f "meta-data" ]; then rm -f "meta-data"; fi
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
        unset DISK_SIZE MEMORY CPUS SSH_PORT PORT_FORWARDS IMG_FILE SEED_FILE CREATED
        unset ENABLE_VIRTIO_GPU DISK_CACHE NETWORK_MODEL IO_THREADS
        
        source "$config_file"
        
        ENABLE_VIRTIO_GPU="${ENABLE_VIRTIO_GPU:-false}"
        DISK_CACHE="${DISK_CACHE:-writeback}"
        NETWORK_MODEL="${NETWORK_MODEL:-virtio-net-pci}"
        IO_THREADS="${IO_THREADS:-true}"
        
        return 0
    else
        print_status "ERROR" "Config not found: $vm_name"
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
PORT_FORWARDS="$PORT_FORWARDS"
IMG_FILE="$IMG_FILE"
SEED_FILE="$SEED_FILE"
CREATED="$CREATED"
ENABLE_VIRTIO_GPU="$ENABLE_VIRTIO_GPU"
DISK_CACHE="$DISK_CACHE"
NETWORK_MODEL="$NETWORK_MODEL"
IO_THREADS="$IO_THREADS"
EOF
    
    print_status "SUCCESS" "Configuration saved"
}

# Function to setup Xorg dummy
setup_xorg_dummy() {
    print_status "INFO" "Setting up Xorg dummy..."
    
    local xorg_conf="/tmp/xorg-dummy-${VM_NAME}.conf"
    cat > "$xorg_conf" << 'EOF'
Section "ServerLayout"
    Identifier "dummy_layout"
    Screen 0 "dummy_screen"
    InputDevice "dummy_mouse"
    InputDevice "dummy_keyboard"
EndSection

Section "Device"
    Identifier "dummy_videocard"
    Driver "dummy"
    VideoRam 256000
EndSection

Section "Screen"
    Identifier "dummy_screen"
    Device "dummy_videocard"
    Monitor "dummy_monitor"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "1920x1080" "1600x900" "1280x720"
        Virtual 1920 1080
    EndSubSection
EndSection

Section "Monitor"
    Identifier "dummy_monitor"
    HorizSync 15.0-100.0
    VertRefresh 15.0-200.0
    Modeline "1920x1080" 148.50 1920 2008 2052 2200 1080 1084 1089 1125 +hsync +vsync
EndSection

Section "InputDevice"
    Identifier "dummy_mouse"
    Driver "void"
EndSection

Section "InputDevice"
    Identifier "dummy_keyboard"
    Driver "void"
EndSection
EOF
    
    # Find free display
    local display_num=10
    while [ -f "/tmp/.X${display_num}-lock" ]; do
        ((display_num++))
    done
    
    print_status "INFO" "Starting Xorg :$display_num..."
    Xorg :$display_num -config "$xorg_conf" &> "/tmp/xorg-${VM_NAME}.log" &
    local xorg_pid=$!
    
    sleep 2
    
    if ps -p $xorg_pid > /dev/null 2>&1; then
        print_status "SUCCESS" "Xorg started (PID: $xorg_pid)"
        echo "$xorg_pid" > "/tmp/xorg-${VM_NAME}.pid"
        echo ":$display_num"
        return 0
    else
        print_status "ERROR" "Xorg failed to start"
        [ -f "/tmp/xorg-${VM_NAME}.log" ] && cat "/tmp/xorg-${VM_NAME}.log"
        return 1
    fi
}

# Function to stop Xorg dummy
stop_xorg_dummy() {
    local xorg_pid_file="/tmp/xorg-${VM_NAME}.pid"
    if [ -f "$xorg_pid_file" ]; then
        local xorg_pid=$(cat "$xorg_pid_file")
        if ps -p $xorg_pid > /dev/null 2>&1; then
            print_status "INFO" "Stopping Xorg (PID: $xorg_pid)"
            kill $xorg_pid 2>/dev/null
            rm -f "$xorg_pid_file"
        fi
    fi
    rm -f "/tmp/xorg-dummy-${VM_NAME}.conf"
    rm -f "/tmp/xorg-${VM_NAME}.log"
}

# Function to create new VM
create_new_vm() {
    print_status "INFO" "Creating new VM"
    
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
        fi
    done

    # VM name
    while true; do
        read -p "$(print_status "INPUT" "VM name (default: $DEFAULT_HOSTNAME): ")" VM_NAME
        VM_NAME="${VM_NAME:-$DEFAULT_HOSTNAME}"
        if validate_input "name" "$VM_NAME"; then
            if [[ -f "$VM_DIR/$VM_NAME.conf" ]]; then
                print_status "ERROR" "VM exists: $VM_NAME"
            else
                break
            fi
        fi
    done

    # Hostname
    while true; do
        read -p "$(print_status "INPUT" "Hostname (default: $VM_NAME): ")" HOSTNAME
        HOSTNAME="${HOSTNAME:-$VM_NAME}"
        validate_input "name" "$HOSTNAME" && break
    done

    # Username
    while true; do
        read -p "$(print_status "INPUT" "Username (default: $DEFAULT_USERNAME): ")" USERNAME
        USERNAME="${USERNAME:-$DEFAULT_USERNAME}"
        validate_input "username" "$USERNAME" && break
    done

    # Password
    while true; do
        read -s -p "$(print_status "INPUT" "Password (default: $DEFAULT_PASSWORD): ")" PASSWORD
        PASSWORD="${PASSWORD:-$DEFAULT_PASSWORD}"
        echo
        [ -n "$PASSWORD" ] && break
    done

    # Disk size
    while true; do
        read -p "$(print_status "INPUT" "Disk size (default: 20G): ")" DISK_SIZE
        DISK_SIZE="${DISK_SIZE:-20G}"
        validate_input "size" "$DISK_SIZE" && break
    done

    # Memory
    while true; do
        read -p "$(print_status "INPUT" "Memory MB (default: 2048): ")" MEMORY
        MEMORY="${MEMORY:-2048}"
        if validate_input "number" "$MEMORY"; then
            if [ "$MEMORY" -gt "$TOTAL_MEM" ]; then
                print_status "WARN" "Exceeds available: $TOTAL_MEM MB"
                read -p "Continue? (y/N): " confirm
                [[ "$confirm" =~ ^[Yy]$ ]] && break
            else
                break
            fi
        fi
    done

    # CPUs
    while true; do
        read -p "$(print_status "INPUT" "CPUs (default: 2, max: $CPU_CORES): ")" CPUS
        CPUS="${CPUS:-2}"
        if validate_input "number" "$CPUS"; then
            if [ "$CPUS" -gt "$CPU_CORES" ]; then
                print_status "WARN" "Exceeds available: $CPU_CORES"
                read -p "Continue? (y/N): " confirm
                [[ "$confirm" =~ ^[Yy]$ ]] && break
            else
                break
            fi
        fi
    done

    # SSH Port
    while true; do
        read -p "$(print_status "INPUT" "SSH Port (default: 2222): ")" SSH_PORT
        SSH_PORT="${SSH_PORT:-2222}"
        if validate_input "port" "$SSH_PORT"; then
            if ss -tln 2>/dev/null | grep -q ":$SSH_PORT "; then
                print_status "ERROR" "Port in use: $SSH_PORT"
            else
                break
            fi
        fi
    done

    # GPU acceleration
    if [ "$VIRGL_AVAILABLE" = true ] && [ "$XORG_AVAILABLE" = true ]; then
        while true; do
            read -p "$(print_status "INPUT" "Enable GPU (virtio-gpu)? (y/n): ")" gpu_input
            gpu_input="${gpu_input:-n}"
            if [[ "$gpu_input" =~ ^[Yy]$ ]]; then
                ENABLE_VIRTIO_GPU=true
                print_status "SUCCESS" "GPU enabled (virgl 3D)"
                break
            elif [[ "$gpu_input" =~ ^[Nn]$ ]]; then
                ENABLE_VIRTIO_GPU=false
                break
            fi
        done
    else
        ENABLE_VIRTIO_GPU=false
        [ "$VIRGL_AVAILABLE" = false ] && print_status "INFO" "virtio-gpu not available"
        [ "$XORG_AVAILABLE" = false ] && print_status "INFO" "Xorg not available"
    fi

    # Performance options
    echo ""
    print_status "INFO" "⚡ Performance Options"
    
    echo "Disk cache:"
    echo "  1) writeback (fastest)"
    echo "  2) writethrough (balanced)"
    echo "  3) none (safest)"
    while true; do
        read -p "Choice (1-3, default: 1): " cache_choice
        cache_choice="${cache_choice:-1}"
        case $cache_choice in
            1) DISK_CACHE="writeback"; break ;;
            2) DISK_CACHE="writethrough"; break ;;
            3) DISK_CACHE="none"; break ;;
        esac
    done
    
    while true; do
        read -p "Enable I/O threads? (y/n, default: y): " io_input
        io_input="${io_input:-y}"
        if [[ "$io_input" =~ ^[Yy]$ ]]; then
            IO_THREADS=true
            break
        elif [[ "$io_input" =~ ^[Nn]$ ]]; then
            IO_THREADS=false
            break
        fi
    done
    
    NETWORK_MODEL="virtio-net-pci"
    
    read -p "$(print_status "INPUT" "Port forwards (e.g., 8080:80): ")" PORT_FORWARDS

    IMG_FILE="$VM_DIR/$VM_NAME.img"
    SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"
    CREATED="$(date)"

    setup_vm_image
    save_vm_config
    
    echo ""
    print_status "SUCCESS" "⚡ VM Created"
    echo "  • CPU: $CPUS cores"
    echo "  • Memory: ${MEMORY}MB"
    echo "  • Disk: $DISK_SIZE ($DISK_CACHE)"
    echo "  • I/O threads: $IO_THREADS"
    [ "$ENABLE_VIRTIO_GPU" = true ] && echo "  • GPU: virtio-gpu (virgl)"
}

# Function to setup VM image
setup_vm_image() {
    print_status "INFO" "Preparing image..."
    
    mkdir -p "$VM_DIR"
    
    if [[ -f "$IMG_FILE" ]]; then
        print_status "INFO" "Image exists, skipping download"
    else
        print_status "INFO" "Downloading from $IMG_URL..."
        wget --progress=bar:force "$IMG_URL" -O "$IMG_FILE.tmp" || {
            print_status "ERROR" "Download failed"
            exit 1
        }
        mv "$IMG_FILE.tmp" "$IMG_FILE"
    fi
    
    qemu-img resize "$IMG_FILE" "$DISK_SIZE" 2>/dev/null || {
        rm -f "$IMG_FILE"
        qemu-img create -f qcow2 "$IMG_FILE" "$DISK_SIZE"
    }

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

    cloud-localds "$SEED_FILE" user-data meta-data || {
        print_status "ERROR" "Failed to create seed"
        exit 1
    }
    
    print_status "SUCCESS" "VM image ready"
}

# Function to build QEMU command
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
    
    # Disk
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
        local aio_mode="threads"
        [ "$DISK_CACHE" = "none" ] && aio_mode="native"
        
        qemu_cmd+=(
            -drive "file=$IMG_FILE,format=qcow2,if=virtio,cache=$DISK_CACHE,aio=$aio_mode"
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
    
    # Display
    if [ "$ENABLE_VIRTIO_GPU" = true ] && [ "$VIRGL_AVAILABLE" = true ]; then
        qemu_cmd+=(
            -device "virtio-vga-gl"
            -display "sdl,gl=on"
            -device "qemu-xhci,id=xhci"
            -device "usb-tablet,bus=xhci.0"
        )
    fi
    
    qemu_cmd+=(-nographic -serial mon:stdio)
    
    # Performance
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

# Function to start VM
start_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Starting VM: $vm_name"
        print_status "INFO" "SSH: ssh -p $SSH_PORT $USERNAME@localhost"
        print_status "INFO" "Password: $PASSWORD"
        
        [[ ! -f "$IMG_FILE" ]] && { print_status "ERROR" "Image not found"; return 1; }
        [[ ! -f "$SEED_FILE" ]] && { print_status "WARN" "Recreating seed..."; setup_vm_image; }
        
        # Setup Xorg if GPU enabled
        local xorg_display=""
        if [ "$ENABLE_VIRTIO_GPU" = true ] && [ "$VIRGL_AVAILABLE" = true ]; then
            if ! command -v Xorg &> /dev/null; then
                print_status "WARN" "Xorg not found, GPU disabled"
                ENABLE_VIRTIO_GPU=false
            elif [ -z "${DISPLAY:-}" ]; then
                print_status "INFO" "🎮 Setting up Xorg dummy..."
                xorg_display=$(setup_xorg_dummy)
                if [ $? -eq 0 ]; then
                    export DISPLAY="$xorg_display"
                    print_status "SUCCESS" "Xorg ready: $DISPLAY"
                else
                    print_status "WARN" "Xorg failed, GPU disabled"
                    ENABLE_VIRTIO_GPU=false
                fi
            else
                print_status "INFO" "Using DISPLAY: $DISPLAY"
            fi
        fi
        
        local qemu_cmd=($(build_qemu_command))
        
        print_status "INFO" "⚡ Performance:"
        [ "$KVM_AVAILABLE" = true ] && echo "  ✓ KVM"
        echo "  ✓ CPU: $CPUS cores"
        echo "  ✓ Disk: $DISK_CACHE"
        [ "$IO_THREADS" = true ] && echo "  ✓ I/O threads"
        echo "  ✓ Network: $NETWORK_MODEL"
        if [ "$ENABLE_VIRTIO_GPU" = true ]; then
            echo "  ✓ GPU: virtio-gpu (virgl)"
            [ -n "$xorg_display" ] && echo "  ✓ Xorg: $xorg_display"
        fi
        
        print_status "INFO" "Starting QEMU..."
        
        [ -n "$xorg_display" ] && trap "stop_xorg_dummy" EXIT INT TERM
        
        "${qemu_cmd[@]}"
        
        [ -n "$xorg_display" ] && stop_xorg_dummy
        
        print_status "INFO" "VM stopped"
    fi
}

# Function to stop VM
stop_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        if is_vm_running "$vm_name"; then
            print_status "INFO" "Stopping VM: $vm_name"
            pkill -f "qemu-system-x86_64.*$IMG_FILE"
            sleep 2
            is_vm_running "$vm_name" && pkill -9 -f "qemu-system-x86_64.*$IMG_FILE"
            stop_xorg_dummy
            print_status "SUCCESS" "VM stopped"
        else
            print_status "INFO" "VM not running"
        fi
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
        echo "========================================"
        echo "OS: $OS_TYPE"
        echo "Hostname: $HOSTNAME"
        echo "User: $USERNAME"
        echo "Password: $PASSWORD"
        echo "SSH Port: $SSH_PORT"
        echo "Memory: $MEMORY MB"
        echo "CPUs: $CPUS"
        echo "Disk: $DISK_SIZE"
        echo "Forwards: ${PORT_FORWARDS:-None}"
        echo ""
        echo "Performance:"
        echo "  Cache: $DISK_CACHE"
        echo "  I/O: $IO_THREADS"
        echo "  GPU: $ENABLE_VIRTIO_GPU"
        echo ""
        echo "Created: $CREATED"
        echo "========================================"
        read -p "Press Enter..."
    fi
}

# Function to check if VM running
is_vm_running() {
    local vm_name=$1
    pgrep -f "qemu-system-x86_64.*$vm_name" >/dev/null
}

# Function to edit VM
edit_vm_config() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        while true; do
            echo "Edit:"
            echo "  1) Hostname"
            echo "  2) Username"
            echo "  3) Password"
            echo "  4) SSH Port"
            echo "  5) Port Forwards"
            echo "  6) Memory"
            echo "  7) CPUs"
            echo "  8) Disk Size"
            echo "  9) Performance"
            echo "  0) Back"
            
            read -p "Choice: " edit_choice
            
            case $edit_choice in
                1)
                    read -p "Hostname (current: $HOSTNAME): " new_hostname
                    new_hostname="${new_hostname:-$HOSTNAME}"
                    validate_input "name" "$new_hostname" && HOSTNAME="$new_hostname"
                    ;;
                2)
                    read -p "Username (current: $USERNAME): " new_username
                    new_username="${new_username:-$USERNAME}"
                    validate_input "username" "$new_username" && USERNAME="$new_username"
                    ;;
                3)
                    read -s -p "Password: " new_password
                    echo
                    [ -n "$new_password" ] && PASSWORD="$new_password"
                    ;;
                4)
                    read -p "SSH Port (current: $SSH_PORT): " new_port
                    new_port="${new_port:-$SSH_PORT}"
                    validate_input "port" "$new_port" && SSH_PORT="$new_port"
                    ;;
                5)
                    read -p "Forwards (current: ${PORT_FORWARDS:-None}): " new_forwards
                    PORT_FORWARDS="${new_forwards:-$PORT_FORWARDS}"
                    ;;
                6)
                    read -p "Memory (current: $MEMORY): " new_mem
                    new_mem="${new_mem:-$MEMORY}"
                    validate_input "number" "$new_mem" && MEMORY="$new_mem"
                    ;;
                7)
                    read -p "CPUs (current: $CPUS): " new_cpus
                    new_cpus="${new_cpus:-$CPUS}"
                    validate_input "number" "$new_cpus" && CPUS="$new_cpus"
                    ;;
                8)
                    read -p "Disk size (current: $DISK_SIZE): " new_disk
                    new_disk="${new_disk:-$DISK_SIZE}"
                    validate_input "size" "$new_disk" && DISK_SIZE="$new_disk"
                    ;;
                9)
                    echo "Performance:"
                    echo "  1) Cache: $DISK_CACHE"
                    echo "  2) I/O: $IO_THREADS"
                    echo "  3) GPU: $ENABLE_VIRTIO_GPU"
                    read -p "Choice: " perf_choice
                    case $perf_choice in
                        1)
                            echo "  1) writeback  2) writethrough  3) none"
                            read -p "Choice: " cache_choice
                            case $cache_choice in
                                1) DISK_CACHE="writeback" ;;
                                2) DISK_CACHE="writethrough" ;;
                                3) DISK_CACHE="none" ;;
                            esac
                            ;;
                        2)
                            read -p "I/O threads (y/n): " io_choice
                            [[ "$io_choice" =~ ^[Yy]$ ]] && IO_THREADS=true || IO_THREADS=false
                            ;;
                        3)
                            if [ "$VIRGL_AVAILABLE" = true ] && [ "$XORG_AVAILABLE" = true ]; then
                                read -p "GPU (y/n): " gpu_choice
                                [[ "$gpu_choice" =~ ^[Yy]$ ]] && ENABLE_VIRTIO_GPU=true || ENABLE_VIRTIO_GPU=false
                            fi
                            ;;
                    esac
                    ;;
                0) return 0 ;;
                *) continue ;;
            esac
            
            [[ "$edit_choice" =~ ^[123]$ ]] && setup_vm_image
            save_vm_config
            
            read -p "Continue? (y/N): " cont
            [[ ! "$cont" =~ ^[Yy]$ ]] && break
        done
    fi
}

# Function to resize disk
resize_vm_disk() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Current: $DISK_SIZE"
        read -p "New size: " new_size
        
        if validate_input "size" "$new_size"; then
            if qemu-img resize "$IMG_FILE" "$new_size"; then
                DISK_SIZE="$new_size"
                save_vm_config
                print_status "SUCCESS" "Resized to $new_size"
            else
                print_status "ERROR" "Resize failed"
            fi
        fi
    fi
}

# Function to show performance
show_vm_performance() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        if is_vm_running "$vm_name"; then
            print_status "INFO" "Performance: $vm_name"
            echo "========================================"
            
            local qemu_pid=$(pgrep -f "qemu-system-x86_64.*$IMG_FILE")
            if [[ -n "$qemu_pid" ]]; then
                echo "Process:"
                ps -p "$qemu_pid" -o pid,%cpu,%mem,vsz,rss --no-headers
                echo ""
                echo "Memory:"
                free -h
                echo ""
                echo "Disk:"
                du -h "$IMG_FILE"
            fi
        else
            print_status "INFO" "VM not running"
            echo "Config:"
            echo "  Memory: $MEMORY MB"
            echo "  CPUs: $CPUS"
            echo "  Disk: $DISK_SIZE"
        fi
        echo "========================================"
        read -p "Press Enter..."
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
                printf "  %2d) %s (%s)\n" $((i+1)) "${vms[$i]}" "$status"
            done
            echo
        fi
        
        echo "Menu:"
        echo "  1) Create VM"
        [ $vm_count -gt 0 ] && cat << EOF
  2) Start VM
  3) Stop VM
  4) VM Info
  5) Edit VM
  6) Delete VM
  7) Resize Disk
  8) Performance
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
                    edit_vm_config "${vms[$((vm_num-1))]}"
                fi
                ;;
            6)
                if [ $vm_count -gt 0 ]; then
                    read -p "VM number: " vm_num
                    [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ] && \
                    delete_vm "${vms[$((vm_num-1))]}"
                fi
                ;;
            7)
                if [ $vm_count -gt 0 ]; then
                    read -p "VM number: " vm_num
                    [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ] && \
                    resize_vm_disk "${vms[$((vm_num-1))]}"
                fi
                ;;
            8)
                if [ $vm_count -gt 0 ]; then
                    read -p "VM number: " vm_num
                    [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ] && \
                    show_vm_performance "${vms[$((vm_num-1))]}"
                fi
                ;;
            0)
                print_status "INFO" "Goodbye!"
                exit 0
                ;;
        esac
        
        read -p "Press Enter..."
    done
}

# Trap cleanup
trap cleanup EXIT

# Check dependencies
check_dependencies

# Check capabilities
check_system_capabilities

# Initialize
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
