using Toybox.Application;
using Toybox.WatchUi;

(:glance)
class SurfTideApp extends Application.AppBase {

    // Créé uniquement pour l'app complète (pas pour le glance, qui a peu de mémoire)
    var dataManager = null;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        dataManager = new DataManager();
        var view = new MainView();
        return [view, new MainDelegate(view)];
    }

    function getGlanceView() {
        return [new SurfGlanceView()];
    }

    // Réglages modifiés depuis Garmin Connect (téléphone)
    function onSettingsChanged() {
        if (dataManager != null) {
            dataManager.setSpot(Spots.currentId());
        }
        WatchUi.requestUpdate();
    }
}
