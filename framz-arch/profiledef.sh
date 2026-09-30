#!/usr/bin/env bash
# FRAMZ OS — профиль archiso (Arch-издание).
#
# Сборка (на Arch или в контейнере archlinux:latest, нужны права root):
#   bash framz-arch/prepare.sh              # собрать airootfs из наших файлов
#   sudo mkarchiso -v -w /tmp/framz-work -o out framz-arch
#
# Результат: out/framz-os-arch-1.0-x86_64.iso

iso_name="framz-os-arch"
iso_label="FRAMZ_ARCH_1"
iso_publisher="FRAMZ OS <https://github.com/Dirkae8/Framz-os>"
iso_application="FRAMZ OS — творческая система (Live + установка)"
iso_version="1.0"
install_dir="arch"
buildmodes=('iso')
# BIOS: syslinux (MBR + El Torito), UEFI: GRUB
bootmodes=('bios.syslinux.mbr' 'bios.syslinux.eltorito' 'uefi-x64.grub.esp' 'uefi-x64.grub.eltorito')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '-19')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/etc/sudoers.d/10-framz-live"]="0:0:440"
  ["/root"]="0:0:750"
  ["/usr/bin/framz"]="0:0:755"
  ["/usr/bin/framz-tune"]="0:0:755"
  ["/usr/bin/framz-welcome"]="0:0:755"
  ["/usr/bin/framz-update"]="0:0:755"
  ["/usr/bin/framz-help"]="0:0:755"
  ["/usr/bin/framz-grub-theme"]="0:0:755"
  ["/usr/local/bin/framz-initramfs.sh"]="0:0:755"
)
