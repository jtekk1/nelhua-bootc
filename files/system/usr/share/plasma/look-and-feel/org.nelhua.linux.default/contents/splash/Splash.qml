// Nelhua Plasma splash screen.
//
// Shown between SDDM/plasmalogin and plasmashell ready. Stage hand-off:
// 1 = wm starting, 2 = plasmashell starting (fade content in), 3 = panels,
// 4 = desktop ready, 5 = handoff (fade busy indicator out).
//
// Structure cribbed from org.fedoraproject.fedoradark.desktop/contents/splash/
// (GPL-2.0-or-later). Differences:
//   - BG #0d0d0d to match the near-black behind the logo asset, so the
//     PNG's anti-aliased edges blend instead of standing out.
//   - Native logo.png (full brand mark — jaguar head + NELHUA LINUX
//     wordmark) instead of plasma.svgz.
//   - QtQuick.Controls.BusyIndicator instead of rotating SVG. Inherits
//     AccentColor (#B875DC) from kdeglobals automatically — one less
//     asset to maintain, automatically tracks accent changes.
//   - No "Plasma made by KDE" watermark. We're Nelhua.

import QtQuick
import QtQuick.Controls
import org.kde.kirigami as Kirigami

Rectangle {
    id: root
    color: "#0d0d0d"

    property int stage

    onStageChanged: {
        if (stage == 2) {
            introAnimation.running = true;
        } else if (stage == 5) {
            introAnimation.target = busyIndicator;
            introAnimation.from = 1;
            introAnimation.to = 0;
            introAnimation.running = true;
        }
    }

    Item {
        id: content
        anchors.fill: parent
        opacity: 0

        Image {
            id: logo
            // Source asset is portrait 704x854. Pick height; width follows
            // aspect. gridUnit*16 ≈ 288px on a typical 96-dpi display —
            // dominant but doesn't crowd the spinner.
            readonly property real logoHeight: Kirigami.Units.gridUnit * 16
            readonly property real logoWidth: logoHeight * (704.0 / 854.0)

            anchors.centerIn: parent

            asynchronous: true
            source: "images/logo.png"

            sourceSize.width: logoWidth
            sourceSize.height: logoHeight
        }

        BusyIndicator {
            id: busyIndicator
            anchors.horizontalCenter: parent.horizontalCenter
            y: logo.y + logo.height + Kirigami.Units.gridUnit * 3
            // Inherits Plasma's accent color automatically. No manual tint.
        }
    }

    OpacityAnimator {
        id: introAnimation
        running: false
        target: content
        from: 0
        to: 1
        duration: Kirigami.Units.veryLongDuration * 2
        easing.type: Easing.InOutQuad
    }
}
