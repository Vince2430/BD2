"""
config.py — paramètres de connexion aux deux bases.

Aucun mot de passe n'est écrit dans le code : tout vient soit des
variables d'environnement du système, soit d'un fichier .env qui
n'est PAS remis (voir .gitignore et .env.example).

C'est l'exigence « lire les paramètres de connexion dans des
variables d'environnement ou un fichier .env exclu de la remise ».
"""

import os
from pathlib import Path

from dotenv import load_dotenv

# ------------------------------------------------------------
# 1. Charger le fichier .env s'il existe
# ------------------------------------------------------------
# On cherche le .env dans le dossier du script, puis dans les
# dossiers parents (ça permet d'avoir un seul .env partagé entre
# l'application Python et l'application C#).
def _trouver_fichier_env() -> Path | None:
    dossier = Path(__file__).resolve().parent
    for candidat in [dossier, *dossier.parents][:5]:
        fichier = candidat / ".env"
        if fichier.is_file():
            return fichier
    return None


_FICHIER_ENV = _trouver_fichier_env()
if _FICHIER_ENV is not None:
    # override=False : une vraie variable d'environnement du système
    # a toujours priorité sur le fichier .env.
    load_dotenv(_FICHIER_ENV, override=False)


# ------------------------------------------------------------
# 2. Lire les variables (avec des valeurs par défaut sûres)
# ------------------------------------------------------------
# Il n'y a volontairement PAS de valeur par défaut pour le mot de
# passe : si la variable est absente, on veut un message d'erreur
# clair plutôt qu'une connexion qui échoue sans explication.
def _lire(nom: str, defaut: str | None = None) -> str:
    valeur = os.getenv(nom, defaut)
    if valeur is None or valeur == "":
        raise RuntimeError(
            f"La variable d'environnement {nom} n'est pas définie.\n"
            f"Copie .env.example en .env et remplis-la, "
            f"ou exporte {nom} dans ton terminal."
        )
    return valeur


def parametres_sql() -> dict:
    """Paramètres de connexion à la base RELATIONNELLE."""
    return {
        "host": _lire("PGHOST", "localhost"),
        "port": int(_lire("PGPORT", "5432")),
        "user": _lire("PGUSER", "postgres"),
        "password": _lire("PGPASSWORD"),
        "dbname": _lire("PGDATABASE_SQL", "atelier_bibliotheque_sql"),
    }


def parametres_jsonb() -> dict:
    """Paramètres de connexion à la base JSONB.

    Même serveur, même utilisateur : seule la base change.
    """
    parametres = parametres_sql()
    parametres["dbname"] = _lire("PGDATABASE_JSONB", "atelier1_bibliotheque_jsonb")
    return parametres


def source_configuration() -> str:
    """Petit message affiché au démarrage pour savoir d'où vient la config
    (utile quand une connexion échoue). Ne montre jamais le mot de passe."""
    if _FICHIER_ENV is not None:
        return f"configuration lue dans {_FICHIER_ENV}"
    return "configuration lue dans les variables d'environnement"
