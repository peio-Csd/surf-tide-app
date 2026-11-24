using Toybox.Lang;
using Toybox.Communications;
using Toybox.Application.Storage;
using Toybox.WatchUi;
using Toybox.Timer;

// Récupère les données du proxy, les met en cache et les expose aux vues.
class DataManager {

    const PROXY_URL = "https://surf-tide-app.onrender.com/api/combined";
    const CACHE_KEY = "cache";
    const GLANCE_KEY = "glance";
    const MAX_AGE = 1800;          // le proxy met en cache 30 min : inutile de redemander avant
    const MAX_RETRIES = 2;         // le serveur Render gratuit peut mettre ~1 min à se réveiller

    var days;              // Array<DayData>, à partir d'aujourd'hui
    var spotId;            // identifiant surf-report du spot
    var lastSync;          // epoch de la dernière synchro réussie
    var isMock;            // true si le proxy a renvoyé des données simulées
    var isSyncing;
    var errorMessage;

    private var _retryCount;
    private var _retryTimer;

    function initialize() {
        days = [];
        spotId = Spots.currentId();
        lastSync = null;
        isMock = false;
        isSyncing = false;
        errorMessage = null;
        _retryCount = 0;
        loadCache();
    }

    // ---------------------------------------------------------------
    // Accès aux données
    // ---------------------------------------------------------------

    function hasData() {
        return getDays().size() > 0;
    }

    // Jours à partir d'aujourd'hui (les jours passés du cache sont ignorés)
    function getDays() {
        var now = Fmt.now();
        var start = 0;
        while (start < days.size() && days[start].midnight + 86400 <= now) {
            start++;
        }
        return start == 0 ? days : days.slice(start, null);
    }

    function getToday() {
        var d = getDays();
        return d.size() > 0 ? d[0] : null;
    }

    // Toutes les marées connues, triées, tous jours confondus
    function allTides() {
        var list = [];
        for (var i = 0; i < days.size(); i++) {
            list.addAll(days[i].tides);
        }
        return list;
    }

    // Les `count` prochaines marées à partir de maintenant (ordre chronologique)
    function nextTides(count) {
        var now = Fmt.now();
        var out = [];
        var all = allTides();
        for (var i = 0; i < all.size() && out.size() < count; i++) {
            if (all[i].time > now) { out.add(all[i]); }
        }
        return out;
    }

    function spotLabel() {
        return Spots.city(spotId);
    }

    // ---------------------------------------------------------------
    // Réseau
    // ---------------------------------------------------------------

    // Rafraîchit si le cache est trop vieux (ou absent)
    function refreshIfNeeded() {
        if (lastSync == null || Fmt.now() - lastSync > MAX_AGE || !hasData()) {
            fetch();
        }
    }

    function fetch() {
        if (isSyncing) { return; }
        isSyncing = true;
        errorMessage = null;
        WatchUi.requestUpdate();

        Communications.makeWebRequest(
            PROXY_URL,
            { "spot" => spotId },
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onResponse)
        );
    }

    function onResponse(code as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {
        isSyncing = false;
        var parsed = (code == 200) ? new ApiParser().parse(data) : [];

        if (parsed.size() > 0) {
            days = parsed;
            lastSync = Fmt.now();
            isMock = (data instanceof Lang.Dictionary) && data["mock"] == true;
            errorMessage = null;
            _retryCount = 0;
            saveCache();
        } else {
            errorMessage = (code == 200) ? "Données vides" : errorText(code);
            if (code != 200 && _retryCount < MAX_RETRIES) {
                _retryCount++;
                _retryTimer = new Timer.Timer();
                _retryTimer.start(method(:onRetry), 8000, false);
            } else {
                _retryCount = 0;
            }
        }
        WatchUi.requestUpdate();
    }

    function onRetry() as Void {
        _retryTimer = null;
        fetch();
    }

    // Changement de spot (depuis le menu montre ou les réglages téléphone)
    function setSpot(id) {
        if (id == spotId) { return; }
        spotId = id;
        days = [];
        lastSync = null;
        isMock = false;
        _retryCount = 0;
        fetch();
    }

    private function errorText(code) {
        if (code == Communications.BLE_CONNECTION_UNAVAILABLE) { return "Téléphone déconnecté"; }
        if (code == Communications.BLE_HOST_TIMEOUT || code == Communications.NETWORK_REQUEST_TIMED_OUT) {
            return "Délai dépassé";
        }
        if (code == Communications.INVALID_HTTP_BODY_IN_NETWORK_RESPONSE) { return "Réponse invalide"; }
        if (code == Communications.NETWORK_RESPONSE_TOO_LARGE || code == Communications.NETWORK_RESPONSE_OUT_OF_MEMORY) {
            return "Réponse trop lourde";
        }
        if (code == Communications.SECURE_CONNECTION_REQUIRED) { return "HTTPS requis"; }
        if (code == 404) { return "Serveur introuvable"; }
        if (code == 400) { return "Spot inconnu"; }
        if (code == 502) { return "surf-report indispo"; }
        if (code == 429) { return "Trop de requêtes"; }
        if (code >= 500) { return "Erreur serveur"; }
        if (code < 0) { return "Erreur réseau (" + code + ")"; }
        return "Erreur " + code;
    }

    // ---------------------------------------------------------------
    // Cache (Storage) : relancer l'app affiche tout de suite les dernières données
    // ---------------------------------------------------------------

    private function saveCache() {
        var arr = [];
        for (var i = 0; i < days.size(); i++) { arr.add(days[i].toArray()); }
        try {
            Storage.setValue(CACHE_KEY, {
                "spot" => spotId,
                "sync" => lastSync,
                "mock" => isMock,
                "days" => arr
            });
            saveGlance();
        } catch (e) {
            // stockage plein : on garde simplement les données en mémoire
        }
    }

    private function loadCache() {
        var c = null;
        try {
            c = Storage.getValue(CACHE_KEY);
            if (c instanceof Lang.Dictionary && c["spot"] == spotId) {
                var arr = c["days"];
                var list = [];
                for (var i = 0; i < arr.size(); i++) { list.add(DayData.fromArray(arr[i])); }
                days = list;
                lastSync = c["sync"];
                isMock = c["mock"] == true;
            }
        } catch (e) {
            days = [];   // cache d'une ancienne version : ignoré
        }
    }

    // Résumé minimal lu par le glance (qui a très peu de mémoire)
    private function saveGlance() {
        var waves = [];
        for (var i = 0; i < days.size(); i++) {
            waves.add([days[i].midnight, days[i].avgWave()]);
        }
        var tides = [];
        var all = allTides();
        for (var i = 0; i < all.size(); i++) {
            tides.add([all[i].time, all[i].type]);
        }
        Storage.setValue(GLANCE_KEY, { "spot" => Spots.city(spotId), "w" => waves, "t" => tides });
    }
}
