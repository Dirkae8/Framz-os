# FRAMZ OS на Arch — наследие: профиль сборки

Arch-издание: **новая база**, лёгкая и полностью наша. Собирается профилем
[archiso](https://wiki.archlinux.org/title/Archiso), установка — Calamares в нашем оформлении.

План и обоснование — [`../docs/ARCH-PLAN.md`](../docs/ARCH-PLAN.md), разбор интерфейса — [`../docs/INTERFACE.md`](../docs/INTERFACE.md).

## Как собрать

```bash
# на Arch (или в контейнере archlinux:latest, права root)
pacman -Sy --needed archiso
bash framz-arch/prepare.sh          # собрать содержимое ISO из наших файлов
sudo mkarchiso -v -w /tmp/framz-work -o out framz-arch
# результат: out/framz-os-arch-1.0-x86_64.iso
```

Или просто запушить изменения в `framz-arch/**` — соберётся в CI
(`.github/workflows/build-arch.yml`) и появится в релизе `v1.0-arch`.

## Что внутри профиля

| Что | Где |
| --- | --- |
| Описание ISO, режимы загрузки, права | `profiledef.sh` |
| Пакеты (лёгкая база, Plasma, творческая настройка, Calamares) | `packages.x86_64` |
| Репозитории | `pacman.conf` |
| Меню загрузки UEFI | `grub/grub.cfg` |
| Меню загрузки BIOS | `syslinux/syslinux.cfg` |
| Надстройка живого режима: пользователь, автозапуск, установщик | `airootfs-seed/` |
| Сборка содержимого ISO из наших файлов | `prepare.sh` |

`airootfs/` не хранится в репозитории: его собирает `prepare.sh` из
`files/system` (наш интерфейс, ядро, скрипты), `iso/branding` (оформление) и
`airootfs-seed` (живой режим и Calamares). Так Arch-издание и Fedora-издание
используют одни и те же наши файлы — расходиться им негде.

## Что делает установщик

Calamares, офлайн: система распаковывается из образа на флешке, интернет не нужен
(приложения затем ставятся из Flatpak). Наш шаг `framz-initramfs` собирает initramfs
установленной системы с нашим экраном загрузки; загрузчик — GRUB с нашей темой.
