#!/usr/bin/env bash
# FRAMZ OS — самопроверка готового ISO.
#
# Что проверяет:
#   1) метку тома и параметры ISO;
#   2) файлы загрузки (ядро, initrd, загрузчики) — ищет их по смыслу, а не по точному пути
#      (в ISO 9660 имена в верхнем регистре и с «;1», поэтому список нормализуется);
#   3) среду установщика: находит squashfs-образ и внутри него — НАШ брендинг;
#   4) наш системный образ: находит OCI-blob-ы внутри ISO и в них — наши файлы;
#   5) печатает карту структуры ISO, чтобы отчёт читался глазами.
#
# Ничего не меняет и не падает: все замечания идут в отчёт.
set -uo pipefail

ISO="${1:?укажи путь к ISO}"
[ -f "${ISO}" ] || { echo "нет файла: ${ISO}"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
PROBLEMS=0
note() { echo "$@"; }
check() { if eval "$2"; then echo "ЕСТЬ   $1"; else echo "НЕТ    $1"; PROBLEMS=$((PROBLEMS + 1)); fi; }

have() { command -v "$1" >/dev/null 2>&1; }

echo "=== FRAMZ OS — самопроверка ISO ==="
date -u +"время: %Y-%m-%d %H:%M UTC"
echo "файл: ${ISO}"
echo "размер: $(stat -c%s "${ISO}" 2>/dev/null || echo '?') байт ($(( $(stat -c%s "${ISO}" 2>/dev/null || echo 0) / 1048576 )) МБ)"
echo

if ! have isoinfo; then
  echo "нет isoinfo (пакет genisoimage) — структурная проверка невозможна"
  exit 0
fi

# ── 1. Параметры ISO ─────────────────────────────────────────────────────────
echo "--- параметры ISO ---"
isoinfo -d -i "${ISO}" 2>&1 | grep -i -E "volume id|volume set id|system id|logical block size" || true
VOLID="$(isoinfo -d -i "${ISO}" 2>/dev/null | grep -i 'volume id' | sed 's/.*: //' | tr -d '\r')"
echo "метка тома: '${VOLID}'"
case "${VOLID}" in
  FRAMZ*) echo "ВЕРНО  метка содержит FRAMZ" ;;
  *)      echo "ВНИМАНИЕ метка не содержит FRAMZ (ожидали FRAMZ_OS_1)"; PROBLEMS=$((PROBLEMS + 1)) ;;
esac
echo

# ── 2. Список файлов (нормализуем: строчные буквы, без «;1») ─────────────────
RAW="${WORK}/raw.txt"
NORM="${WORK}/norm.txt"
isoinfo -f -i "${ISO}" 2>/dev/null | tr -d '\r' > "${RAW}"
sed 's/;[0-9]*$//' "${RAW}" | tr '[:upper:]' '[:lower:]' > "${NORM}"
paste -d'\t' "${RAW}" "${NORM}" > "${WORK}/pair.txt"
TOTAL="$(wc -l < "${NORM}")"

# path_of <нормализованный путь> → путь как записан в ISO (верхний регистр, «;1»)
path_of() { awk -F'\t' -v want="$1" '$2 == want { print $1; exit }' "${WORK}/pair.txt"; }
echo "всего файлов на ISO: ${TOTAL}"
echo

echo "--- карта структуры (два уровня) ---"
awk -F/ 'NF >= 2 && $2 != "" { print "/" $2 }' "${NORM}" | sort -u | while read -r d; do
  printf "%-28s файлов: %s\n" "${d}" "$(grep -c "^${d}/" "${NORM}")"
  awk -F/ -v d="${d}" '($0 ~ "^" d "/") && NF == 3 && $3 != "" { print "    " $3 }' "${NORM}" | sort -u | head -8
done
echo

# ── 3. Файлы загрузки — ищем по смыслу ───────────────────────────────────────
echo "--- файлы загрузки ---"
find_first() { grep -m1 -E "$1" "${NORM}" || true; }
KERNEL="$(find_first '/vmlinuz')"
INITRD="$(find_first '/initrd[^/]*\.img$')"
GRUB_UEFI="$(find_first '/efi/boot/(grub\.cfg|bootx64\.efi)$')"
ISOLINUX="$(find_first '/(isolinux|syslinux)/(isolinux|syslinux)\.(cfg|bin)$|/images/eltorito\.img$')"
TREEINFO="$(find_first '/\.treeinfo$')"
DISCINFO="$(find_first '/\.discinfo$')"
for pair in "ядро:${KERNEL}" "initrd:${INITRD}" "загрузчик UEFI:${GRUB_UEFI}" "загрузчик BIOS:${ISOLINUX}" ".treeinfo:${TREEINFO}" ".discinfo:${DISCINFO}"; do
  name="${pair%%:*}"; path="${pair#*:}"
  if [ -n "${path}" ]; then echo "ЕСТЬ   ${name} — ${path}"; else echo "НЕТ    ${name}"; PROBLEMS=$((PROBLEMS + 1)); fi
