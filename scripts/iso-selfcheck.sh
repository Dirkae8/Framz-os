#!/usr/bin/env bash
# FRAMZ OS — самопроверка готового ISO.
#
# Проверяет: метку тома, файлы загрузки, среду установщика, наш брендинг
# внутри установщика и наши файлы внутри системного образа (OCI-слой).
# Ничего не меняет и НЕ падает: все проблемы попадают в отчёт.
#
# Использование: bash scripts/iso-selfcheck.sh framz-os-1.0.iso
set -uo pipefail

ISO="${1:?укажи путь к ISO}"
[ -f "${ISO}" ] || { echo "нет файла: ${ISO}"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

have() { command -v "$1" >/dev/null 2>&1; }
PROBLEMS=0
note() { echo "$@"; }
check() { # check "описание" условие
  if eval "$2"; then echo "ЕСТЬ   $1"; else echo "НЕТ    $1"; PROBLEMS=$((PROBLEMS + 1)); fi
}

echo "=== FRAMZ OS — самопроверка ISO ==="
date -u +"время: %Y-%m-%d %H:%M UTC"
echo "файл: ${ISO}"
echo "размер: $(stat -c%s "${ISO}" 2>/dev/null || echo '?') байт"
echo

if ! have isoinfo; then
  echo "нет isoinfo (пакет genisoimage) — структурная проверка невозможна"
  exit 0
fi

# ── 1. Параметры ISO ─────────────────────────────────────────────────────────
echo "--- параметры ISO ---"
isoinfo -d -i "${ISO}" 2>&1 | grep -i -E "volume id|volume set id|system id|publisher|data preparer|logical block size" || true
echo
VOLID="$(isoinfo -d -i "${ISO}" 2>/dev/null | grep -i 'volume id' | sed 's/.*: //' | tr -d '\r')"
echo "метка тома: '${VOLID}'"
case "${VOLID}" in
  FRAMZ*) echo "ВЕРНО  метка содержит FRAMZ" ;;
  *)      echo "ВНИМАНИЕ метка не содержит FRAMZ (ожидали FRAMZ_OS_1)"; PROBLEMS=$((PROBLEMS + 1)) ;;
esac
echo

# ── 2. Файлы загрузки ────────────────────────────────────────────────────────
echo "--- файлы загрузки ISO ---"
LISTING="${WORK}/listing.txt"
isoinfo -f -i "${ISO}" 2>/dev/null | tr -d '\r' > "${LISTING}"
for f in /images/install.img /images/pxeboot/vmlinuz /images/pxeboot/initrd.img /.treeinfo /isolinux/isolinux.cfg /EFI/BOOT/grub.cfg; do
  check "${f}" "grep -qx '${f}' '${LISTING}'"
done
echo
echo "всего файлов на ISO: $(wc -l < "${LISTING}")"
echo
echo "--- верхний уровень ISO ---"
grep -E '^/[^/]*$' "${LISTING}" | head -20
echo

# ── 3. Среда установщика ─────────────────────────────────────────────────────
INSTALL_IMG="${WORK}/install.img"
if grep -qx '/images/install.img' "${LISTING}"; then
  echo "--- распаковываю среду установщика (это ~1–2 ГБ, подождите) ---"
  isoinfo -i "${ISO}" -x /images/install.img > "${INSTALL_IMG}" 2>/dev/null
  if have unsquashfs && [ -s "${INSTALL_IMG}" ]; then
    unsquashfs -l "${INSTALL_IMG}" 2>/dev/null | tr -d '\r' > "${WORK}/install-listing.txt"
    echo "файлов в среде установщика: $(wc -l < "${WORK}/install-listing.txt")"
    echo
    echo "--- НАШ БРЕНДИНГ в установщике ---"
    check "оформление: branding.css"  "grep -q 'cockpit/branding/framz/branding.css' '${WORK}/install-listing.txt'"
    check "знак: logo.png"            "grep -q 'cockpit/branding/framz/logo.png' '${WORK}/install-listing.txt'"
    check "настройки: 50-framz.conf"  "grep -q 'anaconda/cockpit/conf.d/50-framz.conf' '${WORK}/install-listing.txt'"
    check "окно входа установщика"    "grep -q 'anaconda/cockpit' '${WORK}/install-listing.txt'"
    echo
    echo "--- содержимое нашего оформления (первые строки) ---"
    unsquashfs -cat "${INSTALL_IMG}" usr/share/cockpit/branding/framz/branding.css 2>/dev/null | head -6
    echo
    echo "--- настройки окна входа ---"
    unsquashfs -cat "${INSTALL_IMG}" etc/anaconda/cockpit/conf.d/50-framz.conf 2>/dev/null | grep -v '^#' | grep -v '^$' | head -5
    echo
    echo "--- чем система установщика себя называет ---"
    unsquashfs -cat "${INSTALL_IMG}" etc/os-release 2>/dev/null | grep -E '^(NAME|PRETTY_NAME|VERSION_ID)=' | head -4
  else
    echo "нет unsquashfs (пакет squashfs-tools) или пустой install.img — пропускаю"
  fi
