#!/bin/bash
set -euo pipefail

# =============================
# Enhanced Multi-VM Manager with Performance Optimizations
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
                print_status "ERROR" "Username must start with a letter or underscore, and contain only letters, numbers, hyphens, and underscores"
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
    
    # Check for AVX2 support (better performance)
    if grep -q avx2 /proc/cpuinfo; then
        print_status "SUCCESS" "AVX2 support detected (enhanced performance)"
        CPU_FEATURES="-cpu host,+avx2"
    else
        CPU_FEATURES="-cpu host"
    fi
    
    # Check available memory
    TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
    print_status "INFO" "Total memory: ${TOTAL_MEM}MB"
    
    # Check virtio-gpu support
    if qemu-system-x86_64 -device help 2>/dev/null | grep -q "virtio-vga-gl"; then
        print_status "SUCCESS" "virtio-gpu with virgl support available"
        VIRGL_AVAILABLE=true
    else
        print_status "WARN" "virtio-gpu-gl not available"
        VIRGL_AVAILABLE=false
    fi
    
    # Check Xorg availability for GPU
    if command -v Xorg &> /dev/null; then
        print_status "SUCCESS" "Xorg server available (for GPU acceleration)"
        XORG_AVAILABLE=true
    else
        if [ "$VIRGL_AVAILABLE" = true ]; then
            print_status "WARN" "Xorg not found - GPU acceleration will not work"
            print_status "INFO" "Add to dev.nix: xorg.xorgserver, xorg.xf86videodummy"
        fi
        XORG_AVAILABLE=false
    fi
    
    # Check huge pages support
    if [ -d /sys/kernel/mm/hugepages ]; then
        print_status "SUCCESS" "Huge pages support available"
        HUGEPAGES_AVAILABLE=true
    else
        print_status "INFO" "Huge pages not available"
        HUGEPAGES_AVAILABLE=false
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
        print_status "ERROR" "Missing dependencies: ${missing_deps[*]}"
        print_status "INFO" "Add to dev.nix: ${missing_deps[*]}"
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
        # Clear previous variables
        unset VM_NAME OS_TYPE CODENAME IMG_URL HOSTNAME USERNAME PASSWORD
        unset DISK_SIZE MEMORY CPUS SSH_PORT GUI_MODE PORT_FORWARDS IMG_FILE SEED_FILE CREATED
        unset ENABLE_VIRTIO_GPU DISK_CACHE NETWORK_MODEL IO_THREADS ENABLE_AUDIO
        
        source "$config_file"
        
        # Set defaults for new options if not present
        ENABLE_VIRTIO_GPU="${ENABLE_VIRTIO_GPU:-false}"
        DISK_CACHE="${DISK_CACHE:-writeback}"
        NETWORK_MODEL="${NETWORK_MODEL:-virtio-net-pci}"
        IO_THREADS="${IO_THREADS:-true}"
        
        # Force headless mode
        GUI_MODE=false
        ENABLE_AUDIO=false
        
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
PORT_FORWARDS="$PORT_FORWARDS"
IMG_FILE="$IMG_FILE"
SEED_FILE="$SEED_FILE"
CREATED="$CREATED"
ENABLE_VIRTIO_GPU="$ENABLE_VIRTIO_GPU"
DISK_CACHE="$DISK_CACHE"
NETWORK_MODEL="$NETWORK_MODEL"
IO_THREADS="$IO_THREADS"
EOF
    
    print_status "SUCCESS" "Configuration saved to $config_file"
}

