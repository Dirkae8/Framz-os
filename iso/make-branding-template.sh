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
#
# Почему стиль кладётся в НЕСКОЛЬКО мест: установщик (Anaconda WebUI) берёт
# оформление как branding.css из Cockpit, причём путь в разных сборках разный —
# либо /usr/share/cockpit/static/branding.css (обычно симлинк), либо каталог
# брендинга по имени (fedora). Пишем свой файл во все разумные точки, а
# на симлинк — сначала разыменовываем и перезаписываем цель.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-${ROOT}/iso/build/framz-branding.tmpl}"
LOGO="${ROOT}/iso/branding/logo.png"
CSS_SRC="${ROOT}/iso/branding/branding.css"
mkdir -p "$(dirname "${OUT}")"

[ -f "${LOGO}" ] || { echo "нет файла: ${LOGO}" >&2; exit 1; }
[ -f "${CSS_SRC}" ] || { echo "нет файла: ${CSS_SRC}" >&2; exit 1; }

# ── Самодостаточный CSS: логотип вшиваем как data-URI ────────────────────────
LOGO_B64="$(base64 -w0 "${LOGO}")"
CSS_TMP="$(mktemp)"
trap 'rm -f "${CSS_TMP}"' EXIT
# Заменяем url("logo.png") на data-URI, чтобы файл работал с любого адреса
sed "s|url(\"logo.png\")|url(\"data:image/png;base64,${LOGO_B64}\")|" "${CSS_SRC}" > "${CSS_TMP}"
grep -q 'data:image/png;base64,' "${CSS_TMP}" || { echo "логотип не вшился в CSS" >&2; exit 1; }

css_b64="$(base64 -w0 "${CSS_TMP}")"
conf_b64="$(base64 -w0 "${ROOT}/iso/anaconda/cockpit-framz.conf")"
logo_b64="${LOGO_B64}"

# ── Пишем файлы ──────────────────────────────────────────────────────────────
# b64write <содержимое-b64> <путь-внутри-системы>
b64write() { printf 'runcmd bash -c "umask 022; printf %%s %s | base64 -d > ${root}%s"\n' "$1" "$2"; }
# b64write_link <содержимое-b64> <путь> — сначала снимаем симлинк, потом пишем файл
b64write_link() {
  printf 'runcmd bash -c "rm -f ${root}%s; umask 022; printf %%s %s | base64 -d > ${root}%s"\n' "$2" "$1" "$2"
}

{
  echo '<%page args="image_name"/>'
  echo ''
  echo '# FRAMZ OS: оформление установщика (генерируется iso/make-branding-template.sh)'
  echo '# Маркер проверки: FRAMZ-BRANDING-v2'
  echo 'mkdir usr/share/cockpit/branding/framz'
  echo 'mkdir usr/share/cockpit/branding/fedora'
  echo 'mkdir usr/share/cockpit/static'
  echo 'mkdir etc/anaconda/cockpit/conf.d'
  echo 'mkdir etc/cockpit/conf.d'
  echo ''
  echo '# 1. Наш каталог оформления'
  b64write "${css_b64}" '/usr/share/cockpit/branding/framz/branding.css'
  b64write "${logo_b64}" '/usr/share/cockpit/branding/framz/logo.png'
  echo ''
  echo '# 2. Перекрываем родное оформление Fedora (его и берёт установщик)'
  b64write_link "${css_b64}" '/usr/share/cockpit/branding/fedora/branding.css'
  b64write "${logo_b64}" '/usr/share/cockpit/branding/fedora/logo.png'
  echo ''
  echo '# 3. Разыменовываем симлинк оформления (если он есть) и перезаписываем цель:'
  echo '#    так оформление меняется даже если установщик берёт бренд по имени, а не по этому пути.'
  printf 'runcmd bash -c "t=$(readlink -f ${root}/usr/share/cockpit/static/branding.css 2>/dev/null || true); if [ -n \\"$t\\" ] && [ -f \\"$t\\" ]; then printf %%s %s | base64 -d > \\"$t\\"; fi; true"\n' "${css_b64}"
  echo ''
  echo '# 4. Сам путь, который подключает установщик (обычно симлинк — заменяем файлом)'
  b64write_link "${css_b64}" '/usr/share/cockpit/static/branding.css'
  echo ''
  echo '# 5. Настройки установщика (имя оформления и заголовок окна)'
  b64write "${conf_b64}" '/etc/anaconda/cockpit/conf.d/50-framz.conf'
  b64write "${conf_b64}" '/etc/cockpit/conf.d/50-framz.conf'
  echo ''
  echo 'runcmd bash -c "chmod -R a+rX ${root}/usr/share/cockpit/branding ${root}/usr/share/cockpit/static ${root}/etc/anaconda ${root}/etc/cockpit; true"'
} > "${OUT}"

echo "▸ шаблон брендинга готов: ${OUT} ($(wc -c < "${OUT}") байт)"
