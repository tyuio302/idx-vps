{ pkgs, ... }: {
  channel = "stable-24.05";

  packages = with pkgs; [
    # Basic tools
    unzip
    openssh
    git
    wget
    curl
    
    # QEMU and VM tools
    qemu_kvm
    qemu
    cdrkit
    cloud-utils
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
