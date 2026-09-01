"""
Script pour générer et insérer plusieurs documents 'emprunt' d'un coup
dans la table document (JSONB).

Installation requise :
    pip install psycopg2-binary
"""

import psycopg2
import json
import random
import itertools
from datetime import date, timedelta

# ============================================================
# Paramètres de connexion — à adapter selon ta base
# ============================================================
CONNEXION = {
    "host": "localhost",
    "dbname": "atelier1_bibliotheque_jsonb",
    "user": "postgres",
    "password": "Gu3pard1",
    "port": 5432,
}

NB_A_INSERER = 800000  # <-- change ce nombre selon combien de documents tu veux générer

# ============================================================
# LIVRES : une vraie liste de 25 titres/auteurs pour varier
# les données (au lieu de toujours répéter les 5 mêmes)
# ============================================================
LIVRES = [
    {"id_livre": 1,  "titre": "Le Petit Prince",                       "auteur": {"id_auteur": 1,  "nom": "Antoine de Saint-Exupéry"}},
    {"id_livre": 2,  "titre": "1984",                                  "auteur": {"id_auteur": 2,  "nom": "George Orwell"}},
    {"id_livre": 3,  "titre": "L'Étranger",                            "auteur": {"id_auteur": 3,  "nom": "Albert Camus"}},
    {"id_livre": 4,  "titre": "La Peste",                              "auteur": {"id_auteur": 3,  "nom": "Albert Camus"}},
    {"id_livre": 5,  "titre": "Harry Potter à l'école des sorciers",   "auteur": {"id_auteur": 4,  "nom": "J.K. Rowling"}},
    {"id_livre": 6,  "titre": "Le Seigneur des anneaux",               "auteur": {"id_auteur": 5,  "nom": "J.R.R. Tolkien"}},
    {"id_livre": 7,  "titre": "Les Misérables",                        "auteur": {"id_auteur": 6,  "nom": "Victor Hugo"}},
    {"id_livre": 8,  "titre": "Notre-Dame de Paris",                   "auteur": {"id_auteur": 6,  "nom": "Victor Hugo"}},
    {"id_livre": 9,  "titre": "Le Comte de Monte-Cristo",              "auteur": {"id_auteur": 7,  "nom": "Alexandre Dumas"}},
    {"id_livre": 10, "titre": "Les Trois Mousquetaires",               "auteur": {"id_auteur": 7,  "nom": "Alexandre Dumas"}},
    {"id_livre": 11, "titre": "Vingt mille lieues sous les mers",      "auteur": {"id_auteur": 8,  "nom": "Jules Verne"}},
    {"id_livre": 12, "titre": "Germinal",                              "auteur": {"id_auteur": 9,  "nom": "Émile Zola"}},
    {"id_livre": 13, "titre": "Le Rouge et le Noir",                   "auteur": {"id_auteur": 10, "nom": "Stendhal"}},
    {"id_livre": 14, "titre": "Madame Bovary",                         "auteur": {"id_auteur": 11, "nom": "Gustave Flaubert"}},
    {"id_livre": 15, "titre": "Bel-Ami",                                "auteur": {"id_auteur": 12, "nom": "Guy de Maupassant"}},
    {"id_livre": 16, "titre": "Candide",                                "auteur": {"id_auteur": 13, "nom": "Voltaire"}},
    {"id_livre": 17, "titre": "Fahrenheit 451",                        "auteur": {"id_auteur": 14, "nom": "Ray Bradbury"}},
    {"id_livre": 18, "titre": "Le Meilleur des mondes",                "auteur": {"id_auteur": 15, "nom": "Aldous Huxley"}},
    {"id_livre": 19, "titre": "Dune",                                   "auteur": {"id_auteur": 16, "nom": "Frank Herbert"}},
    {"id_livre": 20, "titre": "L'Alchimiste",                          "auteur": {"id_auteur": 17, "nom": "Paulo Coelho"}},
    {"id_livre": 21, "titre": "Crime et Châtiment",                    "auteur": {"id_auteur": 18, "nom": "Fiodor Dostoïevski"}},
    {"id_livre": 22, "titre": "Da Vinci Code",                          "auteur": {"id_auteur": 19, "nom": "Dan Brown"}},
    {"id_livre": 23, "titre": "Le Nom de la rose",                     "auteur": {"id_auteur": 20, "nom": "Umberto Eco"}},
    {"id_livre": 24, "titre": "Ready Player One",                      "auteur": {"id_auteur": 21, "nom": "Ernest Cline"}},
    {"id_livre": 25, "titre": "La Servante écarlate",                  "auteur": {"id_auteur": 22, "nom": "Margaret Atwood"}},
]