# Function to create new VM
create_new_vm() {
    print_status "INFO" "Creating a new VM"
    
    # OS Selection
    print_status "INFO" "Select an OS to set up:"
    local os_options=()
    local i=1
    for os in "${!OS_OPTIONS[@]}"; do
        echo "  $i) $os"
        os_options[$i]="$os"
        ((i++))
    done
    
    while true; do
        read -p "$(print_status "INPUT" "Enter your choice (1-${#OS_OPTIONS[@]}): ")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#OS_OPTIONS[@]} ]; then
            local os="${os_options[$choice]}"
            IFS='|' read -r OS_TYPE CODENAME IMG_URL DEFAULT_HOSTNAME DEFAULT_USERNAME DEFAULT_PASSWORD <<< "${OS_OPTIONS[$os]}"
            break
        else
            print_status "ERROR" "Invalid selection. Try again."
        fi
    done

    # Custom Inputs with validation
    while true; do
        read -p "$(print_status "INPUT" "Enter VM name (default: $DEFAULT_HOSTNAME): ")" VM_NAME
        VM_NAME="${VM_NAME:-$DEFAULT_HOSTNAME}"
        if validate_input "name" "$VM_NAME"; then
            if [[ -f "$VM_DIR/$VM_NAME.conf" ]]; then
                print_status "ERROR" "VM with name '$VM_NAME' already exists"
            else
                break
            fi
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Enter hostname (default: $VM_NAME): ")" HOSTNAME
        HOSTNAME="${HOSTNAME:-$VM_NAME}"
        if validate_input "name" "$HOSTNAME"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Enter username (default: $DEFAULT_USERNAME): ")" USERNAME
        USERNAME="${USERNAME:-$DEFAULT_USERNAME}"
        if validate_input "username" "$USERNAME"; then
            break
        fi
    done

    while true; do
        read -s -p "$(print_status "INPUT" "Enter password (default: $DEFAULT_PASSWORD): ")" PASSWORD
        PASSWORD="${PASSWORD:-$DEFAULT_PASSWORD}"
        echo
        if [ -n "$PASSWORD" ]; then
            break
        else
            print_status "ERROR" "Password cannot be empty"
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Disk size (default: 20G): ")" DISK_SIZE
        DISK_SIZE="${DISK_SIZE:-20G}"
        if validate_input "size" "$DISK_SIZE"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Memory in MB (default: 2048): ")" MEMORY
        MEMORY="${MEMORY:-2048}"
        if validate_input "number" "$MEMORY"; then
            if [ "$MEMORY" -gt "$TOTAL_MEM" ]; then
                print_status "WARN" "Requested memory ($MEMORY MB) exceeds available memory ($TOTAL_MEM MB)"
                read -p "Continue anyway? (y/N): " confirm
                [[ "$confirm" =~ ^[Yy]$ ]] && break
            else
                break
            fi
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Number of CPUs (default: 2, max: $CPU_CORES): ")" CPUS
        CPUS="${CPUS:-2}"
        if validate_input "number" "$CPUS"; then
            if [ "$CPUS" -gt "$CPU_CORES" ]; then
                print_status "WARN" "Requested CPUs ($CPUS) exceeds available cores ($CPU_CORES)"
                read -p "Continue anyway? (y/N): " confirm
                [[ "$confirm" =~ ^[Yy]$ ]] && break
            else
                break
            fi
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "SSH Port (default: 2222): ")" SSH_PORT
        SSH_PORT="${SSH_PORT:-2222}"
        if validate_input "port" "$SSH_PORT"; then
            if ss -tln 2>/dev/null | grep -q ":$SSH_PORT "; then
                print_status "ERROR" "Port $SSH_PORT is already in use"
            else
                break
            fi
        fi
    done

    # Ask about GPU acceleration (independent of GUI mode)
    if [ "$VIRGL_AVAILABLE" = true ] && [ "$XORG_AVAILABLE" = true ]; then
        while true; do
            read -p "$(print_status "INPUT" "Enable GPU acceleration (virtio-gpu)? (y/n, default: n): ")" gpu_input
            gpu_input="${gpu_input:-n}"
            if [[ "$gpu_input" =~ ^[Yy]$ ]]; then
                ENABLE_VIRTIO_GPU=true
                print_status "SUCCESS" "virtio-gpu enabled (virgl 3D)"
                print_status "INFO" "Xorg dummy will auto-start for GPU rendering"
                print_status "INFO" "VM will run headless with GPU acceleration"
                break
            elif [[ "$gpu_input" =~ ^[Nn]$ ]]; then
                ENABLE_VIRTIO_GPU=false
                print_status "INFO" "GPU acceleration disabled (using software rendering)"
                break
            else
                print_status "ERROR" "Please answer y or n"
            fi
        done
    else
        ENABLE_VIRTIO_GPU=false
        if [ "$VIRGL_AVAILABLE" = false ]; then
            print_status "INFO" "virtio-gpu not available (qemu not built with virgl)"
        elif [ "$XORG_AVAILABLE" = false ]; then
            print_status "INFO" "Xorg not available (needed for GPU acceleration)"
            print_status "INFO" "Add to dev.nix: xorg.xorgserver, xorg.xf86videodummy"
        fi
    fi
    
    # GPU acceleration works in headless mode
    GUI_MODE=false
    ENABLE_AUDIO=false

    # Performance options
    echo ""
    print_status "INFO" "⚡ Performance Options:"
    
    # Disk cache mode
    echo "Disk cache modes:"
    echo "  1) writeback (best performance, slight risk on host crash)"
    echo "  2) writethrough (balanced)"
    echo "  3) none (safest, slower)"
    while true; do
        read -p "$(print_status "INPUT" "Choose disk cache (1-3, default: 1): ")" cache_choice
        cache_choice="${cache_choice:-1}"
        case $cache_choice in
            1) DISK_CACHE="writeback"; break ;;
            2) DISK_CACHE="writethrough"; break ;;
            3) DISK_CACHE="none"; break ;;
            *) print_status "ERROR" "Invalid choice" ;;
        esac
    done
    print_status "SUCCESS" "Disk cache: $DISK_CACHE"
    
    # IO threads
    while true; do
        read -p "$(print_status "INPUT" "Enable I/O threads for better disk performance? (y/n, default: y): ")" io_input
        io_input="${io_input:-y}"
        if [[ "$io_input" =~ ^[Yy]$ ]]; then
            IO_THREADS=true
            print_status "SUCCESS" "I/O threads enabled"
            break
        elif [[ "$io_input" =~ ^[Nn]$ ]]; then
            IO_THREADS=false
            break
        else
            print_status "ERROR" "Please answer y or n"
        fi
    done
    
    # Network model (always use virtio-net-pci for best performance)
    NETWORK_MODEL="virtio-net-pci"
    print_status "SUCCESS" "Network: virtio-net-pci (optimized)"

    # Additional port forwards
    read -p "$(print_status "INPUT" "Additional port forwards (e.g., 8080:80, press Enter for none): ")" PORT_FORWARDS

    IMG_FILE="$VM_DIR/$VM_NAME.img"
    SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"
    CREATED="$(date)"

    # Download and setup VM image
    setup_vm_image
    
    # Save configuration
    save_vm_config
    
    # Show performance summary
    echo ""
    print_status "SUCCESS" "⚡ Performance Configuration:"
    echo "  • CPU: $CPUS cores with host passthrough"
    echo "  • Memory: ${MEMORY}MB"
    echo "  • Disk cache: $DISK_CACHE"
    echo "  • I/O threads: $IO_THREADS"
    echo "  • Network: $NETWORK_MODEL (optimized)"
    echo "  • Mode: Headless SSH (serial console)"
    if [ "$ENABLE_VIRTIO_GPU" = true ] && [ "$VIRGL_AVAILABLE" = true ]; then
        echo "  • GPU: virtio-gpu with virgl 3D acceleration ✓"
        echo "  • Xorg dummy will auto-start when VM boots"
        echo ""
        echo "  📺 Access VM via SSH:"
        echo "     ssh -p $SSH_PORT $USERNAME@localhost"
        echo ""
        echo "  🚀 Inside VM with GPU:"
        echo "     lspci | grep VGA → Red Hat Virtio GPU"
        echo "     glxinfo | grep renderer → virgl (NOT llvmpipe)"
    else
        echo "  • GPU: Standard VGA (software rendering)"
        echo "  • OpenGL: llvmpipe (CPU-based)"
    fi
    echo "  • KVM acceleration: $KVM_AVAILABLE"
    echo ""
    echo "  💡 To use desktop in VM:"
    echo "     - Install: apt install xfce4"
    echo "     - Remote access: apt install x11vnc or nomachine"
}

