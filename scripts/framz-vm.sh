#!/usr/bin/env bash
#
# FRAMZ OS — скачать установочный ISO и запустить его в виртуальной машине.
#
# Проверено на Arch-подобных системах (Garuda, Manjaro, EndeavourOS) и Fedora.
# Не требует root: QEMU запускается от твоего пользователя.
#
# Примеры:
#   scripts/framz-vm.sh deps                 # что установить и как
#   scripts/framz-vm.sh all                  # скачать ISO + собрать из частей + запустить ВМ
#   scripts/framz-vm.sh run                  # только запустить (ISO уже скачан)
#   scripts/framz-vm.sh run --memory 8192 --cpus 6 --gl
#   scripts/framz-vm.sh download             # только скачать и проверить
#
set -euo pipefail

# ----------------------------- настройки ------------------------------------
REPO="${FRAMZ_REPO:-Dirkae8/Framz-os}"
TAG="${FRAMZ_RELEASE_TAG:-v1.0-preview}"
ISO_NAME="${FRAMZ_ISO_NAME:-framz-os-1.0.iso}"
BASE_URL="${FRAMZ_BASE_URL:-https://github.com/${REPO}/releases/download/${TAG}}"

WORKDIR="${FRAMZ_DIR:-$HOME/framz}"
MEMORY=6144            # МБ оперативной памяти для ВМ
CPUS=4                 # ядер для ВМ
DISK_GB=40             # размер виртуального диска, ГБ
GL=0                   # 3D-ускорение (virtio-vga-gl)
SOUND=0                # звук в ВМ (требует qemu-audio-pipewire)
DISPLAY_BACKEND="gtk"  # gtk | sdl
USE_KVM=1              # аппаратное ускорение
BOOT_ORDER="dc"        # сначала диск, потом CD (чтобы после установки грузиться с диска)
ISO_PATH=""            # готовый ISO по конкретному пути
SRC_DIR=""             # каталог с уже скачанными частями
VM_NAME="FRAMZ OS ${TAG}"

# ----------------------------- вывод ----------------------------------------
c_red=$'\033[31m'; c_yel=$'\033[33m'; c_grn=$'\033[32m'; c_dim=$'\033[2m'; c_off=$'\033[0m'
info() { printf '%s\n' "${c_grn}▸${c_off} $*"; }
warn() { printf '%s\n' "${c_yel}!${c_off} $*" >&2; }
die()  { printf '%s\n' "${c_red}✖${c_off} $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<'EOF'
FRAMZ OS — запуск в виртуальной машине

Использование: framz-vm.sh <команда> [опции]

Команды:
  deps        что установить (и готовые команды для Arch/Garuda и Fedora)
  download    скачать ISO (частями), собрать его и проверить контрольные суммы
  run         запустить виртуальную машину (диск создастся сам)
  all         download + run
  clean       удалить скачанные файлы и виртуальный диск
  help        эта справка

Опции:
  --dir DIR       рабочий каталог                 (по умолчанию ~/framz)
  --iso FILE      запустить готовый ISO по пути   (пропускает скачивание)
  --src DIR       где лежат уже скачанные части   (работает без сети)
  --memory МБ     памяти для ВМ                   (по умолчанию 6144)
  --cpus N        ядер для ВМ                     (по умолчанию 4)
  --disk ГБ       размер виртуального диска       (по умолчанию 40)
  --gl            включить 3D-ускорение           (virtio-vga-gl)
  --sound         включить звук в ВМ              (нужен qemu-audio-pipewire)
  --display X     gtk или sdl                     (по умолчанию gtk)
  --boot ПОРЯДОК  порядок загрузки                (по умолчанию dc: диск, потом CD)
  --no-kvm        без аппаратного ускорения       (очень медленно, только для проверки)
  -h, --help      эта справка
EOF
}

# ----------------------------- утилиты --------------------------------------

# Скачать: поддерживает докачку и локальные file:// (для тестов и офлайн-режима)
fetch() { # url out
  local url="$1" out="$2"
  case "$url" in
    file://*) cp -f "${url#file://}" "$out" ;;
    *) curl -fL --retry 5 --retry-delay 3 --continue-at - --create-dirs -o "$out" "$url" ;;
  esac
}

