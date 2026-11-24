// Proxy Surf&Tide pour l'app Garmin "Waves".
//
// Source : surf-report.com. Une page "prévisions" par spot contient, pour 7 jours :
//   - les créneaux 06h..21h : vagues (min-max), houle (hauteur, période, direction), vent (vitesse, direction)
//   - les marées : horaires pleine/basse mer et coefficients matin/après-midi
// meteoconsult.fr n'est pas utilisé : le site bloque tout accès automatisé (protection Akamai, HTTP 403).
//
// La montre appelle GET /api/combined?spot=<id surf-report> et reçoit un JSON compact.

const express = require('express');
const axios = require('axios');
const cheerio = require('cheerio');
const NodeCache = require('node-cache');
const cors = require('cors');
require('dotenv').config();

const SPOTS = require('./spots.json');

const app = express();
const cache = new NodeCache({ stdTTL: 1800 }); // 30 min : les prévisions ne bougent pas plus vite
const PORT = process.env.PORT || 3000;
const BASE_URL = 'https://www.surf-report.com';
const USER_AGENT = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36';

app.use(cors());

// ============================================================
// Spots
// ============================================================

const spotsById = new Map(SPOTS.map(s => [s.id, s]));

// Compatibilité avec l'ancienne version de la montre (?city=Biarritz&beach=Grande Plage)
function findSpot({ spot, city, beach }) {
    if (spot !== undefined) {
        return spotsById.get(parseInt(spot, 10)) || null;
    }
    if (city) {
        const norm = v => (v || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
        const inCity = SPOTS.filter(s => norm(s.city) === norm(city));
        return inCity.find(s => norm(s.beach) === norm(beach)) || inCity[0] || null;
    }
    return null;
}

// ============================================================
// Scraping surf-report.com
// ============================================================

const DIR_WORDS = { nord: 'N', sud: 'S', est: 'E', ouest: 'W' };

// "Orientation vent Sud Sud Ouest" -> "SSW"
function parseDirection(alt) {
    if (!alt) return '';
    return alt
        .toLowerCase()
        .split(/\s+/)
        .map(w => DIR_WORDS[w.normalize('NFD').replace(/[̀-ͯ]/g, '')] || '')
        .join('');
}

function num(text) {
    const v = parseFloat(String(text).replace(',', '.'));
    return Number.isFinite(v) ? v : 0;
}

function addDays(isoDate, n) {
    const d = new Date(isoDate + 'T12:00:00Z');
    d.setUTCDate(d.getUTCDate() + n);
    return d.toISOString().slice(0, 10);
}

function parseForecastPage(html) {
    const $ = cheerio.load(html);
    const days = [];
    let baseDate = null;

    $('.forecast-tab').each((index, tab) => {
        const $tab = $(tab);
        const scripts = $tab.find('script').map((i, s) => $(s).html()).get().join('\n');

        // Le graphe de marée de CHAQUE onglet est daté du jour courant (bizarrerie du site) :
        // seules les heures sont fiables. La vraie date = 1er jour + rang de l'onglet,
        // vérifiée avec le numéro du jour dans le titre ("Mardi 24 Novembre").
        const graphMatch = scripts.match(/x\.domain\(\[parseTime\("(\d{4}-\d{2}-\d{2})/);
        const graphDate = graphMatch ? graphMatch[1] : null;
        if (baseDate === null) baseDate = graphDate || new Date().toISOString().slice(0, 10);
        let date = addDays(baseDate, index);
        const titleDay = parseInt(($tab.find('.title').first().text().match(/\d+/) || [])[0], 10);
        for (let k = 0; k < 3 && titleDay && parseInt(date.slice(8), 10) !== titleDay; k++) {
            date = addDays(date, 1);
        }

        // ---- Créneaux horaires
        const hours = [];
        $tab.find('.line').each((i, line) => {
            const $line = $(line);
            const time = $line.find('.cell.date').text().trim();
            const m = time.match(/^(\d{1,2}):(\d{2})$/);
            if (!m) return; // ligne d'en-tête ou de marées

            const waves = $line.find('.cell.waves span').not('.m-unit').map((j, s) => num($(s).text())).get();
            const waveMin = waves[0] || 0;
            const waveMax = waves.length > 1 ? waves[1] : waveMin;

            const swell = $line.find('.swell').not('.secondary').not('.img');
            const swellImg = $line.find('.swell.img').not('.secondary').find('img').attr('alt');
            const windSpeed = num($line.find('.wind').not('.img').find('span').first().text());
            const windImg = $line.find('.wind.img img').attr('alt');

            hours.push({
                hour: parseInt(m[1], 10),
                waveMin,
                waveMax,
                waveHeight: Math.round((waveMin + waveMax) * 5) / 10, // moyenne de la fourchette
                swellHeight: num(swell.eq(0).find('span').first().text()),
                swellPeriod: Math.round(num(swell.eq(1).find('span').first().text())),
                swellDirection: parseDirection(swellImg),
                windSpeed: Math.round(windSpeed),
                windGusts: 0, // non fourni par créneau sur surf-report
                windDirection: parseDirection(windImg)
            });
        });

        // ---- Marées : horaires exacts dans le JSON du graphe, coefficients dans le texte
        const coeffs = $tab.find('.tide-element.coeff').text().match(/\d+/g) || [];
        const morningCoeff = parseInt(coeffs[0], 10) || 0;
        const afternoonCoeff = parseInt(coeffs[1], 10) || morningCoeff;

        const events = [];
        const tidesMatch = scripts.match(/dataTidesWithout\s*=\s*(\[[^\]]*\])/);
        if (tidesMatch) {
            try {
                for (const t of JSON.parse(tidesMatch[1])) {
                    const tm = String(t.hour).match(/^(\d{4}-\d{2}-\d{2}) (\d{2}):(\d{2})/);
                    if (!tm || (graphDate && tm[1] !== graphDate)) continue; // marée de la veille
                    const hour = parseInt(tm[2], 10);
                    events.push({
                        // sur surf-report, 5 = pleine mer, 1 = basse mer
                        type: parseInt(t.tide, 10) >= 3 ? 'high' : 'low',
                        hour,
                        minute: parseInt(tm[3], 10),
                        height: 0, // hauteur d'eau non fournie
                        coefficient: hour < 12 ? morningCoeff : afternoonCoeff
                    });
                }
            } catch (e) {
                console.error('Tide JSON parse error:', e.message);
            }
        }
        events.sort((a, b) => (a.hour * 60 + a.minute) - (b.hour * 60 + b.minute));

        days.push({
            date,
            tide: { morningCoeff, afternoonCoeff, events },
            surf: { hours }
        });
    });

    return days;
}

// ------------------------------------------------------------
// Repli : page "horaires-marees" (certains spots, ex. La Guérite, n'ont pas
// les marées sur leur page prévisions). Calendrier mensuel, 2 lignes par jour :
// "Matin" / "Après midi" avec Pleine mer, Basse mer, Coeff.
// ------------------------------------------------------------

const MONTHS = ['janvier', 'fevrier', 'mars', 'avril', 'mai', 'juin', 'juillet',
    'aout', 'septembre', 'octobre', 'novembre', 'decembre'];
const stripAccents = v => v.normalize('NFD').replace(/[\u0300-\u036f]/g, '');

function parseTidePage(html) {
    const $ = cheerio.load(html);
    const byDayMonth = new Map(); // "24-11" -> { morningCoeff, afternoonCoeff, events }

    $('.tides-tab').each((i, tab) => {
        const title = stripAccents($(tab).find('.title').first().text().toLowerCase());
        const tm = title.match(/(\d{1,2})\s+([a-z]+)/);
        if (!tm) return;
        const month = MONTHS.indexOf(tm[2]) + 1;
        if (month === 0) return;

        const coeffs = [];
        const events = [];
        $(tab).find('.line.tides').each((j, line) => {
            let coeff = 0;
            const found = [];
            $(line).find('.cell').each((k, cell) => {
                const text = stripAccents($(cell).text().toLowerCase());
                const m = text.match(/(pleine|basse) mer:\s*(\d{1,2}):(\d{2})/);
                const c = text.match(/coeff:\s*(\d+)/);
                if (m) found.push({ type: m[1] === 'pleine' ? 'high' : 'low', hour: +m[2], minute: +m[3] });
                if (c) coeff = +c[1];
            });
            coeffs.push(coeff);
            for (const e of found) events.push({ ...e, height: 0, coefficient: coeff });
        });
        events.sort((a, b) => (a.hour * 60 + a.minute) - (b.hour * 60 + b.minute));
        byDayMonth.set(`${+tm[1]}-${month}`, {
            morningCoeff: coeffs[0] || 0,
            afternoonCoeff: coeffs[1] || coeffs[0] || 0,
            events
        });
    });
    return byDayMonth;
}

async function fillMissingTides(spot, days) {
    if (days.some(d => d.tide.events.length > 0)) return;
    const url = `${BASE_URL}/horaires-marees/${spot.slug}.html`;
    try {
        const response = await axios.get(url, {
            headers: { 'User-Agent': USER_AGENT, 'Accept-Language': 'fr-FR,fr;q=0.9' },
            timeout: 20000
        });
        const tides = parseTidePage(response.data);
        for (const day of days) {
            const t = tides.get(`${+day.date.slice(8, 10)}-${+day.date.slice(5, 7)}`);
            if (t) day.tide = t;
        }
    } catch (e) {
        console.error(`Tide fallback failed for spot ${spot.id}:`, e.message);
    }
}

async function fetchSpot(spot) {
    const url = `${BASE_URL}/meteo-surf/${spot.slug}-s${spot.id}.html`;
    const response = await axios.get(url, {
        headers: { 'User-Agent': USER_AGENT, 'Accept-Language': 'fr-FR,fr;q=0.9' },
        timeout: 20000
    });
    const days = parseForecastPage(response.data);
    if (days.length === 0 || days.every(d => d.surf.hours.length === 0)) {
        throw new Error('Page parsed but no forecast found (site layout changed?)');
    }
    await fillMissingTides(spot, days);
    return days;
}

// ============================================================
// API
// ============================================================

app.get('/api/combined', async (req, res) => {
    const spot = findSpot(req.query);
    if (!spot) {
        return res.status(400).json({ error: 'unknown spot' });
    }

    const cacheKey = `spot_${spot.id}`;
    const cached = cache.get(cacheKey);
    if (cached) {
        return res.json(cached);
    }

    try {
        const payload = {
            spot: { id: spot.id, city: spot.city, beach: spot.beach },
            source: 'surf-report.com',
            mock: false,
            days: await fetchSpot(spot)
        };
        cache.set(cacheKey, payload);
        res.json(payload);
    } catch (error) {
        console.error(`Scraping error for spot ${spot.id}:`, error.message);
        // Pas de fausses données : la montre affiche l'erreur et garde son cache
        res.status(502).json({ error: 'upstream unavailable' });
    }
});

app.get('/api/spots', (req, res) => {
    res.json({ spots: SPOTS.map(({ id, city, beach, region }) => ({ id, city, beach, region })) });
});

app.get('/health', (req, res) => {
    res.json({ status: 'ok', uptime: process.uptime() });
});

if (require.main === module) {
    app.listen(PORT, () => {
        console.log(`Surf&Tide proxy running on port ${PORT} (${SPOTS.length} spots)`);
    });
}

module.exports = { parseForecastPage, parseTidePage, parseDirection };
