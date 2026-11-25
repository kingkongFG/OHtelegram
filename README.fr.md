# Petrelgram

[English](README.md) · [简体中文](README.zh-CN.md) · [Русский](README.ru.md) · **Français**

[![Telegram](https://img.shields.io/badge/Telegram-Rejoindre%20le%20groupe-26A5E4?style=flat&logo=telegram&logoColor=white)](https://t.me/+khkR9mLZyoliODFl)
[![Release](https://img.shields.io/github/v/release/miramira8295/Petrelgram?style=flat)](https://github.com/miramira8295/Petrelgram/releases)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue?style=flat)](LICENSE)

Un **client Telegram non officiel et open source pour HarmonyOS NEXT**, écrit en
ArkTS/ArkUI au-dessus de [TDLib](https://core.telegram.org/tdlib), la
bibliothèque cliente de Telegram, reliée par un pont natif N-API.

## Fonctionnalités

- **Comptes** — connexion par téléphone avec 2FA, plusieurs comptes, bascule et
  déconnexion
- **Liste des discussions** — dossiers, archives, badges non lus, état de la
  connexion en direct
- **Messages** — texte enrichi, photos, albums, vidéos, fichiers, stickers
  (WEBP / TGS / WEBM), émojis personnalisés, réponses, transferts, réactions,
  fils de commentaires, messages épinglés et programmés, sélection multiple
- **Rédaction** — autocomplétion des mentions et commandes, médias, fichiers,
  messages vocaux, musique, position, contacts, sondages, dés
- **Appels** — audio et vidéo 1:1 chiffrés de bout en bout via tgcalls
- **Appels de groupe et directs** — audio multi-participants, caméra et partage
  d'écran, diffusions de chaînes, fenêtre flottante dans l'application
- **Sujets et stories** — listes de sujets de forum avec fils dédiés ; lecteur
  de stories en plein écran
- **Recherche** — recherche globale sur 11 catégories
- **Profils** — utilisateurs, bots, groupes et chaînes ; modification de
  l'avatar, de la bio et du nom d'utilisateur ; carte de visite QR
- **Réglages** — confidentialité et sécurité, notifications, stockage, sessions
  et appareils, dossiers de discussion, économie d'énergie, thème sombre

## Arborescence

```
AppScope/            configuration applicative (nom du paquet, icône)
entry/src/main/ets/
  tdkit/             pont TDLib N-API, client, service d'authentification
  store/             stores immuables + abonnements (discussions, messages, …)
  pages/             pages ArkUI (connexion, liste, discussion, profil, recherche …)
  services/          streaming média, tâches d'arrière-plan des directs, audio
  util/              analyse et formatage (texte enrichi, albums, dates …)
entry/src/main/cpp/  pont natif (libentry.so → libtdjson.so / libtgcalls_ohos.so)
entry/src/test/      tests unitaires (via scripts/run-local-tests.sh)
libs/                ijkplayer-2.0.13-pg.10.har (référencé par oh-package.json5)
entry/libs/arm64-v8a/ libentry.so / libtdjson.so / libtgcalls_ohos.so précompilés
third_party/         bibliothèques statiques libvpx-ohos/ et rlottie-ohos/
scripts/             scripts de reconstruction facultatifs (TDLib, tgcalls,
                     libvpx, rlottie, ijkplayer) et contrôle local
```

## Compilation

### Prérequis

- **DevEco Studio 6.0+** avec son SDK/NDK OpenHarmony intégré
- Un appareil ou un émulateur HarmonyOS NEXT (arm64-v8a)
- Un compte développeur Huawei, uniquement pour la signature automatique

Rien d'autre à installer avant de compiler : les bibliothèques natives et le paquet
ijkplayer sont déjà dans le dépôt.

### 1. Bibliothèques natives (déjà fournies)

Tout ce à quoi `libentry.so` se lie est versionné dans le dépôt : un clone neuf ne
télécharge et ne compile rien.

| Chemin | Contenu |
| --- | --- |
| `entry/libs/arm64-v8a/` | `libentry.so` (pont N-API), `libtdjson.so` (~33 Mo), `libtgcalls_ohos.so` (~18 Mo) |
| `third_party/libvpx-ohos/` | `libvpx.a` + en-têtes |
| `third_party/rlottie-ohos/` | `librlottie.a` + en-têtes |
| `libs/` | `ijkplayer-2.0.13-pg.10.har`, référencé par `oh-package.json5` |

Conséquences :

- Il n'est **pas** nécessaire de lancer `scripts/fetch-libs.sh`,
  `scripts/fetch-tdlib.sh`, `scripts/fetch-ijkplayer.sh`,
  `scripts/build-tdlib.sh`, `scripts/build-tgcalls-ohos.sh`,
  `scripts/build-libvpx-ohos.sh` ni `scripts/build-rlottie-ohos.sh`. Ces scripts
  ne servent qu'à reconstruire les artefacts depuis les sources, ce qui exige une
  chaîne OHOS NDK (clang, cmake, ninja, gperf, patchelf) et une première
  compilation WebRTC très longue.
- `entry/build-profile.json5` ne déclare aucun `externalNativeOptions` : hvigor ne
  compile jamais le pont C++, il empaquette le `libentry.so` précompilé tel quel.
  Le reconstruire est une étape séparée et rare, décrite en fin de section.
- Pour référence : TDLib 1.8.65 ; tgcalls tel que figé dans
  [`scripts/tgcalls/README.md`](scripts/tgcalls/README.md) ; ijkplayer
  `2.0.13-pg.10` (le correctif « async release » est
  `scripts/ijkplayer-pg10-async-release.patch`).

### 2. Identifiants de l'API Telegram (à enregistrer vous-même)

Ce dépôt ne fournit **aucun** `api_id`/`api_hash`, ni aucun script qui les génère,
les empaquette ou les obscurcit. TDLib ne peut pas se connecter sans une paire dont
vous êtes titulaire :

1. Enregistrez une application sur <https://my.telegram.org/apps>. La page renvoie
   un `api_id` (un nombre) et un `api_hash` (32 caractères hexadécimaux).
2. Copiez `entry/src/main/ets/tdkit/ApiCredentials.template.ets` en
   `ApiCredentials.ets` dans le même dossier.
3. Renseignez les deux constantes en clair de cette copie :

   ```ts
   export const apiId: number = 1234567;                              // votre api_id
   export const apiHash: string = '0123456789abcdef0123456789abcdef'; // votre api_hash
   ```

   Le même fichier contient quatre champs facultatifs — `pushRelayBase`,
   `pushRelayToken`, `crashReportBase`, `crashReportToken` — qui restent vides
   sauf si vous exploitez votre propre relais de notifications ou collecteur de
   rapports de plantage. Une valeur vide masque simplement la fonction
   correspondante ; rien d'autre n'en dépend.
4. Compilez. Aucun autre fichier ne lit ces valeurs, et aucune étape de compilation
   n'a besoin du réseau.

`**/ApiCredentials.ets` figure dans `.gitignore` : la copie remplie ne peut pas être
validée par accident — **ne validez jamais de véritables identifiants** et, en cas de
fuite, révoquez-les et réenregistrez immédiatement. Ne les collez pas non plus dans
une issue, une capture d'écran ou un journal : ils identifient votre application, pas
votre compte, mais ils ne sont pas publics pour autant.

### 3. Signature

`signingConfigs` dans `build-profile.json5` est vide, et le dépôt ne contient ni
certificat, ni keystore, ni profil de provisionnement :

1. Ouvrez le projet dans DevEco Studio.
2. Allez dans **File > Project Structure > Signing Configs** et cochez
   **Automatically generate signature** (signature automatique HarmonyOS ; l'IDE
   doit être connecté à un compte développeur Huawei).
3. Laissez DevEco Studio générer le certificat et le profil de débogage pour
   `com.ohtelegram.client`. Ils sont stockés dans votre profil utilisateur, hors du
   dépôt.

Aucun paquet HAP ou APP n'est conservé dans le dépôt non plus : la sortie de build
reste sous `entry/build/`, qui est dans le gitignore.

Les sources amont livraient ce fichier avec des chemins absolus vers un certificat,
un keystore et un profil locaux, accompagnés du mot de passe du keystore, le tout en
clair. Ce fork a tout supprimé. Si vous compilez depuis l'amont, considérez ces
valeurs comme compromises : générez votre propre certificat et ne réutilisez jamais
un keystore ou un mot de passe déjà publié.

### 4. Compiler et lancer

Le parcours complet tient en quatre étapes dans DevEco Studio :

1. **Ouvrir le projet** — `File > Open`, choisissez la racine du dépôt (le dossier
   qui contient `build-profile.json5`) et laissez la synchronisation lancée à
   l'ouverture se terminer (elle exécute `ohpm install`).
2. **Configurer la signature** — voir l'étape 3 ci-dessus.
3. **Construire le HAP** — `Build > Build Hap(s)/APP(s) > Build Hap(s)`, ou
   `hvigorw assembleHap --no-daemon` dans un terminal où `hvigorw` est dans le
   `PATH`. La sortie se trouve dans `entry/build/default/outputs/default/`.
4. **Lancer sur l'appareil** — connectez un appareil HarmonyOS NEXT avec le débogage
   USB activé (ou démarrez un émulateur), sélectionnez-le dans le sélecteur
   d'appareil et appuyez sur **Run**. Le premier lancement demande un numéro de
   téléphone et le code envoyé par Telegram ; TDLib fait le reste.

Comme `externalNativeOptions` n'est pas déclaré, ce parcours empaquette le
`libentry.so` précompilé de `entry/libs/arm64-v8a/` : le pont n'est pas compilé.
Aucun script `fetch-*` ou `build-*` n'a à tourner avant, pendant ou après la
compilation.

Facultatif, uniquement après modification des sources C++ : réintroduisez dans
`entry/build-profile.json5` une entrée `externalNativeOptions` pointant vers
`entry/src/main/cpp` avec `abiFilters: ["arm64-v8a"]` (le projet CMake et la cible
partagée `entry` sont toujours dans l'arborescence, `project(Petrelgram)`), compilez
une fois pour que cmake/ninja produisent `libentry.so`, copiez-le dans
`entry/libs/arm64-v8a/`, puis retirez l'option. Exclure le pont de la compilation de
l'application est délibéré : ce sont quelques milliers de lignes de C++ qui changent
rarement, alors que le HAP est reconstruit plusieurs fois par jour.

Contrôle facultatif, réservé aux contributeurs (nécessite Node.js ; hors build de
l'application) :

```bash
./scripts/run-local-tests.sh    # doit afficher "LOCAL TESTS: PASS"
```

Le script exécute la vérification i18n avant les tests unitaires : un contrôle
statique qui répond en une seconde ne doit pas attendre deux minutes de compilation.

## Localisation

Tous les textes de l'interface vivent dans les fichiers de ressources. La langue
source (chinois simplifié) est dans
`entry/src/main/resources/base/element/string.json` ; les traductions vont dans
les dossiers qualifiés par langue (`fr/element/string.json`, etc.), les pluriels
dans `element/plural.json`. Le système fait correspondre la langue de l'appareil
et retombe sur `base`.

**`$r()` ou `str()`.** Tout ce qu'un composant affiche utilise
`$r('app.string.x')` : c'est une `Resource`, que ArkUI réévalue lors d'un
changement de configuration, donc le changement de langue prend effet
immédiatement. `str('x')` renvoie une chaîne ordinaire figée à la compilation —
à réserver aux cas où un `string` est réellement nécessaire : `@State` de type
`string`, champs de modèle, comparaisons, `.join()` et code hors interface. Si
un paramètre `@Builder` provoque un conflit de types, élargissez-le en
`ResourceStr` plutôt que de revenir à `str()` sur l'appelant.

**Une `const` au niveau du module ne peut pas contenir de texte.** Les constantes
sont construites au premier import, avant que la source des chaînes ne soit
prête, ce qui fige la langue à cet instant. Utilisez une fonction
(`fallbackCountries()`, pas `FALLBACK_COUNTRIES`).

**Ne comparez jamais du texte affiché.** `label.substring(0, 2)` ou
`text.includes('Réessayer')` cassent dès le changement de langue ; branchez sur
des champs structurés.

Les chaînes de diagnostic qui n'atteignent que `console.*` ne sont pas
traduites ; annotez-les avec `// i18n-exempt: <raison>`.

```bash
node scripts/i18n-extract.mjs               # textes encore codés en dur, par domaine
node scripts/i18n-extract.mjs --domain util # détails et suggestions de clés
node scripts/i18n-lit.mjs <file>            # littéraux avec numéros de ligne
node scripts/i18n-check.mjs                 # le contrôle (inclus dans run-local-tests.sh)
```

`i18n-check.mjs` vérifie cinq points : chaque clé référencée dans le code existe
dans `base` ; chaque clé de `base` est référencée quelque part ; **aucune source
de gabarit `${` ne subsiste dans une valeur de ressource, et la numérotation des
paramètres est identique d'une langue à l'autre** ; aucune clé orpheline hors de
`base`, et quelles entrées manquent à chaque langue ; **aucun littéral chinois ne
subsiste dans les dossiers déjà couverts**.

Le troisième point a été ajouté après coup : le contrôle, les tests et le
compilateur voient chacun une classe d'erreurs, mais aucun ne voit que la valeur
de `file_downloading` *est* la source du gabarit `${sizeLabel} ·
téléchargement`. Ce genre d'erreur n'apparaît que sur l'appareil.

`MIGRATED` dans `scripts/i18n-config.mjs` couvre désormais tous les dossiers
sources — les nouveaux dossiers doivent y être ajoutés, sinon le contrôle les
ignore silencieusement. Nommage des clés : `<domaine>_<composant>_<sens>`, par
exemple `chat_forward_title`.

## État et avertissement

- En développement actif ; l'interface vise à rester proche du client Android
  officiel.
- Il s'agit d'un client **non officiel**. Utilisez vos propres identifiants API
  et respectez les
  [conditions d'utilisation de l'API Telegram](https://core.telegram.org/api/terms).
- La recherche d'inconnus suit les règles de découvrabilité côté serveur de
  Telegram/TDLib : elle ne trouve généralement que les utilisateurs dotés d'un
  nom d'utilisateur public ou entrant dans le périmètre de recherche du serveur,
  et ne permet pas d'énumérer des numéros de téléphone arbitraires.

## Licence

[Apache License 2.0](LICENSE)