# Строгая проверка: содержимое файла контрольной суммы == реальная сумма файла
verify_against() { # checksumfile file [метка]
  local cfile="$1" file="$2" label="${3:-$2}"
  [ -f "$cfile" ] || { warn "нет файла контрольной суммы: $cfile"; return 2; }
  local expected actual
  expected="$(awk 'NR==1{print $1}' "$cfile")"
  [ -n "$expected" ] || { warn "пустой файл контрольной суммы: $cfile"; return 2; }
  actual="$(sha256sum "$file" | awk '{print $1}')"
  if [ "$expected" = "$actual" ]; then
    info "сумма совпала: ${label}"
    return 0
  fi
  warn "СУММА НЕ СОВПАЛА: ${label}"
  warn "  ожидалось: ${expected}"
  warn "  получилось: ${actual}"
  return 1
}

# Проверка всех частей по файлу .parts-SHA256 (терпимо к префиксам путей)
verify_parts() {
  local cfile="$WORKDIR/${ISO_NAME}.parts-SHA256" ok=1 hash name base actual
  [ -f "$cfile" ] || { warn "нет файла ${ISO_NAME}.parts-SHA256"; return 2; }
  while read -r hash name; do
    [ -n "${hash:-}" ] || continue
    base="$(basename "${name}")"
    if [ ! -f "$WORKDIR/$base" ]; then warn "не хватает части: ${base}"; ok=0; continue; fi
    actual="$(sha256sum "$WORKDIR/$base" | awk '{print $1}')"
    if [ "$actual" != "$hash" ]; then warn "часть повреждена: ${base}"; ok=0; fi
  done < "$cfile"
  [ "$ok" = 1 ]
}

# ----------------------------- deps -----------------------------------------
cmd_deps() {
  local id="${FRAMZ_OS_ID:-}"
  if [ -z "$id" ] && [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    id="${ID:-}"
  fi

  cat <<EOF
Нужны две вещи: QEMU (сама виртуалка) и UEFI-прошивка OVMF.

EOF
  case "$id" in
    arch|garuda|manjaro|endeavouros|garuda-linux|artix|cachyos)
      cat <<'EOF'
Arch / Garuda (достаточно этого — libvirt не обязателен):

  garuda-update                     # или: sudo pacman -Syu
  sudo pacman -S --needed qemu-desktop edk2-ovmf

Хочешь звук в виртуалке (для проверки аудио):
  sudo pacman -S --needed qemu-audio-pipewire

Хочешь графический менеджер виртуалок (virt-manager):
  sudo pacman -S --needed virt-manager libvirt dnsmasq iptables-nft
  sudo systemctl enable --now libvirtd.socket
  sudo virsh net-start default && sudo virsh net-autostart default

Доступ к аппаратному ускорению (после этого выйти и войти заново):
  sudo usermod -aG kvm "$USER"
  ls -l /dev/kvm        # должно быть: crw-rw---- root kvm

Если /dev/kvm вообще отсутствует — включи виртуализацию
(VT-x / AMD-V / SVM) в BIOS/UEFI материнской платы.
EOF
      ;;
    fedora|rhel|centos)
      cat <<'EOF'
Fedora:

  sudo dnf install qemu-kvm qemu-audio-pipewire edk2-ovmf
  sudo usermod -aG kvm "$USER"       # потом выйти и войти заново
  ls -l /dev/kvm                     # crw-rw---- root kvm
EOF
      ;;
    debian|ubuntu|linuxmint|pop|neon)
      cat <<'EOF'
Debian / Ubuntu:

  sudo apt update
  sudo apt install qemu-system-x86 qemu-utils ovmf
  sudo usermod -aG kvm "$USER"       # потом выйти и войти заново
  ls -l /dev/kvm                     # crw-rw---- root kvm
EOF
      ;;
    *)
      cat <<'EOF'
Не удалось определить систему. Установи вручную:
  — QEMU для своей системы (пакет с qemu-system-x86_64 и qemu-img)
  — UEFI-прошивку OVMF (edk2-ovmf / ovmf)
  — себя добавь в группу kvm, если /dev/kvm недоступен на запись
