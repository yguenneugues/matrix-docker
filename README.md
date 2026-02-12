# Matrix Synapse Docker Deployment

Déploiement Docker Compose de Matrix Synapse avec PostgreSQL, Nginx (HTTPS) et authentification OpenID Connect via Keycloak.

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│     Nginx       │────▶│     Synapse     │────▶│   PostgreSQL    │
│   (Reverse      │     │    (Matrix      │     │   (Database)    │
│    Proxy)       │     │    Server)      │     │                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │                       │
        │                       ▼
        │               ┌─────────────────┐
        │               │    Keycloak     │
        │               │   (External)    │
        │               │     OIDC        │
        │               └─────────────────┘
        ▼
┌─────────────────┐
│    Certbot      │
│  (Let's Encrypt)│
└─────────────────┘
```

## Prérequis

- Docker et Docker Compose installés
- Un nom de domaine pointant vers votre serveur
- Ports 80, 443 et 8448 ouverts
- Un serveur Keycloak opérationnel avec un client configuré pour Synapse

## Configuration

### 1. Configurer les variables d'environnement

Copiez et modifiez le fichier `.env` :

```bash
cp .env .env.backup
nano .env
```

Variables importantes à modifier :

| Variable | Description |
|----------|-------------|
| `MATRIX_DOMAIN` | Domaine de votre serveur Matrix (ex: `matrix.example.com`) |
| `SERVER_NAME` | Nom du serveur Matrix (ex: `example.com`) |
| `POSTGRES_PASSWORD` | Mot de passe PostgreSQL |
| `SYNAPSE_REGISTRATION_SHARED_SECRET` | Secret pour l'inscription admin |
| `SYNAPSE_MACAROON_SECRET_KEY` | Clé secrète Macaroon |
| `OIDC_ISSUER` | URL de l'issuer Keycloak |
| `OIDC_CLIENT_ID` | ID du client Keycloak |
| `OIDC_CLIENT_SECRET` | Secret du client Keycloak |
| `LETSENCRYPT_EMAIL` | Email pour Let's Encrypt |

### 2. Générer des secrets sécurisés

```bash
# Générer un secret aléatoire
openssl rand -hex 32

# Ou avec pwgen
pwgen -s 64 1
```

### 3. Configuration Keycloak

Dans votre serveur Keycloak, configurez le client Synapse avec :

- **Client ID** : `synapse`
- **Client Protocol** : `openid-connect`
- **Access Type** : `confidential`
- **Valid Redirect URIs** : 
  - `https://matrix.example.com/_synapse/client/oidc/callback`
- **Web Origins** : `https://matrix.example.com`

Récupérez le **Client Secret** dans l'onglet "Credentials".

### 4. Mettre à jour les fichiers de configuration

Modifiez les fichiers suivants avec votre domaine :

**synapse/homeserver.yaml** :
- `server_name`
- `public_baseurl`
- Paramètres de base de données
- Configuration OIDC

**nginx/conf.d/matrix.conf** :
- Remplacez `matrix.example.com` par votre domaine

Ou utilisez le script :
```bash
chmod +x scripts/generate-config.sh
./scripts/generate-config.sh
```

## Déploiement

### Étape 1 : Génération des certificats Let's Encrypt

```bash
# Rendre le script exécutable
chmod +x scripts/init-letsencrypt.sh

# Lancer l'initialisation des certificats
./scripts/init-letsencrypt.sh
```

**Mode staging** : Pour tester sans risquer de dépasser les limites de Let's Encrypt :
```bash
# Dans .env
CERTBOT_STAGING=true
```

### Étape 2 : Démarrer les services

```bash
# Démarrer tous les services
docker compose up -d

# Vérifier les logs
docker compose logs -f

# Vérifier l'état des services
docker compose ps
```

### Étape 3 : Générer la clé de signature Synapse

Au premier démarrage, Synapse génère automatiquement sa clé de signature.

```bash
# Vérifier que la clé est créée
docker compose exec synapse ls -la /data/signing.key
```

### Étape 4 : Créer un utilisateur admin

```bash
# Créer un utilisateur admin
docker compose exec synapse register_new_matrix_user http://localhost:8008 \
    -c /data/homeserver.yaml \
    -u admin \
    -p <mot_de_passe> \
    --admin
```

## Vérification

### Test de la fédération

```bash
# Test via API
curl -s https://matrix.example.com/_matrix/federation/v1/version

# Test via Matrix Federation Tester
# https://federationtester.matrix.org/
```

### Test de l'authentification OIDC

1. Ouvrez `https://matrix.example.com/_matrix/client/r0/login`
2. Vérifiez que Keycloak apparaît comme option de connexion
3. Testez la connexion via Element ou un autre client Matrix

## Maintenance

### Renouvellement des certificats

Le renouvellement est automatique via le conteneur Certbot. Pour forcer un renouvellement :

```bash
docker compose run --rm certbot renew --force-renewal
docker compose exec nginx nginx -s reload
```

### Sauvegardes

```bash
# Sauvegarder la base de données
docker compose exec postgres pg_dump -U synapse synapse > backup_$(date +%Y%m%d).sql

# Sauvegarder les données Synapse
docker run --rm -v matrix-docker_synapse_data:/data -v $(pwd)/backup:/backup \
    alpine tar czf /backup/synapse_data_$(date +%Y%m%d).tar.gz /data
```

### Mise à jour

```bash
# Arrêter les services
docker compose down

# Mettre à jour les images
docker compose pull

# Redémarrer
docker compose up -d
```

### Logs

```bash
# Tous les logs
docker compose logs -f

# Logs d'un service spécifique
docker compose logs -f synapse
docker compose logs -f nginx
docker compose logs -f postgres
```

## Structure du projet

```
matrix-docker/
├── .env                          # Variables d'environnement
├── docker-compose.yml            # Configuration Docker Compose
├── nginx/
│   ├── nginx.conf               # Configuration principale Nginx
│   └── conf.d/
│       ├── matrix.conf          # Configuration du site Matrix
│       └── matrix.conf.initial  # Config initiale (avant certificats)
├── synapse/
│   ├── homeserver.yaml          # Configuration Synapse
│   └── log.config               # Configuration des logs
├── scripts/
│   ├── init-letsencrypt.sh      # Script d'initialisation Let's Encrypt
│   └── generate-config.sh       # Génération de config depuis .env
├── certbot/
│   ├── conf/                    # Certificats Let's Encrypt
│   └── www/                     # Challenges ACME
└── README.md
```

## Dépannage

### Problèmes courants

**Erreur de certificat SSL** :
```bash
# Vérifier les certificats
docker compose exec nginx nginx -t
ls -la certbot/conf/live/
```

**Synapse ne démarre pas** :
```bash
# Vérifier la configuration
docker compose exec synapse python -m synapse.config -c /data/homeserver.yaml
```

**Erreur de connexion à PostgreSQL** :
```bash
# Vérifier que PostgreSQL est prêt
docker compose exec postgres pg_isready
```

**Erreur OIDC** :
- Vérifiez que l'`issuer` est correct
- Vérifiez les redirect URIs dans Keycloak
- Consultez les logs Synapse pour les erreurs détaillées

### Ports utilisés

| Port | Service | Usage |
|------|---------|-------|
| 80 | Nginx | HTTP (redirection + ACME) |
| 443 | Nginx | HTTPS (Client-Server API) |
| 8448 | Nginx | HTTPS (Federation API) |
| 8008 | Synapse | API interne (non exposé) |
| 5432 | PostgreSQL | Base de données (non exposé) |

## Sécurité

- [ ] Changez tous les mots de passe par défaut
- [ ] Utilisez des secrets générés aléatoirement
- [ ] Restreignez l'accès aux fichiers `.env` et de configuration
- [ ] Configurez un pare-feu pour n'exposer que les ports nécessaires
- [ ] Activez le reporting de statistiques si vous le souhaitez

## Ressources

- [Documentation Synapse](https://matrix-org.github.io/synapse/latest/)
- [Spécification Matrix](https://spec.matrix.org/)
- [Documentation Keycloak](https://www.keycloak.org/documentation)
- [Let's Encrypt](https://letsencrypt.org/docs/)
