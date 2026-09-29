/*
    FRAMZ OS — экран загрузки.
    Фирменный приём: метки кадрирования по углам + знак FRAMZ.
*/

import QtQuick
import QtQuick.Controls as Controls

Rectangle {
    id: root
    color: "#0B0B12"          // Frame Dark — глубокий чёрный с холодным отливом
    property int stage

    // --- метки кадрирования по углам (визуальный код FRAMZ) -------------------
    component CropMark: Rectangle {
        width: 84
        height: 24
        color: "#8B5CF6"
        opacity: 0.55
    }

    Item {
        anchors.fill: parent

        // верхний левый
        CropMark { anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 64 }
        Rectangle { width: 24; height: 84; color: "#8B5CF6"; opacity: 0.55
                    anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 64 }
        // верхний правый
        CropMark { anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 64 }
        Rectangle { width: 24; height: 84; color: "#8B5CF6"; opacity: 0.55
                    anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 64 }
        // нижний левый
        CropMark { anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 64 }
        Rectangle { width: 24; height: 84; color: "#8B5CF6"; opacity: 0.55
                    anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 64 }
        // нижний правый
        CropMark { anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 64 }
        Rectangle { width: 24; height: 84; color: "#8B5CF6"; opacity: 0.55
                    anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 64 }
    }

    // --- знак FRAMZ ----------------------------------------------------------
    Image {
        id: logo
        anchors.centerIn: parent
        readonly property real side: Math.min(root.width, root.height) * 0.24
        width: side
        height: side
        source: "images/framz-mark.svg"
        sourceSize.width: side
        sourceSize.height: side
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        opacity: 0

        NumberAnimation on opacity {
            to: 1.0
            duration: 600
            easing.type: Easing.InOutQuad
            running: true
        }
    }

    // --- индикатор загрузки --------------------------------------------------
    Controls.BusyIndicator {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: logo.bottom
        anchors.topMargin: 48
        width: 40
        height: 40
        running: root.stage < 5
        visible: root.stage < 5
        palette.dark: "#8B5CF6"
    }

    // --- подпись -------------------------------------------------------------
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 64
        color: "#8B5CF6"
        text: "FRAMZ OS"
        font.pointSize: 13
        font.letterSpacing: 8
        opacity: 0.85
        Accessible.name: text
        Accessible.role: Accessible.StaticText
    }
}