EOF
      ;;
  esac
}

# ----------------------------- download -------------------------------------
cmd_download() {
  have curl || die "нужен curl (sudo pacman -S curl)"
  mkdir -p "$WORKDIR"
  cd "$WORKDIR"

  # 1. Уже есть собранный ISO?
  if [ -f "$ISO_NAME" ]; then
    if verify_against "${ISO_NAME}-SHA256" "$ISO_NAME" >/dev/null 2>&1; then
      info "ISO уже скачан и проверен: ${WORKDIR}/${ISO_NAME}"
      return 0
    fi
    warn "есть файл ${ISO_NAME}, но сумма не сошлась — перекачиваем"
    rm -f "$ISO_NAME"
  fi

  # 2. Файлы из локального каталога?
  if [ -n "$SRC_DIR" ]; then
    info "копирую файлы из ${SRC_DIR}"
    for f in "$SRC_DIR/${ISO_NAME}" "$SRC_DIR/${ISO_NAME}-SHA256" "$SRC_DIR/${ISO_NAME}.parts-SHA256"; do
      [ -f "$f" ] && cp -f "$f" "$WORKDIR/" || true
    done
    for f in "$SRC_DIR/${ISO_NAME}".part-*; do
      [ -f "$f" ] && cp -f "$f" "$WORKDIR/" || true
    done
  fi

  # 3. Целый ISO или частями?
  local parts_mode=0
  if [ ! -f "${ISO_NAME}.parts-SHA256" ]; then
    info "проверяю, выложен ли ISO частями…"
    if fetch "$BASE_URL/${ISO_NAME}.parts-SHA256" "${ISO_NAME}.parts-SHA256" 2>/dev/null; then
      parts_mode=1
    else
      rm -f "${ISO_NAME}.parts-SHA256"
      warn "частей нет — качаю ISO целиком"
    fi
  else
    parts_mode=1
  fi

  if [ "$parts_mode" = 1 ]; then
    local -a parts=()
    while read -r _hash name; do
      if [ -n "${name:-}" ]; then parts+=("$(basename "$name")"); fi
    done < "${ISO_NAME}.parts-SHA256"
    [ "${#parts[@]}" -gt 0 ] || die "не удалось прочитать список частей"

    info "частей: ${#parts[@]}, качаю с докачкой (это ~4 ГБ, можно прервать и продолжить)"
    local p
    for p in "${parts[@]}"; do
      if [ -f "$p" ] && sha256sum "$p" 2>/dev/null | awk '{print $1}' | grep -q .; then
        info "уже скачано: $p"
        continue
      fi
      info "качаю $p"
      fetch "$BASE_URL/$p" "$p" || die "не удалось скачать $p (проверь интернет и запусти снова — докачает)"
    done

    info "проверяю части по контрольным суммам…"
    verify_parts || die "части повреждены. Удали битые и запусти снова: rm -f ${WORKDIR}/${ISO_NAME}.part-*"

    info "собираю ISO из ${#parts[@]} частей…"
    : > "$ISO_NAME"
    for p in "${parts[@]}"; do cat "$p" >> "$ISO_NAME"; done
  else
    info "качаю ${ISO_NAME} (~4 ГБ, можно прервать и продолжить)"
    fetch "$BASE_URL/${ISO_NAME}" "$ISO_NAME" || die "не удалось скачать ISO"
  fi

  # 4. Итоговая проверка
  if ! fetch "$BASE_URL/${ISO_NAME}-SHA256" "${ISO_NAME}-SHA256" 2>/dev/null; then
    warn "в релизе нет файла суммы для целого ISO — пропускаю проверку"
  fi
  if [ -f "${ISO_NAME}-SHA256" ]; then
    verify_against "${ISO_NAME}-SHA256" "$ISO_NAME" "$ISO_NAME" \
      || die "ISO собран неверно. Запусти: rm -f ${WORKDIR}/${ISO_NAME}*  и повтори команду"
  fi

  ls -lh "$WORKDIR/$ISO_NAME"
  info "готово: ${WORKDIR}/${ISO_NAME}"
}

