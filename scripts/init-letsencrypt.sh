#!/bin/bash
# ===========================================
# Script d'initialisation des certificats Let's Encrypt
# ===========================================

set -e

# Charger les variables d'environnement
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Variables
DOMAIN=${MATRIX_DOMAIN:-"matrix.example.com"}
EMAIL=${LETSENCRYPT_EMAIL:-"admin@example.com"}
STAGING=${CERTBOT_STAGING:-"false"}
RSA_KEY_SIZE=4096
DATA_PATH="./certbot"

echo "========================================"
echo "Initialisation des certificats Let's Encrypt"
echo "========================================"
echo "Domaine: $DOMAIN"
echo "Email: $EMAIL"
echo "Mode staging: $STAGING"
echo "========================================"

# Vérifier si les certificats existent déjà
if [ -d "$DATA_PATH/conf/live/$DOMAIN" ]; then
    read -p "Les certificats existent déjà. Voulez-vous les remplacer? (y/N) " decision
    if [ "$decision" != "Y" ] && [ "$decision" != "y" ]; then
        echo "Opération annulée."
        exit 0
    fi
fi

# Créer les répertoires nécessaires
mkdir -p "$DATA_PATH/conf"
mkdir -p "$DATA_PATH/www"

# Configuration staging si activé
STAGING_ARG=""
if [ "$STAGING" = "true" ]; then
    STAGING_ARG="--staging"
    echo "MODE STAGING ACTIVÉ - Les certificats ne seront PAS valides pour la production"
fi

# Télécharger les paramètres TLS recommandés
if [ ! -e "$DATA_PATH/conf/options-ssl-nginx.conf" ] || [ ! -e "$DATA_PATH/conf/ssl-dhparams.pem" ]; then
    echo "Téléchargement des paramètres TLS recommandés..."
    curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > "$DATA_PATH/conf/options-ssl-nginx.conf"
    curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem > "$DATA_PATH/conf/ssl-dhparams.pem"
    echo "Paramètres TLS téléchargés."
fi

# Créer un certificat dummy pour démarrer nginx
echo "Création d'un certificat temporaire..."
CERT_PATH="$DATA_PATH/conf/live/$DOMAIN"
mkdir -p "$CERT_PATH"
docker compose run --rm --entrypoint "\
    openssl req -x509 -nodes -newkey rsa:$RSA_KEY_SIZE -days 1 \
    -keyout '/etc/letsencrypt/live/$DOMAIN/privkey.pem' \
    -out '/etc/letsencrypt/live/$DOMAIN/fullchain.pem' \
    -subj '/CN=localhost'" certbot
echo "Certificat temporaire créé."

# Démarrer nginx pour la validation ACME
echo "Démarrage de nginx..."
docker compose up -d nginx
sleep 5

# Supprimer le certificat temporaire
echo "Suppression du certificat temporaire..."
docker compose run --rm --entrypoint "\
    rm -rf /etc/letsencrypt/live/$DOMAIN && \
    rm -rf /etc/letsencrypt/archive/$DOMAIN && \
    rm -rf /etc/letsencrypt/renewal/$DOMAIN.conf" certbot

# Demander le certificat Let's Encrypt
echo "Demande du certificat Let's Encrypt..."
docker compose run --rm --entrypoint "\
    certbot certonly --webroot -w /var/www/certbot \
    $STAGING_ARG \
    --email $EMAIL \
    --rsa-key-size $RSA_KEY_SIZE \
    --agree-tos \
    --no-eff-email \
    --force-renewal \
    -d $DOMAIN" certbot

echo "========================================"
echo "Certificat obtenu avec succès!"
echo "========================================"

# Recharger nginx
echo "Rechargement de nginx..."
docker compose exec nginx nginx -s reload

echo "========================================"
echo "Configuration terminée!"
echo "Votre serveur Matrix est prêt sur https://$DOMAIN"
echo "========================================"
