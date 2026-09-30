#!/usr/bin/env bash
# Установка оформления FRAMZ OS внутрь образа (выполняется при сборке).
# Запускается модулем script из recipes/recipe.yml.
set -euo pipefail

# DESTDIR удобен для локальных проверок скрипта без прав root.
DESTDIR="${FRAMZ_DESTDIR:-}"

echo "▸ FRAMZ: устанавливаю набор иконок Kora"

# ── 1. Набор иконок Kora (github.com/bikass/kora, GPL-3.0) ────────────────────
# Версия зафиксирована по коммиту: сборка всегда воспроизводима.
KORA_SHA="ba1e9e279aa5b3f6674ec6b17534ea05032de580"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

command -v curl >/dev/null 2>&1 || { echo "нет curl"; exit 1; }
command -v tar  >/dev/null 2>&1 || { echo "нет tar"; exit 1; }

curl -fsSL -o "${TMP}/kora.tar.gz" \
  "https://codeload.github.com/bikass/kora/tar.gz/${KORA_SHA}"

tar -xzf "${TMP}/kora.tar.gz" -C "${TMP}"
SRC="${TMP}/kora-${KORA_SHA}"
[ -d "${SRC}/kora" ] || { echo "не нашёл каталог темы в архиве"; exit 1; }

install -d "${DESTDIR}/usr/share/icons"
rm -rf "${DESTDIR}/usr/share/icons/kora" "${DESTDIR}/usr/share/icons/kora-pgrey"
cp -a "${SRC}/kora"       "${DESTDIR}/usr/share/icons/kora"
cp -a "${SRC}/kora-pgrey" "${DESTDIR}/usr/share/icons/kora-pgrey"

# Лицензия авторов — обязательна при распространении (GPL-3.0)
install -Dm644 "${SRC}/LICENSE" "${DESTDIR}/usr/share/licenses/kora/LICENSE"

# ── 2. Права на окно первого запуска + наш знак в набор иконок ──────────────
# Модуль files копирует файлы, но страховка от потери бита запуска не помешает.
if [ -f "${DESTDIR}/usr/bin/framz-welcome" ]; then
  chmod 0755 "${DESTDIR}/usr/bin/framz-welcome"
  echo "▸ FRAMZ: окно первого запуска готово"
fi

# Знак FRAMZ доступен как обычная иконка (hicolor наследуется всеми наборами)
MARK="${DESTDIR}/usr/share/framz/branding/logo/framz-mark.svg"
if [ -f "${MARK}" ]; then
  install -Dm644 "${MARK}" "${DESTDIR}/usr/share/icons/hicolor/scalable/apps/framz-logo.svg"
fi

# ── 3. Службы, которые должны работать «из коробки» ─────────────────────────
# Включаем офлайн (в образе), чтобы у человека ничего не требовалось запускать руками.
for unit in irqbalance.service gamemoded.service framz-grub-theme.service; do
  if systemctl enable "${unit}" >/dev/null 2>&1; then
    echo "▸ FRAMZ: служба включена — ${unit}"
  elif [ -f "/usr/lib/systemd/system/${unit}" ]; then
    # запасной путь: ручная ссылка, если systemctl в контейнере недоступен
    wants="${DESTDIR}/etc/systemd/system/multi-user.target.wants"
    mkdir -p "${wants}"
    ln -sf "/usr/lib/systemd/system/${unit}" "${wants}/${unit}"
    echo "▸ FRAMZ: служба включена вручную — ${unit}"
  fi
done

# Тема загрузчика GRUB: копию темы кладём сразу (юнит при первом запуске соберёт grub.cfg)
if [ -d /usr/share/grub/themes/framz ] && [ -d /boot/grub2 ]; then
  mkdir -p /boot/grub2/themes/framz 2>/dev/null || true
  cp -f /usr/share/grub/themes/framz/* /boot/grub2/themes/framz/ 2>/dev/null && \
    echo "▸ FRAMZ: тема загрузчика подготовлена (framz)" || true
fi

# Экран загрузки: выбираем наш Plymouth-тему (и обновляем initramfs, если инструмент есть)
if command -v plymouth-set-default-theme >/dev/null 2>&1 && [ -d /usr/share/plymouth/themes/framz ]; then
  plymouth-set-default-theme framz >/dev/null 2>&1 && echo "▸ FRAMZ: экран загрузки — наш (framz)" || true
fi

# ── 4. Кэш иконок ────────────────────────────────────────────────────────────
for theme in kora kora-pgrey; do
  if [ -d "${DESTDIR}/usr/share/icons/${theme}" ] && [ -x /usr/bin/gtk-update-icon-cache ]; then
    gtk-update-icon-cache -q -t -f "${DESTDIR}/usr/share/icons/${theme}" || true
  fi
done

echo "▸ FRAMZ: иконки Kora установлены ($(find "${DESTDIR}/usr/share/icons/kora" -type f | wc -l) файлов)"
