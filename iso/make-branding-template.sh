#!/usr/bin/env bash
# FRAMZ OS — сборка брендинга установщика для lorax.
#
# Делает mako-шаблон из файлов в iso/branding и iso/anaconda, упаковывая их
# в base64: так русский текст и PNG не портятся при подстановке в шаблон.
#
# Использование:
#   bash iso/make-branding-template.sh [куда_положить.tmpl]
#
# Готовый шаблон передаётся сборщику ISO как ADDITIONAL_TEMPLATES.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-${ROOT}/iso/build/framz-branding.tmpl}"
mkdir -p "$(dirname "${OUT}")"

# Что и куда кладём внутри среды установщика
FILES=(
  "iso/branding/branding.css:/usr/share/cockpit/branding/framz/branding.css"
  "iso/branding/logo.png:/usr/share/cockpit/branding/framz/logo.png"
  "iso/anaconda/cockpit-framz.conf:/etc/anaconda/cockpit/conf.d/50-framz.conf"
)

{
  echo '<%page args="image_name"/>'
  echo ''
  echo '# FRAMZ OS: оформление установщика (генерируется iso/make-branding-template.sh)'
  echo '# Каталоги создаём заранее, чтобы не зависеть от состава пакетов.'
  echo 'mkdir usr/share/cockpit/branding/framz'
  echo 'mkdir etc/anaconda/cockpit/conf.d'
  echo ''
  for entry in "${FILES[@]}"; do
    src="${ROOT}/${entry%%:*}"
    dest="${entry##*:}"
    [ -f "${src}" ] || { echo "нет файла: ${src}" >&2; exit 1; }
    b64="$(base64 -w0 "${src}")"
    # Каталоги уже созданы командами mkdir выше, поэтому здесь только запись файла.
    # Кавычки внутри bash -c не нужны: пути без пробелов, а ${root} подставит mako.
    printf 'runcmd bash -c "umask 022; printf %%s %s | base64 -d > ${root}%s"\n' "${b64}" "${dest}"
  done
  echo ''
  echo 'runcmd bash -c "chmod -R a+rX ${root}/usr/share/cockpit/branding/framz ${root}/etc/anaconda"'
} > "${OUT}"

echo "▸ шаблон брендинга готов: ${OUT} ($(wc -c < "${OUT}") байт)"