# Function to setup VM image
setup_vm_image() {
    print_status "INFO" "Downloading and preparing image..."
    
    mkdir -p "$VM_DIR"
    
    if [[ -f "$IMG_FILE" ]]; then
        print_status "INFO" "Image file already exists. Skipping download."
    else
        print_status "INFO" "Downloading image from $IMG_URL..."
        if ! wget --progress=bar:force "$IMG_URL" -O "$IMG_FILE.tmp"; then
            print_status "ERROR" "Failed to download image from $IMG_URL"
            exit 1
        fi
        mv "$IMG_FILE.tmp" "$IMG_FILE"
    fi
    
    # Resize with better options
    if ! qemu-img resize "$IMG_FILE" "$DISK_SIZE" 2>/dev/null; then
        print_status "WARN" "Failed to resize disk image. Creating new image with specified size..."
        rm -f "$IMG_FILE"
        # Create with preallocation for better performance
        qemu-img create -f qcow2 "$IMG_FILE" "$DISK_SIZE"
    fi

    # cloud-init configuration
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

    # Add GUI packages if needed
    if [ "$GUI_MODE" = true ]; then
        cat >> user-data <<'EOF'
packages:
  - xfce4
  - xfce4-terminal
  - firefox-esr
  - mesa-utils
  - mesa-vulkan-drivers
runcmd:
  - systemctl set-default graphical.target
EOF
    fi

    cat > meta-data <<EOF
instance-id: iid-$VM_NAME
local-hostname: $HOSTNAME
EOF

    if ! cloud-localds "$SEED_FILE" user-data meta-data; then
        print_status "ERROR" "Failed to create cloud-init seed image"
        exit 1
    fi
    
    print_status "SUCCESS" "VM '$VM_NAME' created successfully."
}

