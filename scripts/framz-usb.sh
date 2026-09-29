#!/usr/bin/env bash
#
# FRAMZ OS — записать установочный ISO на USB-флешку.
#
# Скрипт с защитами: не даст записать на системный диск, на смонтированную флешку,
# на слишком маленькое устройство и на раздел вместо диска. Перед записью проверяет
# контрольную сумму ISO.
#
# Примеры:
#   scripts/framz-usb.sh list                                   # что подключено
#   scripts/framz-usb.sh write --device /dev/sdb                # записать ISO на флешку
#   scripts/framz-usb.sh write --device /dev/sdb --iso ~/framz/framz-os-1.0.iso --yes
#   scripts/framz-usb.sh verify --iso ~/framz/framz-os-1.0.iso  # только проверить ISO
#
set -euo pipefail

ISO_DEFAULT="${HOME}/framz/framz-os-1.0.iso"
DEVICE=""
ISO="$ISO_DEFAULT"
ASSUME_YES=0
SKIP_VERIFY=0
FORCE=0

c_red=$'\033[31m'; c_yel=$'\033[33m'; c_grn=$'\033[32m'; c_dim=$'\033[2m'; c_bold=$'\033[1m'; c_off=$'\033[0m'
info() { printf '%s\n' "${c_grn}▸${c_off} $*"; }
warn() { printf '%s\n' "${c_yel}!${c_off} $*" >&2; }
die()  { printf '%s\n' "${c_red}✖${c_off} $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
FRAMZ OS — запись ISO на флешку

Использование: framz-usb.sh <команда> [опции]

Команды:
  list                               показать подключённые диски и флешки
  write --device /dev/sdX            записать ISO на флешку  (ВСЁ НА ФЛЕШКЕ БУДЕТ СТЁРТО)
  verify                             проверить ISO по контрольной сумме
  help                               эта справка

Опции:
  --device /dev/sdX   флешка (обязательно для write)
  --iso FILE          путь к ISO            (по умолчанию ~/framz/framz-os-1.0.iso)
  --yes               не спрашивать подтверждение (для скриптов)
  --no-verify         пропустить проверку контрольной суммы (не советую)
  --force             разрешить запись на устройство с нестандартным типом
                      (например, /dev/loop* или внешний бокс без метки "диск")
EOF
}

# ------------------------------- list ---------------------------------------
cmd_list() {
  printf '%s\n' "${c_bold}Диски и флешки в системе:${c_off}"
  printf '%s\n' "${c_dim}NAME        РАЗМЕР  ТИП      СЪЁМН.  МОДЕЛЬ${c_off}"
  lsblk -dno NAME,SIZE,TYPE,RM,MODEL | while read -r name size type rm model; do
    local mark=" "
    [ "$rm" = "1" ] && mark="${c_grn}← флешка${c_off}"
    [ "$(echo "$name" | grep -cE '^(nvme|sd|vd|mmcblk)')" -gt 0 ] || continue
    printf '%-11s %-7s %-8s %-7s %s %b\n' "/dev/$name" "$size" "$type" \
      "$([ "$rm" = 1 ] && echo да || echo нет)" "$model" "$mark"
  done
  printf '\n%s\n' "${c_dim}Выбирай устройство КАК ДИСК, а не раздел: /dev/sdb, а не /dev/sdb1.${c_off}"
  printf '%s\n' "${c_dim}Проверить, какая из них системная: lsblk -o NAME,SIZE,MOUNTPOINTS,MODEL${c_off}"
}

# ------------------------------ verify --------------------------------------
do_verify() { # iso -> 0/1
  local iso="$1" sumfile="${1}-SHA256" expected actual
  if [ ! -f "$iso" ]; then warn "нет файла ISO: $iso"; return 1; fi
  if [ ! -f "$sumfile" ]; then
    warn "нет файла контрольной суммы: $sumfile — пропускаю проверку"
    return 2
  fi
  expected="$(awk 'NR==1{print $1}' "$sumfile")"
  actual="$(sha256sum "$iso" | awk '{print $1}')"
  if [ "$expected" = "$actual" ]; then
    info "сумма совпала: $(basename "$iso")"
    return 0
  fi
  warn "СУММА НЕ СОВПАЛА для $(basename "$iso")"
  warn "  ожидалось:  $expected"
  warn "  получилось: $actual"
  warn "Файл повреждён или релиз пересобирается прямо сейчас — скачай заново."
  return 1
}

