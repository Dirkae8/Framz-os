#!/usr/bin/env bash
# FRAMZ OS — сборка содержимого Arch-ISO (airootfs).
#
# Что делает (запускать на Arch или в контейнере archlinux):
#   1. собирает airootfs из наших файлов: files/system (интерфейс, ядро, скрипты)
#      и framz-arch/airootfs-seed (живой режим, установщик, автозапуск);
#   2. создаёт живого пользователя framz (без пароля, с sudo) — это флешка, не система с данными;
#   3. включает службы (рабочий стол, сеть, bluetooth, irqbalance);
#   4. кладёт набор иконок Kora (скачивает; если не вышло — останутся Breeze, система работает);
#   5. подгоняет пути под Arch (тема GRUB в /boot/grub, а не /boot/grub2).
#
# Ничего не устанавливает в систему, где запущено: работает только с framz-arch/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="${ROOT}/framz-arch"
AIROOT="${PROFILE}/airootfs"

echo "▸ FRAMZ OS: сборка airootfs"
rm -rf "${AIROOT}"
mkdir -p "${AIROOT}"

# ── 1. Наши системные файлы (то же, что в Fedora-редакции) ───────────────────
if [ -d "${ROOT}/files/system" ]; then
  cp -a "${ROOT}/files/system/." "${AIROOT}/"
  echo "  · наши файлы системы: $(find "${ROOT}/files/system" -type f | wc -l)"
fi

# ── 2. Надстройка живого режима и установщика ────────────────────────────────
cp -a "${PROFILE}/airootfs-seed/." "${AIROOT}/"
echo "  · живой режим и установщик добавлены"

# ── 3. Пути под Arch ─────────────────────────────────────────────────────────
# На Arch тема загрузчика лежит в /boot/grub (в Fedora — /boot/grub2)
if [ -f "${AIROOT}/etc/default/grub" ]; then
  sed -i 's#/boot/grub2/themes/framz#/boot/grub/themes/framz#g' "${AIROOT}/etc/default/grub"
fi
# Наш скрипт темы GRUB тоже должен знать про Arch-путь
if [ -f "${AIROOT}/usr/bin/framz-grub-theme" ]; then
  sed -i 's#GRUB_CFG="/boot/grub2/grub.cfg"#GRUB_CFG="/boot/grub/grub.cfg"#' "${AIROOT}/usr/bin/framz-grub-theme" 2>/dev/null || true
fi

# ── 4. Живой пользователь framz (только в ISO, в системе его нет) ────────────
LIVE_USER=framz
if ! grep -q "^${LIVE_USER}:" "${AIROOT}/etc/passwd" 2>/dev/null; then
  cat >> "${AIROOT}/etc/passwd" <<EOF
${LIVE_USER}:x:1000:1000:FRAMZ Live:/home/${LIVE_USER}:/bin/bash
EOF
  # пустой пароль: вход в живой режим без пароля (sudo настроен отдельно)
  cat >> "${AIROOT}/etc/shadow" <<EOF
${LIVE_USER}::19000:0:99999:7:::
EOF
  cat >> "${AIROOT}/etc/group" <<EOF
${LIVE_USER}:x:1000:
EOF
  for g in wheel audio video network storage rfkill power users; do
    if grep -q "^${g}:" "${AIROOT}/etc/group"; then
      sed -i "s/^${g}:\([^:]*\):\([0-9]*\):.*/${g}:\1:\2:${LIVE_USER}/" "${AIROOT}/etc/group"
    fi
  done
  mkdir -p "${AIROOT}/home/${LIVE_USER}"
  if [ -d "${AIROOT}/etc/skel" ]; then
    cp -a "${AIROOT}/etc/skel/." "${AIROOT}/home/${LIVE_USER}/" 2>/dev/null || true
  fi
  chmod 700 "${AIROOT}/home/${LIVE_USER}" 2>/dev/null || true
  chown -R 1000:1000 "${AIROOT}/home/${LIVE_USER}" 2>/dev/null || true
  echo "  · живого пользователя создали: ${LIVE_USER}"
fi

# ── 5. Службы: включаем офлайн (ссылки в multi-user.target.wants) ────────────
WANTS="${AIROOT}/etc/systemd/system/multi-user.target.wants"
mkdir -p "${WANTS}"
for unit in sddm.service NetworkManager.service bluetooth.service irqbalance.service firewalld.service; do
  ln -sf "/usr/lib/systemd/system/${unit}" "${WANTS}/${unit}"
done
echo "  · службы включены: $(ls "${WANTS}" | wc -l)"

# ── 6. Иконки Kora (если получится скачать; иначе остаются штатные) ──────────
KORA_DIR="${AIROOT}/usr/share/icons/kora"
if [ ! -d "${KORA_DIR}" ]; then
  TMP="$(mktemp -d)"
  URLS=(
    "https://codeload.github.com/bikass/kora/tar.gz/refs/heads/master"
    "https://codeload.github.com/bikass/kora/tar.gz/refs/heads/main"
  )
  for url in "${URLS[@]}"; do
    if curl -fsSL --max-time 120 -o "${TMP}/kora.tar.gz" "${url}" 2>/dev/null; then
      mkdir -p "${TMP}/src"
      if tar -xzf "${TMP}/kora.tar.gz" -C "${TMP}/src" 2>/dev/null; then
        SRC="$(find "${TMP}/src" -maxdepth 2 -type d -name kora 2>/dev/null | head -1)"
        # в архиве бывает вложенный каталог kora/kora
        if [ -n "${SRC}" ] && [ -d "${SRC}/kora" ]; then SRC="${SRC}/kora"; fi
        if [ -n "${SRC}" ] && [ -f "${SRC}/index.theme" ]; then
          mkdir -p "${KORA_DIR}"
          cp -a "${SRC}/." "${KORA_DIR}/"
          echo "  · иконки Kora: добавлены"
          break
        fi
      fi
    fi
  done
  rm -rf "${TMP}"
  [ -d "${KORA_DIR}" ] || echo "  ! иконки Kora не скачались — останутся штатные Breeze (это не мешает работе)"
fi

# ── 7. Тема иконок по умолчанию: Kora, если есть ─────────────────────────────
if [ -f "${KORA_DIR}/index.theme" ] && [ -f "${AIROOT}/etc/xdg/kdeglobals" ]; then
  sed -i 's/^Theme=.*/Theme=kora/' "${AIROOT}/etc/xdg/kdeglobals"
fi

# ── 9. Итог ──────────────────────────────────────────────────────────────────
echo "▸ airootfs готов: $(find "${AIROOT}" -type f | wc -l) файлов, $(du -sh "${AIROOT}" | cut -f1)"
