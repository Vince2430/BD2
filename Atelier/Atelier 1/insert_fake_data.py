"""
insert_fake_data.py

Insert fake/random data into the bibliotheque database:
    auteur -> livre -> membre -> emprunt

Respects foreign key dependencies:
    - livre.id_auteur   references auteur.id_auteur
    - emprunt.id_livre  references livre.id_livre
    - emprunt.id_membre references membre.id_membre

Requirements:
    pip install psycopg2-binary faker

Usage:
    python insert_fake_data.py
"""

import random
from datetime import timedelta

import psycopg2
from psycopg2.extras import execute_values
from faker import Faker

fake = Faker("fr_FR")  # French names/locale — change if you prefer another

# ─────────────────────────────────────────────────────────────
# CONFIG — edit connection info and row counts here
# ─────────────────────────────────────────────────────────────

DB_CONFIG = {
    "host": "localhost",
    "port": 5432,
    "dbname": "atelier_bibliotheque_sql",
    "user": "postgres",
    "password": "Gu3pard1",
}

NUM_AUTEURS = 20
NUM_LIVRES = 50
NUM_MEMBRES = 30
NUM_EMPRUNTS = 80

# Fraction of emprunts that already have a date_retour (returned books)
FRACTION_RETURNED = 0.6

# ─────────────────────────────────────────────────────────────
# SCRIPT LOGIC
# ─────────────────────────────────────────────────────────────


def insert_auteurs(conn, n: int) -> list[int]:
    """Insert n auteurs, return their generated id_auteur values."""
    rows = [(fake.name(),) for _ in range(n)]
    with conn.cursor() as cur:
        query = "INSERT INTO auteur (nom) VALUES %s RETURNING id_auteur"
        ids = execute_values(cur, query, rows, fetch=True)
    conn.commit()
    return [row[0] for row in ids]


def insert_livres(conn, n: int, auteur_ids: list[int]) -> list[int]:
    """Insert n livres, each linked to a random existing auteur."""
    rows = [
        (fake.sentence(nb_words=4).rstrip("."), random.choice(auteur_ids))
        for _ in range(n)
    ]
    with conn.cursor() as cur:
        query = "INSERT INTO livre (nom, id_auteur) VALUES %s RETURNING id_livre"
        ids = execute_values(cur, query, rows, fetch=True)
    conn.commit()
    return [row[0] for row in ids]


def insert_membres(conn, n: int) -> list[int]:
    """Insert n membres, return their generated id_membre values."""
    rows = [(fake.name(),) for _ in range(n)]
    with conn.cursor() as cur:
        query = "INSERT INTO membre (nom) VALUES %s RETURNING id_membre"
        ids = execute_values(cur, query, rows, fetch=True)
    conn.commit()
    return [row[0] for row in ids]


def insert_emprunts(
    conn, n: int, livre_ids: list[int], membre_ids: list[int], fraction_returned: float
) -> None:
    """Insert n emprunts, each linked to a random livre and membre."""
    rows = []
    for _ in range(n):
        id_livre = random.choice(livre_ids)
        id_membre = random.choice(membre_ids)
        date_emprunt = fake.date_between(start_date="-1y", end_date="today")

        date_retour = None
        if random.random() < fraction_returned:
            date_retour = date_emprunt + timedelta(days=random.randint(1, 30))

        rows.append((id_livre, id_membre, date_emprunt, date_retour))

    with conn.cursor() as cur:
        query = (
            "INSERT INTO emprunt (id_livre, id_membre, date_emprunt, date_retour) "
            "VALUES %s"
        )
        execute_values(cur, query, rows)
    conn.commit()


def main():
    print(f"Connecting to database '{DB_CONFIG['dbname']}'...")
    conn = psycopg2.connect(**DB_CONFIG)

    try:
        print(f"Inserting {NUM_AUTEURS} auteurs...")
        auteur_ids = insert_auteurs(conn, NUM_AUTEURS)

        print(f"Inserting {NUM_LIVRES} livres...")
        livre_ids = insert_livres(conn, NUM_LIVRES, auteur_ids)

        print(f"Inserting {NUM_MEMBRES} membres...")
        membre_ids = insert_membres(conn, NUM_MEMBRES)

        print(f"Inserting {NUM_EMPRUNTS} emprunts...")
        insert_emprunts(conn, NUM_EMPRUNTS, livre_ids, membre_ids, FRACTION_RETURNED)

        print("Done. Inserted:")
        print(f"  {len(auteur_ids)} auteurs")
        print(f"  {len(livre_ids)} livres")
        print(f"  {len(membre_ids)} membres")
        print(f"  {NUM_EMPRUNTS} emprunts")

    except Exception as e:
        conn.rollback()
        print(f"Error occurred, rolled back transaction: {e}")
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
