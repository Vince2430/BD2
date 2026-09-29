#!/bin/bash
# =============================================================
# TP1 - Base de donnees II (420-B56)
# Lanceur des tests : execute 08_tests.sql sur tp1_vincent_trudel
# et affiche le resultat de CHAQUE test (OK ou ECHEC), puis un bilan.
#
# Prealable : la base doit exister (lancer creer_bd.command avant).
# Les tests ne modifient pas la base (ROLLBACK a la fin de
# 08_tests.sql) : ce lanceur peut etre relance a volonte.
# Double-cliquer ce fichier dans le Finder pour l'executer.
#
# Pourquoi tous les tests s'executent meme si l'un echoue :
#   ON_ERROR_ROLLBACK=on -> psql place un point de sauvegarde avant
#   chaque instruction. Si un test echoue, seul ce test est annule,
#   la transaction reste utilisable et psql passe au test suivant.
#   (Sans cette option, la premiere erreur rendrait la transaction
#   inutilisable et tous les tests suivants echoueraient.)
# =============================================================

# Se placer dans le dossier du script (08_tests.sql est a cote)
cd "$(dirname "$0")" || exit 1

SCRIPT_TESTS="08_tests.sql"

echo "============================================="
echo " TP1 - Tests de la base tp1_vincent_trudel"
echo "============================================="
echo

if [ ! -f "$SCRIPT_TESTS" ]; then
    echo "ERREUR : $SCRIPT_TESTS est introuvable dans ce dossier."
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
# Un super-utilisateur est necessaire : les tests T16 et T17 font
# SET ROLE demo_employe / demo_gestionnaire.
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

# Journal complet de l'execution (hors du dossier du TP : il ne doit
# pas se retrouver dans la remise)
JOURNAL="$(mktemp -t tp1_tests)"

# Nombre de tests attendus = nombre de messages "OK Txx" dans le script
NB_TOTAL=$(grep -c "RAISE NOTICE 'OK  T" "$SCRIPT_TESTS")

# --- Execution ----------------------------------------------------
#   -X                    : ignore ~/.psqlrc (execution reproductible)
#   -q                    : n'affiche pas "DO", "SET", ... apres chaque instruction
#   ON_ERROR_ROLLBACK=on  : un test en echec n'arrete pas les suivants
#   VERBOSITY=terse       : une seule ligne par erreur
echo "--- Execution de $SCRIPT_TESTS ($NB_TOTAL tests) ---"
echo

"$PSQL" -X -q \
    -v ON_ERROR_ROLLBACK=on \
    -v VERBOSITY=terse \
    -d tp1_vincent_trudel \
    -f "$SCRIPT_TESTS" 2>&1 \
| tee "$JOURNAL" \
| awk '
    # Test reussi : "... NOTICE:  OK  T05 - Stock : ..."
    /OK  T[0-9][0-9] - / {
        sub(/.*OK  /, "")
        print "  [OK]     " $0
        next
    }
    # Test en echec (ou erreur imprevue) :
    # "psql:08_tests.sql:250: ERROR:  ECHEC T05 : ..."
    /(ERROR|ERREUR) ?:/ {
        ligne = ""
        if (match($0, /sql:[0-9]+:/)) ligne = substr($0, RSTART + 4, RLENGTH - 5)
        sub(/.*(ERROR|ERREUR) ?: +/, "")
        sub(/^ECHEC /, "")
        print "  [ECHEC]  " $0 "   (ligne " ligne " de 08_tests.sql)"
        next
    }
    # Messages d information du script (donnees de test, fin)
    /(---|===) / {
        sub(/.*NOTICE: +/, "")
        print "  " $0
        next
    }
    # Le reste (messages de avancer_commande, etc.) reste dans le journal
'
CODE_PSQL=${PIPESTATUS[0]}

unset PGPASSWORD

# --- Bilan --------------------------------------------------------
NB_OK=$(grep -c "OK  T[0-9][0-9] - " "$JOURNAL")
NB_ECHEC=$(grep -cE "(ERROR|ERREUR) ?:" "$JOURNAL")

echo
echo "============================================="
if [ "$CODE_PSQL" -ne 0 ] && [ "$NB_OK" -eq 0 ] && [ "$NB_ECHEC" -eq 0 ]; then
    # psql n'a meme pas pu se connecter
    echo " ECHEC : impossible d'executer les tests."
    echo "============================================="
    echo
    cat "$JOURNAL"
    echo
    echo "Verifiez la connexion, et que creer_bd.command a bien ete execute."
elif [ "$NB_OK" -eq "$NB_TOTAL" ] && [ "$NB_ECHEC" -eq 0 ]; then
    echo " TOUS LES TESTS ONT REUSSI ($NB_OK/$NB_TOTAL)"
    echo "============================================="
    rm -f "$JOURNAL"
else
    echo " $NB_OK/$NB_TOTAL test(s) reussi(s), $NB_ECHEC echec(s)"
    echo "============================================="
    echo
    echo "Journal complet : $JOURNAL"
    echo "Attention : les tests s'enchainent (ex. T05 prepare T14). Un echec"
    echo "peut en provoquer d'autres : corriger d'abord le PREMIER echec."
fi
echo
read -r -p "Appuyez sur Entree pour fermer..."
