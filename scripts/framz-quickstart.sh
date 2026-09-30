#!/usr/bin/env bash
#
# FRAMZ OS — быстрый запуск на Garuda / Arch «одной командой».
#
# Что делает по шагам (и объясняет каждый шаг человеческими словами):
#   1. проверяет, что это Arch-подобная система и есть базовые утилиты
#   2. ставит виртуалку (QEMU) и UEFI-прошивку, если их нет
#   3. даёт доступ к аппаратному ускорению (/dev/kvm)
#   4. скачивает ISO FRAMZ OS и проверяет контрольные суммы
#   5. запускает виртуальную машину — дальше только установщик в окне
#
# Примеры:
#   bash framz-quickstart.sh                  # всё автоматически
#   bash framz-quickstart.sh --dry-run        # скачать и подготовить, но не запускать
#   bash framz-quickstart.sh --download-only  # только скачать ISO
#   bash framz-quickstart.sh --memory 8192 --cpus 6 --gl
#
set -euo pipefail

# ------------------------------ параметры -----------------------------------
WORKDIR="${FRAMZ_DIR:-$HOME/framz}"
# Скрипт запуска берём из релиза: он всегда соответствует выложенному ISO.
RAW_URL="${FRAMZ_RAW_URL:-https://github.com/Dirkae8/Framz-os/releases/download/${FRAMZ_RELEASE_TAG:-v1.0}}"
EDITION="base"
ASSUME_YES=0
SKIP_DEPS=0
DRY_RUN=0
DOWNLOAD_ONLY=0
ALLOW_NO_KVM=0
PASSTHRU=()      # флаги, которые передаём скрипту запуска (--gl, --sound, --memory ...)

c_red=$'\033[31m'; c_yel=$'\033[33m'; c_grn=$'\033[32m'; c_blu=$'\033[36m'
c_dim=$'\033[2m'; c_bold=$'\033[1m'; c_off=$'\033[0m'
step()  { printf '\n%s\n' "${c_bold}${c_blu}═══ $* ═══${c_off}"; }
info()  { printf '%s\n' "${c_grn}▸${c_off} $*"; }
warn()  { printf '%s\n' "${c_yel}!${c_off} $*" >&2; }
die()   { printf '%s\n' "${c_red}✖${c_off} $*" >&2; exit 1; }
have()  { command -v "$1" >/dev/null 2>&1; }

# Заглушки для тестов: FRAMZ_TEST_PREFIX=/tmp/stub добавляет каталог в PATH
[ -n "${FRAMZ_TEST_PREFIX:-}" ] && PATH="$FRAMZ_TEST_PREFIX:$PATH"

usage() {
  cat <<'EOF'
FRAMZ OS — быстрый запуск на Garuda (одной командой)

Использование: bash framz-quickstart.sh [опции]

Опции:
  --dir DIR        куда качать ISO и хранить диск ВМ (по умолчанию ~/framz)
  --yes            не задавать вопросов (для автоматического запуска)
  --skip-deps      не ставить пакеты (если QEMU уже установлен)
  --dry-run        подготовить и скачать, но НЕ запускать виртуалку
  --download-only  только скачать ISO и проверить суммы
  --allow-no-kvm   разрешить запуск без аппаратного ускорения (ОЧЕНЬ медленно)
  --memory МБ      памяти для ВМ        (по умолчанию 6144)
  --cpus N         ядер для ВМ          (по умолчанию 4)
  --disk ГБ        размер диска ВМ      (по умолчанию 40)
  --gl             включить 3D-ускорение
  --sound          включить звук в ВМ (нужен qemu-audio-pipewire)
  --edition X      редакция: base (по умолчанию) | nvidia | studio
  --iso FILE       использовать готовый ISO по пути
  -h, --help       эта справка
EOF
}

# ------------------------- разбор аргументов ---------------------------------
[ "$#" -gt 0 ] && while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir)           WORKDIR="$2"; shift 2 ;;
    --edition)       EDITION="$2"; shift 2 ;;
    --yes|-y)        ASSUME_YES=1; shift ;;
    --skip-deps)     SKIP_DEPS=1; shift ;;
    --dry-run)       DRY_RUN=1; shift ;;
    --download-only) DOWNLOAD_ONLY=1; shift ;;
    --allow-no-kvm)  ALLOW_NO_KVM=1; shift ;;
    --sound)         FRAMZ_SOUND=1; PASSTHRU+=(--sound); shift ;;
    --gl)            PASSTHRU+=(--gl); shift ;;
    --memory)        PASSTHRU+=(--memory "$2"); shift 2 ;;
    --cpus)          PASSTHRU+=(--cpus "$2"); shift 2 ;;
    --disk)          PASSTHRU+=(--disk "$2"); shift 2 ;;
    --iso)           FRAMZ_ISO_PATH="$2"; shift 2 ;;
    -h|--help)       usage; exit 0 ;;
    *)               usage; die "неизвестная опция: $1" ;;
  esac
