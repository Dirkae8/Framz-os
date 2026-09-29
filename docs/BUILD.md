# FRAMZ OS — как собрать и протестировать

> Пока это инструкция «что делать руками» для этапа 1. Всё, что можно автоматизировать, живёт
> в `.github/workflows/build.yml`.

---

## 1. Что нужно

- Аккаунт GitHub (сборка идёт в Actions, локальная сборочная машина не нужна).
- Для локальной сборки: Linux с `podman` (>= 4.9), 40+ ГБ свободного места, интернет.
- CLI BlueBuild: `cargo install --locked blue-build` или `brew install blue-build/tap/bluebuild`.

## 2. Сборка через GitHub Actions (основной путь)

Workflow **`.github/workflows/build.yml`** (имя `build-framz`) делает всё сам, в два шага:

| Job | Что делает | Результат |
|---|---|---|
| **image** | ставит BlueBuild CLI из контейнера и выполняет `bluebuild build -v recipes/recipe.yml` | образ в `ghcr.io/<владелец>/framz:latest` |
| **iso** | скачивает собранный образ и запускает установщик `ghcr.io/jasonn3/build-container-installer` | `framz-os-1.0.iso` в артефактах и в Release `v1.0-preview` |

Запускается:
- автоматически при изменениях в `recipes/**`, `files/**`, `.github/workflows/build.yml`
  (ветки `main` и текущая рабочая ветка);
- по расписанию — ежедневно в 05:30 UTC (свежая база Fedora + обновления);
- вручную: **Actions → build-framz → Run workflow**.

**Особенности первой сборки:**
- Подписи (cosign) **нет**: в репозиторий пока нельзя добавить секрет ключа, поэтому сборка идёт
  с `BB_BUILD_NO_SIGN=true`. Включается позже, когда у проекта есть доступ к секретам:
  ```
  bluebuild generate-keys --output-dir .
  # cosign.key → секрет репозитория SIGNING_SECRET, cosign.pub → в репозиторий
  ```
  и затем раскомментировать модуль `signing` в рецепте + убрать `BB_BUILD_NO_SIGN`.
- ISO собирается только после успешного образа (job `iso` ждёт job `image` через `needs`).
- Если ISO больше 1,9 ГБ, workflow режет его на части — GitHub не принимает файлы > 2 ГиБ.

## 3. Локальная проверка и сборка

```bash
bluebuild validate recipes/recipe.yml     # проверить рецепт
bluebuild build recipes/recipe.yml        # собрать образ (долго, особенно первый раз)
```

Результат — локальный образ `localhost/framz:latest`.

## 4. Как протестировать в виртуальной машине

Пока не готов ISO, годится такой путь: поставить чистую Fedora Atomic KDE (или Bazzite/Kinoite)
в ВМ и **переключить систему на наш образ**:

```bash
sudo bootc switch ghcr.io/<owner>/framz:latest   # для bootc-образов
# или
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/<owner>/framz:latest
systemctl reboot
```

Это же — путь для миграции пользователей с других атомарных Fedora.

## 5. ISO локально (если нужен свой ISO без CI)

```bash
# собрать ISO из уже опубликованного образа (образ тянется из реестра)
bluebuild generate-iso image ghcr.io/<владелец>/framz:latest \
  --output-dir ./output --iso-name framz-os-1.0.iso -V kinoite

# либо: собрать образ локально и сразу из него сделать ISO (долго, нужен podman)
bluebuild generate-iso recipe recipes/recipe.yml \
  --output-dir ./output --iso-name framz-os-1.0.iso -V kinoite
```

Внутри используется установщик `ghcr.io/jasonn3/build-container-installer` — тот же, что в CI,
поэтому ISO из CI и ISO, собранный руками, эквивалентны. Нужен `podman` и права root
(контейнер запускается с `--privileged`).

## 6. Что проверять руками на каждом тесте (чек-лист)

- [ ] Система загружается, экран входа в FRAMZ-теме, вход без ошибок.
- [ ] Wayland-сессия, звук, микрофон, веб-камера.
- [ ] Планшет: рисует в Krita, чувствительность и кнопки работают, калибровка сохраняется.
- [ ] Аудио: запись в Ardour без xrun при буфере 128/256 сэмплов.
- [ ] Видео: VAAPI/NVENC включается в Kdenlive/OBS, монтаж 4K не «сыпется».
- [ ] 3D: Blender видит GPU (CUDA/HIP/OptiX), рендер ускоряется.
- [ ] Цвет: ICC-профиль монитора применяется, печать без «зелёного оттенка».
- [ ] Обновление: `framz-update` / окно обновления тянет новый образ, откат возвращает систему назад.
- [ ] Магазин: установка/удаление Flatpak, обновления видны, русский язык корректный.
- [ ] Первый запуск: мастер проходит, приложения ставятся, раскладки применяются.

## 7. Правила гигиены репозитория

- Не коммитить ISO и образы (`.gitignore` уже настроен).
- Большие бинарные ассеты добавлять только в `files/system/usr/share/framz/...`,
  с осознанием, что они попадают в образ.
- Каждое изменение рецепта — отдельный коммит с понятным сообщением: `recipe: включаю кодеки`.