# Function to setup Xorg dummy for GPU acceleration
setup_xorg_dummy() {
    print_status "INFO" "Setting up Xorg dummy display for GPU acceleration..."
    
    # Install X server and dummy driver if not present
    if ! command -v Xorg &> /dev/null || ! dpkg -l | grep -q xserver-xorg-video-dummy; then
        print_status "INFO" "Installing Xorg and dummy driver..."
        apt update -qq
        DEBIAN_FRONTEND=noninteractive apt install -y -qq xserver-xorg-core xserver-xorg-video-dummy x11-xserver-utils
    fi
    
    # Create Xorg config for dummy driver
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
    
    # Find free display number
    local display_num=10
    while [ -f "/tmp/.X${display_num}-lock" ]; do
        ((display_num++))
    done
    
    # Start Xorg dummy in background
    print_status "INFO" "Starting Xorg dummy on display :$display_num..."
    Xorg :$display_num -config "$xorg_conf" &> "/tmp/xorg-${VM_NAME}.log" &
    local xorg_pid=$!
    
    # Wait for X server to start
    sleep 2
    
    # Check if Xorg started successfully
    if ps -p $xorg_pid > /dev/null; then
        print_status "SUCCESS" "Xorg dummy started on display :$display_num (PID: $xorg_pid)"
        echo "$xorg_pid" > "/tmp/xorg-${VM_NAME}.pid"
        echo "DISPLAY=:$display_num"
        return 0
    else
        print_status "ERROR" "Failed to start Xorg dummy"
        cat "/tmp/xorg-${VM_NAME}.log"
        return 1
    fi
}

# Function to stop Xorg dummy
stop_xorg_dummy() {
    local xorg_pid_file="/tmp/xorg-${VM_NAME}.pid"
    if [ -f "$xorg_pid_file" ]; then
        local xorg_pid=$(cat "$xorg_pid_file")
        if ps -p $xorg_pid > /dev/null 2>&1; then
            print_status "INFO" "Stopping Xorg dummy (PID: $xorg_pid)..."
            kill $xorg_pid 2>/dev/null
            rm -f "$xorg_pid_file"
        fi
    fi
    rm -f "/tmp/xorg-dummy-${VM_NAME}.conf"
    rm -f "/tmp/xorg-${VM_NAME}.log"
}
build_qemu_command() {
    local qemu_cmd=(qemu-system-x86_64)
    
    # KVM acceleration
    if [ "$KVM_AVAILABLE" = true ]; then
        qemu_cmd+=(-enable-kvm)
    fi
    
    # CPU configuration with optimizations
    qemu_cmd+=(
        -m "$MEMORY"
        -smp "cpus=$CPUS,cores=$CPUS,threads=1,sockets=1"
        $CPU_FEATURES
    )
    
    # Machine type - use Q35 for better PCIe support with optimizations
    local machine_opts="q35,hpet=off"
    [ "$KVM_AVAILABLE" = true ] && machine_opts+=",accel=kvm"
    qemu_cmd+=(-machine "$machine_opts")
    
    # Disk configuration with optimizations
    if [ "$IO_THREADS" = true ]; then
        # Use virtio-scsi with iothread for best performance
        local aio_mode="threads"
        # Use native AIO only with direct cache mode
        if [ "$DISK_CACHE" = "none" ]; then
            aio_mode="native"
        fi
        
        qemu_cmd+=(
            -object "iothread,id=io1"
            -device "virtio-scsi-pci,id=scsi0,iothread=io1"
            -drive "file=$IMG_FILE,if=none,id=drive0,format=qcow2,cache=$DISK_CACHE,aio=$aio_mode"
            -device "scsi-hd,drive=drive0,bus=scsi0.0"
            -drive "file=$SEED_FILE,if=none,id=drive1,format=raw,cache=none,aio=threads"
            -device "scsi-cd,drive=drive1,bus=scsi0.0"
        )
    else
        # Standard virtio-blk
        local aio_mode="threads"
        if [ "$DISK_CACHE" = "none" ]; then
            aio_mode="native"
        fi
        
        qemu_cmd+=(
            -drive "file=$IMG_FILE,format=qcow2,if=virtio,cache=$DISK_CACHE,aio=$aio_mode"
            -drive "file=$SEED_FILE,format=raw,if=virtio,cache=none"
        )
    fi
    
    # Boot order
    qemu_cmd+=(-boot order=c)
    
    # Network with optimizations
    qemu_cmd+=(
        -device "$NETWORK_MODEL,netdev=n0"
        -netdev "user,id=n0,hostfwd=tcp::$SSH_PORT-:22"
    )
    
    # Add port forwards if specified
    if [[ -n "$PORT_FORWARDS" ]]; then
        IFS=',' read -ra forwards <<< "$PORT_FORWARDS"
        local net_id=1
        for forward in "${forwards[@]}"; do
            IFS=':' read -r host_port guest_port <<< "$forward"
            qemu_cmd+=(",hostfwd=tcp::$host_port-:$guest_port")
        done
    fi
    
    # Display configuration
    if [ "$ENABLE_VIRTIO_GPU" = true ] && [ "$VIRGL_AVAILABLE" = true ]; then
        # virtio-gpu with virgl, headless mode with SDL offscreen
        qemu_cmd+=(
            -device "virtio-vga-gl"
            -display "sdl,gl=on"
        )
        # USB tablet for better mouse (if user connects remotely)
        qemu_cmd+=(
            -device "qemu-xhci,id=xhci"
            -device "usb-tablet,bus=xhci.0"
        )
    fi
    
    # Always run headless with serial console for SSH access
    qemu_cmd+=(-nographic -serial mon:stdio)
    
    # Performance enhancements
    qemu_cmd+=(
        # Virtio RNG for better entropy
        -object "rng-random,filename=/dev/urandom,id=rng0"
        -device "virtio-rng-pci,rng=rng0"
        
        # Balloon for dynamic memory
        -device "virtio-balloon-pci"
        
        # Modern UEFI firmware (if available)
        # -bios /usr/share/ovmf/OVMF.fd
    )
    
    # Additional optimizations
    qemu_cmd+=(
        # Disable S3/S4 sleep states for better performance
        -global "ICH9-LPC.disable_s3=1"
        -global "ICH9-LPC.disable_s4=1"
        
        # Modern RTC
        -rtc "base=utc,clock=host,driftfix=slew"
    )
    
    echo "${qemu_cmd[@]}"
}

