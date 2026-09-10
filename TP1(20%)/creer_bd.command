#!/bin/bash
# =============================================================
# TP1 - Base de donnees II (420-B56)
# Lanceur : cree la base tp1_vincent_trudel puis son schema.
# Double-cliquer ce fichier dans le Finder pour l'executer.
# =============================================================

# Se placer dans le dossier du script (les .sql sont a cote)
cd "$(dirname "$0")" || exit 1

echo "============================================="
echo " TP1 - Creation de la base tp1_vincent_trudel"
echo "============================================="
echo

# --- Trouver psql -------------------------------------------------
PSQL=""
if command -v psql >/dev/null 2>&1; then
    PSQL="$(command -v psql)"
else
    for CANDIDAT in \
        /opt/homebrew/bin/psql \
        /usr/local/bin/psql \
        /Applications/Postgres.app/Contents/Versions/latest/bin/psql \
        /Library/PostgreSQL/*/bin/psql
    do
        if [ -x "$CANDIDAT" ]; then PSQL="$CANDIDAT"; break; fi
    done
fi

if [ -z "$PSQL" ]; then
    echo "ERREUR : psql est introuvable."
    echo "Installez les outils client PostgreSQL ou ajoutez psql au PATH."
    echo
    read -r -p "Appuyez sur Entree pour fermer..."
    exit 1
fi
echo "psql utilise : $PSQL"
echo

# --- Parametres de connexion --------------------------------------
read -r -p "Hote [localhost] : " PGHOST_IN
read -r -p "Port [5432] : "     PGPORT_IN
read -r -p "Utilisateur [postgres] : " PGUSER_IN
read -r -s -p "Mot de passe : " PGPASSWORD_IN
echo
echo

export PGHOST="${PGHOST_IN:-localhost}"
export PGPORT="${PGPORT_IN:-5432}"
export PGUSER="${PGUSER_IN:-postgres}"
export PGPASSWORD="$PGPASSWORD_IN"

# --- Execution ----------------------------------------------------
echo "--- Etape 0 : creation de la base ---"
"$PSQL" -v ON_ERROR_STOP=1 -d postgres -f "00_create_database.sql"
if [ $? -ne 0 ]; then
    echo
    echo "ECHEC a l'etape 0. Verifiez la connexion, ou fermez les sessions"
    echo "ouvertes sur tp1_vincent_trudel (pgAdmin) puis relancez."
    unset PGPASSWORD
    read -r -p "Appuyez sur Entree pour fermer..."
    exit 1
fi

echo
echo "--- Etape 1 : creation du schema et des tables ---"
"$PSQL" -v ON_ERROR_STOP=1 -d tp1_vincent_trudel -f "01_create_schema.sql"
if [ $? -ne 0 ]; then
    echo
    echo "ECHEC a l'etape 1."
    unset PGPASSWORD
    read -r -p "Appuyez sur Entree pour fermer..."
    exit 1
fi

echo
echo "--- Etape 2 : installation des declencheurs ---"
"$PSQL" -v ON_ERROR_STOP=1 -d tp1_vincent_trudel -f "02_declencheurs.sql"
if [ $? -ne 0 ]; then
    echo
    echo "ECHEC a l'etape 2."
    unset PGPASSWORD
    read -r -p "Appuyez sur Entree pour fermer..."
    exit 1
fi

unset PGPASSWORD
echo
echo "============================================="
echo " Termine. Base tp1_vincent_trudel prete."
echo "============================================="
echo
read -r -p "Appuyez sur Entree pour fermer..."
