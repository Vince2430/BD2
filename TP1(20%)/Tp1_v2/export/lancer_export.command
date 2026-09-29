#!/bin/bash
# =============================================================
# TP1 - Base de donnees II (420-B56)
# Lanceur de l'export (etape 7) : regenere base_connaissances.jsonl
# a partir de PostgreSQL. Lecture seule.
# Double-cliquer ce fichier dans le Finder pour l'executer.
# =============================================================

cd "$(dirname "$0")" || exit 1

echo "============================================="
echo " TP1 - Export de la base de connaissances"
echo "============================================="
echo

pause_et_quitter() {
    unset PGPASSWORD
    echo
    read -r -p "Appuyez sur Entree pour fermer..."
    exit "$1"
}

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
    pause_et_quitter 1
fi

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

"$PSQL" -X -v ON_ERROR_STOP=1 -d tp1_vincent_trudel -f export_connaissances.sql
if [ $? -ne 0 ]; then
    echo
    echo "ECHEC : le fichier n'a pas ete regenere."
    pause_et_quitter 1
fi

echo
echo "Lignes ecrites : $(wc -l < base_connaissances.jsonl | tr -d ' ')"
pause_et_quitter 0