# Function to start a VM
start_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Starting VM: $vm_name"
        print_status "INFO" "SSH: ssh -p $SSH_PORT $USERNAME@localhost"
        print_status "INFO" "Password: $PASSWORD"
        
        if [[ ! -f "$IMG_FILE" ]]; then
            print_status "ERROR" "VM image file not found: $IMG_FILE"
            return 1
        fi
        
        if [[ ! -f "$SEED_FILE" ]]; then
            print_status "WARN" "Seed file not found, recreating..."
            setup_vm_image
        fi
        
        # Setup Xorg dummy if GPU acceleration is enabled
        local xorg_display=""
        if [ "$ENABLE_VIRTIO_GPU" = true ] && [ "$VIRGL_AVAILABLE" = true ]; then
            # Check if Xorg is available
            if ! command -v Xorg &> /dev/null; then
                print_status "WARN" "Xorg not found, GPU acceleration disabled"
                print_status "INFO" "Add to dev.nix: xorg.xorgserver, xorg.xf86videodummy"
                ENABLE_VIRTIO_GPU=false
            elif [ -z "${DISPLAY:-}" ]; then
                print_status "INFO" "🎮 GPU acceleration enabled, setting up Xorg dummy..."
                xorg_display=$(setup_xorg_dummy)
                if [ $? -eq 0 ]; then
                    export DISPLAY="$xorg_display"
                    print_status "SUCCESS" "Xorg dummy started: $DISPLAY"
                    print_status "INFO" "VM will run headless with GPU acceleration"
                else
                    print_status "WARN" "Failed to setup Xorg dummy, disabling GPU"
                    ENABLE_VIRTIO_GPU=false
                fi
            else
                print_status "INFO" "Using existing display: $DISPLAY"
            fi
        fi
        
        # Build and execute QEMU command
        local qemu_cmd=($(build_qemu_command))
        
        print_status "INFO" "⚡ Performance optimizations enabled:"
        [ "$KVM_AVAILABLE" = true ] && echo "  ✓ KVM acceleration"
        echo "  ✓ CPU: $CPUS cores with host features"
        echo "  ✓ Disk cache: $DISK_CACHE"
        [ "$IO_THREADS" = true ] && echo "  ✓ I/O threads enabled"
        echo "  ✓ Network: $NETWORK_MODEL"
        echo "  ✓ Mode: Headless (SSH access)"
        if [ "$ENABLE_VIRTIO_GPU" = true ] && [ "$VIRGL_AVAILABLE" = true ]; then
            echo "  ✓ GPU: virtio-gpu with virgl 3D acceleration"
            [ -n "$xorg_display" ] && echo "  ✓ Xorg dummy: $xorg_display"
        else
            echo "  ✓ GPU: Standard VGA (software rendering)"
        fi
        
        print_status "INFO" "Starting QEMU..."
        
        # Trap to cleanup Xorg on exit
        if [ -n "$xorg_display" ]; then
            trap "stop_xorg_dummy" EXIT INT TERM
        fi
        
        "${qemu_cmd[@]}"
        
        # Cleanup Xorg dummy after VM stops
        if [ -n "$xorg_display" ]; then
            stop_xorg_dummy
        fi
        
        print_status "INFO" "VM $vm_name has been shut down"
    fi
}

