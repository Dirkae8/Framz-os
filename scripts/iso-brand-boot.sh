#!/usr/bin/env bash
# FRAMZ OS — фирменное меню загрузки самого ISO.
#
# Что делает: берёт готовый ISO и заменяет в нём меню GRUB (загрузка UEFI) на наше —
# русские и английские пункты, тёмный фон, знак FRAMZ, время ожидания.
# Ядро, initrd и сами команды загрузки не трогаются: меняются только подписи пунктов
# и оформление, поэтому шанс сломать загрузку минимален.
#
# Запасной вариант: если xorriso не справился, исходный ISO остаётся как был.
#
# Использование: bash scripts/iso-brand-boot.sh ISO
set -uo pipefail

ISO="${1:?укажи путь к ISO}"
[ -f "${ISO}" ] || { echo "нет файла: ${ISO}"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }
have xorriso || { echo "нет xorriso — меню загрузки не меняю"; exit 0; }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# ── 1. Достаём текущее меню и список файлов ─────────────────────────────────
isoinfo -f -i "${ISO}" 2>/dev/null | tr -d '\r' > "${WORK}/list.txt"
find_iso_path() { # $1 — регулярное выражение для нормализованного пути
  sed 's/;[0-9]*$//' "${WORK}/list.txt" | tr '[:upper:]' '[:lower:]' | nl -ba \
    | grep -E "$1" | head -1 | awk '{print $1}'
}

MENUS=()
for pattern in '/efi/boot/grub\.cfg$' '/boot/grub2/grub\.cfg$'; do
  n="$(find_iso_path "${pattern}")"
  [ -n "${n}" ] || continue
  path="$(sed -n "${n}p" "${WORK}/list.txt")"
  out="${WORK}/$(echo "${path}" | tr -d '/;' ).cfg"
  if isoinfo -i "${ISO}" -x "${path}" > "${out}" 2>/dev/null && [ -s "${out}" ]; then
    MENUS+=("${path}|${out}")
    echo "меню найдено: ${path} ($(wc -l < "${out}") строк)"
  fi
done

if [ "${#MENUS[@]}" -eq 0 ]; then
  echo "меню GRUB в ISO не найдено — оставляю как есть"
  exit 0
fi

# ── 2. Готовим наши версии меню ─────────────────────────────────────────────
# Заголовок меню: только оформление, ни одной команды загрузки мы не меняем
HEADER='# FRAMZ OS — меню загрузки (оформление наше; команды загрузки не изменялись)
set timeout=30
set default=0
set menu_color_normal=light-gray/black
set menu_color_highlight=black/light-gray
if [ -f /framz-boot/bg.png ]; then
  background_image /framz-boot/bg.png
fi
'

translate_titles() { # $1 — файл меню; меняем только подписи пунктов
  sed -E \
    -e "s/(menuentry|submenu) '([^']*[Ii]nstall[^']*)'/\1 'Установить FRAMZ OS'/" \
    -e "s/(menuentry|submenu) \"([^\"]*[Ii]nstall[^\"]*)\"/\1 \"Установить FRAMZ OS\"/" \
    -e "s/(menuentry|submenu) '([^']*[Tt]est[^']*)'/\1 'Проверить носитель'/" \
    -e "s/(menuentry|submenu) '([^']*[Tt]roubleshoot[^']*)'/\1 'Решение проблем'/" \
    -e "s/(menuentry|submenu) '([^']*[Ss]tart [^']*)'/\1 'Запустить FRAMZ OS без установки'/" \
    -e "s/(menuentry|submenu) '([^']*Fedora[^']*)'/\1 'FRAMZ OS'/" \
    "$1"
}

# ── 3. Пересобираем ISO с нашими меню и фоном ───────────────────────────────
OUT="${ISO}.framz"
ARGS=()
for entry in "${MENUS[@]}"; do
  iso_path="${entry%%|*}"
  src="${entry##*|}"
  { printf '%s\n' "${HEADER}"; translate_titles "${src}"; } > "${src}.framz"
  ARGS+=(-map "${src}.framz" "${iso_path}")
done

# Наш фон для меню (берём уже готовую картинку из темы загрузчика)
BG="files/system/usr/share/grub/themes/framz/background.png"
if [ -f "${BG}" ]; then
  ARGS+=(-map "${BG}" "/framz-boot/bg.png")
  echo "фон меню добавлен: ${BG}"
fi

if xorriso -indev "${ISO}" -outdev "${OUT}" \
     -boot_image any replay \
     "${ARGS[@]}" \
     -volid FRAMZ_OS_1 2>"${WORK}/xorriso.err"
then
  if [ -s "${OUT}" ] && [ "$(stat -c%s "${OUT}")" -gt 1000000000 ]; then
    mv -f "${OUT}" "${ISO}"
    echo "меню загрузки обновлено: пункты и фон FRAMZ"
  else
    echo "пересобранный ISO подозрительного размера — оставляю исходный"; rm -f "${OUT}"
  fi
else
  echo "xorriso не справился — оставляю исходный ISO. Вот что сказал:"
  tail -5 "${WORK}/xorriso.err"
  rm -f "${OUT}"
fi

exit 0
