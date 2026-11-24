using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Application.Storage;
using Toybox.Lang;

// Aperçu (glance) affiché dans la liste des widgets du cadran :
//   ligne 1 : vague moyenne du jour
//   ligne 2 : les 2 prochaines marées, dans l'ordre chronologique
// Le glance a très peu de mémoire : il ne lit qu'un petit résumé préparé par l'app.
(:glance)
class SurfGlanceView extends WatchUi.GlanceView {

    function initialize() {
        GlanceView.initialize();
    }

    function onUpdate(dc) {
        var h = dc.getHeight();
        var font = (Graphics has :FONT_GLANCE) ? Graphics.FONT_GLANCE : Graphics.FONT_XTINY;
        var lineH = dc.getFontHeight(font);
        var y1 = h / 2 - lineH / 2;
        var y2 = h / 2 + lineH / 2;
        var just = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;

        var data = null;
        try {
            data = Storage.getValue("glance");
        } catch (e) {
            data = null;
        }

        if (!(data instanceof Lang.Dictionary)) {
            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
            dc.drawText(0, y1, font, "WAVES", just);
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            dc.drawText(0, y2, font, "Ouvrir l'app", just);
            return;
        }

        var now = Fmt.now();

        // Vague moyenne d'aujourd'hui
        var wave = null;
        var waves = data["w"];
        for (var i = 0; i < waves.size(); i++) {
            if (now >= waves[i][0] && now < waves[i][0] + 86400) {
                wave = waves[i][1];
                break;
            }
        }
        var x = 0;
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        var title = data["spot"].toUpper() + "  ";
        dc.drawText(x, y1, font, title, just);
        x += dc.getTextWidthInPixels(title, font);
        dc.setColor(0x55FF55, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y1, font, wave != null ? Fmt.meters(wave) + " m" : "-- m", just);

        // 2 prochaines marées (▲ pleine mer, ▼ basse mer), ordre chronologique
        var tides = data["t"];
        var mark = lineH / 6;
        x = mark;
        var shown = 0;
        for (var i = 0; i < tides.size() && shown < 2; i++) {
            if (tides[i][0] <= now) { continue; }
            var high = tides[i][1] == 1;
            dc.setColor(high ? 0x55AAFF : 0xFFAA55, Graphics.COLOR_TRANSPARENT);
            if (high) {
                dc.fillPolygon([[x, y2 - mark], [x + mark, y2 + mark * 0.7], [x - mark, y2 + mark * 0.7]]);
            } else {
                dc.fillPolygon([[x, y2 + mark], [x + mark, y2 - mark * 0.7], [x - mark, y2 - mark * 0.7]]);
            }
            x += mark * 2;
            var t = Fmt.timeOf(tides[i][0]);
            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y2, font, t, just);
            x += dc.getTextWidthInPixels(t + "  ", font) + mark;
            shown++;
        }
        if (shown == 0) {
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            dc.drawText(0, y2, font, "Données à rafraîchir", just);
        }
    }
}