# Function to delete a VM
delete_vm() {
    local vm_name=$1
    
    print_status "WARN" "This will permanently delete VM '$vm_name' and all its data!"
    read -p "$(print_status "INPUT" "Are you sure? (y/N): ")" -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if load_vm_config "$vm_name"; then
            rm -f "$IMG_FILE" "$SEED_FILE" "$VM_DIR/$vm_name.conf"
            print_status "SUCCESS" "VM '$vm_name' has been deleted"
        fi
    else
        print_status "INFO" "Deletion cancelled"
    fi
}

# Function to show VM info
show_vm_info() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        echo
        print_status "INFO" "VM Information: $vm_name"
        echo "=========================================="
        echo "OS: $OS_TYPE"
        echo "Hostname: $HOSTNAME"
        echo "Username: $USERNAME"
        echo "Password: $PASSWORD"
        echo "SSH Port: $SSH_PORT"
        echo "Memory: $MEMORY MB"
        echo "CPUs: $CPUS"
        echo "Disk: $DISK_SIZE"
        echo "Mode: Headless SSH"
        echo "Port Forwards: ${PORT_FORWARDS:-None}"
        echo ""
        echo "⚡ Performance Settings:"
        echo "  Disk Cache: $DISK_CACHE"
        echo "  I/O Threads: $IO_THREADS"
        echo "  Network: $NETWORK_MODEL"
        if [ "$ENABLE_VIRTIO_GPU" = true ]; then
            echo "  GPU: virtio-gpu with virgl (3D acceleration)"
        else
            echo "  GPU: Standard VGA (software rendering)"
        fi
        echo ""
        echo "Created: $CREATED"
        echo "Image File: $IMG_FILE"
        echo "Seed File: $SEED_FILE"
        echo "=========================================="
        echo
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    fi
}

# Function to check if VM is running
is_vm_running() {
    local vm_name=$1
    if pgrep -f "qemu-system-x86_64.*$vm_name" >/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to stop a running VM
stop_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        if is_vm_running "$vm_name"; then
            print_status "INFO" "Stopping VM: $vm_name"
            pkill -f "qemu-system-x86_64.*$IMG_FILE"
            sleep 2
            if is_vm_running "$vm_name"; then
                print_status "WARN" "VM did not stop gracefully, forcing termination..."
                pkill -9 -f "qemu-system-x86_64.*$IMG_FILE"
            fi
            
            # Cleanup Xorg dummy if it was started for this VM
            stop_xorg_dummy
            
            print_status "SUCCESS" "VM $vm_name stopped"
        else
            print_status "INFO" "VM $vm_name is not running"
        fi
    fi
}

