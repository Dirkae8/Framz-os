# FRAMZ OS 1.0

**Творческая система на базе Fedora Atomic KDE Plasma.** Один установочный образ для всех устройств:
система, свой интерфейс FRAMZ и творческий набор приложений — уже внутри.

> **Скачать:** `framz-os-1.0.iso` (обычная, для большинства компьютеров) ·
> `framz-os-1.0-nvidia.iso` (для видеокарт NVIDIA, с драйвером и CUDA внутри).
> GitHub не принимает файлы больше 2 ГиБ, поэтому ISO выложены **частями** — склеиваются сами,
> если ставить через скрипты ниже.

| | `framz-os-1.0.iso` | `framz-os-1.0-nvidia.iso` |
|---|---|---|
| **Для кого** | любой компьютер: AMD, Intel, NVIDIA (свободный драйвер nouveau) | владельцы NVIDIA, кому нужны CUDA, NVENC и рендер в Blender |
| **Размер** | ≈4,3 ГБ (3 части) | ≈6,3 ГБ (4 части) |
| **База** | Fedora 44 Atomic KDE (Kinoite) | Universal Blue kinoite-nvidia 44 |
| **Драйвер NVIDIA** | нет (работает свободный nouveau) | да, проприетарный + CUDA |

---

## Как поставить

### Путь 1 — попробовать в виртуалке (ничего не сломает, система не тронет)

Одна команда, дальше скрипт всё делает сам: поставит виртуалку, скачает ISO частями,
проверит контрольные суммы, склеит его и откроет окно установки.

```bash
bash -c "$(curl -fsSL https://github.com/Dirkae8/Framz-os/releases/download/v1.0/framz-quickstart.sh)"
```

Что делать в окне: язык `Русский` → **Хранилище** → диск `40 GiB` → **Автоматически** →
создать пользователя (галочка «Сделать администратором») → **Начать установку** → **Перезагрузить**.
После перезагрузки увидишь наш экран загрузки, наш экран входа и рабочий стол FRAMZ OS.

