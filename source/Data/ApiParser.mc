using Toybox.Lang;
using Toybox.Math;

// Transforme la réponse JSON du proxy (/api/combined) en Array<DayData>.
// Tolérant aux champs manquants : un champ absent ne fait plus planter l'app.
class ApiParser {

    function initialize() {}

    function parse(json) {
        var results = [];
        if (!(json instanceof Lang.Dictionary)) { return results; }
        var days = json["days"];
        if (!(days instanceof Lang.Array)) { return results; }

        for (var i = 0; i < days.size(); i++) {
            var day = parseDay(days[i]);
            if (day != null) { results.add(day); }
        }
        return results;
    }

    private function parseDay(d) {
        if (!(d instanceof Lang.Dictionary)) { return null; }
        var date = parseDate(d["date"]);
        if (date == null) { return null; }

        var day = new DayData();
        day.setDate(date[0], date[1], date[2]);

        var tide = d["tide"];
        if (tide instanceof Lang.Dictionary) {
            day.morningCoeff = num(tide["morningCoeff"], 0);
            day.afternoonCoeff = num(tide["afternoonCoeff"], 0);
            var events = tide["events"];
            if (events instanceof Lang.Array) {
                for (var i = 0; i < events.size(); i++) {
                    var ev = events[i];
                    if (!(ev instanceof Lang.Dictionary)) { continue; }
                    var type = ("high".equals(ev["type"])) ? 1 : 0;
                    day.addTide(new TideEvent(type,
                        num(ev["hour"], 0), num(ev["minute"], 0),
                        flt(ev["height"], 0.0f), num(ev["coefficient"], 0)));
                }
            }
            sortTides(day.tides);
        }

        var surf = d["surf"];
        if (surf instanceof Lang.Dictionary) {
            var hours = surf["hours"];
            if (hours instanceof Lang.Array) {
                for (var i = 0; i < hours.size(); i++) {
                    var hr = hours[i];
                    if (!(hr instanceof Lang.Dictionary)) { continue; }
                    var s = new SurfHourData();
                    s.hour = num(hr["hour"], 0);
                    s.waveHeight = flt(hr["waveHeight"], 0.0f);
                    s.waveMin = flt(hr["waveMin"], s.waveHeight);
                    s.waveMax = flt(hr["waveMax"], s.waveHeight);
                    s.swellHeight = flt(hr["swellHeight"], 0.0f);
                    s.swellDirection = str(hr["swellDirection"]);
                    s.swellPeriod = num(hr["swellPeriod"], 0);
                    s.windDirection = str(hr["windDirection"]);
                    s.windSpeed = num(hr["windSpeed"], 0);
                    s.windGusts = num(hr["windGusts"], 0);
                    day.hours.add(s);
                }
            }
        }
        return day;
    }

    // "2026-07-09" -> [2026, 7, 9]
    private function parseDate(s) {
        if (!(s instanceof Lang.String) || s.length() < 10) { return null; }
        var y = s.substring(0, 4).toNumber();
        var m = s.substring(5, 7).toNumber();
        var d = s.substring(8, 10).toNumber();
        if (y == null || m == null || d == null) { return null; }
        return [y, m, d];
    }

    private function sortTides(list) {
        // tri par insertion (4 éléments max)
        for (var i = 1; i < list.size(); i++) {
            var cur = list[i];
            var j = i - 1;
            while (j >= 0 && list[j].time > cur.time) {
                list[j + 1] = list[j];
                j--;
            }
            list[j + 1] = cur;
        }
    }

    private function num(v, def) {
        if (v == null) { return def; }
        if (v instanceof Lang.Number) { return v; }
        if (v instanceof Lang.Float || v instanceof Lang.Double || v instanceof Lang.Long) {
            return Math.round(v).toNumber();
        }
        if (v instanceof Lang.String) {
            var n = v.toNumber();
            return n == null ? def : n;
        }
        return def;
    }

    private function flt(v, def) {
        if (v == null) { return def; }
        if (v instanceof Lang.Number || v instanceof Lang.Float || v instanceof Lang.Double || v instanceof Lang.Long) {
            return v.toFloat();
        }
        if (v instanceof Lang.String) {
            var f = v.toFloat();
            return f == null ? def : f;
        }
        return def;
    }

    private function str(v) {
        return (v instanceof Lang.String) ? v : "";
    }
}