done
FRAMZ_SOUND="${FRAMZ_SOUND:-0}"

# --------------------------- шаг 1: проверки ---------------------------------
step "ШАГ 1 из 6 — проверяю систему"
[ "$(uname -s)" = "Linux" ] || die "нужен Linux (у тебя $(uname -s)). На Windows/macOS смотри docs/INSTALL-ON-PC.md"

DISTRO_ID=""
if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  DISTRO_ID="${ID:-}"
fi
DISTRO_ID="${FRAMZ_OS_ID:-$DISTRO_ID}"     # FRAMZ_OS_ID — для тестов
info "система: ${PRETTY_NAME:-$(uname -o)} (id=$DISTRO_ID)"

case "$DISTRO_ID" in
  arch|garuda|garuda-linux|manjaro|endeavouros|cachyos|artix|arcolinux|rebornos)
    info "это Arch-подобная система — путь установки известен (pacman)" ;;
  *)
    warn "система не похожа на Arch/Garuda (id=${DISTRO_ID:-неизвестно})"
    warn "сама виртуалка (QEMU) работать будет, но автопостановка пакетов — только для Arch."
    warn "поставь QEMU и OVMF сам, либо запусти только скачивание: --download-only"
    SKIP_DEPS=1
    ;;
esac

for c in curl; do have "$c" || die "не найдена утилита $c — установи её (sudo pacman -S $c)"; done
info "curl на месте"

mkdir -p "$WORKDIR"
info "рабочая папка: $WORKDIR (здесь будут ISO и виртуальный диск)"

# --------------------------- шаг 2: пакеты -----------------------------------
step "ШАГ 2 из 6 — виртуалка (QEMU) и UEFI-прошивка"
if [ "$SKIP_DEPS" = 1 ]; then
  info "пропускаю установку пакетов"
elif [ "$DRY_RUN" = 1 ] && have qemu-system-x86_64; then
  info "QEMU уже установлен — ничего ставить не нужно"
else
  PKGS=(qemu-desktop edk2-ovmf)
  [ "${FRAMZ_SOUND:-0}" = 1 ] && PKGS+=(qemu-audio-pipewire)
  MISSING=()
  for p in "${PKGS[@]}"; do
    if have pacman && pacman -Qi "$p" >/dev/null 2>&1; then
      info "уже установлен: $p"
    else
      MISSING+=("$p")
    fi
  done
  if [ "${#MISSING[@]}" -eq 0 ]; then
    info "все нужные пакеты уже есть"
  else
    info "нужно поставить: ${MISSING[*]}"
    if [ "$DRY_RUN" = 1 ]; then
      warn "режим --dry-run: пакеты не ставлю (запусти команду без --dry-run)"
    else
      if [ "$ASSUME_YES" != 1 ]; then
        printf 'Поставить сейчас? [Y/n] '
        read -r ans
        case "$ans" in n|N|no|НЕТ|нет) die "остановлено. Поставь вручную: sudo pacman -S --needed ${MISSING[*]}" ;; esac
      fi
      have sudo || die "нет sudo — поставь пакеты от root: pacman -S --needed ${MISSING[*]}"
      info "свободное место в / (нужно ~8 ГБ):"
      df -h / | tail -1
      sudo pacman -S --needed --noconfirm "${MISSING[@]}" \
        || die "не удалось поставить пакеты. Попробуй сначала: garuda-update"
      info "пакеты установлены"
    fi
  fi
fi

# ------------------------- шаг 3: /dev/kvm -----------------------------------
step "ШАГ 3 из 6 — аппаратное ускорение (/dev/kvm)"
KVM_OK=0
if [ -e /dev/kvm ]; then
  if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    KVM_OK=1
    info "доступ к /dev/kvm есть — виртуалка будет работать быстро"
  else
    warn "есть /dev/kvm, но у тебя нет прав на него"
    if [ "$DRY_RUN" != 1 ]; then
      if have sudo; then
        info "даю доступ двумя способами: сразу (ACL) и навсегда (группа kvm)"
        sudo usermod -aG kvm "$USER" 2>/dev/null || true
        if have setfacl; then sudo setfacl -m "u:$USER:rw" /dev/kvm 2>/dev/null || true; fi
        if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
          KVM_OK=1
          info "доступ выдан (после перезагрузки правило сохранится уже через группу kvm)"
        fi
      fi
    fi
    [ "$KVM_OK" = 1 ] || warn "не получилось выдать доступ: sudo usermod -aG kvm \"$USER\" и войти заново"
  fi
else
  warn "/dev/kvm отсутствует — в BIOS/UEFI выключена виртуализация (VT-x / AMD-V / SVM)"
fi

if [ "$KVM_OK" != 1 ]; then
  cat >&2 <<EOF