# Function to edit VM configuration
edit_vm_config() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Editing VM: $vm_name"
        
        while true; do
            echo "What would you like to edit?"
            echo "  1) Hostname"
            echo "  2) Username"
            echo "  3) Password"
            echo "  4) SSH Port"
            echo "  5) Port Forwards"
            echo "  6) Memory (RAM)"
            echo "  7) CPU Count"
            echo "  8) Disk Size"
            echo "  9) Performance Settings"
            echo "  0) Back to main menu"
            
            read -p "$(print_status "INPUT" "Enter your choice: ")" edit_choice
            
            case $edit_choice in
                1)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new hostname (current: $HOSTNAME): ")" new_hostname
                        new_hostname="${new_hostname:-$HOSTNAME}"
                        if validate_input "name" "$new_hostname"; then
                            HOSTNAME="$new_hostname"
                            break
                        fi
                    done
                    ;;
                2)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new username (current: $USERNAME): ")" new_username
                        new_username="${new_username:-$USERNAME}"
                        if validate_input "username" "$new_username"; then
                            USERNAME="$new_username"
                            break
                        fi
                    done
                    ;;
                3)
                    while true; do
                        read -s -p "$(print_status "INPUT" "Enter new password (current: ****): ")" new_password
                        new_password="${new_password:-$PASSWORD}"
                        echo
                        if [ -n "$new_password" ]; then
                            PASSWORD="$new_password"
                            break
                        else
                            print_status "ERROR" "Password cannot be empty"
                        fi
                    done
                    ;;
                4)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new SSH port (current: $SSH_PORT): ")" new_ssh_port
                        new_ssh_port="${new_ssh_port:-$SSH_PORT}"
                        if validate_input "port" "$new_ssh_port"; then
                            if [ "$new_ssh_port" != "$SSH_PORT" ] && ss -tln 2>/dev/null | grep -q ":$new_ssh_port "; then
                                print_status "ERROR" "Port $new_ssh_port is already in use"
                            else
                                SSH_PORT="$new_ssh_port"
                                break
                            fi
                        fi
                    done
                    ;;
                5)
                    read -p "$(print_status "INPUT" "Additional port forwards (current: ${PORT_FORWARDS:-None}): ")" new_port_forwards
                    PORT_FORWARDS="${new_port_forwards:-$PORT_FORWARDS}"
                    ;;
                6)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new memory in MB (current: $MEMORY): ")" new_memory
                        new_memory="${new_memory:-$MEMORY}"
                        if validate_input "number" "$new_memory"; then
                            MEMORY="$new_memory"
                            break
                        fi
                    done
                    ;;
                7)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new CPU count (current: $CPUS): ")" new_cpus
                        new_cpus="${new_cpus:-$CPUS}"
                        if validate_input "number" "$new_cpus"; then
                            CPUS="$new_cpus"
                            break
                        fi
                    done
                    ;;
                8)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new disk size (current: $DISK_SIZE): ")" new_disk_size
                        new_disk_size="${new_disk_size:-$DISK_SIZE}"
                        if validate_input "size" "$new_disk_size"; then
                            DISK_SIZE="$new_disk_size"
                            break
                        fi
                    done
                    ;;
                9)
                    # Performance settings submenu
                    echo ""
                    print_status "INFO" "⚡ Performance Settings:"
                    echo "  1) Disk Cache Mode (current: $DISK_CACHE)"
                    echo "  2) I/O Threads (current: $IO_THREADS)"
                    echo "  3) virtio-gpu (current: $ENABLE_VIRTIO_GPU)"
                    echo "  4) Audio (current: $ENABLE_AUDIO)"
                    
                    read -p "$(print_status "INPUT" "Choose setting to change (1-4): ")" perf_choice
                    
                    case $perf_choice in
                        1)
                            echo "  1) writeback (fastest)"
                            echo "  2) writethrough (balanced)"
                            echo "  3) none (safest)"
                            read -p "Choose (1-3): " cache_choice
                            case $cache_choice in
                                1) DISK_CACHE="writeback" ;;
                                2) DISK_CACHE="writethrough" ;;
                                3) DISK_CACHE="none" ;;
                            esac
                            ;;
                        2)
                            read -p "Enable I/O threads? (y/n): " io_choice
                            [[ "$io_choice" =~ ^[Yy]$ ]] && IO_THREADS=true || IO_THREADS=false
                            ;;
                        3)
                            read -p "Enable virtio-gpu? (y/n): " gpu_choice
                            [[ "$gpu_choice" =~ ^[Yy]$ ]] && ENABLE_VIRTIO_GPU=true || ENABLE_VIRTIO_GPU=false
                            ;;
                        4)
                            read -p "Enable audio? (y/n): " audio_choice
                            [[ "$audio_choice" =~ ^[Yy]$ ]] && ENABLE_AUDIO=true || ENABLE_AUDIO=false
                            ;;
                    esac
                    ;;
                0)
                    return 0
                    ;;
                *)
                    print_status "ERROR" "Invalid selection"
                    continue
                    ;;
            esac
            
            if [[ "$edit_choice" -eq 1 || "$edit_choice" -eq 2 || "$edit_choice" -eq 3 ]]; then
                print_status "INFO" "Updating cloud-init configuration..."
                setup_vm_image
            fi
            
            save_vm_config
            
            read -p "$(print_status "INPUT" "Continue editing? (y/N): ")" continue_editing
            if [[ ! "$continue_editing" =~ ^[Yy]$ ]]; then
                break
            fi
        done
    fi
}

