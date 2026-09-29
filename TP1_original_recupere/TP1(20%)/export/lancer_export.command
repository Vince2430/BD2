#!/bin/bash
# =============================================================
# TP1 - Base de donnees II (420-B56)
# Lanceur de l'export (etape 7) : execute export_connaissances.sql
# sur tp1_vincent_trudel et (re)genere base_connaissances.jsonl
# dans ce dossier.
#
# Prealable : la base doit exister (lancer creer_bd.command avant).
# Lecture seule : l'export ne modifie pas la base; relancable a
# volonte. Si une verification echoue (moins de 50 unites, donnee
# personnelle detectee...), le fichier n'est PAS regenere.
# Double-cliquer ce fichier dans le Finder pour l'executer.
# =============================================================

# Se placer dans le dossier du script (le .sql est a cote, et le
# fichier JSONL est ecrit ici)
cd "$(dirname "$0")" || exit 1

SCRIPT_EXPORT="export_connaissances.sql"

echo "============================================="
echo " TP1 - Export de la base de connaissances"
echo "============================================="
echo

if [ ! -f "$SCRIPT_EXPORT" ]; then
    echo "ERREUR : $SCRIPT_EXPORT est introuvable dans ce dossier."
    read -r -p "Appuyez sur Entree pour fermer..."
    exit 1
fi

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
# -X : ignore ~/.psqlrc (un reglage personnel pourrait changer le
#      format de sortie et abimer le fichier JSONL)
"$PSQL" -X -v ON_ERROR_STOP=1 -d tp1_vincent_trudel -f "$SCRIPT_EXPORT"
RESULTAT=$?
unset PGPASSWORD

echo
if [ $RESULTAT -ne 0 ]; then
    echo "ECHEC de l'export (voir le message ci-dessus)."
    echo "base_connaissances.jsonl n'a pas ete regenere."
else
    echo "============================================="
    echo " Termine : $(wc -l < base_connaissances.jsonl | tr -d ' ') unites"
    echo " dans export/base_connaissances.jsonl"
    echo "============================================="
fi
echo
read -r -p "Appuyez sur Entree pour fermer..."
