// Génère, à partir de proxy-server/spots.json, les fichiers de l'app montre :
//   source/Data/SpotList.mc            (listes utilisées par le menu de la montre)
//   resources/strings/spots.xml        (libellés de la liste des réglages téléphone)
//   resources/settings/settings.xml    (réglage "Spot" dans Garmin Connect)
//
// Usage : node scripts/generate-watch-spots.js   (depuis proxy-server/)
// Relancer après toute modification de spots.json, puis recompiler l'app.

const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..', '..');
const spots = require('../spots.json');

const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const mcStr = s => '"' + s.replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"';
const label = s => (s.beach ? `${s.city} – ${s.beach}` : s.city);

const header = '// FICHIER GÉNÉRÉ par proxy-server/scripts/generate-watch-spots.js — ne pas modifier à la main.\n';

const mc = `${header}
module SpotList {
    const IDS = [${spots.map(s => s.id).join(', ')}];
    const CITIES = [
        ${spots.map(s => mcStr(s.city)).join(',\n        ')}
    ];
    const BEACHES = [
        ${spots.map(s => mcStr(s.beach)).join(',\n        ')}
    ];
}
`;
fs.writeFileSync(path.join(root, 'source/Data/SpotList.mc'), mc);

const strings = `<?xml version="1.0" encoding="UTF-8"?>
<!-- ${header.trim().slice(3)} -->
<resources>
${spots.map(s => `    <string id="Spot${s.id}">${esc(label(s))}</string>`).join('\n')}
</resources>
`;
fs.writeFileSync(path.join(root, 'resources/strings/spots.xml'), strings);

const settings = `<?xml version="1.0" encoding="UTF-8"?>
<!-- ${header.trim().slice(3)} -->
<resources>
    <!-- Réglage modifiable depuis l'app Garmin Connect (téléphone) -->
    <settings>
        <setting propertyKey="@Properties.spot" title="@Strings.SpotTitle">
            <settingConfig type="list">
${spots.map(s => `                <listEntry value="${s.id}">@Strings.Spot${s.id}</listEntry>`).join('\n')}
            </settingConfig>
        </setting>
    </settings>
</resources>
`;
fs.writeFileSync(path.join(root, 'resources/settings/settings.xml'), settings);

console.log(`${spots.length} spots générés.`);
