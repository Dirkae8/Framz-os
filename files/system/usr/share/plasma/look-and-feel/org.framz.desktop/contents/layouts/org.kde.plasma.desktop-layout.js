// FRAMZ OS — наша раскладка рабочего стола (тема «Minimal Mono»).
//
// Применяется автоматически при первом входе нового пользователя, когда
// активна тема оформления org.framz.desktop. Панель снизу, парящая,
// кнопка запуска — наш знак.
//
// Всё необязательное обёрнуто в try/catch: если в системе другая версия
// Plasma и какое-то свойство отсутствует — панель всё равно соберётся.

function framzTry(fn) {
    try { fn(); } catch (e) { print("FRAMZ: пропущено необязательное свойство: " + e); }
}

var panel = new Panel

panel.location = "bottom";
panel.height = 2 * Math.ceil(gridUnit * 2.5 / 2);

// Панель парит над обоями (вид «плавающей» панели)
framzTry(function() { panel.floating = true; });
// Полупрозрачность подбирается под обои
framzTry(function() { panel.opacityMode = "adaptive"; });

// Ограничиваем ширину на очень широких мониторах (как в Breeze),
// чтобы панель не растягивалась на 32:9
framzTry(function() {
    const maximumAspectRatio = 21 / 9;
    if (panel.formFactor === "horizontal") {
        const geo = screenGeometry(panel.screen);
        const maximumWidth = Math.ceil(geo.height * maximumAspectRatio);
        if (geo.width > maximumWidth) {
            panel.alignment = "center";
            panel.minimumLength = maximumWidth;
            panel.maximumLength = maximumWidth;
        }
    }
});

// Слева — запуск с нашим знаком вместо стандартной иконки
var launcher = panel.addWidget("org.kde.plasma.kickoff");
framzTry(function() {
    launcher.currentConfigGroup = ["General"];
    launcher.writeConfig("icon", "framz-logo");
    launcher.writeConfig("useCustomButtonImage", true);
});

// По центру — задачи: только значки, без подписей (вид дока)
panel.addWidget("org.kde.plasma.icontasks");

// Справа — разделитель, системный лоток и часы
panel.addWidget("org.kde.plasma.marginsseparator");
panel.addWidget("org.kde.plasma.systemtray");
panel.addWidget("org.kde.plasma.digitalclock");

// Обои FRAMZ на всех рабочих столах
var desktopsArray = desktopsForActivity(currentActivity());
for (var j = 0; j < desktopsArray.length; j++) {
    desktopsArray[j].wallpaperPlugin = 'org.kde.image';
}