Подробная инструкция для Garuda: [`docs/RUN-ON-GARUDA.md`](https://github.com/Dirkae8/Framz-os/blob/main/docs/RUN-ON-GARUDA.md).

### Путь 2 — поставить на настоящий компьютер, с флешки

Нужна флешка ≥ 8 ГБ. **Всё на ней будет стёрто.**

```bash
bash -c "$(curl -fsSL https://github.com/Dirkae8/Framz-os/releases/download/v1.0/framz-usb.sh)"
```

Скрипт спросит, куда писать, скачает ISO, проверит сумму и запишет на флешку.
Дальше: загрузка с флешки (в BIOS/UEFI включена загрузка USB, **Secure Boot выключен** —
образы пока без подписи) → тот же установщик FRAMZ OS.

### Путь 3 — вручную, без скриптов

```bash
cd ~/Загрузки
BASE=https://github.com/Dirkae8/Framz-os/releases/download/v1.0
for p in aa ab ac; do curl -LO "$BASE/framz-os-1.0.iso.part-$p"; done
curl -LO "$BASE/framz-os-1.0.iso.parts-SHA256"
curl -LO "$BASE/framz-os-1.0.iso-SHA256"

sha256sum -c framz-os-1.0.iso.parts-SHA256     # проверка частей
cat framz-os-1.0.iso.part-* > framz-os-1.0.iso # склейка
sha256sum -c framz-os-1.0.iso-SHA256           # проверка целого ISO: ждём «OK»

lsblk                                          # найти свою флешку, например /dev/sdb
sudo dd if=framz-os-1.0.iso of=/dev/sdX bs=4M status=progress oflag=sync   # sdX — именно флешка!
```

Для NVIDIA-редакции — то же с именем `framz-os-1.0-nvidia.iso` (части `part-aa…part-ad`).

---

## Что внутри

**Наш интерфейс:**

* **Меню загрузки флешки** — наше: «Установить FRAMZ OS», «Проверить носитель», тёмный фон со знаком.
* **Загрузчик на диске (GRUB)** — наша тема: знак, «FRAMZ OS», аккуратные пункты; конфиг собирается
  при первом запуске и подменяется только после проверки, что система загрузится.
* **Экран загрузки (Plymouth)** — знак FRAMZ вместо логотипа Fedora, спокойное выключение.
* **Пароль для шифрованного диска** — запрос в том же стиле: ровный текст, без «сырых» консолей.
* **Экран входа (SDDM)** — своя тема: тёмные обои FRAMZ, наш знак, вход без лишнего.
* **Лаунчер в панели** — свой, не штатный: разделы **Творчество · Медиа · Система**,
  поиск по приложениям, быстрый запуск.
* **Оформление установщика** — установщик подписан и оформлен как FRAMZ OS
  (чёрно-белый стиль «Minimal Mono»), а не как Fedora.
* **Профили ядра `framz-tune`** — одним словом переключаешь систему под задачу:
  `sudo framz-tune game` (игры: планировщик, приоритеты, звук),
  `sudo framz-tune dev` (разработка), `sudo framz-tune studio` (творчество: маленькая задержка звука),
  `framz-tune --status` — что сейчас включено.
* **Одна команда `framz`** — `framz status`, `framz tune game`, `framz update`, `framz rollback`, `framz help-me`.
* **Окно «Обновления FRAMZ»** — показывает состояние системы, обновляет и предлагает откат одной кнопкой.
* **Своя справка** — «Справка FRAMZ» в меню: где программы, как обновляться, что делать если сломалось.
* **Терминал** — наш профиль и раскраска по умолчанию.
* **Быстрые окна** — короткие анимации и низкая задержка отрисовки: система ощущается отзывчивее.
* Тема **Frame Dark** (тёмная) и **Studio Light** (светлая), обои 4K, знак FRAMZ,
  шрифты Noto Sans + JetBrains Mono.

**Настройка системы под творчество и разработку:** планировщик ввода-вывода под тип диска
(NVMe/SSD/HDD), zram-сжатие памяти, BBR для сети, баланс отзывчивости и многозадачности
(автогруппировка задач), звук без задержек (PipeWire + JACK), графические планшеты (libwacom),
цвет и калибровка (colord + argyllcms), инструменты (btop, ark, filelight, partitionmanager,
KDE Connect), контейнеры для «Мастерской» (distrobox, podman).

**Иконки:** открытый набор [Kora](https://github.com/bikass/kora) (GPL-3.0) + серая версия Kora Grey.

**Окно первого запуска (`framz-welcome`):** выбор темы, проверка железа (видео, звук, планшет),
быстрые ссылки на Discover, Krita, Blender, Kdenlive, OBS, Ardour, darktable. Показывается один раз.

**Система видит себя как FRAMZ OS:** `PRETTY_NAME="FRAMZ OS 1.0"`, `ID=framz`, `ID_LIKE=fedora`.

**Творческий набор (Flatpak из Flathub):**
Krita · Inkscape · GIMP · Scribus · Blender · darktable · Kdenlive · OBS Studio · Ardour · LibreOffice ·
Firefox · Flatseal · Warehouse.
Набор приписан к образу: система **докачивает приложения при первом входе** (нужен интернет, 5–15 минут).
Так ISO остаётся 4,3 ГБ вместо ~11 ГБ, а приложения всегда свежие.

**Магазин:** штатный **Discover** с Flathub — в нашей теме выглядит как часть FRAMZ.

**Обновления и откат:** атомарные, через `rpm-ostree` / `bootc`. Обновился — стало плохо —
одна команда `sudo rpm-ostree rollback` и перезагрузка возвращают прошлое состояние.

---

## Проверенные контрольные суммы

```
framz-os-1.0.iso          01ad3d156d4bcc81141e2ae5e6e741a7a71e80f20dbb7d1d9265a15995e7428d
framz-os-1.0.iso.part-aa  cfe27391dc003e296ce94549d15160079b434cf1e1dc1fd0072c5e3fd5357ded
framz-os-1.0.iso.part-ab  0ea2151dbc75e82da9fce7ab16b460f6b69c8812bef3d9a5e98bb12f91e99059
framz-os-1.0.iso.part-ac  f57f857e31cbb9bdd2047dee0076b4147396d8d3b4a590d58ae5c6766a08bc3c

framz-os-1.0-nvidia.iso   a70bcd69c6a32cbb30a87129de62b16f2c8545174242d4fbe4fd9dc965266ab5
```

Скрипты (`framz-quickstart.sh`, `framz-vm.sh`, `framz-usb.sh`) проверяют суммы сами —
руками считать не нужно.

---

## Чего пока нет (честно)

- своего набора иконок (используем открытый Kora; свой — в планах);
- расширенного мастера первого запуска (сейчас упрощённое окно);
- подписи образов для Secure Boot;
- сборки с приложениями целиком внутри ISO (~11 ГБ, без докачивания) — будет, если понадобится;
- полного форка на своей базе: сейчас база — Fedora Kinoite, переход на Arch с откатом
  через снапшоты описан в [`docs/ARCH-PLAN.md`](https://github.com/Dirkae8/Framz-os/blob/main/docs/ARCH-PLAN.md).

Планы и устройство проекта — в репозитории:
[`docs/VISION.md`](https://github.com/Dirkae8/Framz-os/blob/main/docs/VISION.md),
[`docs/WHAT-IS-OURS.md`](https://github.com/Dirkae8/Framz-os/blob/main/docs/WHAT-IS-OURS.md).

**Лицензии:** система — Fedora/Atomic (MIT и др.), оформление FRAMZ — наше, иконки Kora — GPL-3.0
(текст лицензии внутри образа: `/usr/share/licenses/kora/LICENSE`).
