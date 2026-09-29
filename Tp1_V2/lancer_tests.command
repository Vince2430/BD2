#!/bin/bash
# =============================================================
# TP1 - Base de donnees II (420-B56)
# Lanceur des tests : execute 08_tests.sql et affiche [OK] / [ECHEC]
# pour chaque test, puis le bilan.
# Double-cliquer ce fichier dans le Finder pour l'executer.
#
# Prerequis : la base a ete creee par creer_bd.command.
# Les tests ne modifient pas la base (ROLLBACK final).
#
# ON_ERROR_ROLLBACK=on : psql entoure chaque instruction d'un point de
# sauvegarde; un test en echec n'empeche donc pas les suivants de
# s'executer (contrairement a pgAdmin, qui s'arrete au premier echec).
# =============================================================

cd "$(dirname "$0")" || exit 1

echo "============================================="
echo " TP1 - Tests automatises (08_tests.sql)"
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
    pause_et_quitter 1
fi

if [ ! -f "08_tests.sql" ]; then
    echo "ERREUR : 08_tests.sql introuvable a cote du lanceur."
    pause_et_quitter 1
fi

# --- Parametres de connexion (superutilisateur : SET ROLE demo_*) --
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

# Nombre de tests : les en-tetes « -- Txx » de 08_tests.sql
TOTAL=$(grep -cE '^-- T[0-9]{2} ' 08_tests.sql)

# Journal complet dans un fichier temporaire, HORS du dossier du TP
JOURNAL="$(mktemp -t tp1_tests)"

"$PSQL" -X -v ON_ERROR_ROLLBACK=on -d tp1_vincent_trudel -f 08_tests.sql > "$JOURNAL" 2>&1
CODE_PSQL=$?

# Une ligne par test : [OK] Txx ... ou [ECHEC] Txx ...
grep -oE '\[(OK|ECHEC)\] T[0-9]{2}.*' "$JOURNAL"

REUSSIS=$(grep -cE '\[OK\] T[0-9]{2}' "$JOURNAL")
ECHECS=$(grep -cE '\[ECHEC\] T[0-9]{2}' "$JOURNAL")

# Autres erreurs (ex. connexion refusee, erreur hors d'un test)
AUTRES=$(grep -E 'ERROR|ERREUR|FATAL' "$JOURNAL" | grep -vcE '\[ECHEC\]')

echo
echo "============================================="
echo " Bilan : $REUSSIS / $TOTAL test(s) reussi(s)"
[ "$ECHECS" -gt 0 ] && echo " Echecs : $ECHECS"
echo "============================================="

if [ "$REUSSIS" -eq "$TOTAL" ] && [ "$AUTRES" -eq 0 ] && [ $CODE_PSQL -eq 0 ]; then
    rm -f "$JOURNAL"
    pause_et_quitter 0
else
    echo
    echo "Journal complet : $JOURNAL"
    if [ "$AUTRES" -gt 0 ]; then
        echo "Autres erreurs :"
        grep -E 'ERROR|ERREUR|FATAL' "$JOURNAL" | grep -vE '\[ECHEC\]' | head -5
    fi
    pause_et_quitter 1
fi
