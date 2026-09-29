# FRAMZ OS 1.0

**Творческая система на базе Fedora Atomic KDE Plasma.** Один установочный образ для всех устройств:
система, своё оформление FRAMZ и творческий набор приложений — уже внутри.

> **Скачать:** `framz-os-1.0.iso` (обычная, для большинства компьютеров) ·
> `framz-os-1.0-nvidia.iso` (для видеокарт NVIDIA, с драйвером и CUDA внутри).
> GitHub не принимает файлы больше 2 ГиБ, поэтому ISO выложены **частями** — склей их, как написано ниже.

| | `framz-os-1.0.iso` | `framz-os-1.0-nvidia.iso` |
|---|---|---|
| **Для кого** | любой компьютер: AMD, Intel, NVIDIA (свободный драйвер nouveau) | владельцы NVIDIA, кому нужны CUDA, NVENC и рендер в Blender |
| **Размер** | ≈4,3 ГБ (3 части) | ≈6,3 ГБ (4 части) |
| **База** | Fedora 44 Atomic KDE (Kinoite) | Universal Blue kinoite-nvidia 44 |
| **Драйвер NVIDIA** | нет (работает свободный nouveau) | да, проприетарный + CUDA |

---

## Что внутри

**Оформление FRAMZ (наше):**
тема **Frame Dark** (тёмная, фиолетово-маджентовая) и **Studio Light** (светлая, тёплая),
обои 4K (3840×2160), свой экран загрузки с метками кадрирования, знак FRAMZ, шрифты
Noto Sans + JetBrains Mono, тема оформления `org.framz.desktop` применяется при первом входе.

**Иконки:** открытый набор [Kora](https://github.com/bikass/kora) (GPL-3.0) + серая версия Kora Grey.

**Окно первого запуска (`framz-welcome`):** выбор темы, проверка железа (видео, звук, планшет),
быстрые ссылки на Discover, Krita, Blender, Kdenlive, OBS, Ardour, darktable. Показывается один раз.

**Система видит себя как FRAMZ OS:** `PRETTY_NAME="FRAMZ OS 1.0"`, `ID=framz`, `ID_LIKE=fedora`.

**Творческая настройка системы:** звук без задержек (PipeWire + JACK), графические планшеты (libwacom),
цвет и калибровка (colord + argyllcms), инструменты (btop, ark, filelight, partitionmanager, KDE Connect),
контейнеры для «Мастерской» (distrobox, podman). Firefox из системы убран — ставится Flatpak'ом.

**Творческий набор (Flatpak из Flathub):**
Krita · Inkscape · GIMP · Scribus · Blender · darktable · Kdenlive · OBS Studio · Ardour · LibreOffice ·
Firefox · Flatseal · Warehouse.
Набор приписан к образу: система **докачивает приложения при первом входе** (нужен интернет, 5–15 минут).
Так ISO остаётся 4,3 ГБ вместо ~11 ГБ, а приложения всегда свежие.

**Магазин:** штатный **Discover** с Flathub — в нашей теме выглядит как часть FRAMZ.

**Обновления:** атомарные, через `rpm-ostree` (`sudo bootc upgrade` / `rpm-ostree update`), с откатом при проблемах.

---

## Установка (инструкция для Linux-системы, например Garuda)

```bash
# 1. Скачать все части и файлы контрольных сумм
cd ~/Загрузки
BASE=https://github.com/Dirkae8/Framz-os/releases/download/v1.0
for p in aa ab ac; do curl -LO "$BASE/framz-os-1.0.iso.part-$p"; done
curl -LO "$BASE/framz-os-1.0.iso.parts-SHA256"
curl -LO "$BASE/framz-os-1.0.iso-SHA256"

# 2. Проверить каждую часть и склеить в один ISO
sha256sum -c framz-os-1.0.iso.parts-SHA256
cat framz-os-1.0.iso.part-* > framz-os-1.0.iso

# 3. Проверить целый ISO
sha256sum -c framz-os-1.0.iso-SHA256
#    ожидаем: framz-os-1.0.iso: OK

# 4. Записать на флешку (8 ГБ и больше). ВНИМАНИЕ: /dev/sdX — именно флешка, не диск с данными!
lsblk
sudo dd if=framz-os-1.0.iso of=/dev/sdX bs=4M status=progress oflag=sync
sync
```

Для NVIDIA-редакции — то же самое, заменив имя файла на `framz-os-1.0-nvidia.iso`
(части `part-aa…part-ad`).

**Установка на компьютер без операционной системы:** флешка грузится сама (BIOS/UEFI → USB),
дальше штатный установщик Fedora Atomic: выбор диска → установка → перезагрузка.
Автоматический помощник для скачивания и записи — в репозитории: `scripts/framz-usb.sh`.

**Secure Boot:** сейчас образы без подписи. Если Secure Boot включён — либо отключи его на время установки,
либо дождись подписанных сборок (в планах). В виртуальной машине Secure Boot не мешает.

---

## Проверенные контрольные суммы

```
framz-os-1.0.iso          85bc270424516cb337e3c9adcc3291bf1ba13696d5c370dcce0548f2b52c4214
framz-os-1.0-nvidia.iso   a70bcd69c6a32cbb30a87129de62b16f2c8545174242d4fbe4fd9dc965266ab5
```

---

## Чего пока нет (честно)

- своего набора иконок (используем открытый Kora; свой — в планах);
- расширенного мастера первого запуска (сейчас упрощённое окно);
- подписи образов для Secure Boot;
- сборки с приложениями целиком внутри ISO (~11 ГБ, без докачивания) — будет, если понадобится.

Планы и устройство проекта — в репозитории: [`docs/VISION.md`](https://github.com/Dirkae8/Framz-os/blob/main/docs/VISION.md),
[`docs/WHAT-IS-OURS.md`](https://github.com/Dirkae8/Framz-os/blob/main/docs/WHAT-IS-OURS.md).

**Лицензии:** система — Fedora/Atomic (MIT и др.), оформление FRAMZ — наше, иконки Kora — GPL-3.0
(текст лицензии внутри образа: `/usr/share/licenses/kora/LICENSE`).