# ----------------------------- run ------------------------------------------

find_ovmf() {
  local c
  for c in \
    /usr/share/edk2/x64/OVMF_CODE.4m.fd \
    /usr/share/edk2/x64/OVMF_CODE.fd \
    /usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
    /usr/share/OVMF/OVMF_CODE_4M.fd \
    /usr/share/OVMF/OVMF_CODE.fd \
    /usr/share/qemu/OVMF_CODE.fd
  do
    if [ -f "$c" ]; then OVMF_CODE="$c"; break; fi
  done
  local v
  for v in \
    /usr/share/edk2/x64/OVMF_VARS.4m.fd \
    /usr/share/edk2/x64/OVMF_VARS.fd \
    /usr/share/edk2-ovmf/x64/OVMF_VARS.fd \
    /usr/share/OVMF/OVMF_VARS_4M.fd \
    /usr/share/OVMF/OVMF_VARS.fd \
    /usr/share/qemu/OVMF_VARS.fd
  do
    if [ -f "$v" ]; then OVMF_VARS="$v"; break; fi
  done
  # Функция обязана вернуть успех: иначе из-за `set -e` скрипт молча завершится,
  # когда OVMF не найден (это допустимый сценарий — тогда грузимся в режиме BIOS).
  return 0
}

cmd_run() {
  have qemu-system-x86_64 || die "QEMU не установлен. Запусти: $(basename "$0") deps"

  # 1. ISO
  if [ -z "$ISO_PATH" ]; then
    ISO_PATH="$WORKDIR/$ISO_NAME"
  fi
  [ -f "$ISO_PATH" ] || die "не нашёл ISO: ${ISO_PATH}
Сначала скачай: $(basename "$0") download
Или укажи готовый: $(basename "$0") run --iso /путь/к/framz-os-1.0.iso"
  ISO_PATH="$(readlink -f "$ISO_PATH")"
  info "ISO: $ISO_PATH ($(du -h "$ISO_PATH" | cut -f1))"

  mkdir -p "$WORKDIR"
  local DISK_PATH="$WORKDIR/framz.qcow2"

  # 2. Аппаратное ускорение
  local ACCEL="kvm" CPU_MODEL="host"
  if [ "$USE_KVM" = 1 ]; then
    if [ ! -e /dev/kvm ]; then
      cat >&2 <<EOF
${c_red}✖${c_off} Нет /dev/kvm — виртуализация выключена или недоступна.

Что делать (по порядку):
  1) включи VT-x / AMD-V (SVM) в BIOS/UEFI материнской платы;
  2) добавь себя в группу kvm и войди заново:
       sudo usermod -aG kvm "\$USER"
  3) проверь: ls -l /dev/kvm   → crw-rw---- root kvm
  4) если хочешь всё равно попробовать (ОЧЕНЬ медленно): --no-kvm
