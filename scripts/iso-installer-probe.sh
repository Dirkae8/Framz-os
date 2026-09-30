#!/usr/bin/env bash
# FRAMZ OS — разбор среды установщика внутри ISO.
#
# Достаёт из ISO образ среды установщика (/images/install.img) и показывает:
#   · какие файлы оформления там лежат и куда указывают симлинки;
#   · подхватился ли наш стиль (ищем маркер FRAMZ-BRANDING);
#   · какие настройки установщика применились;
#   · где живёт веб-интерфейс установщика и откуда он берёт оформление.
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
paste -d'\t' "${WORK}/raw.txt" "${WORK}/norm.txt" > "${WORK}/pair.txt"

path_of() { awk -F'\t' -v want="$1" '$2 == want { print $1; exit }' "${WORK}/pair.txt"; }

ENV_IMG="$(path_of '/images/install.img')"
[ -n "${ENV_IMG}" ] || ENV_IMG="$(awk -F'\t' '$2 ~ /(^|\/)(install|squashfs)[^\/]*\.(img|squashfs)$/ { print $1; exit }' "${WORK}/pair.txt")"
[ -n "${ENV_IMG}" ] || { echo "образ среды установщика в ISO не найден"; exit 1; }
echo "образ среды: ${ENV_IMG}"

isoinfo -i "${ISO}" -x "${ENV_IMG}" > "${WORK}/install.img" 2>/dev/null
[ -s "${WORK}/install.img" ] || { echo "не удалось извлечь образ среды"; exit 1; }
echo "размер образа: $(( $(stat -c%s "${WORK}/install.img") / 1048576 )) МБ"
echo

unsquashfs -l "${WORK}/install.img" 2>/dev/null | tr -d '\r' > "${WORK}/list-raw.txt"
# В списке unsquashfs пути идут с префиксом squashfs-root/ — убираем его,
# иначе сравнение с путями внутри системы всегда даёт «нет файла».
sed 's#^squashfs-root/*##' "${WORK}/list-raw.txt" > "${WORK}/list.txt"
echo "--- содержимое среды (unsquashfs) ---"
echo "файлов: $(wc -l < "${WORK}/list.txt")"
echo

# В списке unsquashfs пути БЕЗ ведущего слэша — ищем по basename-виду
in_env() { grep -qx "$1" "${WORK}/list.txt" || grep -qx "/$1" "${WORK}/list.txt"; }

echo "--- где живёт веб-интерфейс установщика ---"
grep -E '^/usr/share/cockpit/[^/]*/(index\.html|manifest\.json)$' "${WORK}/list.txt" | head -10 || true
echo
echo "--- все файлы оформления в среде ---"
grep -E 'branding|/logo\.png$' "${WORK}/list.txt" | grep -v '^/usr/share/icons' | head -30 || true
echo
echo "--- символические ссылки, связанные с оформлением ---"
unsquashfs -ll "${WORK}/install.img" 2>/dev/null | tr -d '\r' | sed 's#squashfs-root/*##' | grep -E '^l.*(branding|cockpit)' | head -10 || true
echo

echo "--- подхватился ли НАШ стиль (ищем маркер FRAMZ-BRANDING) ---"
FOUND_OURS=0
for path in \
  usr/share/cockpit/static/branding.css \
  usr/share/cockpit/branding/framz/branding.css \
  usr/share/cockpit/branding/fedora/branding.css \
  usr/static/branding.css \
  usr/share/static/branding.css
do
  if in_env "${path}"; then
    if unsquashfs -cat "${WORK}/install.img" "${path}" 2>/dev/null | grep -q 'FRAMZ-BRANDING'; then
      echo "ЕСТЬ   наш стиль — /${path}"
      FOUND_OURS=1
    else
      echo "НЕТ    файл есть, но это НЕ наш стиль — /${path}"
    fi
  else
    echo "нет    файла нет — /${path}"
  fi
done
[ "${FOUND_OURS}" = "1" ] || echo "ВНИМАНИЕ: наш стиль в среду установщика не попал"
echo

echo "--- что подключает веб-интерфейс (строки со стилями) ---"
for html in $(grep -E '^/usr/share/cockpit/[^/]*/index\.html$' "${WORK}/list.txt" | head -2); do
  echo "    ${html}:"
  unsquashfs -cat "${WORK}/install.img" "${html#/}" 2>/dev/null | grep -i -E 'stylesheet|branding' | sed 's/^/       /' || true
done
echo

echo "--- настройки установщика ---"
for path in etc/anaconda/cockpit/conf.d/50-framz.conf etc/cockpit/conf.d/50-framz.conf; do
  if in_env "${path}"; then
    echo "ЕСТЬ   /${path}:"
    unsquashfs -cat "${WORK}/install.img" "${path}" 2>/dev/null | grep -v '^#' | grep -v '^$' | sed 's/^/       /'
  else
    echo "нет    /${path}"
  fi
done
echo

echo "--- какие стили задают цвет верхней полосы (из index.css среды) ---"
for css in $(grep -E '^/?usr/share/cockpit/[^/]*/index\.css$' "${WORK}/list.txt" | head -1); do
  echo "    файл: ${css#/}"
  unsquashfs -cat "${WORK}/install.img" "${css#/}" 2>/dev/null | tr '}' '}\n' \
    | grep -E 'radial-gradient|brand-default-light' | head -4 | cut -c1-240 | sed 's/^/       /'
done
echo
echo "--- имя системы в среде установщика ---"
unsquashfs -cat "${WORK}/install.img" etc/os-release 2>/dev/null | grep -E '^(NAME|PRETTY_NAME|VERSION_ID|VARIANT|ID)=' | sed 's/^/    /'
echo

echo "=== конец разбора ==="
exit 0
