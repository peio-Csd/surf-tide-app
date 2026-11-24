using Toybox.Lang;
using Toybox.Math;

// Une pleine mer (type = 1) ou basse mer (type = 0)
class TideEvent {
    var type;         // 1 = pleine mer (PM), 0 = basse mer (BM)
    var hour;
    var minute;
    var height;       // mètres (Float)
    var coefficient;
    var time;         // instant en secondes epoch (heure locale de la montre)

    function initialize(type_, hour_, minute_, height_, coeff_) {
        type = type_;
        hour = hour_;
        minute = minute_;
        height = height_;
        coefficient = coeff_;
        time = 0;
    }

    function isHigh() {
        return type == 1;
    }

    function getLabel() {
        return isHigh() ? "PM" : "BM";
    }

    function getTimeString() {
        return Fmt.hm(hour, minute);
    }

    function toArray() {
        return [type, hour, minute, height, coefficient];
    }

    static function fromArray(a) {
        return new TideEvent(a[0], a[1], a[2], a[3], a[4]);
    }
}

// Un créneau horaire surf-report (vagues, houle, vent)
class SurfHourData {
    var hour;
    var waveHeight;      // m (Float) : milieu de la fourchette
    var waveMin;         // m
    var waveMax;         // m
    var swellHeight;     // m
    var swellDirection;  // "WNW", "SO", ...
    var swellPeriod;     // s
    var windDirection;
    var windSpeed;       // km/h
    var windGusts;       // km/h

    function initialize() {
        hour = 0;
        waveHeight = 0.0f;
        waveMin = 0.0f;
        waveMax = 0.0f;
        swellHeight = 0.0f;
        swellDirection = "";
        swellPeriod = 0;
        windDirection = "";
        windSpeed = 0;
        windGusts = 0;
    }

    function toArray() {
        return [hour, waveHeight, swellDirection, swellPeriod, windDirection, windSpeed, windGusts, waveMin, waveMax, swellHeight];
    }

    static function fromArray(a) {
        var h = new SurfHourData();
        h.hour = a[0];
        h.waveHeight = a[1];
        h.swellDirection = a[2];
        h.swellPeriod = a[3];
        h.windDirection = a[4];
        h.windSpeed = a[5];
        h.windGusts = a[6];
        h.waveMin = a[7];
        h.waveMax = a[8];
        h.swellHeight = a[9];
        return h;
    }
}

// Toutes les données d'une journée
class DayData {
    var year;
    var month;
    var day;
    var dayOfWeek;      // 1 = dimanche ... 7 = samedi (convention Garmin)
    var midnight;       // minuit local, secondes epoch
    var morningCoeff;
    var afternoonCoeff;
    var tides;          // Array<TideEvent>, triées par heure
    var hours;          // Array<SurfHourData>, triées par heure

    function initialize() {
        year = 0;
        month = 0;
        day = 0;
        dayOfWeek = 1;
        midnight = 0;
        morningCoeff = 0;
        afternoonCoeff = 0;
        tides = [];
        hours = [];
    }

    function hasTides() {
        return tides.size() > 0;
    }

    // surf-report ne fournit pas la hauteur d'eau des marées (uniquement horaires + coefficients)
    function hasTideHeights() {
        for (var i = 0; i < tides.size(); i++) {
            if (tides[i].height > 0) { return true; }
        }
        return false;
    }

    function hasSurf() {
        return hours.size() > 0;
    }

    function avgWave() {
        var total = 0.0f;
        var n = 0;
        for (var i = 0; i < hours.size(); i++) {
            if (hours[i].waveHeight > 0) {
                total += hours[i].waveHeight;
                n++;
            }
        }
        return n > 0 ? total / n : 0.0f;
    }

    function minWave() {
        var m = null;
        for (var i = 0; i < hours.size(); i++) {
            var w = hours[i].waveMin > 0 ? hours[i].waveMin : hours[i].waveHeight;
            if (w > 0 && (m == null || w < m)) { m = w; }
        }
        return m == null ? 0.0f : m;
    }

    function maxWave() {
        var m = 0.0f;
        for (var i = 0; i < hours.size(); i++) {
            var w = hours[i].waveMax > 0 ? hours[i].waveMax : hours[i].waveHeight;
            if (w > m) { m = w; }
        }
        return m;
    }

    function avgWind() {
        if (hours.size() == 0) { return 0; }
        var total = 0;
        for (var i = 0; i < hours.size(); i++) {
            total += hours[i].windSpeed;
        }
        return Math.round(total.toFloat() / hours.size()).toNumber();
    }

    // Direction la plus fréquente sur la journée
    function mainWindDirection() {
        var best = "";
        var bestCount = 0;
        for (var i = 0; i < hours.size(); i++) {
            var d = hours[i].windDirection;
            var c = 0;
            for (var j = 0; j < hours.size(); j++) {
                if (hours[j].windDirection.equals(d)) { c++; }
            }
            if (c > bestCount) {
                best = d;
                bestCount = c;
            }
        }
        return best;
    }

    // Créneau correspondant à l'heure donnée (le dernier créneau commencé)
    function slotIndexAt(hourOfDay) {
        if (hours.size() == 0) { return -1; }
        var idx = 0;
        for (var i = 0; i < hours.size(); i++) {
            if (hours[i].hour <= hourOfDay) { idx = i; }
        }
        return idx;
    }

    function toArray() {
        var t = [];
        for (var i = 0; i < tides.size(); i++) { t.add(tides[i].toArray()); }
        var h = [];
        for (var i = 0; i < hours.size(); i++) { h.add(hours[i].toArray()); }
        return [year, month, day, morningCoeff, afternoonCoeff, t, h];
    }

    static function fromArray(a) {
        var d = new DayData();
        d.setDate(a[0], a[1], a[2]);
        d.morningCoeff = a[3];
        d.afternoonCoeff = a[4];
        for (var i = 0; i < a[5].size(); i++) { d.addTide(TideEvent.fromArray(a[5][i])); }
        for (var i = 0; i < a[6].size(); i++) { d.hours.add(SurfHourData.fromArray(a[6][i])); }
        return d;
    }

    function setDate(y, m, dd) {
        year = y;
        month = m;
        day = dd;
        midnight = Fmt.localMidnight(y, m, dd);
        dayOfWeek = Fmt.dayOfWeek(midnight);
    }

    function addTide(ev) {
        ev.time = midnight + ev.hour * 3600 + ev.minute * 60;
        tides.add(ev);
    }
}
