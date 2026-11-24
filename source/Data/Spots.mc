using Toybox.Lang;
using Toybox.Application.Properties;

// Accès aux spots. La liste elle-même (SpotList) est générée depuis proxy-server/spots.json
// par proxy-server/scripts/generate-watch-spots.js.
// Le réglage "spot" contient l'identifiant surf-report du spot (ex : 998 = Biarritz Grande Plage).
module Spots {

    const DEFAULT_ID = 998;

    function count() {
        return SpotList.IDS.size();
    }

    function currentId() {
        var id = null;
        try {
            id = Properties.getValue("spot");
        } catch (e) {
            id = null;
        }
        if (!(id instanceof Lang.Number) || indexOf(id) < 0) {
            id = DEFAULT_ID;
        }
        return id;
    }

    function setCurrentId(id) {
        Properties.setValue("spot", id);
    }

    function indexOf(id) {
        return SpotList.IDS.indexOf(id);
    }

    function city(id) {
        var i = indexOf(id);
        return i < 0 ? "?" : SpotList.CITIES[i];
    }

    function beach(id) {
        var i = indexOf(id);
        return i < 0 ? "" : SpotList.BEACHES[i];
    }

    // "Biarritz · Grande Plage" ou "Lacanau"
    function label(id) {
        var b = beach(id);
        return b.length() > 0 ? city(id) + " · " + b : city(id);
    }

    // Villes distinctes, dans l'ordre de la liste
    function cities() {
        var out = [];
        for (var i = 0; i < SpotList.CITIES.size(); i++) {
            if (out.indexOf(SpotList.CITIES[i]) < 0) { out.add(SpotList.CITIES[i]); }
        }
        return out;
    }

    // Identifiants des spots d'une ville
    function idsOfCity(c) {
        var out = [];
        for (var i = 0; i < SpotList.CITIES.size(); i++) {
            if (SpotList.CITIES[i].equals(c)) { out.add(SpotList.IDS[i]); }
        }
        return out;
    }
}