done
echo

# ── 3.1 Меню загрузки: наше ли оно ───────────────────────────────────────────
echo "--- меню загрузки ---"
MENU_FOUND=0
for menu_norm in '/efi/boot/grub.cfg' '/boot/grub2/grub.cfg'; do
  menu_path="$(path_of "${menu_norm}")"
  [ -n "${menu_path}" ] || continue
  isoinfo -i "${ISO}" -x "${menu_path}" > "${WORK}/menu.cfg" 2>/dev/null || continue
  echo "нашлось меню: ${menu_path}"
  if grep -q 'Установить FRAMZ OS' "${WORK}/menu.cfg"; then
    echo "ЕСТЬ   наши пункты (Установить FRAMZ OS)"
    MENU_FOUND=1
  fi
  grep -m1 'set timeout' "${WORK}/menu.cfg" | sed 's/^/       /' || true
  if grep -q 'framz-boot/bg.png' "${WORK}/menu.cfg"; then
    echo "ЕСТЬ   наш фон меню"
  fi
  if grep -q 'FRAMZ OS — меню загрузки' "${WORK}/menu.cfg"; then
    echo "ЕСТЬ   наша подпись меню"
  fi
done
if [ "${MENU_FOUND}" = "0" ]; then
  echo "нет    наши пункты в меню не найдены (меню осталось стандартным)"
  PROBLEMS=$((PROBLEMS + 1))
fi
echo

# ── 4. Среда установщика и наш брендинг в ней ────────────────────────────────
echo "--- среда установщика ---"
SQUASH="$(path_of '/images/install.img')"
[ -n "${SQUASH}" ] || SQUASH="$(awk -F'\t' '$2 ~ /\/(install|squashfs)[^\/]*\.(img|squashfs)$/ { print $1; exit }' "${WORK}/pair.txt")"
if [ -n "${SQUASH}" ]; then
  ISO_PATH="${SQUASH}"
  echo "образ среды: ${ISO_PATH}"
  if have unsquashfs; then
    echo "распаковываю список файлов среды…"
    isoinfo -i "${ISO}" -x "${ISO_PATH}" > "${WORK}/install.img" 2>/dev/null
    if [ -s "${WORK}/install.img" ]; then
      unsquashfs -l "${WORK}/install.img" 2>/dev/null | tr -d '\r' > "${WORK}/install-list.txt"
      echo "файлов в среде установщика: $(wc -l < "${WORK}/install-list.txt")"
      echo
      echo "--- НАШ БРЕНДИНГ в установщике ---"
      check "оформление: branding.css" "grep -q 'cockpit/branding/framz/branding.css' '${WORK}/install-list.txt'"
      check "знак FRAMZ: logo.png"     "grep -q 'cockpit/branding/framz/logo.png' '${WORK}/install-list.txt'"
      check "настройки установщика"    "grep -q 'anaconda/cockpit/conf.d/50-framz.conf' '${WORK}/install-list.txt'"
      echo
      echo "--- фрагмент нашего оформления ---"
      unsquashfs -cat "${WORK}/install.img" usr/share/cockpit/branding/framz/branding.css 2>/dev/null | head -8
      echo
      echo "--- настройки окна установщика ---"
      unsquashfs -cat "${WORK}/install.img" etc/anaconda/cockpit/conf.d/50-framz.conf 2>/dev/null | grep -v '^#' | grep -v '^$' | head -6
      echo
      echo "--- как называется система установщика ---"
      unsquashfs -cat "${WORK}/install.img" etc/os-release 2>/dev/null | grep -E '^(NAME|PRETTY_NAME|VERSION_ID)=' | head -4
    else
      echo "не удалось извлечь образ среды из ISO"
      PROBLEMS=$((PROBLEMS + 1))
    fi
  else
    echo "нет unsquashfs — пропускаю разбор среды установщика"
  fi
else
  echo "не нашёл squashfs-образ среды установщика в ISO"
  PROBLEMS=$((PROBLEMS + 1))
fi
echo

