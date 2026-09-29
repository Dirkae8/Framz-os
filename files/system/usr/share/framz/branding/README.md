# Брендинг FRAMZ OS в образе

Сюда попадают файлы брендинга, которые должны быть в системе у всех пользователей:

```
usr/share/framz/branding/
├── logo/            ← вектор (SVG) и PNG-версии знака  (TODO: этап 2)
├── wallpapers/      ← обои по умолчанию для 4 тем      (TODO: этап 2)
├── icons/           ← своя линейка иконок              (TODO: этап 2)
├── cursors/         ← курсоры                          (TODO: этап 2)
├── sounds/          ← звуки интерфейса                 (TODO: этап 2)
└── fonts/           ← Unbounded/Manrope, если нужно    (TODO: этап 2)

usr/share/plasma/look-and-feel/org.framz.desktop/    ← тема Plasma (TODO: этап 2)
usr/share/plasma/shells/org.framz.desktop/           ← своя панель/док (TODO: этап 2)
```

Ориентиры для этих файлов — концепты из репозитория:
`docs/brand/concepts/` и `docs/brand/wallpapers/`.

Пока это заглушка: файлы брендинга создаются на этапе 2 (см. `docs/VISION.md`, дорожная карта).
