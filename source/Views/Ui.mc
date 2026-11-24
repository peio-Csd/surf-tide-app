using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;

// Couleurs et petits éléments graphiques partagés par toutes les pages.
// Les couleurs sont choisies dans la palette 64 couleurs (composantes 00/55/AA/FF)
// pour un rendu identique sur écrans AMOLED (FR165, FR265...) et MIP (FR955, Fenix...).
module Ui {

    const BG = 0x000000;
    const TEXT = 0xFFFFFF;
    const MUTED = 0xAAAAAA;
    const DIM = 0x555555;
    const ACCENT = 0x55AAFF;     // bleu océan (titres)
    const HIGH_TIDE = 0x55AAFF;  // pleine mer : bleu
    const LOW_TIDE = 0xFFAA55;   // basse mer : sable
    const TIDE_FILL = 0x0055AA;
    const ERROR = 0xFF5555;

    // Vent : bleu "transparent" très faible -> vert léger -> jaune/orange -> rouge fort
    function windColor(kmh) {
        if (kmh < 8) { return 0x0055FF; }
        if (kmh < 15) { return 0x55FF55; }
        if (kmh < 25) { return 0xFFFF00; }
        if (kmh < 35) { return 0xFFAA00; }
        return 0xFF0000;
    }

    // Vagues : petit -> gris, surfable -> cyan/vert, gros -> orange/rouge
    function waveColor(m) {
        m = Math.round(m * 10) / 10.0;   // même arrondi que la valeur affichée
        if (m < 0.5) { return 0xAAAAAA; }
        if (m < 1.0) { return 0x55FFFF; }
        if (m < 2.0) { return 0x55FF55; }
        if (m < 3.0) { return 0xFFAA00; }
        return 0xFF5555;
    }

    function tideColor(ev) {
        return ev.isHigh() ? HIGH_TIDE : LOW_TIDE;
    }

    // Demi-largeur utilisable à la hauteur y sur un écran rond (marge comprise)
    function halfChord(w, h, y, margin) {
        var r = w / 2.0;
        var dy = (y - h / 2.0).abs();
        if (dy >= r) { return 0; }
        var hc = Math.sqrt(r * r - dy * dy) - margin;
        return hc < 0 ? 0 : hc.toNumber();
    }

    // Angle (degrés, 0 = nord, sens horaire) d'une direction texte.
    // Accepte l'anglais (N, NNE, WSW...) et le français (O, SO, ONO...).
    function directionAngle(dir) {
        if (dir == null) { return null; }
        var d = dir.toUpper();
        var en = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                  "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"];
        var fr = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                  "S", "SSO", "SO", "OSO", "O", "ONO", "NO", "NNO"];
        for (var i = 0; i < 16; i++) {
            if (en[i].equals(d) || fr[i].equals(d)) { return i * 22.5; }
        }
        return null;
    }

    // Flèche de vent centrée en (x, y). La direction est celle d'où VIENT le vent
    // (convention météo) ; la flèche pointe là où il VA, comme sur surf-report.
    function drawWindArrow(dc, x, y, dir, size, color) {
        var angle = directionAngle(dir);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        if (angle == null) {
            dc.fillCircle(x, y, size / 4);
            return;
        }
        var a = Math.toRadians(angle + 180);
        var s = Math.sin(a);
        var c = -Math.cos(a);           // axe y de l'écran vers le bas
        // pointe, ailes, encoche arrière
        var tip = [x + s * size, y + c * size];
        var back = [x - s * size * 0.35, y - c * size * 0.35];
        var px = -c;                    // perpendiculaire
        var py = s;
        var w = size * 0.75;
        var left = [x - s * size + px * w, y - c * size + py * w];
        var right = [x - s * size - px * w, y - c * size - py * w];
        dc.fillPolygon([tip, left, back, right]);
    }

    // Petit triangle haut (pleine mer) / bas (basse mer)
    function drawTideMark(dc, x, y, high, size, color) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        if (high) {
            dc.fillPolygon([[x, y - size], [x + size, y + size * 0.7], [x - size, y + size * 0.7]]);
        } else {
            dc.fillPolygon([[x, y + size], [x + size, y - size * 0.7], [x - size, y - size * 0.7]]);
        }
    }

    // Indicateur de page sur le bord droit, façon menus Garmin
    function drawPageDots(dc, w, h, page, total) {
        if (total <= 1) { return; }
        var r = w / 2.0;
        var radius = r - (w * 0.035);
        var step = 5.0;                        // degrés entre deux points
        var start = -(total - 1) * step / 2.0;
        var dotR = w >= 360 ? 4 : 3;
        for (var i = 0; i < total; i++) {
            var a = Math.toRadians(start + i * step);
            var px = r + radius * Math.cos(a);
            var py = r + radius * Math.sin(a);
            if (i == page) {
                dc.setColor(TEXT, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(px, py, dotR);
            } else {
                dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(px, py, dotR - 1);
            }
        }
    }

    // Raccourcit un texte avec "…" pour qu'il tienne dans maxW pixels
    function fit(dc, str, font, maxW) {
        if (dc.getTextWidthInPixels(str, font) <= maxW) { return str; }
        var n = str.length();
        while (n > 1 && dc.getTextWidthInPixels(str.substring(0, n) + "…", font) > maxW) {
            n--;
        }
        return str.substring(0, n) + "…";
    }

    // Texte centré verticalement sur y
    function text(dc, x, y, font, str, color, justify) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, str, justify | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Plusieurs morceaux de couleurs différentes sur une même ligne, centrés en x
    function textRow(dc, cx, y, font, parts, colors) {
        var total = 0;
        for (var i = 0; i < parts.size(); i++) {
            total += dc.getTextWidthInPixels(parts[i], font);
        }
        var x = cx - total / 2;
        for (var i = 0; i < parts.size(); i++) {
            text(dc, x, y, font, parts[i], colors[i], Graphics.TEXT_JUSTIFY_LEFT);
            x += dc.getTextWidthInPixels(parts[i], font);
        }
    }
}