# ============================================================
# MEMBRES : générés en combinant prénoms x noms de famille,
# pour obtenir des dizaines de membres uniques sans avoir à
# tous les taper à la main
# ============================================================
PRENOMS = [
    "Julie", "Marc", "Sophie", "David", "Amélie", "Simon", "Camille", "Alexandre",
    "Émilie", "Nicolas", "Isabelle", "Mathieu", "Catherine", "François", "Valérie",
    "Étienne", "Geneviève", "Philippe", "Nathalie", "Sébastien",
]

NOMS_FAMILLE = [
    "Bouchard", "Gagnon", "Lavoie", "Roy", "Côté", "Tremblay", "Gauthier", "Morin",
    "Fortin", "Bergeron", "Lévesque", "Pelletier", "Bélanger", "Paquette", "Girard",
    "Simard", "Boucher", "Caron", "Beaulieu", "Cloutier",
]

NB_MEMBRES = 50  # nombre de membres uniques à générer


def generer_membres(nb):
    """Génère `nb` membres uniques en combinant aléatoirement des
    prénoms et des noms de famille (sans répétition de la même paire)."""
    toutes_les_combinaisons = list(itertools.product(PRENOMS, NOMS_FAMILLE))
    combinaisons_choisies = random.sample(toutes_les_combinaisons, nb)
    return [
        {"id_membre": i, "nom": f"{prenom} {nom}"}
        for i, (prenom, nom) in enumerate(combinaisons_choisies, start=1)
    ]


MEMBRES = generer_membres(NB_MEMBRES)


def generer_emprunt():
    """Construit un seul document 'emprunt' aléatoire, cohérent avec
    la structure qu'on a définie (livre + auteur imbriqués, membre imbriqué)."""
    livre = random.choice(LIVRES)
    membre = random.choice(MEMBRES)

    date_emprunt = date.today() - timedelta(days=random.randint(1, 180))

    # 30% de chance que l'emprunt soit encore actif (pas encore retourné)
    if random.random() < 0.3:
        date_retour = None
    else:
        date_retour = date_emprunt + timedelta(days=random.randint(1, 30))

    return {
        "livre": livre,
        "membre": membre,
        "date_emprunt": date_emprunt.isoformat(),
        "date_retour": date_retour.isoformat() if date_retour else None,
    }


def inserer_emprunts(nb):
    """Génère `nb` documents et les insère tous d'un coup dans la table document."""
    conn = psycopg2.connect(**CONNEXION)
    cur = conn.cursor()

    documents = [generer_emprunt() for _ in range(nb)]

    requete = "INSERT INTO document (type_document, donnees) VALUES (%s, %s)"
    valeurs = [("emprunt", json.dumps(doc)) for doc in documents]

    cur.executemany(requete, valeurs)

    conn.commit()
    cur.close()
    conn.close()

    print(f"{nb} documents 'emprunt' insérés avec succès.")
    print(f"({len(LIVRES)} livres et {len(MEMBRES)} membres uniques utilisés pour varier les combinaisons)")


if __name__ == "__main__":
    inserer_emprunts(NB_A_INSERER)
