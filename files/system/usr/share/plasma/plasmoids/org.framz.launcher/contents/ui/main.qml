// FRAMZ OS — своё меню запуска (плазмоид).
//
// Первая версия: вкладки «Творчество», «Медиа», «Система», поиск по названию
// и запуск приложений. Запуск делается через проверенный механизм
// Qt.openUrlExternally("applications:<файл.desktop>") — он не зависит от
// внутренних интерфейсов Plasma и работает одинаково во всех версиях.
//
// Что сознательно НЕ делаем в первой версии (чтобы не рисковать):
//   • список «недавние файлы» и поиск по всей системе — это вторая версия;
//   • кнопки питания — оставлены штатному меню и панели.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3

PlasmoidItem {
    id: root

    // ── наша палитра (монохром + акцент) ──────────────────────────────────
    readonly property color inkColor: PlasmaCore.Theme.textColor
    readonly property color dimColor: Qt.rgba(inkColor.r, inkColor.g, inkColor.b, 0.6)
    readonly property color accentColor: "#8B5CF6"
    readonly property int gap: 8

    // ── наш каталог приложений ────────────────────────────────────────────
    readonly property var catalog: [
        // Творчество
        { "name": "Krita",       "nameEn": "Krita",       "icon": "krita",            "app": "org.kde.krita.desktop",            "tab": "create" },
        { "name": "Blender",     "nameEn": "Blender",     "icon": "blender",          "app": "org.blender.Blender.desktop",      "tab": "create" },
        { "name": "Kdenlive",    "nameEn": "Kdenlive",    "icon": "kdenlive",         "app": "org.kde.kdenlive.desktop",         "tab": "create" },
        { "name": "OBS Studio",  "nameEn": "OBS Studio",  "icon": "com.obsproject.Studio", "app": "com.obsproject.Studio.desktop", "tab": "create" },
        { "name": "Ardour",      "nameEn": "Ardour",      "icon": "ardour",           "app": "org.ardour.Ardour.desktop",        "tab": "create" },
        { "name": "darktable",   "nameEn": "darktable",   "icon": "darktable",        "app": "org.darktable.Darktable.desktop",  "tab": "create" },
        { "name": "Inkscape",    "nameEn": "Inkscape",    "icon": "inkscape",         "app": "org.inkscape.Inkscape.desktop",    "tab": "create" },
        { "name": "GIMP",        "nameEn": "GIMP",        "icon": "gimp",             "app": "org.gimp.GIMP.desktop",            "tab": "create" },
        { "name": "Scribus",     "nameEn": "Scribus",     "icon": "scribus",          "app": "net.scribus.Scribus.desktop",      "tab": "create" },
        { "name": "LibreOffice", "nameEn": "LibreOffice", "icon": "libreoffice",      "app": "org.libreoffice.LibreOffice.desktop", "tab": "create" },

        // Медиа и повседневное
        { "name": "Firefox",     "nameEn": "Firefox",     "icon": "firefox",          "app": "org.mozilla.firefox.desktop",      "tab": "media" },
        { "name": "Фотографии",  "nameEn": "Photos",      "icon": "gwenview",         "app": "org.kde.gwenview.desktop",         "tab": "media" },
        { "name": "Снимок экрана","nameEn": "Screenshot", "icon": "spectacle",        "app": "org.kde.spectacle.desktop",        "tab": "media" },
        { "name": "Видео",       "nameEn": "Video",       "icon": "mpv",              "app": "mpv.desktop",                      "tab": "media" },

        // Система
        { "name": "Параметры",        "nameEn": "Settings",     "icon": "systemsettings", "app": "systemsettings.desktop",           "tab": "system" },
        { "name": "Магазин",          "nameEn": "Store",        "icon": "plasmadiscover", "app": "org.kde.discover.desktop",         "tab": "system" },
        { "name": "Файлы",            "nameEn": "Files",        "icon": "system-file-manager", "app": "org.kde.dolphin.desktop",     "tab": "system" },
        { "name": "Терминал",         "nameEn": "Terminal",     "icon": "utilities-terminal", "app": "org.kde.konsole.desktop",     "tab": "system" },
        { "name": "Архивы",           "nameEn": "Archives",     "icon": "ark",            "app": "org.kde.ark.desktop",              "tab": "system" },
        { "name": "Профиль нагрузки", "nameEn": "Performance",  "icon": "speedometer",    "app": "framz-tune.desktop",               "tab": "system" },
        { "name": "Обновления FRAMZ", "nameEn": "FRAMZ Updates", "icon": "system-software-update", "app": "framz-update.desktop",      "tab": "system" },
        { "name": "Справка FRAMZ",    "nameEn": "FRAMZ Help",   "icon": "help-contents",  "app": "framz-help.desktop",               "tab": "system" },
        { "name": "Первый запуск",    "nameEn": "First run",    "icon": "framz-logo",     "app": "framz-welcome.desktop",            "tab": "system" }
    ]

    property int currentTab: 0
    readonly property var tabIds: ["create", "media", "system"]

    // Состав плиток: вкладка + поиск
    readonly property var visibleApps: {
        var tab = root.tabIds[root.currentTab];
        // читаем поле поиска, чтобы список пересобирался при вводе
        // searchField создаётся ниже по файлу — на этапе инициализации его может ещё не быть
        var query = (searchField ? (searchField.text || "") : "").toLowerCase().trim();
        var out = [];
        for (var i = 0; i < root.catalog.length; ++i) {
            var app = root.catalog[i];
            if (app.tab !== tab) {
                continue;
            }
            if (query.length > 0
                && app.name.toLowerCase().indexOf(query) === -1
                && app.nameEn.toLowerCase().indexOf(query) === -1) {
                continue;
            }
            out.push(app);
        }
        return out;
    }

    function label(app) {
        return root.ru ? app.name : app.nameEn;
    }

    readonly property bool ru: Qt.locale().name.indexOf("ru") === 0

    function launch(appFile) {
        if (!appFile) {
            return;
        }
        Qt.openUrlExternally("applications:" + appFile);
        root.expanded = false;
    }

    // ── кнопка в панели ───────────────────────────────────────────────────
    compactRepresentation: Item {
        Layout.preferredWidth: 34
        Layout.preferredHeight: 34

        PlasmaCore.IconItem {
            anchors.centerIn: parent
            width: 26
            height: 26
            source: "framz-logo"
            active: mouseArea.containsMouse
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.expanded = !root.expanded
        }
    }

    // ── раскрытое меню ────────────────────────────────────────────────────
    fullRepresentation: Item {
        Layout.preferredWidth: 460
        Layout.preferredHeight: 560

        Rectangle {
            anchors.fill: parent
            radius: 14
            color: Qt.rgba(0.043, 0.043, 0.071, 0.96)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // шапка: знак + заголовок
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                PlasmaCore.IconItem {
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 26
                    source: "framz-logo"
                }

                PC3.Label {
                    Layout.fillWidth: true
                    text: root.ru ? "FRAMZ Запуск" : "FRAMZ Launcher"
                    font.pointSize: 13
                    font.weight: Font.DemiBold
                    color: "#EDEDF2"
                }
            }

            // поиск
            PC3.TextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: root.ru ? "Найти приложение…" : "Find an app…"
            }

            // вкладки
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: [root.ru ? "Творчество" : "Create",
                            root.ru ? "Медиа" : "Media",
                            root.ru ? "Система" : "System"]

                    PC3.Button {
                        Layout.fillWidth: true
                        text: modelData
                        checkable: true
                        checked: root.currentTab === index
                        onClicked: {
                            root.currentTab = index;
                            searchField.text = "";
                        }
                    }
                }
            }

            // плитки приложений
            GridView {
                id: grid
                Layout.fillWidth: true
                Layout.fillHeight: true
                cellWidth: 100
                cellHeight: 100
                clip: true
                model: root.visibleApps
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    width: grid.cellWidth
                    height: grid.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 4
                        radius: 12
                        color: tileMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
                        border.width: tileMouse.containsMouse ? 1 : 0
                        border.color: root.accentColor
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6

                        PlasmaCore.IconItem {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 40
                            source: modelData.icon
                        }

                        PC3.Label {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignHCenter
                            horizontalAlignment: Text.AlignHCenter
                            text: root.label(modelData)
                            color: "#EDEDF2"
                            font.pointSize: 9
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            wrapMode: Text.WordWrap
                        }
                    }

                    MouseArea {
                        id: tileMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.launch(modelData.app)
                    }
                }

                // когда поиск ничего не нашёл
                PC3.Label {
                    anchors.centerIn: parent
                    visible: grid.count === 0
                    text: root.ru ? "Ничего не нашлось" : "Nothing found"
                    color: root.dimColor
                }
            }

            // подсказка
            PC3.Label {
                Layout.fillWidth: true
                text: root.ru
                      ? "Все приложения — в магазине «Магазин», обновления — в «Параметрах»"
                      : "More apps in Store, updates in System Settings"
                color: root.dimColor
                font.pointSize: 8
                elide: Text.ElideRight
            }
        }
    }

    preferredRepresentation: fullRepresentation
}