else
  echo "на ISO нет /images/install.img — структура необычная"
  PROBLEMS=$((PROBLEMS + 1))
fi
echo

# ── 4. Наш системный образ внутри ISO (OCI-слой) ─────────────────────────────
echo "--- наш системный образ внутри ISO ---"
IDX_ISO_PATH="$(grep -E '/index\.json$' "${LISTING}" | head -1 || true)"
if [ -n "${IDX_ISO_PATH}" ]; then
  echo "индекс OCI: ${IDX_ISO_PATH}"
  isoinfo -i "${ISO}" -x "${IDX_ISO_PATH}" > "${WORK}/index.json" 2>/dev/null
  if have python3; then
    python3 - "${WORK}" "${INSTALL_IMG}" "${LISTING}" <<'PY'
import json, os, re, subprocess, sys, tarfile, gzip, io, hashlib
work, install_img, listing_path = sys.argv[1], sys.argv[2], sys.argv[3]

def find_manifest_paths(listing_path, digests):
    """Пути blob-ов внутри ISO для нужных дайджестов."""
    paths = {}
    with open(listing_path, encoding='utf-8', errors='replace') as fh:
        names = [l.strip() for l in fh if l.strip()]
    for d in digests:
        hexdigest = d.split(':', 1)[1]
        for n in names:
            if n.endswith(f'blobs/sha256/{hexdigest}'):
                paths[d] = n
                break
    return paths

idx = os.path.join(work, 'index.json')
try:
    data = json.load(open(idx, encoding='utf-8'))
except Exception as exc:
    print('не удалось прочитать index.json:', exc)
    sys.exit(0)

manifests = []
for m in data.get('manifests', []):
    d = m.get('digest')
    if d and m.get('mediaType', '').endswith('image.manifest.v1+json'):
        manifests.append(d)
print('манифестов в индексе:', len(manifests))

paths = find_manifest_paths(listing_path, manifests)
print('найдено blob-ов внутри ISO:', len(paths))

MARKERS = [
    ('окно первого запуска', 'usr/bin/framz-welcome'),
    ('тема иконок Kora', 'usr/share/icons/kora/index.theme'),
    ('набор Kora (шрифты MIME)', 'usr/share/icons/kora/mimetypes'),
    ('системные настройки KDE', 'etc/xdg/kdeglobals'),
    ('тема оформления FRAMZ', 'org.framz.desktop/metadata.json'),
    ('обои FRAMZ', 'framz/branding/wallpapers'),
    ('своё имя системы', 'etc/os-release'),
    ('автозапуск окна', 'etc/xdg/autostart/framz-welcome.desktop'),
]
found = {name: False for name, _ in MARKERS}
checked_layers = 0
for d in manifests:
    p = paths.get(d)
    if not p:
        continue
    tmp = os.path.join(work, 'manifest.json')
    subprocess.run(['isoinfo', '-i', ISO, '-x', p], stdout=open(tmp, 'wb'), stderr=subprocess.DEVNULL)
    try:
        man = json.load(open(tmp, encoding='utf-8'))
    except Exception:
        continue
    for layer in man.get('layers', []):
        size = layer.get('size', 0)
        # Наши слои маленькие (файлы оформления). Большие базовые качаем по одному.
        if size > 120 * 1024 * 1024 or checked_layers > 12:
            continue
        lp = paths.get(layer['digest']) or next(
            (n for n in open(listing_path, encoding='utf-8', errors='replace').read().split('\n')
             if n.strip().endswith(layer['digest'].split(':', 1)[1])), None)
        if not lp:
            continue
        blob = os.path.join(work, 'layer.tar.gz')
        subprocess.run(['isoinfo', '-i', ISO, '-x', lp], stdout=open(blob, 'wb'), stderr=subprocess.DEVNULL)
        if os.path.getsize(blob) == 0:
            continue
        checked_layers += 1
        try:
            with tarfile.open(blob, 'r:gz') as tf:
                names = tf.getnames()
        except Exception as exc:
            print('слой не прочитан:', exc)
            continue
        joined = '\n'.join(names)
        for name, marker in MARKERS:
            if marker in joined:
                found[name] = True

print('проверено слоёв образа:', checked_layers)
print()
print('--- НАШИ ФАЙЛЫ ВНУТРИ СИСТЕМНОГО ОБРАЗА ---')
missing = 0
for name, marker in MARKERS:
    if found[name]:
        print('ЕСТЬ   ' + name + '  (' + marker + ')')
    else:
        print('НЕТ    ' + name + '  (' + marker + ')')
        missing += 1
print()
print('не найдено пунктов:', missing)
PY
  else
    echo "нет python3 — пропускаю проверку слоёв"
  fi
else
  echo "в ISO не найден index.json (OCI) — возможно, другая структура"
  PROBLEMS=$((PROBLEMS + 1))
fi

echo
echo "=== ИТОГ: замечаний ${PROBLEMS} ==="
exit 0
