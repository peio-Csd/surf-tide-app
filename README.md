# Waves — app Garmin surf & marées

App Connect IQ (Monkey C) qui affiche, pour un spot de la côte basque/landaise/girondine, de Vendée et de Bretagne :
vagues, houle, vent par créneau et marées (pleine/basse mer + coefficients) sur 7 jours.
Rendu de référence : Forerunner 165 Music (390×390 AMOLED), fonctionne sur les montres rondes récentes.

## Organisation

| Dossier | Contenu |
|---|---|
| `source/` | code de l'app montre |
| `resources/` | icône, textes, réglages téléphone (`settings/`) |
| `proxy-server/` | serveur Node (Render) qui lit surf-report.com et renvoie un JSON compact |
| `proxy-server/spots.json` | **liste des spots** (source unique) |

Les données viennent de **surf-report.com** (prévisions + marées ; si la page prévisions d'un spot
n'a pas les marées, le serveur les lit sur sa page `horaires-marees`). meteoconsult.fr bloque
tout accès automatisé (HTTP 403 Akamai), il n'est donc pas utilisé.

## Ajouter / retirer un spot

1. Modifier `proxy-server/spots.json` (`id` et `slug` = ceux de l'URL surf-report,
   ex. `https://www.surf-report.com/meteo-surf/biarritz-grande-plage-s998.html` → slug `biarritz-grande-plage`, id `998`).
2. `cd proxy-server && node scripts/generate-watch-spots.js` (régénère la liste montre + réglages téléphone).
3. Redéployer le serveur (push sur GitHub → Render) **et** recompiler/re-publier l'app.

## Utilisation sur la montre

- **HAUT / BAS** (ou glisser) : pages Aujourd'hui → Marées → Vagues → Vent → jours suivants
- **START** (ou appui long HAUT) : menu *Actualiser* / *Spot* (ville → plage)
- **BACK** : retour à la 1re page, puis quitter
- Glance (liste des widgets depuis le cadran) : vagues du jour + 2 prochaines marées

## Choisir le spot depuis le téléphone (publication en « bêta »)

Les réglages modifiables dans **Garmin Connect** ne marchent que pour une app installée
depuis le Connect IQ Store. Une app copiée en USB (`.prg`) n'a pas de réglages téléphone.
La solution sans publication publique : une **app bêta**, visible uniquement par ton compte.

1. Compiler le paquet toutes montres :
   VS Code → `Monkey C: Export Project`, ou
   `monkeyc -e -r -f monkey.jungle -o bin/SurfTide.iq -y ../key/developer_key`
2. Aller sur <https://apps.garmin.com/developer/> (connexion avec le compte Garmin de la montre)
   → **Upload an App** → cocher **Beta App** → envoyer `bin/SurfTide.iq`, remplir nom/description/catégorie.
3. Une fois traitée (quelques minutes, pas de validation humaine pour une bêta),
   l'app apparaît dans l'app **Connect IQ** du téléphone (même compte) → l'installer sur la FR165.
4. Choisir le spot : app **Garmin Connect** → Appareils → Forerunner 165 → Activités & applis
   (ou *Connect IQ*) → **Waves** → **Paramètres** → *Spot (ville – plage)*.
   La montre recharge automatiquement les données du nouveau spot.
5. Mise à jour : recompiler le `.iq` et l'envoyer sur la même app bêta (« Upload new version »).

⚠️ Garder `../key/developer_key` en lieu sûr : une mise à jour doit être signée avec la même clé.

## Serveur (Render)

`proxy-server/` : `npm install && npm start`. Endpoints :
- `GET /api/combined?spot=998` — prévisions 7 jours du spot (cache 30 min)
- `GET /api/spots` — liste des spots
- `GET /health`

En cas d'échec de surf-report, le serveur renvoie une erreur 502 (pas de fausses données) :
la montre garde ses dernières données et affiche « surf-report indispo ».