# ── 5. Наш системный образ (OCI-blob-ы) ──────────────────────────────────────
echo "--- наш системный образ внутри ISO ---"
BLOBS="$(grep -c '/blobs/sha256/' "${NORM}" || true)"
echo "слоёв (файлов blobs) найдено: ${BLOBS}"
INDEX_IN_ISO="$(path_of '/framz/index.json')"
[ -n "${INDEX_IN_ISO}" ] || INDEX_IN_ISO="$(awk -F'\t' '$2 ~ /(^|\/)index\.json$/ { print $1; exit }' "${WORK}/pair.txt")"
if [ -n "${INDEX_IN_ISO}" ]; then
  echo "индекс образа: ${INDEX_IN_ISO}"
  isoinfo -i "${ISO}" -x "${INDEX_IN_ISO}" > "${WORK}/index.json" 2>/dev/null
  if have python3 && [ -s "${WORK}/index.json" ]; then
    python3 - "${WORK}" "${ISO}" "${RAW}" "${NORM}" <<'PY'
import json, os, subprocess, sys, tarfile
work, iso, raw_path, norm_path = sys.argv[1:5]

raw = [l.strip() for l in open(raw_path, encoding='utf-8', errors='replace') if l.strip()]
norm = [l.strip() for l in open(norm_path, encoding='utf-8', errors='replace') if l.strip()]

def iso_path_for(blob_digest_hex):
    """Путь внутри ISO (в исходном регистре) для blob-а по дайджесту."""
    target = f'/blobs/sha256/{blob_digest_hex}'.lower()
    for orig, n in zip(raw, norm):
        if n.endswith(target):
            return orig
    return None

try:
    index = json.load(open(os.path.join(work, 'index.json'), encoding='utf-8'))
except Exception as exc:
    print('index.json прочитать не удалось:', exc)
    sys.exit(0)

manifests = [m['digest'] for m in index.get('manifests', [])
             if m.get('digest') and 'manifest' in m.get('mediaType', '')]
print('манифестов в индексе:', len(manifests))

MARKERS = {
    'окно первого запуска': 'usr/bin/framz-welcome',
    'профили нагрузки (ядро)': 'usr/bin/framz-tune',
    'набор иконок Kora': 'usr/share/icons/kora/index.theme',
    'знак FRAMZ в теме иконок': 'framz-logo.svg',
    'тема оформления FRAMZ': 'org.framz.desktop/metadata.json',
    'наш лаунчер (плазмоид)': 'org.framz.launcher/metadata.json',
    'обои FRAMZ': 'framz/branding/wallpapers',
    'экран входа SDDM': 'sddm/themes/framz/Main.qml',
    'экран загрузки Plymouth': 'plymouth/themes/framz/framz.script',
    'настройки ядра': 'sysctl.d/99-framz.conf',
    'имя системы': 'etc/os-release',
    'автозапуск окна первого запуска': 'framz-welcome.desktop',
}
found = {k: False for k in MARKERS}
layers_read = 0

for digest in manifests:
    hexdigest = digest.split(':', 1)[1]
    p = iso_path_for(hexdigest)
    if not p:
        continue
    man_file = os.path.join(work, 'manifest.json')
    with open(man_file, 'wb') as fh:
        subprocess.run(['isoinfo', '-i', iso, '-x', p], stdout=fh, stderr=subprocess.DEVNULL)
    try:
        man = json.load(open(man_file, encoding='utf-8'))
    except Exception:
        continue
    for layer in man.get('layers', []):
        # Наши слои маленькие; большие базовые читаем, но не больше 8 штук
        if layer.get('size', 0) > 150 * 1024 * 1024 and layers_read >= 8:
            continue
        lp = iso_path_for(layer['digest'].split(':', 1)[1])
        if not lp:
            continue
        blob = os.path.join(work, 'layer.tar.gz')
        with open(blob, 'wb') as fh:
            subprocess.run(['isoinfo', '-i', iso, '-x', lp], stdout=fh, stderr=subprocess.DEVNULL)
        if not os.path.getsize(blob):
            continue
        layers_read += 1
        try:
            with tarfile.open(blob, 'r:gz') as tf:
                names = '\n'.join(tf.getnames())
        except Exception:
            continue
        for key, marker in MARKERS.items():
            if marker in names:
                found[key] = True

print('прочитано слоёв образа:', layers_read)
print()
print('--- НАШИ ФАЙЛЫ ВНУТРИ СИСТЕМНОГО ОБРАЗА ---')
missing = 0
for key, marker in MARKERS.items():
    if found[key]:
        print('ЕСТЬ   ' + key)
    else:
        print('НЕТ    ' + key + '   (искали: ' + marker + ')')
        missing += 1
print()
print('не найдено пунктов:', missing)
PY
  else
    echo "нет python3 или пустой index.json — пропускаю разбор слоёв"
  fi
else
  echo "index.json внутри ISO не найден — возможно, образ лежит иначе"
fi
echo

echo "=== ИТОГ: замечаний ${PROBLEMS} ==="
exit 0
