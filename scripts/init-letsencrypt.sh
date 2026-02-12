#!/bin/bash

# Script d'initialisation des certificats Let's Encrypt
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

# Charger les variables sans utiliser export sur tout le fichier .env
MATRIX_DOMAIN=$(grep '^MATRIX_DOMAIN=' .env | cut -d'=' -f2)
LETSENCRYPT_EMAIL=$(grep '^LETSENCRYPT_EMAIL=' .env | cut -d'=' -f2)
CERTBOT_STAGING=$(grep '^CERTBOT_STAGING=' .env | cut -d'=' -f2)

echo "========================================"
echo "Initialisation Let's Encrypt"
echo "========================================"
echo "Domaine: $MATRIX_DOMAIN"
echo "Email: $LETSENCRYPT_EMAIL"
echo "Mode staging: $CERTBOT_STAGING"
echo ""

# Créer les répertoires nécessaires
mkdir -p certbot/conf certbot/www

# Télécharger les paramètres SSL recommandés
if [ ! -e "certbot/conf/options-ssl-nginx.conf" ]; then
    echo "Téléchargement des paramètres SSL..."
    curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > certbot/conf/options-ssl-nginx.conf
    echo "✓ options-ssl-nginx.conf téléchargé"
fi

if [ ! -e "certbot/conf/ssl-dhparams.pem" ]; then
    echo "Téléchargement des paramètres DH..."
    curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem > certbot/conf/ssl-dhparams.pem
    echo "✓ ssl-dhparams.pem téléchargé"
fi

# Utiliser la config initiale nginx (HTTP only)
echo "Configuration de Nginx en mode HTTP..."
cp nginx/conf.d/matrix.conf.initial nginx/conf.d/matrix.conf

# Démarrer nginx
echo "Démarrage de Nginx..."
docker compose up -d nginx
sleep 5

# Vérifier que nginx est accessible
echo "Vérification de Nginx..."
if ! docker compose ps nginx | grep -q "Up"; then
    echo "❌ Erreur: Nginx n'a pas démarré"
    docker compose logs nginx
    exit 1
fi
echo "✓ Nginx démarré"

# Préparer les arguments certbot
STAGING_ARG=""
if [ "$CERTBOT_STAGING" = "true" ]; then
    STAGING_ARG="--staging"
    echo "⚠ Mode staging activé (certificat de test)"
fi

# Demander le certificat
echo ""
echo "Demande du certificat Let's Encrypt..."
docker compose run --rm certbot certonly \
    --webroot \
    --webroot-path=/var/www/certbot \
    --email "$LETSENCRYPT_EMAIL" \
    --agree-tos \
    --no-eff-email \
    $STAGING_ARG \
    -d "$MATRIX_DOMAIN"

# Vérifier si le certificat a été obtenu
if [ -d "certbot/conf/live/$MATRIX_DOMAIN" ]; then
    echo "✓ Certificat obtenu avec succès!"
    
    # Régénérer la config nginx avec SSL
    echo "Mise à jour de la configuration Nginx avec SSL..."
    ./scripts/generate-config.sh
    
    # Redémarrer nginx avec la nouvelle config
    echo "Redémarrage de Nginx..."
    docker compose restart nginx
    
    echo ""
    echo "========================================"
    echo "✓ Configuration SSL terminée!"
    echo "========================================"
    echo ""
    echo "Vous pouvez maintenant lancer:"
    echo "  docker compose up -d"
else
    echo "❌ Erreur: Le certificat n'a pas été obtenu"
    echo "Vérifiez que le domaine $MATRIX_DOMAIN pointe vers ce serveur"
    exit 1
fi