cmd_verify() {
  local rc=0
  do_verify "$ISO" || rc=$?
  case "$rc" in
    0) info "ISO в порядке: $ISO" ;;
    2) info "контрольной суммы нет, но файл на месте: $(du -h "$ISO" | cut -f1)" ;;
    *) die "ISO не прошёл проверку — скачай заново" ;;
  esac
}

# ---------------------------- проверки устройства ---------------------------
check_device() {
  local dev="$1"

  [ -n "$dev" ] || die "не указано устройство. Пример: --device /dev/sdb (см. команду list)"
  [ -e "$dev" ] || die "устройство не найдено: $dev (подключи флешку и запусти list)"
  [ -b "$dev" ] || die "$dev — не блочное устройство (возможно, это файл или папка)"

  # 1) Отказ, если передан раздел, а не диск
  if [ "$(lsblk -ndo TYPE "$dev" 2>/dev/null | tr -d ' ')" = "part" ]; then
    local parent
    parent="$(lsblk -ndo PKNAME "$dev" 2>/dev/null | tr -d ' ')"
    die "$dev — это РАЗДЕЛ, а не диск. Нужен сам диск: ${parent:+/dev/$parent}"
  fi

  local type
  type="$(lsblk -ndo TYPE "$dev" 2>/dev/null | tr -d ' ')"
  if [ "$type" != "disk" ] && [ "$FORCE" != 1 ]; then
    die "$dev имеет тип '${type:-неизвестный}', а нужен именно диск (type=disk).
Если ты уверен, что это твоя флешка или внешний диск — повтори с флагом --force."
  fi
  [ "$FORCE" = 1 ] && [ "$type" != "disk" ] && warn "тип устройства '$type' — пишу из-за флага --force"

  # 2) Отказ, если это системный диск
  local root_src root_base
  root_src="$(findmnt -no SOURCE / 2>/dev/null || true)"
  root_base="/dev/$(lsblk -ndo PKNAME "$root_src" 2>/dev/null || true)"
  [ "$root_base" = "/dev/" ] && root_base="$root_src"
  local sys_sources=("$root_src" "$root_base")
  local mnt
  for mnt in /boot /boot/efi /home /var /; do
    local src
    src="$(findmnt -no SOURCE "$mnt" 2>/dev/null || true)"
    [ -n "$src" ] && sys_sources+=("$src")
  done
  local s
  for s in "${sys_sources[@]}"; do
    local base
    base="$(lsblk -ndo PKNAME "$s" 2>/dev/null || true)"
    base="${base:+/dev/$base}"
    if [ "$s" = "$dev" ] || [ "$base" = "$dev" ]; then
      die "$dev — СИСТЕМНЫЙ диск (на нём: $s). Запись уничтожит твою систему. Выбери флешку."
    fi
  done
  # swap на этом устройстве — тоже стоп
  if swapon --show=NAME --noheadings 2>/dev/null | grep -q "^${dev}"; then
    die "$dev используется как swap. Сначала выключи: sudo swapoff ${dev}*"
  fi

  # 3) Отказ, если флешка смонтирована
  local mounts
  mounts="$(lsblk -nro MOUNTPOINTS "$dev" 2>/dev/null | grep -v '^$' || true)"
  if [ -n "$mounts" ]; then
    die "$dev смонтирован ($(echo "$mounts" | tr '\n' ' ')). Отмонтируй: sudo umount ${dev}* — и повтори."
  fi

  # 4) Размер: флешка должна быть не меньше ISO
  local iso_bytes dev_bytes
  iso_bytes="$(stat -c%s "$ISO")"
  dev_bytes="$(lsblk -bdno SIZE "$dev" | tr -d ' ')"
  if [ "$dev_bytes" -lt "$iso_bytes" ]; then
    die "$(awk -v d="$dev_bytes" -v i="$iso_bytes" 'BEGIN{
      if (i >= 1073741824) printf "флешка меньше ISO: %.1f ГБ против %.1f ГБ.", d/1073741824, i/1073741824;
      else printf "флешка меньше ISO: %.0f МБ против %.0f МБ.", d/1048576, i/1048576
      printf " Нужна флешка от 8 ГБ."
    }')"
  fi

  # 5) Пустая флешка или нет — предупреждение (не блокируем)
  local children
  children="$(lsblk -nro NAME "$dev" | tail -n +2 | grep -c . || true)"
  if [ "${children:-0}" -gt 0 ]; then
    warn "на устройстве уже есть разделы — они будут стёрты"
  fi
}