${c_yel}Что это значит:${c_off} виртуалка запустится, но без аппаратного ускорения —
установка системы может занять часы вместо 15 минут.

${c_bold}Как включить (рекомендую):${c_off}
  1) войди в BIOS/UEFI (обычно Del или F2) и включи виртуализацию:
     Intel → «Intel Virtualization Technology (VT-x)»
     AMD   → «SVM Mode» / «AMD-V»
  2) сохрани и выйди (F10)
  3) если система уже запущена: sudo usermod -aG kvm "\$USER", затем выйди и войди заново

${c_dim}Продолжить без ускорения можно так: --allow-no-kvm${c_off}
EOF
  if [ "$ALLOW_NO_KVM" != 1 ] && [ "$DRY_RUN" != 1 ]; then
    die "остановлено: сначала включи виртуализацию (или запусти с --allow-no-kvm)"
  fi
fi

# ------------------ шаг 4: скрипт запуска и скачивание -----------------------
step "ШАГ 4 из 6 — ISO FRAMZ OS"
VM_SH="$WORKDIR/framz-vm.sh"
if [ -f "$VM_SH" ]; then
  info "скрипт запуска уже есть: $VM_SH"
else
  info "скачиваю вспомогательный скрипт запуска…"
  if [ "$DRY_RUN" = 1 ] && [ -n "${FRAMZ_BASE_URL:-}" ]; then
    info "(в тестовом режиме скрипт не скачиваю)"
  else
    curl -fsSL -o "$VM_SH" "$RAW_URL/scripts/framz-vm.sh" \
      || die "не удалось скачать $RAW_URL/scripts/framz-vm.sh (проверь интернет)"
  fi
  chmod +x "$VM_SH" 2>/dev/null || true
fi

case "$EDITION" in
  base|"")     ISO_FILE="framz-os-1.0.iso" ;;
  nvidia)      ISO_FILE="framz-os-1.0-nvidia.iso" ;;
  studio|full) ISO_FILE="framz-os-1.0-studio.iso" ;;
  *)           die "неизвестная редакция: $EDITION (доступно: base, nvidia, studio)" ;;
esac
info "редакция: $EDITION → файл $ISO_FILE"

ISO_PATH="${FRAMZ_ISO_PATH:-}"
[ -n "$ISO_PATH" ] || ISO_PATH="$WORKDIR/$ISO_FILE"

if [ -f "$ISO_PATH" ]; then
  info "ISO уже скачан: $ISO_PATH ($(du -h "$ISO_PATH" | cut -f1))"
else
  cat <<EOF

${c_dim}Сейчас скачается примерно 4,3 ГБ (ISO выложен тремя частями по 1,8 ГБ).
Это самая долгая часть — зависит от скорости интернета. Можно прервать (Ctrl+C)
и запустить команду снова: скачивание продолжится с места обрыва.${c_off}
EOF
  if [ "$DRY_RUN" = 1 ] && [ -n "${FRAMZ_BASE_URL:-}" ]; then
    info "(тестовый режим: пропускаю скачивание)"
  else
    bash "$VM_SH" download --dir "$WORKDIR" --edition "$EDITION" || die "не удалось скачать ISO (см. сообщение выше)"
  fi
fi

step "ШАГ 5 из 6 — проверка контрольной суммы"
if [ -f "$ISO_PATH" ]; then
  if ! bash "$VM_SH" verify --iso "$ISO_PATH" --dir "$WORKDIR" 2>/dev/null; then
    warn "проверка не прошла — пробую скачать заново"
    bash "$VM_SH" download --dir "$WORKDIR" \
      || die "ISO не проходит проверку — удали файлы в $WORKDIR и запусти снова"
  fi
else
  warn "ISO пока нет — пропускаю (скачается при следующем запуске)"
fi

if [ "$DOWNLOAD_ONLY" = 1 ]; then
  step "ГОТОВО (только скачивание)"
  info "ISO: $ISO_PATH"
  info "Запустить виртуалку позже: bash $WORKDIR/framz-vm.sh run --dir $WORKDIR --edition $EDITION"
  exit 0
fi

# ---------------------------- шаг 6: запуск ----------------------------------
step "ШАГ 6 из 6 — запускаю виртуальную машину"
if [ "$DRY_RUN" = 1 ]; then
  info "режим --dry-run: виртуалку не запускаю"
  info "Чтобы запустить: bash $WORKDIR/framz-vm.sh run --dir $WORKDIR ${PASSTHRU[*]:-}"
  exit 0
fi

EXTRA=()
[ "$ALLOW_NO_KVM" = 1 ] && EXTRA+=(--no-kvm)   # не используем ${VAR:+...}: «0» тоже не пусто
bash "$VM_SH" run --dir "$WORKDIR" --iso "$ISO_PATH" \
  ${EXTRA[@]+"${EXTRA[@]}"} ${PASSTHRU[@]+"${PASSTHRU[@]}"}
