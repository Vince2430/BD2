"""
config_bd.py — paramètres de connexion partagés par les scripts
de création, d'insertion et d'export.

AUCUN mot de passe n'est écrit ici. Les valeurs viennent :
  1. des variables d'environnement du système, si elles existent ;
  2. sinon du fichier .env situé dans Remise_Atelier1/ (voir
     .env.example), qui n'est PAS remis et qui est ignoré par git.

Utilisation dans un script placé dans ce même dossier :

    import config_bd
    conn = psycopg2.connect(**config_bd.PARAMS_SQL)
"""

import os
from pathlib import Path

try:
    from dotenv import load_dotenv
except ImportError:  # python-dotenv non installé
    load_dotenv = None


# ------------------------------------------------------------
# Trouver et charger le .env (ce dossier, puis les parents)
# ------------------------------------------------------------
def _charger_env() -> Path | None:
    dossier = Path(__file__).resolve().parent
    for candidat in [dossier, *dossier.parents][:5]:
        fichier = candidat / ".env"
        if fichier.is_file():
            if load_dotenv is not None:
                # override=False : une vraie variable d'environnement
                # a toujours priorité sur le fichier.
                load_dotenv(fichier, override=False)
            else:
                # Repli minimal si python-dotenv n'est pas installé.
                for ligne in fichier.read_text(encoding="utf-8").splitlines():
                    ligne = ligne.strip()
                    if not ligne or ligne.startswith("#") or "=" not in ligne:
                        continue
                    cle, valeur = ligne.split("=", 1)
                    os.environ.setdefault(cle.strip(), valeur.strip().strip("\"'"))
            return fichier
    return None


FICHIER_ENV = _charger_env()


# ------------------------------------------------------------
# Lecture des variables
# ------------------------------------------------------------
# Pas de valeur par défaut pour le mot de passe : on veut un message
# clair plutôt qu'une connexion qui échoue sans explication.
def _lire(nom: str, defaut: str | None = None) -> str:
    valeur = os.getenv(nom, defaut)
    if not valeur:
        raise RuntimeError(
            f"La variable {nom} n'est pas definie.\n"
            f"Copie Remise_Atelier1/.env.example en .env et remplis-la, "
            f"ou exporte {nom} dans ton terminal."
        )
    return valeur


def _params(nom_variable_base: str, base_par_defaut: str) -> dict:
    return {
        "host": _lire("PGHOST", "localhost"),
        "port": int(_lire("PGPORT", "5432")),
        "user": _lire("PGUSER", "postgres"),
        "password": _lire("PGPASSWORD"),
        "dbname": _lire(nom_variable_base, base_par_defaut),
    }


def params_sql() -> dict:
    """Connexion à la base relationnelle."""
    return _params("PGDATABASE_SQL", "atelier_bibliotheque_sql")


def params_jsonb() -> dict:
    """Connexion à la base documentaire JSONB."""
    return _params("PGDATABASE_JSONB", "atelier1_bibliotheque_jsonb")


# Raccourcis pratiques (évalués à l'import : une variable manquante
# se signale immédiatement, avant toute tentative de connexion).
PARAMS_SQL = params_sql()
PARAMS_JSONB = params_jsonb()


def source() -> str:
    """Message informatif — n'affiche jamais le mot de passe."""
    if FICHIER_ENV is not None:
        return f"configuration lue dans {FICHIER_ENV}"
    return "configuration lue dans les variables d'environnement"
