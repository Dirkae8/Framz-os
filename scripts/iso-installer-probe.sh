#!/usr/bin/env bash
# FRAMZ OS — разбор среды установщика внутри ISO.
#
# Достаёт из ISO образ среды установщика (/images/install.img) и показывает:
#   · какие файлы оформления там реально лежат и куда указывают симлинки;
#   · подхватился ли наш стиль (ищем маркер FRAMZ-BRANDING);
#   · какие настройки установщика применились;
#   · чем называется система в среде установщика.
#
# Нужен, чтобы проверять оформление по факту, а не по предположению.
# Ничего не меняет; печатает отчёт.
set -uo pipefail

ISO="${1:?укажи путь к ISO}"
[ -f "${ISO}" ] || { echo "нет файла: ${ISO}"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

have() { command -v "$1" >/dev/null 2>&1; }
for tool in isoinfo unsquashfs; do
  have "${tool}" || { echo "нет ${tool} — разбор невозможен"; exit 0; }
done

echo "=== FRAMZ OS — разбор среды установщика ==="
date -u +"время: %Y-%m-%d %H:%M UTC"
echo "файл: ${ISO}"
echo

# Список файлов ISO: raw (как есть) и norm (строчные, без «;1») — строки совпадают
isoinfo -f -i "${ISO}" 2>/dev/null | tr -d '\r' > "${WORK}/raw.txt"
sed 's/;[0-9]*$//' "${WORK}/raw.txt" | tr '[:upper:]' '[:lower:]' > "${WORK}/norm.txt"
rm -f "${WORK}/pair.txt"; paste -d'\t' "${WORK}/raw.txt" "${WORK}/norm.txt" > "${WORK}/pair.txt"

# path_of <нормализованный путь> → путь как он записан в ISO
path_of() { awk -F'\t' -v want="$1" '$2 == want { print $1; exit }' "${WORK}/pair.txt"; }

ENV_IMG="$(path_of '/images/install.img')"
if [ -z "${ENV_IMG}" ]; then
  ENV_IMG="$(awk -F'\t' '$2 ~ /\.(squashfs|img)$/ && $2 ~ /install/ { print $1; exit }' "${WORK}/pair.txt")"
fi
[ -n "${ENV_IMG}" ] || { echo "образ среды установщика в ISO не найден"; exit 1; }
echo "образ среды: ${ENV_IMG}"

isoinfo -i "${ISO}" -x "${ENV_IMG}" > "${WORK}/install.img" 2>/dev/null
[ -s "${WORK}/install.img" ] || { echo "не удалось извлечь образ среды"; exit 1; }
echo "размер образа: $(( $(stat -c%s "${WORK}/install.img") / 1048576 )) МБ"
echo

echo "--- содержимое среды (unsquashfs) ---"
unsquashfs -l "${WORK}/install.img" 2>/dev/null | tr -d '\r' > "${WORK}/list.txt"
echo "файлов: $(wc -l < "${WORK}/list.txt")"
echo

echo "--- оформление: что лежит в среде ---"
grep -E 'cockpit/(static|branding)' "${WORK}/list.txt" | head -30 || echo "(ничего не найдено)"
echo

echo "--- симлинки оформления (куда указывают) ---"
unsquashfs -ll "${WORK}/install.img" 2>/dev/null | tr -d '\r' | grep -E ' -> .*branding' | head -10 || echo "(симлинков нет)"
echo

echo "--- подхватился ли НАШ стиль ---"
FOUND_OURS=0
for path in \
  usr/share/cockpit/static/branding.css \
  usr/share/cockpit/branding/framz/branding.css \
  usr/share/cockpit/branding/fedora/branding.css
do
  if grep -qx "/${path}" "${WORK}/list.txt"; then
    if unsquashfs -cat "${WORK}/install.img" "${path}" 2>/dev/null | grep -q 'FRAMZ-BRANDING'; then
      echo "ЕСТЬ   стиль FRAMZ — ${path}"
      FOUND_OURS=1
    else
      echo "НЕТ    наш стиль не найден — ${path} (файл есть, маркера FRAMZ нет)"
    fi
  else
    echo "НЕТ    файла нет — ${path}"
  fi
done
[ "${FOUND_OURS}" = "1" ] || echo "ВНИМАНИЕ: наш стиль в среду установщика не попал"
echo

echo "--- настройки установщика ---"
for path in etc/anaconda/cockpit/conf.d/50-framz.conf etc/cockpit/conf.d/50-framz.conf; do
  if grep -qx "/${path}" "${WORK}/list.txt"; then
    echo "ЕСТЬ   ${path}:"
    unsquashfs -cat "${WORK}/install.img" "${path}" 2>/dev/null | grep -v '^#' | grep -v '^$' | sed 's/^/       /'
  else
    echo "НЕТ    ${path}"
  fi
done
echo

echo "--- имя системы в среде установщика ---"
unsquashfs -cat "${WORK}/install.img" etc/os-release 2>/dev/null | grep -E '^(NAME|PRETTY_NAME|VERSION_ID|VARIANT|ID)=' | sed 's/^/    /'
echo

echo "--- как установщик подключает оформление ---"
for path in usr/share/cockpit/anaconda/index.html usr/share/cockpit/anaconda-webui/index.html; do
  if grep -qx "/${path}" "${WORK}/list.txt"; then
    echo "    ${path}:"
    unsquashfs -cat "${WORK}/install.img" "${path}" 2>/dev/null | grep -i 'branding' | sed 's/^/       /'
  fi
done

echo
echo "=== конец разбора ==="
exit 0