# ------------------------------- write --------------------------------------
cmd_write() {
  command -v lsblk >/dev/null || die "нужна утилита lsblk (пакет util-linux)"
  [ -f "$ISO" ] || die "нет файла ISO: $ISO
Сначала скачай: ~/framz-vm.sh download
Или укажи путь:  --iso /путь/к/framz-os-1.0.iso"

  info "ISO: $ISO ($(du -h "$ISO" | cut -f1))"
  if [ "$SKIP_VERIFY" = 1 ]; then
    warn "проверка контрольной суммы отключена (--no-verify)"
  else
    local vrc=0
    do_verify "$ISO" || vrc=$?
    case "$vrc" in
      0) ;;                                   # сумма совпала
      2) warn "суммы нет — пишу как есть (убедись, что ISO скачан полностью)" ;;
      *) die "проверь ISO, прежде чем писать на флешку" ;;
    esac
  fi

  check_device "$DEVICE"

  local model size
  model="$(lsblk -dno MODEL "$DEVICE" | sed 's/ *$//')"
  size="$(lsblk -dno SIZE "$DEVICE")"

  cat <<EOF

${c_bold}${c_red}ВНИМАНИЕ: всё содержимое устройства будет СТЁРТО.${c_off}

  Устройство : ${c_bold}${DEVICE}${c_off}  (${size}${model:+, $model})
  Файл       : $ISO
  Съёмное    : $(lsblk -dno RM "$DEVICE" | grep -q 1 && echo "да (флешка)" || echo "${c_yel}НЕТ — это может быть жёсткий диск!${c_off}")

EOF

  if [ "$ASSUME_YES" != 1 ]; then
    printf 'Чтобы продолжить, введи слово ЗАПИСАТЬ: '
    local answer
    read -r answer
    [ "$answer" = "ЗАПИСАТЬ" ] || die "отменено (ожидалось слово ЗАПИСАТЬ)"
  fi

  info "записываю… это занимает 3–10 минут, не выдёргивай флешку"
  sudo dd if="$ISO" of="$DEVICE" bs=4M status=progress conv=fsync
  sudo sync

  info "готово. Флешка записана."
  cat <<EOF

${c_bold}Дальше — установка на компьютер:${c_off}

  1. Выключи компьютер, вставь флешку.
  2. Включи и сразу жми клавишу входа в BIOS / меню загрузки
     (чаще всего: Del, F2, F10, F12, Esc — см. таблицу в docs/INSTALL-ON-PC.md).
  3. В BIOS: ${c_bold}выключи Secure Boot${c_off} (ISO пока не подписан), режим загрузки — UEFI.
  4. В меню загрузки выбери свою флешку (её имя обычно содержит название производителя).
  5. Дальше — установщик Fedora/Kinoite: язык, диск, пользователь. Полный разбор:
     docs/INSTALL-ON-PC.md

${c_dim}Флешку можно вынуть только после сообщения "готово" выше.${c_off}
EOF
}

# ----------------------------- разбор аргументов ----------------------------
[ "$#" -gt 0 ] || { usage; exit 1; }
CMD="$1"; shift

while [ "$#" -gt 0 ]; do
  case "$1" in
    --device)    DEVICE="$2"; shift 2 ;;
    --iso)       ISO="$2"; shift 2 ;;
    --yes|-y)    ASSUME_YES=1; shift ;;
    --no-verify) SKIP_VERIFY=1; shift ;;
    --force)     FORCE=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           die "неизвестная опция: $1 (см. --help)" ;;
  esac
done

case "$CMD" in
  list)   cmd_list ;;
  verify) cmd_verify ;;
  write)  cmd_write ;;
  help)   usage ;;
  *)      usage; die "неизвестная команда: $CMD" ;;
esac