EOF
      die "запуск отменён"
    fi
    if [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; then
      warn "нет прав на /dev/kvm — добавь себя в группу kvm: sudo usermod -aG kvm \"$USER\" (и войди заново)"
      die "запуск отменён"
    fi
    have qemu-img || die "не найден qemu-img (пакет qemu-desktop / qemu-utils)"
  else
    ACCEL="tcg"; CPU_MODEL="max"
    warn "режим без ускорения: установка системы займёт часы. Только для проверки."
  fi

  # 3. Виртуальный диск
  if [ ! -f "$DISK_PATH" ]; then
    info "создаю виртуальный диск ${DISK_GB} ГБ: $DISK_PATH"
    qemu-img create -f qcow2 "$DISK_PATH" "${DISK_GB}G" >/dev/null
  else
    info "использую существующий диск: $DISK_PATH ($(du -h "$DISK_PATH" | cut -f1))"
  fi

  # 4. Прошивка UEFI
  OVMF_CODE=""; OVMF_VARS=""
  find_ovmf
  local -a fw=()
  if [ -n "$OVMF_CODE" ] && [ -n "$OVMF_VARS" ]; then
    local VARS_COPY="$WORKDIR/OVMF_VARS.fd"
    [ -f "$VARS_COPY" ] || cp -f "$OVMF_VARS" "$VARS_COPY"
    fw+=( -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE" )
    fw+=( -drive "if=pflash,format=raw,file=$VARS_COPY" )
    info "прошивка UEFI: $(basename "$OVMF_CODE") (Secure Boot выключен — ISO пока не подписан)"
  else
    warn "OVMF не найден — загружаюсь в режиме BIOS (тоже должно работать)"
  fi

  # 5. Собираем команду
  local -a args=(
    -name "$VM_NAME"
    -machine q35
    -accel "$ACCEL"
    -cpu "$CPU_MODEL"
    -smp "$CPUS" -m "$MEMORY"
    "${fw[@]}"
    -drive "file=$DISK_PATH,if=virtio,format=qcow2,cache=writeback"
    -drive "file=$ISO_PATH,media=cdrom,readonly=on"
    -boot "order=${BOOT_ORDER},menu=on"
    -device qemu-xhci -device usb-tablet
    -netdev "user,id=n0" -device virtio-net-pci,netdev=n0
    -object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0
    -rtc base=localtime
  )
  if [ "$GL" = 1 ]; then
    args+=( -device virtio-vga-gl -display "${DISPLAY_BACKEND},gl=on" )
  else
    args+=( -device virtio-vga -display "$DISPLAY_BACKEND" )
  fi
  if [ "$SOUND" = 1 ]; then
    args+=( -audiodev pipewire,id=snd0 -device ich9-intel-hda -device hda-duplex,audiodev=snd0 )
  fi

  cat <<EOF

${c_dim}Команда запуска:${c_off}
  qemu-system-x86_64 ${args[*]}

${c_dim}Что делать в окне виртуалки:${c_off}
  1. Загрузится установщик Fedora в оформлении Kinoite.
  2. Язык → диск (выбрать наш 40-гиговый virtio-диск, «автоматическая разметка»)
     → создать пользователя (поставь галочку «сделать администратором») → «Начать установку».
  3. Установка 10–20 минут. Затем «Перезагрузить».
  4. После перезагрузки система загрузится уже с диска — это и есть FRAMZ OS.
  5. Кнопку мыши можно «отдать» системе: Ctrl+Alt+G, закрыть окно — Ctrl+Alt+F.

EOF
  exec qemu-system-x86_64 "${args[@]}"
}

# ----------------------------- clean ----------------------------------------
cmd_clean() {
  [ -d "$WORKDIR" ] || { info "нечего удалять: $WORKDIR"; return 0; }
  printf 'Удалить всё в %s (ISO, части, виртуальный диск)? [y/N] ' "$WORKDIR"
  read -r answer
  case "$answer" in
    y|Y|yes|YES) rm -rf "$WORKDIR"; info "удалено: $WORKDIR" ;;
    *) info "отменено" ;;
  esac
}

# ----------------------------- разбор аргументов ----------------------------
[ "$#" -gt 0 ] || { usage; exit 1; }
CMD="$1"; shift

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir)        WORKDIR="$2"; shift 2 ;;
    --iso)        ISO_PATH="$2"; shift 2 ;;
    --src)        SRC_DIR="$2"; shift 2 ;;
    --memory)     MEMORY="$2"; shift 2 ;;
    --cpus)       CPUS="$2"; shift 2 ;;
    --disk)       DISK_GB="$2"; shift 2 ;;
    --display)    DISPLAY_BACKEND="$2"; shift 2 ;;
    --boot)       BOOT_ORDER="$2"; shift 2 ;;
    --gl)         GL=1; shift ;;
    --sound)      SOUND=1; shift ;;
    --no-kvm)     USE_KVM=0; shift ;;
    -h|--help)    usage; exit 0 ;;
    *)            die "неизвестная опция: $1 (см. --help)" ;;
  esac
done

case "$CMD" in
  deps)     cmd_deps ;;
  download) cmd_download ;;
  run)      cmd_run ;;
  all)      cmd_download; cmd_run ;;
  clean)    cmd_clean ;;
  help|-h|--help) usage ;;
  *)        usage; die "неизвестная команда: $CMD" ;;
esac
