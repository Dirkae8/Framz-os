#!/usr/bin/env bash
# FRAMZ OS — шаг установки: собрать initramfs с нашим экраном загрузки.
# Запускается установщиком внутри устанавливаемой системы (Calamares, shellprocess).
set -uo pipefail

MKCONF="/etc/mkinitcpio.conf"

if [ -f "${MKCONF}" ]; then
  if ! grep -q 'plymouth' "${MKCONF}"; then
    # ставим plymouth перед block — так требует порядок хуков mkinitcpio
    sed -i -E 's/^(HOOKS=\(.*)(block[^)]*)\)/\1plymouth \2)/' "${MKCONF}" || true
    grep -q 'plymouth' "${MKCONF}" || \
      sed -i -E 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont plymouth block filesystems fsck)/' "${MKCONF}"
  fi
fi

# Наша тема загрузки и пересборка initramfs
if command -v plymouth-set-default-theme >/dev/null 2>&1 && [ -d /usr/share/plymouth/themes/framz ]; then
  plymouth-set-default-theme framz >/dev/null 2>&1 || true
fi
if command -v mkinitcpio >/dev/null 2>&1; then
  mkinitcpio -P >/dev/null 2>&1 || true
fi
exit 0