# Function to resize VM disk
resize_vm_disk() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Current disk size: $DISK_SIZE"
        
        while true; do
            read -p "$(print_status "INPUT" "Enter new disk size (e.g., 50G): ")" new_disk_size
            if validate_input "size" "$new_disk_size"; then
                if [[ "$new_disk_size" == "$DISK_SIZE" ]]; then
                    print_status "INFO" "New disk size is the same as current size. No changes made."
                    return 0
                fi
                
                local current_size_num=${DISK_SIZE%[GgMm]}
                local new_size_num=${new_disk_size%[GgMm]}
                local current_unit=${DISK_SIZE: -1}
                local new_unit=${new_disk_size: -1}
                
                if [[ "$current_unit" =~ [Gg] ]]; then
                    current_size_num=$((current_size_num * 1024))
                fi
                if [[ "$new_unit" =~ [Gg] ]]; then
                    new_size_num=$((new_size_num * 1024))
                fi
                
                if [[ $new_size_num -lt $current_size_num ]]; then
                    print_status "WARN" "Shrinking disk size is not recommended and may cause data loss!"
                    read -p "$(print_status "INPUT" "Are you sure you want to continue? (y/N): ")" confirm_shrink
                    if [[ ! "$confirm_shrink" =~ ^[Yy]$ ]]; then
                        print_status "INFO" "Disk resize cancelled."
                        return 0
                    fi
                fi
                
                print_status "INFO" "Resizing disk to $new_disk_size..."
                if qemu-img resize "$IMG_FILE" "$new_disk_size"; then
                    DISK_SIZE="$new_disk_size"
                    save_vm_config
                    print_status "SUCCESS" "Disk resized successfully to $new_disk_size"
                else
                    print_status "ERROR" "Failed to resize disk"
                    return 1
                fi
                break
            fi
        done
    fi
}

# Function to show VM performance metrics
show_vm_performance() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        if is_vm_running "$vm_name"; then
            print_status "INFO" "Performance metrics for VM: $vm_name"
            echo "=========================================="
            
            local qemu_pid=$(pgrep -f "qemu-system-x86_64.*$IMG_FILE")
            if [[ -n "$qemu_pid" ]]; then
                echo "QEMU Process Stats:"
                ps -p "$qemu_pid" -o pid,%cpu,%mem,sz,rss,vsz,cmd --no-headers
                echo
                
                echo "Memory Usage:"
                free -h
                echo
                
                echo "Disk Usage:"
                df -h "$IMG_FILE" 2>/dev/null || du -h "$IMG_FILE"
                echo
                
                echo "Performance Configuration:"
                echo "  KVM: $KVM_AVAILABLE"
                echo "  Disk Cache: $DISK_CACHE"
                echo "  I/O Threads: $IO_THREADS"
                echo "  virtio-gpu: $ENABLE_VIRTIO_GPU"
            else
                print_status "ERROR" "Could not find QEMU process for VM $vm_name"
            fi
        else
            print_status "INFO" "VM $vm_name is not running"
            echo "Configuration:"
            echo "  Memory: $MEMORY MB"
            echo "  CPUs: $CPUS"
            echo "  Disk: $DISK_SIZE"
            echo ""
            echo "Performance Settings:"
            echo "  Disk Cache: $DISK_CACHE"
            echo "  I/O Threads: $IO_THREADS"
            if [ "$ENABLE_VIRTIO_GPU" = true ]; then
                echo "  GPU: virtio-gpu (3D acceleration)"
            else
                echo "  GPU: Standard VGA (software rendering)"
            fi
        fi
        echo "=========================================="
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    fi
}

# Main menu function
main_menu() {
    while true; do
        display_header
        
        local vms=($(get_vm_list))
        local vm_count=${#vms[@]}
        
        if [ $vm_count -gt 0 ]; then
            print_status "INFO" "Found $vm_count existing VM(s):"
            for i in "${!vms[@]}"; do
                local status="Stopped"
                if is_vm_running "${vms[$i]}"; then
                    status="Running"
                fi
                printf "  %2d) %s (%s)\n" $((i+1)) "${vms[$i]}" "$status"
            done
            echo
        fi
        
        echo "Main Menu:"
        echo "  1) Create a new VM"
        if [ $vm_count -gt 0 ]; then
            echo "  2) Start a VM"
            echo "  3) Stop a VM"
            echo "  4) Show VM info"
            echo "  5) Edit VM configuration"
            echo "  6) Delete a VM"
            echo "  7) Resize VM disk"
            echo "  8) Show VM performance"
        fi
        echo "  0) Exit"
        echo
        
        read -p "$(print_status "INPUT" "Enter your choice: ")" choice
        
        case $choice in
            1)
                create_new_vm
                ;;
            2)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to start: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        start_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            3)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to stop: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        stop_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            4)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to show info: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        show_vm_info "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            5)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to edit: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        edit_vm_config "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            6)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to delete: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        delete_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            7)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to resize disk: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        resize_vm_disk "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            8)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to show performance: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        show_vm_performance "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
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
        
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    done
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Check dependencies
check_dependencies

# Check system capabilities
check_system_capabilities

# Initialize paths
VM_DIR="${VM_DIR:-$HOME/vms}"
mkdir -p "$VM_DIR"

# Supported OS list
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

# Start the main menu
main_menu
