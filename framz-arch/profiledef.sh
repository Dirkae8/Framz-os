#!/usr/bin/env bash
# FRAMZ OS — профиль archiso (черновая версия).
# Сборка: sudo mkarchiso -v -w /tmp/framz-work -o out framz-arch

iso_name="framz-os-arch"
iso_label="FRAMZ_ARCH_1"
iso_publisher="FRAMZ OS <https://github.com/Dirkae8/Framz-os>"
iso_application="FRAMZ OS — творческая система (Live + установка)"
iso_version="1.0"
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux' 'uefi.grub')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '-19')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/usr/local/bin/framz-welcome"]="0:0:755"
)
