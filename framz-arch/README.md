# FRAMZ OS на Arch — профиль сборки

Черновая версия профиля [archiso](https://wiki.archlinux.org/title/Archiso) для Arch-редакции FRAMZ OS.
План и обоснование — [`../docs/ARCH-PLAN.md`](../docs/ARCH-PLAN.md); разбор интерфейса — [`../docs/INTERFACE.md`](../docs/INTERFACE.md).

## Сборка

```bash
# нужен Arch (или контейнер archlinux:latest) и права root
sudo pacman -S --needed archiso
sudo mkarchiso -v -w /tmp/framz-work -o out framz-arch/
# результат: out/framz-os-arch-1.0-x86_64.iso
```

## Что уже есть в профиле

- `profiledef.sh` — имя ISO, метка тома, режимы загрузки (BIOS + UEFI), права на файлы;
- `packages.x86_64` — наш список пакетов: лёгкая база, Plasma, творческая настройка, откат, Calamares;
- `airootfs/` — то, что попадёт внутрь системы (сюда сборка подкладывает `../files/system/*`
  и `../iso/branding/*`, чтобы не дублировать наш брендинг).

## Следующие шаги (этап 1 плана)

1. Дописать оверлей `airootfs`: автозапуск `framz-welcome` в Live-режиме, ярлык «Установить FRAMZ OS».
2. Настроить `mkinitcpio` + Plymouth (наш знак), SDDM (наш экран входа).
3. Подключить Calamares с нашим оформлением и разметкой Btrfs по умолчанию.
4. Собрать ISO в CI (workflow `build-arch.yml`), прогнать жёсткий тест из `docs/ARCH-PLAN.md` (раздел 7).
