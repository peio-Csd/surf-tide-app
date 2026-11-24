using Toybox.WatchUi;
using Toybox.Application;

// Menu natif Garmin (Menu2) : s'affiche correctement sur toutes les montres
class MainMenu extends WatchUi.Menu2 {

    function initialize() {
        Menu2.initialize({ :title => "Waves" });
        var dm = Application.getApp().dataManager;
        var sync = dm.lastSync != null ? "màj " + Fmt.timeOf(dm.lastSync) : "jamais synchronisé";
        addItem(new WatchUi.MenuItem("Actualiser", sync, :refresh, null));
        addItem(new WatchUi.MenuItem("Spot", Spots.label(dm.spotId), :spot, null));
    }
}

class MainMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) {
        var id = item.getId();
        if (id == :refresh) {
            Application.getApp().dataManager.fetch();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (id == :spot) {
            WatchUi.pushView(new CityMenu(), new CityMenuDelegate(), WatchUi.SLIDE_LEFT);
        }
    }
}

// 1er niveau : la ville
class CityMenu extends WatchUi.Menu2 {

    function initialize() {
        var currentCity = Spots.city(Application.getApp().dataManager.spotId);
        var list = Spots.cities();
        var focus = list.indexOf(currentCity);
        Menu2.initialize({ :title => "Ville", :focus => focus < 0 ? 0 : focus });
        for (var i = 0; i < list.size(); i++) {
            var n = Spots.idsOfCity(list[i]).size();
            addItem(new WatchUi.MenuItem(list[i], n > 1 ? n + " plages" : null, list[i], null));
        }
    }
}

class CityMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) {
        var ids = Spots.idsOfCity(item.getId());
        if (ids.size() == 1) {
            chooseSpot(ids[0], 2);
        } else {
            WatchUi.pushView(new BeachMenu(item.getId(), ids), new BeachMenuDelegate(), WatchUi.SLIDE_LEFT);
        }
    }
}

// 2e niveau : la plage
class BeachMenu extends WatchUi.Menu2 {

    function initialize(city, ids) {
        var current = Application.getApp().dataManager.spotId;
        var focus = ids.indexOf(current);
        Menu2.initialize({ :title => city, :focus => focus < 0 ? 0 : focus });
        for (var i = 0; i < ids.size(); i++) {
            var b = Spots.beach(ids[i]);
            addItem(new WatchUi.MenuItem(b.length() > 0 ? b : city, null, ids[i], null));
        }
    }
}

class BeachMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) {
        chooseSpot(item.getId(), 3);
    }
}

// Enregistre le spot, relance le chargement et revient à la vue principale
function chooseSpot(id, menusToClose) {
    Spots.setCurrentId(id);
    Application.getApp().dataManager.setSpot(id);
    for (var i = 0; i < menusToClose - 1; i++) {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
    }
    WatchUi.popView(WatchUi.SLIDE_RIGHT);
}
