// FRAMZ OS — экран входа (тема SDDM), стиль Minimal Mono.
//
// Устройство: почти чёрный фон + наши обои, по центру знак FRAMZ, список
// пользователей, поле пароля, выбор сессии, кнопки питания.
//
// Написано только на общедоступных модулях (QtQuick, Layouts, Controls,
// org.kde.plasma.components) — без приватных компонентов Breeze, чтобы тема
// не сломалась при обновлении Plasma.
//
// Опирается на проверенный набор объектов SDDM:
//   sddm.login(имя, пароль, номер сессии), sddm.powerOff/reboot/suspend,
//   userModel (роли name/realName/icon/lastUser/lastIndex), sessionModel.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PC3

Item {
    id: root

    width: 1600
    height: 900

    // ── язык: русский, если локаль русская; иначе английский ────────────────
    readonly property bool ru: Qt.locale().name.indexOf("ru") === 0
    function t(ruText, enText) { return root.ru ? ruText : enText }

    property string notificationMessage: ""
    property string userName: ""
    property var userNames: []

    // ── фон ────────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: config.background ? config.background : "#0B0B12"
    }

    Image {
        anchors.fill: parent
        source: "file:///usr/share/framz/branding/wallpapers/framz-frame-dark.jpg"
        fillMode: Image.PreserveAspectCrop
        opacity: 0.45
        asynchronous: true
    }

    // ── сбор имён пользователей (роли модели доступны в делегате) ──────────
    Repeater {
        model: userModel
        Item {
            Component.onCompleted: {
                var list = root.userNames.slice(0);
                if (list.indexOf(name) === -1) {
                    list.push(name);
                }
                root.userNames = list;
                if (root.userName === "") {
                    // сначала последний вошедший, иначе первый в списке
                    root.userName = (userModel.lastUser && list.indexOf(userModel.lastUser) !== -1)
                        ? userModel.lastUser : list[0];
                }
            }
        }
    }

    // ── центральный блок ───────────────────────────────────────────────────
    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.36, 520)
        spacing: 18

        // знак FRAMZ
        Image {
            Layout.alignment: Qt.AlignHCenter
            source: "logo.png"
            sourceSize.width: 96
            sourceSize.height: 96
        }

        PC3.Label {
            Layout.alignment: Qt.AlignHCenter
            text: t(config.greeting, config.greetingEn)
            font.pointSize: 20
            font.weight: Font.DemiBold
            color: "#EDEDF2"
        }

        PC3.Label {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            text: t(config.hint, config.hintEn)
            color: "#9A9AAB"
        }

        // список пользователей
        ListView {
            id: userList
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 160)
            clip: true
            spacing: 6
            visible: userModel.count > 0
            model: userModel
            currentIndex: {
                for (var i = 0; i < root.userNames.length; ++i) {
                    if (root.userNames[i] === root.userName) {
                        return i;
                    }
                }
                return 0;
            }

            delegate: PC3.ItemDelegate {
                width: userList.width
                text: (typeof realName !== "undefined" && realName && realName !== name) ? realName : name
                highlighted: ListView.isCurrentItem
                onClicked: {
                    root.userName = name;
                    passwordField.forceActiveFocus();
                }
            }
        }

        // имя пользователя (когда список пуст — например, все пользователи скрыты)
        PC3.TextField {
            id: usernameField
            Layout.fillWidth: true
            visible: userModel.count === 0
            placeholderText: t(config.usernamePlaceholder, config.usernamePlaceholderEn)
            text: root.userName
            onTextChanged: root.userName = text
            onAccepted: passwordField.forceActiveFocus()
        }

        // пароль
        PC3.TextField {
            id: passwordField
            Layout.fillWidth: true
            placeholderText: t(config.passwordPlaceholder, config.passwordPlaceholderEn)
            echoMode: TextInput.Password
            focus: true
            enabled: root.notificationMessage !== t(config.wrongPassword, config.wrongPasswordEn)
                    || root.notificationMessage === ""
            onAccepted: root.startLogin()
            onTextChanged: if (root.notificationMessage !== "") { root.notificationMessage = ""; }
        }

        // сообщение об ошибке / Caps Lock
        PC3.Label {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: {
                if (root.notificationMessage !== "") {
                    return root.notificationMessage;
                }
                if (typeof keyboard !== "undefined" && keyboard && keyboard.capsLock) {
                    return t(config.capsLock, config.capsLockEn);
                }
                return "";
            }
            color: root.notificationMessage !== "" ? "#E2603F" : "#9A9AAB"
        }

        // кнопка входа
        PC3.Button {
            Layout.fillWidth: true
            text: t(config.loginButton, config.loginButtonEn)
            enabled: root.userName.length > 0
            onClicked: root.startLogin()
        }

        // выбор сессии
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            PC3.Label {
                text: root.ru ? "Сессия:" : "Session:"
                color: "#9A9AAB"
            }

            PC3.ComboBox {
                id: sessionBox
                Layout.fillWidth: true
                model: sessionModel
                textRole: "name"
                currentIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
                onActivated: sessionModel.lastIndex = currentIndex
            }
        }

        // кнопки питания
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 6
            spacing: 14

            PC3.Button {
                icon.name: "system-suspend"
                text: t(config.suspend, config.suspendEn)
                onClicked: sddm.suspend()
            }
            PC3.Button {
                icon.name: "system-reboot"
                text: t(config.reboot, config.rebootEn)
                onClicked: sddm.reboot()
            }
            PC3.Button {
                icon.name: "system-shutdown"
                text: t(config.powerOff, config.powerOffEn)
                enabled: sddm.canPowerOff
                onClicked: sddm.powerOff()
            }
        }
    }

    // ── вход и реакция на ошибку ───────────────────────────────────────────
    function startLogin() {
        var user = root.userName.length > 0 ? root.userName : usernameField.text;
        if (user.length === 0) {
            return;
        }
        root.notificationMessage = "";
        sddm.login(user, passwordField.text, sessionBox.currentIndex);
    }

    Connections {
        target: sddm

        function onLoginFailed() {
            root.notificationMessage = root.t(config.wrongPassword, config.wrongPasswordEn);
            passwordField.text = "";
            passwordField.forceActiveFocus();
        }
    }
}
