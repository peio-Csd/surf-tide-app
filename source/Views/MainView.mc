using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;
using Toybox.Application;

// Vue principale, organisée en pages (boutons HAUT/BAS ou glisser vertical) :
//   0 : Aujourd'hui (résumé)
//   1 : Marées du jour (courbe + horaires)
//   2 : Vagues par créneau
//   3 : Vent par créneau
//   4+: un résumé par jour suivant
// Toutes les positions sont calculées en proportion de l'écran et de la hauteur
// réelle des polices : le rendu s'adapte de 240 px (MIP) à 454 px (AMOLED).
class MainView extends WatchUi.View {

    const FIXED_PAGES = 4;

    var page = 0;

    private var _w;
    private var _h;
    private var _cx;
    private var _hXtiny;
    private var _hTiny;
    private var _hSmall;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc) {
        _w = dc.getWidth();
        _h = dc.getHeight();
        _cx = _w / 2;
        _hXtiny = dc.getFontHeight(Graphics.FONT_XTINY);
        _hTiny = dc.getFontHeight(Graphics.FONT_TINY);
        _hSmall = dc.getFontHeight(Graphics.FONT_SMALL);
    }

    function onShow() {
        dm().refreshIfNeeded();
    }

    private function dm() {
        return Application.getApp().dataManager;
    }

    // ---------------------------------------------------------------
    // Navigation
    // ---------------------------------------------------------------

    function pageCount() {
        var n = dm().getDays().size();
        return n > 0 ? FIXED_PAGES + n - 1 : 1;
    }

    function nextPage() {
        page = (page + 1) % pageCount();
        WatchUi.requestUpdate();
    }

    function prevPage() {
        var n = pageCount();
        page = (page - 1 + n) % n;
        WatchUi.requestUpdate();
    }

    function goHome() {
        if (page == 0) { return false; }
        page = 0;
        WatchUi.requestUpdate();
        return true;
    }

    // ---------------------------------------------------------------
    // Rendu
    // ---------------------------------------------------------------

    function onUpdate(dc) {
        dc.setColor(Ui.BG, Ui.BG);
        dc.clear();
        if (dc has :setAntiAlias) { dc.setAntiAlias(true); }

        var data = dm();
        var days = data.getDays();
        if (days.size() == 0) {
            page = 0;
            drawEmpty(dc, data);
            return;
        }
        if (page >= pageCount()) { page = 0; }

        if (page == 0) { drawToday(dc, data, days[0]); }
        else if (page == 1) { drawTides(dc, data, days[0]); }
        else if (page == 2) { drawWaves(dc, days[0]); }
        else if (page == 3) { drawWind(dc, days[0]); }
        else { drawDay(dc, days[page - FIXED_PAGES + 1]); }

        Ui.drawPageDots(dc, _w, _h, page, pageCount());
    }

    // y en proportion de la hauteur d'écran
    private function py(f) {
        return (_h * f).toNumber();
    }

    private function px(f) {
        return (_w * f).toNumber();
    }

    private function drawTitle(dc, title) {
        Ui.text(dc, _cx, py(0.13), Graphics.FONT_XTINY, title, Ui.ACCENT, Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function hLine(dc, y) {
        var half = Ui.halfChord(_w, _h, y, px(0.10));
        dc.setColor(Ui.DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(_cx - half, y, _cx + half, y);
    }

    // ----- Écran sans données -----------------------------------------
    private function drawEmpty(dc, data) {
        drawTitle(dc, data.spotLabel().toUpper());
        if (data.isSyncing) {
            Ui.text(dc, _cx, py(0.45), Graphics.FONT_SMALL, "Chargement…", Ui.TEXT, Graphics.TEXT_JUSTIFY_CENTER);
            Ui.text(dc, _cx, py(0.45) + _hSmall, Graphics.FONT_XTINY, "Le serveur peut mettre", Ui.MUTED, Graphics.TEXT_JUSTIFY_CENTER);
            Ui.text(dc, _cx, py(0.45) + _hSmall + _hXtiny, Graphics.FONT_XTINY, "jusqu'à 1 min à répondre", Ui.MUTED, Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            var msg = data.errorMessage != null ? data.errorMessage : "Aucune donnée";
            Ui.text(dc, _cx, py(0.45), Graphics.FONT_SMALL, msg, Ui.ERROR, Graphics.TEXT_JUSTIFY_CENTER);
            Ui.text(dc, _cx, py(0.45) + _hSmall, Graphics.FONT_XTINY, "START : réessayer", Ui.MUTED, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // ----- Page 0 : aujourd'hui ----------------------------------------
    private function drawToday(dc, data, today) {
        drawTitle(dc, data.spotLabel().toUpper() + " · " + Fmt.dayShort(today.dayOfWeek) + " " + today.day);

        // Vague moyenne, en grand
        var avg = today.avgWave();
        var numFont = Graphics.FONT_NUMBER_MEDIUM;
        var numStr = today.hasSurf() ? Fmt.meters(avg) : "--";
        var unit = " m";
        var yNum = py(0.30);
        var wNum = dc.getTextWidthInPixels(numStr, numFont);
        var wUnit = dc.getTextWidthInPixels(unit, Graphics.FONT_SMALL);
        var x0 = _cx - (wNum + wUnit) / 2;
        var color = Ui.waveColor(avg);
        Ui.text(dc, x0, yNum, numFont, numStr, color, Graphics.TEXT_JUSTIFY_LEFT);
        // unité alignée sur le bas des chiffres
        var numH = dc.getFontHeight(numFont);
        Ui.text(dc, x0 + wNum, yNum + numH / 4, Graphics.FONT_SMALL, unit, color, Graphics.TEXT_JUSTIFY_LEFT);

        // Houle du créneau actuel
        var slot = currentSlot(today);
        var ySwell = yNum + numH / 2 + _hXtiny / 2;
        if (slot != null) {
            Ui.textRow(dc, _cx, ySwell, Graphics.FONT_XTINY,
                ["houle ", (slot.swellHeight > 0 ? Fmt.meters(slot.swellHeight) + " m  " : "") + slot.swellDirection + "  " + slot.swellPeriod + " s"],
                [Ui.MUTED, Ui.TEXT]);
        }

        var ySep = py(0.53);
        hLine(dc, ySep);

        // Deux colonnes : prochaine marée | vent actuel
        var yLabel = ySep + _hXtiny * 3 / 4;
        var yValue = yLabel + _hXtiny / 2 + _hSmall / 2;
        var ySub = yValue + _hSmall / 2 + _hXtiny / 2;
        var xl = _cx - px(0.20);
        var xr = _cx + px(0.20);

        dc.setColor(Ui.DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(_cx, ySep + px(0.03), _cx, ySub + _hXtiny / 2);

        Ui.text(dc, xl, yLabel, Graphics.FONT_XTINY, "MARÉE", Ui.MUTED, Graphics.TEXT_JUSTIFY_CENTER);
        var next = data.nextTides(1);
        if (next.size() > 0) {
            var ev = next[0];
            drawMarkedValue(dc, xl, yValue, ev);
            Ui.text(dc, xl, ySub, Graphics.FONT_XTINY,
                (ev.isHigh() ? "pleine" : "basse") + " · " + ev.coefficient, Ui.MUTED, Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            Ui.text(dc, xl, yValue, Graphics.FONT_SMALL, "--", Ui.MUTED, Graphics.TEXT_JUSTIFY_CENTER);
        }

        Ui.text(dc, xr, yLabel, Graphics.FONT_XTINY, "VENT", Ui.MUTED, Graphics.TEXT_JUSTIFY_CENTER);
        if (slot != null) {
            drawWindValue(dc, xr, yValue, slot.windDirection, slot.windSpeed);
            Ui.text(dc, xr, ySub, Graphics.FONT_XTINY,
                slot.windDirection + " · km/h", Ui.MUTED, Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            Ui.text(dc, xr, yValue, Graphics.FONT_SMALL, "--", Ui.MUTED, Graphics.TEXT_JUSTIFY_CENTER);
        }

        drawStatus(dc, data, py(0.87));
    }

    // "▲ 13:14" centré en x, couleur selon le type de marée
    private function drawMarkedValue(dc, x, y, ev) {
        var str = ev.getTimeString();
        var mark = (_hSmall / 5).toNumber();
        var w = dc.getTextWidthInPixels(str, Graphics.FONT_SMALL);
        var gap = mark;
        var start = x - (mark * 2 + gap + w) / 2;
        Ui.drawTideMark(dc, start + mark, y, ev.isHigh(), mark, Ui.tideColor(ev));
        Ui.text(dc, start + mark * 2 + gap, y, Graphics.FONT_SMALL, str, Ui.TEXT, Graphics.TEXT_JUSTIFY_LEFT);
    }

    // flèche + vitesse, centré en x
    private function drawWindValue(dc, x, y, dir, speed) {
        var str = "" + speed;
        var size = (_hSmall / 3).toNumber();
        var w = dc.getTextWidthInPixels(str, Graphics.FONT_SMALL);
        var gap = size;
        var start = x - (size * 2 + gap + w) / 2;
        var color = Ui.windColor(speed);
        Ui.drawWindArrow(dc, start + size, y, dir, size, color);
        Ui.text(dc, start + size * 2 + gap, y, Graphics.FONT_SMALL, str, color, Graphics.TEXT_JUSTIFY_LEFT);
    }

    private function drawStatus(dc, data, y) {
        var msg;
        var color = Ui.DIM;
        if (data.isSyncing) {
            msg = "synchro…";
            color = Ui.MUTED;
        } else if (data.errorMessage != null) {
            msg = data.errorMessage;
            color = Ui.ERROR;
        } else if (data.isMock) {
            msg = "données simulées";
            color = Ui.LOW_TIDE;
        } else if (data.lastSync != null) {
            msg = "màj " + Fmt.timeOf(data.lastSync);
        } else {
            return;
        }
        Ui.text(dc, _cx, y, Graphics.FONT_XTINY, msg, color, Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function currentSlot(day) {
        var idx = day.slotIndexAt(nowHour());
        return idx < 0 ? null : day.hours[idx];
    }

    private function nowHour() {
        var info = Toybox.Time.Gregorian.info(Toybox.Time.now(), Toybox.Time.FORMAT_SHORT);
        return info.hour;
    }

    // ----- Page 1 : marées ---------------------------------------------
    private function drawTides(dc, data, today) {
        drawTitle(dc, "MARÉES");
        if (!today.hasTides()) {
            Ui.text(dc, _cx, py(0.5), Graphics.FONT_SMALL, "Pas de données", Ui.MUTED, Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        var yCoef = py(0.21);
        var full = "coef matin " + today.morningCoeff + "  ·  aprèm " + today.afternoonCoeff;
        if (dc.getTextWidthInPixels(full, Graphics.FONT_XTINY) <= Ui.halfChord(_w, _h, yCoef - _hXtiny / 2, px(0.04)) * 2) {
            Ui.textRow(dc, _cx, yCoef, Graphics.FONT_XTINY,
                ["coef matin ", "" + today.morningCoeff, "  ·  aprèm ", "" + today.afternoonCoeff],
                [Ui.MUTED, Ui.TEXT, Ui.MUTED, Ui.TEXT]);
        } else {
            Ui.textRow(dc, _cx, yCoef, Graphics.FONT_XTINY,
                ["coef ", today.morningCoeff + " · " + today.afternoonCoeff],
                [Ui.MUTED, Ui.TEXT]);
        }

        // Courbe de marée sur 24 h
        var top = py(0.28);
        var bottom = py(0.50);
        var half = px(0.36);
        drawTideCurve(dc, data.allTides(), today.midnight, _cx - half, _cx + half, top, bottom);

        // Liste des 4 marées du jour
        var rows = today.tides.size();
        var yStart = py(0.59);
        var yEnd = py(0.85);
        var step = rows > 1 ? (yEnd - yStart) / (rows - 1) : 0;
        if (step > _hTiny) { step = _hTiny; }
        yStart = (yStart + yEnd) / 2 - step * (rows - 1) / 2;

        // Colonnes dimensionnées sur la largeur réelle du texte (les polices MIP sont plus larges)
        var mark = (_hTiny / 6).toNumber();
        var wTime = dc.getTextWidthInPixels("00:00", Graphics.FONT_TINY);
        var withHeights = today.hasTideHeights();
        var wHeight = dc.getTextWidthInPixels(withHeights ? "0.0 m" : "coef 100", Graphics.FONT_XTINY);
        var gap = px(0.05);
        var x0 = _cx - (mark * 2 + gap + wTime + gap + wHeight) / 2;
        var xTime = x0 + mark * 2 + gap;
        var xHeight = xTime + wTime + gap + wHeight;

        var now = Fmt.now();
        for (var i = 0; i < rows; i++) {
            var ev = today.tides[i];
            var y = yStart + i * step;
            var past = ev.time < now;
            Ui.drawTideMark(dc, x0 + mark, y, ev.isHigh(), mark, past ? Ui.DIM : Ui.tideColor(ev));
            Ui.text(dc, xTime, y, Graphics.FONT_TINY, ev.getTimeString(),
                past ? Ui.DIM : Ui.TEXT, Graphics.TEXT_JUSTIFY_LEFT);
            Ui.text(dc, xHeight, y, Graphics.FONT_XTINY,
                withHeights ? Fmt.meters(ev.height) + " m" : "coef " + ev.coefficient,
                past ? Ui.DIM : Ui.MUTED, Graphics.TEXT_JUSTIFY_RIGHT);
        }
    }

    // Sans hauteur d'eau (surf-report), la courbe utilise une forme normalisée PM = 1, BM = 0
    private var _nominalTides = false;

    private function tideLevel(ev) {
        if (_nominalTides) { return ev.isHigh() ? 1.0 : 0.0; }
        return ev.height;
    }

    // Interpolation en cosinus entre deux marées successives
    private function tideHeightAt(tides, t) {
        var n = tides.size();
        if (t <= tides[0].time) { return tideLevel(tides[0]); }
        if (t >= tides[n - 1].time) { return tideLevel(tides[n - 1]); }
        for (var i = 0; i < n - 1; i++) {
            var a = tides[i];
            var b = tides[i + 1];
            if (t >= a.time && t <= b.time) {
                var span = (b.time - a.time).toFloat();
                var f = span > 0 ? (t - a.time) / span : 0.0;
                var ha = tideLevel(a);
                return ha + (tideLevel(b) - ha) * (1 - Math.cos(Math.PI * f)) / 2;
            }
        }
        return tideLevel(tides[n - 1]);
    }

    private function drawTideCurve(dc, tides, midnight, x0, x1, top, bottom) {
        if (tides.size() == 0) { return; }
        _nominalTides = true;
        for (var i = 0; i < tides.size(); i++) {
            if (tides[i].height > 0) { _nominalTides = false; break; }
        }
        var hMin = tideLevel(tides[0]);
        var hMax = hMin;
        for (var i = 1; i < tides.size(); i++) {
            var lv = tideLevel(tides[i]);
            if (lv < hMin) { hMin = lv; }
            if (lv > hMax) { hMax = lv; }
        }
        var range = hMax - hMin;
        if (!_nominalTides && range < 0.5) { range = 0.5; }
        if (range <= 0) { range = 1.0; }

        var width = x1 - x0;
        var prevX = null;
        var prevY = null;
        var step = _w >= 300 ? 3 : 2;
        for (var x = x0; x <= x1; x += step) {
            var t = midnight + ((x - x0).toFloat() / width * 86400).toNumber();
            var hgt = tideHeightAt(tides, t);
            var y = (bottom - (hgt - hMin) / range * (bottom - top)).toNumber();
            dc.setColor(Ui.TIDE_FILL, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x, y, step, bottom - y + 1);
            if (prevX != null) {
                dc.setColor(Ui.ACCENT, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(2);
                dc.drawLine(prevX, prevY, x, y);
                dc.setPenWidth(1);
            }
            prevX = x;
            prevY = y;
        }

        // graduations 6h / 12h / 18h
        dc.setColor(Ui.DIM, Graphics.COLOR_TRANSPARENT);
        for (var hh = 6; hh < 24; hh += 6) {
            var gx = x0 + width * hh / 24;
            dc.drawLine(gx, bottom + 2, gx, bottom + 6);
        }

        // position actuelle
        var now = Fmt.now();
        if (now >= midnight && now < midnight + 86400) {
            var nx = x0 + ((now - midnight).toFloat() / 86400 * width).toNumber();
            var ny = (bottom - (tideHeightAt(tides, now) - hMin) / range * (bottom - top)).toNumber();
            dc.setColor(Ui.TEXT, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(nx, top - 4, nx, bottom);
            dc.fillCircle(nx, ny, _w >= 300 ? 5 : 3);
        }
    }

    // ----- Page 2 : vagues ---------------------------------------------
    private function drawWaves(dc, today) {
        drawTitle(dc, "VAGUES");
        if (!today.hasSurf()) {
            Ui.text(dc, _cx, py(0.5), Graphics.FONT_SMALL, "Pas de données", Ui.MUTED, Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        Ui.textRow(dc, _cx, py(0.21), Graphics.FONT_XTINY,
            ["moy ", Fmt.meters(today.avgWave()), "  ·  max ", Fmt.meters(today.maxWave()), " m"],
            [Ui.MUTED, Ui.TEXT, Ui.MUTED, Ui.TEXT, Ui.MUTED]);

        // Colonnes calées sur la largeur réelle du texte : heure | vagues (min-max) | houle
        var fT = Graphics.FONT_TINY;
        var fX = Graphics.FONT_XTINY;
        var gap = px(0.035);
        var wHour = dc.getTextWidthInPixels("21h", fX);
        var wWave = dc.getTextWidthInPixels("0.0-0.0", fT);
        var wSwell = dc.getTextWidthInPixels("WNW 10s", fX);
        var x0 = _cx - (wHour + gap + wWave + gap + wSwell) / 2;
        var xHour = x0 + wHour;
        var xWave = xHour + gap;
        var xSwell = xWave + wWave + gap + wSwell;

        var rows = visibleSlots(today);
        var cur = today.slotIndexAt(nowHour());
        for (var r = 0; r < rows[1]; r++) {
            var i = rows[0] + r;
            var s = today.hours[i];
            var y = rows[2] + r * rows[3];
            drawHourCell(dc, xHour, y, s.hour, i == cur);
            var wave = (s.waveMax > s.waveMin && s.waveMin > 0)
                ? Fmt.meters(s.waveMin) + "-" + Fmt.meters(s.waveMax)
                : Fmt.meters(s.waveHeight);
            Ui.text(dc, xWave, y, fT, wave, Ui.waveColor(s.waveHeight), Graphics.TEXT_JUSTIFY_LEFT);
            Ui.text(dc, xSwell, y, fX, s.swellDirection + " " + s.swellPeriod + "s",
                Ui.MUTED, Graphics.TEXT_JUSTIFY_RIGHT);
        }
    }

    // ----- Page 3 : vent -----------------------------------------------
    private function drawWind(dc, today) {
        drawTitle(dc, "VENT");
        if (!today.hasSurf()) {
            Ui.text(dc, _cx, py(0.5), Graphics.FONT_SMALL, "Pas de données", Ui.MUTED, Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        var gusts = false;
        for (var i = 0; i < today.hours.size(); i++) {
            if (today.hours[i].windGusts > today.hours[i].windSpeed) { gusts = true; }
        }
        Ui.text(dc, _cx, py(0.21), Graphics.FONT_XTINY, gusts ? "km/h  ·  rafales" : "vitesse en km/h",
            Ui.MUTED, Graphics.TEXT_JUSTIFY_CENTER);

        // Colonnes : heure | flèche | direction | vitesse | (rafales)
        var fT = Graphics.FONT_TINY;
        var fX = Graphics.FONT_XTINY;
        var gap = px(0.03);
        var arrow = (_hTiny / 3).toNumber();
        var wHour = dc.getTextWidthInPixels("21h", fX);
        var wDir = dc.getTextWidthInPixels("WNW", fX);
        var wSpeed = dc.getTextWidthInPixels("00", fT);
        var wGust = gusts ? gap + dc.getTextWidthInPixels("00", fX) : 0;
        var x0 = _cx - (wHour + gap + arrow * 2 + gap + wDir + gap + wSpeed + wGust) / 2;
        var xHour = x0 + wHour;
        var xArrow = xHour + gap + arrow;
        var xDir = xArrow + arrow + gap;
        var xSpeed = xDir + wDir + gap + wSpeed;
        var xGust = xSpeed + wGust;

        var rows = visibleSlots(today);
        var cur = today.slotIndexAt(nowHour());
        for (var r = 0; r < rows[1]; r++) {
            var i = rows[0] + r;
            var s = today.hours[i];
            var y = rows[2] + r * rows[3];
            var color = Ui.windColor(s.windSpeed);
            drawHourCell(dc, xHour, y, s.hour, i == cur);
            Ui.drawWindArrow(dc, xArrow, y, s.windDirection, arrow, color);
            Ui.text(dc, xDir, y, fX, s.windDirection, Ui.MUTED, Graphics.TEXT_JUSTIFY_LEFT);
            Ui.text(dc, xSpeed, y, fT, "" + s.windSpeed, color, Graphics.TEXT_JUSTIFY_RIGHT);
            if (gusts && s.windGusts > s.windSpeed) {
                Ui.text(dc, xGust, y, fX, "" + s.windGusts, Ui.MUTED, Graphics.TEXT_JUSTIFY_RIGHT);
            }
        }
    }

    // Heure du créneau, avec repère sur le créneau en cours
    private function drawHourCell(dc, xRight, y, hour, current) {
        if (current) {
            dc.setColor(Ui.ACCENT, Graphics.COLOR_TRANSPARENT);
            var w = dc.getTextWidthInPixels("21h", Graphics.FONT_XTINY);
            dc.fillCircle(xRight - w - px(0.03), y, _w >= 300 ? 4 : 3);
        }
        Ui.text(dc, xRight, y, Graphics.FONT_XTINY, hour + "h",
            current ? Ui.TEXT : Ui.MUTED, Graphics.TEXT_JUSTIFY_RIGHT);
    }

    // Choisit les créneaux affichables : [premier index, nombre, y du premier, pas]
    private function visibleSlots(day) {
        var yStart = py(0.31);
        var yEnd = py(0.84);
        var step = _hTiny;
        var fit = ((yEnd - yStart) / step).toNumber() + 1;
        var n = day.hours.size();
        var count = n < fit ? n : fit;
        var first = 0;
        if (n > fit) {
            // on garde le créneau en cours visible (en 2e position si possible)
            first = day.slotIndexAt(nowHour()) - 1;
            if (first < 0) { first = 0; }
            if (first > n - count) { first = n - count; }
        }
        var y0 = (yStart + yEnd) / 2 - step * (count - 1) / 2;
        return [first, count, y0, step];
    }

    // ----- Pages 4+ : jours suivants -----------------------------------
    private function drawDay(dc, day) {
        drawTitle(dc, Fmt.dayName(day.dayOfWeek).toUpper() + " " + day.day);

        if (day.hasTides()) {
            Ui.textRow(dc, _cx, py(0.21), Graphics.FONT_XTINY,
                ["coef ", day.morningCoeff + " · " + day.afternoonCoeff],
                [Ui.MUTED, Ui.TEXT]);
            drawTideLine(dc, day, true, py(0.30));
            drawTideLine(dc, day, false, py(0.30) + _hTiny);
        }

        var ySep = py(0.30) + _hTiny * 3 / 2;
        hLine(dc, ySep);

        if (!day.hasSurf()) { return; }

        var yLabel = ySep + _hXtiny * 3 / 4;
        var yValue = yLabel + _hXtiny / 2 + _hSmall / 2;
        var ySub = yValue + _hSmall / 2 + _hXtiny / 2;
        var xl = _cx - px(0.20);
        var xr = _cx + px(0.20);

        dc.setColor(Ui.DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(_cx, ySep + px(0.03), _cx, ySub + _hXtiny / 2);

        var avg = day.avgWave();
        Ui.text(dc, xl, yLabel, Graphics.FONT_XTINY, "VAGUES", Ui.MUTED, Graphics.TEXT_JUSTIFY_CENTER);
        Ui.text(dc, xl, yValue, Graphics.FONT_SMALL, Fmt.meters(avg) + " m", Ui.waveColor(avg), Graphics.TEXT_JUSTIFY_CENTER);
        Ui.text(dc, xl, ySub, Graphics.FONT_XTINY,
            Fmt.meters(day.minWave()) + " – " + Fmt.meters(day.maxWave()), Ui.MUTED, Graphics.TEXT_JUSTIFY_CENTER);

        var wind = day.avgWind();
        var dir = day.mainWindDirection();
        Ui.text(dc, xr, yLabel, Graphics.FONT_XTINY, "VENT", Ui.MUTED, Graphics.TEXT_JUSTIFY_CENTER);
        drawWindValue(dc, xr, yValue, dir, wind);
        Ui.text(dc, xr, ySub, Graphics.FONT_XTINY, dir + " · km/h", Ui.MUTED, Graphics.TEXT_JUSTIFY_CENTER);

        drawSlotStrip(dc, day, ySub + _hXtiny / 2 + px(0.03), py(0.89));
    }

    // Mini-prévision de la journée : une barre par créneau (hauteur = vagues)
    // et une flèche de vent colorée en dessous
    private function drawSlotStrip(dc, day, top, bottom) {
        var n = day.hours.size();
        if (n == 0 || bottom - top < 20) { return; }
        var arrow = (_w / 40).toNumber();
        var barBottom = bottom - arrow * 2 - 4;
        var maxH = barBottom - top;
        if (maxH < 6) { return; }
        var span = Ui.halfChord(_w, _h, bottom, px(0.08)) * 2;
        if (span > px(0.56)) { span = px(0.56); }
        var cell = span / n;
        var barW = cell * 3 / 5;
        var x0 = _cx - span / 2;
        var scale = day.maxWave() > 2.0 ? day.maxWave() : 2.0;
        for (var i = 0; i < n; i++) {
            var s = day.hours[i];
            var cxs = x0 + cell * i + cell / 2;
            var bh = (s.waveHeight / scale * maxH).toNumber();
            if (bh < 2) { bh = 2; }
            dc.setColor(Ui.waveColor(s.waveHeight), Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(cxs - barW / 2, barBottom - bh, barW, bh);
            Ui.drawWindArrow(dc, cxs, bottom - arrow, s.windDirection, arrow, Ui.windColor(s.windSpeed));
        }
    }

    // "▲ 01:34  13:12" : toutes les pleines (ou basses) mers du jour sur une ligne
    private function drawTideLine(dc, day, high, y) {
        var times = "";
        for (var i = 0; i < day.tides.size(); i++) {
            var ev = day.tides[i];
            if (ev.isHigh() == high) {
                times += (times.length() > 0 ? "   " : "") + ev.getTimeString();
            }
        }
        if (times.length() == 0) { return; }
        var color = high ? Ui.HIGH_TIDE : Ui.LOW_TIDE;
        var mark = (_hTiny / 6).toNumber();
        var w = dc.getTextWidthInPixels(times, Graphics.FONT_TINY);
        var gap = mark * 2;
        var start = _cx - (mark * 2 + gap + w) / 2;
        Ui.drawTideMark(dc, start + mark, y, high, mark, color);
        Ui.text(dc, start + mark * 2 + gap, y, Graphics.FONT_TINY, times, Ui.TEXT, Graphics.TEXT_JUSTIFY_LEFT);
    }
}

class MainDelegate extends WatchUi.BehaviorDelegate {
    private var _view;

    function initialize(view) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    // Bouton BAS / glisser vers le haut
    function onNextPage() {
        _view.nextPage();
        return true;
    }

    // Bouton HAUT / glisser vers le bas
    function onPreviousPage() {
        _view.prevPage();
        return true;
    }

    // START / appui écran : menu (actualiser, changer de spot)
    function onSelect() {
        openMenu();
        return true;
    }

    // Appui long HAUT
    function onMenu() {
        openMenu();
        return true;
    }

    // BACK : revient à la première page, puis quitte
    function onBack() {
        return _view.goHome();
    }

    private function openMenu() {
        WatchUi.pushView(new MainMenu(), new MainMenuDelegate(), WatchUi.SLIDE_UP);
    }
}
