#!/bin/bash
# =============================================================
# TP1 - Base de donnees II (420-B56)
# Lanceur principal : cree la base tp1_vincent_trudel et execute les
# scripts 00 a 05 dans l'ordre, en s'arretant a la premiere erreur.
# Double-cliquer ce fichier dans le Finder pour l'executer.
#
# ATTENTION : destructif. La base est supprimee puis recreee.
# Apres l'execution, redefinir les mots de passe des roles demo_*
# (voir README.md).
# =============================================================

# Se placer dans le dossier du script (les .sql sont a cote)
cd "$(dirname "$0")" || exit 1

echo "============================================="
echo " TP1 - Creation de la base tp1_vincent_trudel"
echo "============================================="
echo

pause_et_quitter() {
    unset PGPASSWORD
    echo
    read -r -p "Appuyez sur Entree pour fermer..."
    exit "$1"
}

# --- Trouver psql -------------------------------------------------
PSQL=""
if command -v psql >/dev/null 2>&1; then
    PSQL="$(command -v psql)"
else
    for CANDIDAT in \
        /Library/PostgreSQL/*/bin/psql \
        /opt/homebrew/bin/psql \
        /usr/local/bin/psql \
        /Applications/Postgres.app/Contents/Versions/latest/bin/psql
    do
        if [ -x "$CANDIDAT" ]; then PSQL="$CANDIDAT"; fi
    done
fi

if [ -z "$PSQL" ]; then
    echo "ERREUR : psql est introuvable."
    echo "Installez les outils client PostgreSQL ou ajoutez psql au PATH."
    pause_et_quitter 1
fi
echo "psql utilise : $PSQL"
echo

# --- Parametres de connexion (superutilisateur) --------------------
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
# Format : fichier|base de connexion|description
ETAPES=(
    "00_create_database.sql|postgres|creation de la base"
    "01_create_schema.sql|tp1_vincent_trudel|schema, tables, JSONB et index"
    "02_declencheurs.sql|tp1_vincent_trudel|declencheurs"
    "03_donnees.sql|tp1_vincent_trudel|donnees fictives (1 a 2 minutes)"
    "04_vues_fonctions.sql|tp1_vincent_trudel|vues, vue materialisee, fonction, procedure"
    "05_roles.sql|tp1_vincent_trudel|roles et privileges"
)

for ETAPE in "${ETAPES[@]}"; do
    IFS='|' read -r FICHIER BASE DESCRIPTION <<< "$ETAPE"
    echo "--- $FICHIER : $DESCRIPTION ---"

    if [ ! -f "$FICHIER" ]; then
        echo "ECHEC : fichier $FICHIER introuvable."
        pause_et_quitter 1
    fi

    "$PSQL" -X -q -v ON_ERROR_STOP=1 -d "$BASE" -f "$FICHIER"
    if [ $? -ne 0 ]; then
        echo
        echo "ECHEC a l'etape $FICHIER : execution arretee."
        if [ "$FICHIER" = "00_create_database.sql" ]; then
            echo "Verifiez la connexion, ou fermez les sessions ouvertes"
            echo "sur tp1_vincent_trudel (pgAdmin), puis relancez."
        fi
        pause_et_quitter 1
    fi
    echo
done

echo "============================================="
echo " Termine. Base tp1_vincent_trudel prete."
echo " N'oubliez pas : ALTER ROLE demo_gestionnaire WITH PASSWORD '...';"
echo "                 ALTER ROLE demo_employe      WITH PASSWORD '...';"
echo "============================================="
pause_et_quitter 0
