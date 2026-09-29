# Начни здесь: как получить FRAMZ OS 1.0 и запустить его

> **СОБРАНО И ОПУБЛИКОВАНО.** Релиз: **[FRAMZ OS 1.0 (preview) →](https://github.com/Dirkae8/Framz-os/releases/tag/v1.0-preview)**
> Там лежит установочный ISO и контрольные суммы. Ниже — как скачать, собрать из частей
> и запустить в виртуальной машине (эмуляторе).
> Есть и второй путь: проверить систему вообще без ISO, переключив уже установленную Fedora.

---

## Скачать ISO

Страница релиза: <https://github.com/Dirkae8/Framz-os/releases/tag/v1.0-preview>

| Файл | Размер | Что это |
|---|---|---|
| `framz-os-1.0.iso.part-aa` | 1800 МБ | первая часть ISO |
| `framz-os-1.0.iso.part-ab` | 1800 МБ | вторая часть ISO |
| `framz-os-1.0.iso.part-ac` | 699 МБ | третья часть ISO |
| `framz-os-1.0.iso.parts-SHA256` | маленький | контрольные суммы частей |
| `framz-os-1.0.iso-SHA256` | маленький | контрольная сумма целого ISO |

**Почему частями:** GitHub не принимает файлы больше 2 ГиБ, поэтому ISO (≈4,2 ГиБ) разрезан
на три части. После скачивания собери их в один файл:

```bash
cd ~/Загрузки            # или куда скачались файлы
cat framz-os-1.0.iso.part-* > framz-os-1.0.iso
```

**Проверка целостности** (сначала частей, потом целого файла):

```bash
sha256sum -c framz-os-1.0.iso.parts-SHA256   # все части: OK
sha256sum -c framz-os-1.0.iso-SHA256         # собранный ISO: OK
```

Если хотя бы одна проверка не прошла — файл скачался битым, скачай заново (обычно помогает
докачать именно ту часть, которая не совпала).

## Что внутри ISO

- База: **Fedora Atomic KDE (Kinoite), Fedora 44** — атомарная система с откатом обновлений.
- Образ системы: `ghcr.io/dirkae8/framz:br-arena_01a0ee0e-framz-os-44`
- Установщик: Anaconda в варианте Kinoite (`IMAGE_SIGNED=false` — образ пока не подписан).
- Из нашего рецепта в системе: RPM Fusion (кодеки), `pipewire-jack` + `qjackctl` (звук без задержек),
  `libwacom` (планшеты), `colord` + `argyllcms` + расширенные ICC-профили (цвет),
  шрифты JetBrains Mono и Noto, `distrobox`/`podman` (контейнеры для «Мастерской»),
  `btop`, KDE Connect, `ark`, `filelight`, `partitionmanager`.
  Плюс предустановленные Flatpak'и: Firefox, Flatseal, Warehouse.
- **Чего пока нет:** нашей темы, своих панели/дока/лаунчера, мастера первого запуска
  и магазина FRAMZ — рабочий стол пока штатный KDE Plasma. Это этапы 2–3 (`docs/VISION.md`).

## Запустить ISO на Linux в виртуальной машине

Виртуальная машина (эмулятор) — это «компьютер внутри компьютера»: FRAMZ OS запустится в окне
и ничего не сделает с твоей настоящей системой. Если что-то не понравится — просто закрываешь окно.

### Вариант 0 — GNOME Boxes: проще всего, только мышкой

```bash
# Debian/Ubuntu
sudo apt install gnome-boxes
# Fedora
sudo dnf install gnome-boxes
```

1. Открыть **Boxes** → кнопка **+** → **Install from file** → выбрать `framz-os-1.0.iso`.
2. Память: **4096 МБ**, диск: **30 ГБ** (можно и 60).
3. Запустить и следовать установщику.

### Вариант 1 — virt-manager: чуть сложнее, зато всё видно

```bash
# Debian/Ubuntu
sudo apt install virt-manager qemu-kvm libvirt-daemon-system ovmf
sudo usermod -aG libvirt,kvm "$USER"   # потом выйти и войти заново
# Fedora
sudo dnf install virt-manager libvirt-daemon-kvm edk2-ovmf
```

Дальше: **Create a new virtual machine → Local install media → выбрать ISO →**
Linux / Fedora / версия Fedora 44 → RAM 4096 МБ, CPU 2–4, диск 30 ГБ → **Customize before install**
и там **снять галочку Secure Boot** (ISO пока не подписан — с ним система не загрузится).

### Вариант 2 — одной командой из терминала (без графических настроек)

```bash
qemu-img create -f qcow2 framz.qcow2 40G     # подготовить диск

qemu-system-x86_64 \
  -enable-kvm -cpu host -smp 4 -m 4096 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd \
  -drive file=framz.qcow2,if=virtio \
  -cdrom framz-os-1.0.iso -boot d \
  -machine q35 -vga virtio -device virtio-net-pci,netdev=n0 -netdev user,id=n0 \
  -display gtk
```

Что значат строки: `-m 4096` — 4 ГБ памяти, `-smp 4` — 4 ядра, `-cdrom` — наш ISO,
`-drive` — виртуальный диск. Если файла OVMF нет — установить пакет `ovmf` (`edk2-ovmf`),
либо запускать без UEFI (тогда удалить строку с `pflash`).

### Быстрая альтернатива: ISO можно вообще не ставить

Если есть уже установленная атомарная Fedora (Kinoite, Silverblue, Bazzite, Aurora),
FRAMZ OS можно подключить как обычное обновление:

```bash
# 1) переключить систему на наш образ (образ пока не подписан — поэтому unverified)
sudo rpm-ostree rebase ostree-unverified-registry:ghcr.io/dirkae8/framz:br-arena_01a0ee0e-framz-os-44
systemctl reboot
```

Так ты увидишь систему за пару минут и без установки — идеально для быстрой проверки.

## После загрузки

1. Появится установщик Fedora в стиле Kinoite: язык → диск → пользователь и пароль.
2. Установка на виртуальный диск занимает 5–15 минут.
3. После перезагрузки — рабочий стол KDE Plasma (пока штатный).
4. Проверить, что наш рецепт внутри образа работает — в терминале:
   ```bash
   rpm -q btop distrobox pipewire-jack-audio-connection-kit libwacom argyllcms
   flatpak list --app          # должны быть Firefox, Flatseal, Warehouse
   ```

## Если что-то не работает

| Симптом | Причина и лечение |
|---|---|
| «Security violation» / система не грузится | Включён Secure Boot. Выключить его в настройках виртуальной машины (или в BIOS железа) |
| Чёрный экран, ничего не происходит | Мало памяти: виртуальной машине нужно **не меньше 4 ГБ** |
| Установка падает на середине | Проверить контрольные суммы (`sha256sum -c`) — вероятно, файл докачался не полностью |
| Очень медленно | Не включено аппаратное ускорение: нужен пакет `qemu-kvm`/`libvirt` и включённая виртуализация в BIOS |
| Нет интернета в виртуалке | Проверить, что в настройках машины включено устройство сети (для QEMU — строка `-netdev user`) |
| `cat` не находит части | Убедиться, что скачаны все три части и команда выполняется в той же папке |

## Что означает «не подписано» и почему это не страшно

Обычная атомарная система проверяет подпись обновлений. У нас на этапе preview подписи ещё нет
(для неё нужен ключ проекта), поэтому переключение делается через `ostree-unverified-registry`.
Это нормально для тестов на своей машине, и **не** нормально для релиза 1.0 — подпись включим
к публичной бете (в `recipes/recipe.yml` для этого есть готовый модуль `signing`).

## Что дальше (по дорожной карте)

1. **Этап 2:** оболочка FRAMZ — тема, обои, экран входа, своя панель/док/лаунчер, 4 темы.
2. **Этап 3:** мастер первого запуска (профили «Графика/Фото/3D/Видео/Звук/Контент/Обычный»)
   и магазин FRAMZ Store на базе Discover с кураторскими подборками.
3. **Этап 4:** включение подписи образов, Secure Boot, сайт и документация, публичная бета.
