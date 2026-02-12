#!/bin/bash
# ===========================================
# Script de génération de la configuration Synapse
# À partir des variables d'environnement
# ===========================================

set -e

# Charger les variables d'environnement
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

echo "========================================"
echo "Génération de la configuration Synapse"
echo "========================================"

# Fichiers template et destination
TEMPLATE_FILE="./synapse/homeserver.yaml.template"
OUTPUT_FILE="./synapse/homeserver.yaml"
NGINX_TEMPLATE="./nginx/conf.d/matrix.conf.template"
NGINX_OUTPUT="./nginx/conf.d/matrix.conf"

# Copier le template si homeserver.yaml n'existe pas
if [ -f "$OUTPUT_FILE" ]; then
    echo "homeserver.yaml existe déjà."
    read -p "Voulez-vous le régénérer? (y/N) " decision
    if [ "$decision" != "Y" ] && [ "$decision" != "y" ]; then
        echo "Conservation de la configuration existante."
    else
        cp "$TEMPLATE_FILE" "$OUTPUT_FILE"
        echo "Configuration Synapse régénérée."
    fi
else
    cp "$TEMPLATE_FILE" "$OUTPUT_FILE"
    echo "Configuration Synapse créée."
fi

# Remplacer les variables dans homeserver.yaml
echo "Application des variables d'environnement..."

# Fonction pour remplacer les variables
replace_var() {
    local var_name=$1
    local var_value=$2
    local file=$3
    if [ -n "$var_value" ]; then
        sed -i "s|\${$var_name}|$var_value|g" "$file"
        sed -i "s|changeme_${var_name,,}|$var_value|g" "$file"
    fi
}

# Variables Synapse
sed -i "s|server_name: \"example.com\"|server_name: \"$SERVER_NAME\"|g" "$OUTPUT_FILE"
sed -i "s|https://matrix.example.com|https://$MATRIX_DOMAIN|g" "$OUTPUT_FILE"
sed -i "s|changeme_postgres_password|$POSTGRES_PASSWORD|g" "$OUTPUT_FILE"
sed -i "s|changeme_registration_secret|$SYNAPSE_REGISTRATION_SHARED_SECRET|g" "$OUTPUT_FILE"
sed -i "s|changeme_macaroon_secret|$SYNAPSE_MACAROON_SECRET_KEY|g" "$OUTPUT_FILE"

# Variables OIDC/Keycloak
sed -i "s|https://keycloak.example.com/realms/master|$OIDC_ISSUER|g" "$OUTPUT_FILE"
sed -i "s|client_id: \"synapse\"|client_id: \"$OIDC_CLIENT_ID\"|g" "$OUTPUT_FILE"
sed -i "s|changeme_keycloak_client_secret|$OIDC_CLIENT_SECRET|g" "$OUTPUT_FILE"

# Mettre à jour la configuration Nginx
echo "Mise à jour de la configuration Nginx..."
sed -i "s|matrix.example.com|$MATRIX_DOMAIN|g" "$NGINX_OUTPUT"

echo "========================================"
echo "Configuration terminée!"
echo "========================================"
echo ""
echo "Vérifiez les fichiers suivants:"
echo "  - $OUTPUT_FILE"
echo "  - $NGINX_OUTPUT"
echo ""
echo "Puis lancez: docker compose up -d"
