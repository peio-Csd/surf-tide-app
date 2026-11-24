using Toybox.Lang;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;

// Petites fonctions de formatage (utilisables aussi par le glance)
(:glance)
module Fmt {

    const DAYS = ["Dimanche", "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi"];
    const DAYS_SHORT = ["DIM", "LUN", "MAR", "MER", "JEU", "VEN", "SAM"];

    function two(n) {
        return n < 10 ? "0" + n : "" + n;
    }

    function hm(h, m) {
        return two(h) + ":" + two(m);
    }

    // "HH:MM" pour un instant epoch (heure locale)
    function timeOf(epoch) {
        var info = Gregorian.info(new Time.Moment(epoch), Time.FORMAT_SHORT);
        return hm(info.hour, info.min);
    }

    function meters(v) {
        return v.format("%.1f");
    }

    // Minuit local (secondes epoch) pour une date donnée
    function localMidnight(y, m, d) {
        var utc = Gregorian.moment({ :year => y, :month => m, :day => d, :hour => 0, :minute => 0, :second => 0 });
        return utc.value() - System.getClockTime().timeZoneOffset;
    }

    function dayOfWeek(epoch) {
        // +2h pour éviter tout effet de bord autour de minuit (changement d'heure)
        return Gregorian.info(new Time.Moment(epoch + 7200), Time.FORMAT_SHORT).day_of_week;
    }

    function dayName(dow) {
        return DAYS[(dow - 1) % 7];
    }

    function dayShort(dow) {
        return DAYS_SHORT[(dow - 1) % 7];
    }

    function now() {
        return Time.now().value();
    }
}
