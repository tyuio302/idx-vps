{ pkgs, ... }: {
  channel = "stable-24.05";

  packages = with pkgs; [
    # Basic tools
    unzip
    openssh
    git
    sudo
    
    # QEMU and VM tools
    qemu_kvm
    qemu
    cdrkit
    cloud-utils
    
    # Xorg dummy for GPU acceleration
    xorg.xorgserver
    xorg.xf86videodummy
    xorg.xrandr
    
    # Additional utilities
    wget
    curl
  ];

  env = {
    EDITOR = "nano";
  };

  idx = {
    extensions = [
      "Dart-Code.flutter"
      "Dart-Code.dart-code"
    ];

    workspace = {
      onCreate = { };
      onStart = { };
    };

    previews = {
      enable = false;
    };
  };
}
