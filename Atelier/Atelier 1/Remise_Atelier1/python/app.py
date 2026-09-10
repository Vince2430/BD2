"""
app.py — application console Python (partie 4 de l'atelier).

Menu :
    1. Afficher la liste des livres            (base relationnelle)
    2. Rechercher un livre ou un auteur        (base relationnelle)
    3. Afficher l'information équivalente      (base JSONB)
    4. Ajouter un livre / modifier un titre    (requêtes paramétrées)
    0. Quitter

Lancement :
    python app.py
"""

import sys

import psycopg

import bibliotheque as bd
import config


# ============================================================
# Petits utilitaires d'affichage
# ============================================================

def demander(question: str) -> str:
    """Lit une saisie utilisateur et enlève les espaces autour."""
    return input(question).strip()


def afficher_tableau(entetes: list[str], lignes: list[tuple]) -> None:
    """Affiche des lignes de résultat sous forme de tableau aligné."""
    if not lignes:
        print("  (aucun résultat)")
        return

    colonnes = [[str(v) if v is not None else "" for v in ligne] for ligne in lignes]
    largeurs = [
        max(len(entetes[i]), max(len(c[i]) for c in colonnes))
        for i in range(len(entetes))
    ]

    ligne_entete = "  ".join(e.ljust(largeurs[i]) for i, e in enumerate(entetes))
    print("  " + ligne_entete)
    print("  " + "  ".join("-" * l for l in largeurs))
    for c in colonnes:
        print("  " + "  ".join(c[i].ljust(largeurs[i]) for i in range(len(entetes))))
    print(f"\n  {len(lignes)} ligne(s).")


# ============================================================
# Les 4 opérations du menu
# ============================================================

def operation_lister_livres(conn_sql: psycopg.Connection) -> None:
    """1. Liste des livres de la base relationnelle."""
    print("\n--- Liste des livres (base relationnelle) ---")
    livres = bd.lister_livres(conn_sql, limite=20)
    afficher_tableau(["ID", "TITRE", "AUTEUR"], livres)
    print(f"  (20 premiers sur {bd.compter_livres(conn_sql)} livres au total)")


def operation_rechercher(conn_sql: psycopg.Connection) -> None:
    """2. Recherche d'un livre ou d'un auteur à partir d'une saisie."""
    terme = demander("\nTitre ou auteur à chercher : ")
    if not terme:
        print("  Recherche annulée (rien de saisi).")
        return

    print(f"\n--- Résultats pour « {terme} » (base relationnelle) ---")
    resultats = bd.rechercher_livre_ou_auteur(conn_sql, terme)
    afficher_tableau(
        ["ID", "TITRE", "AUTEUR", "EMPRUNTS", "EN COURS"],
        resultats,
    )


def operation_jsonb(conn_jsonb: psycopg.Connection) -> None:
    """3. La même information, mais lue dans la base documentaire."""
    terme = demander("\nTitre ou auteur à chercher dans la base JSONB : ")
    if not terme:
        print("  Recherche annulée (rien de saisi).")
        return

    print(f"\n--- Documents 'livre' correspondant à « {terme} » ---")
    print("    (opérateurs ->, ->> et #>> sur la colonne JSONB)")
    documents = bd.rechercher_documents_livre(conn_jsonb, terme)
    afficher_tableau(["ID DOC", "TITRE", "AUTEUR", "NB EMPRUNTS"], documents)

    # Deuxième requête : recherche par contenance (@>), celle qui peut
    # utiliser l'index GIN. Elle exige le nom exact de l'auteur.
    print(f"\n--- Recherche par contenance @> sur l'auteur exact « {terme} » ---")
    exacts = bd.rechercher_documents_par_auteur_exact(conn_jsonb, terme)
    afficher_tableau(["ID DOC", "TITRE"], exacts)
    if not exacts:
        print("  (normal si « {0} » n'est pas le nom complet d'un auteur :".format(terme))
        print("   @> compare la valeur exacte, contrairement à ILIKE)")

    # Troisième requête : recherche à l'intérieur d'un TABLEAU JSON.
    if documents:
        titre_exact = documents[0][1]
        print(f"\n--- Membres ayant « {titre_exact} » dans leur tableau emprunts_actifs ---")
        membres = bd.membres_ayant_le_livre_en_cours(conn_jsonb, titre_exact)
        afficher_tableau(["MEMBRE"], membres)


def operation_ajouter_ou_modifier(
    conn_sql: psycopg.Connection, conn_jsonb: psycopg.Connection
) -> None:
    """4. Ajout ou modification, toujours en requêtes paramétrées."""
    print("\n  a) Ajouter un livre")
    print("  b) Modifier le titre d'un livre")
    choix = demander("  Choix : ").lower()

    if choix == "a":
        titre = demander("  Titre du nouveau livre : ")
        auteur = demander("  Nom de l'auteur : ")
        if not titre or not auteur:
            print("  Ajout annulé : le titre et l'auteur sont obligatoires.")
            return

        id_livre = bd.ajouter_livre(conn_sql, titre, auteur)
        print(f"  Livre ajouté dans la base relationnelle (id_livre = {id_livre}).")

        id_document = bd.ajouter_document_livre(conn_jsonb, titre, auteur)
        print(f"  Document ajouté dans la base JSONB (id = {id_document}).")

    elif choix == "b":
        saisie = demander("  id_livre à modifier : ")
        if not saisie.isdigit():
            print("  Modification annulée : l'id doit être un nombre entier.")
            return
        nouveau_titre = demander("  Nouveau titre : ")
        if not nouveau_titre:
            print("  Modification annulée : le nouveau titre est vide.")
            return

        ancien_titre = bd.modifier_titre_livre(conn_sql, int(saisie), nouveau_titre)
        if ancien_titre is None:
            print(f"  Aucun livre avec l'id {saisie}.")
            return
        print(f"  Base relationnelle : « {ancien_titre} » -> « {nouveau_titre} ».")

        nb = bd.modifier_titre_document(conn_jsonb, ancien_titre, nouveau_titre)
        print(f"  Base JSONB : {nb} document(s) mis à jour avec jsonb_set.")

    else:
        print("  Choix invalide.")


# ============================================================
# Boucle principale
# ============================================================

MENU = """
============================================================
  Bibliothèque — application Python (psycopg)
============================================================
  1. Afficher la liste des livres          (relationnel)
  2. Rechercher un livre ou un auteur      (relationnel)
  3. Chercher la même information          (JSONB)
  4. Ajouter un livre / modifier un titre  (paramétré)
  0. Quitter
------------------------------------------------------------"""


def main() -> int:
    print(f"Démarrage — {config.source_configuration()}")

    conn_sql = None
    conn_jsonb = None

    # ------------------------------------------------------------
    # Connexion : on distingue bien les erreurs de CONFIGURATION
    # (variable manquante) des erreurs de CONNEXION (serveur
    # éteint, mauvais mot de passe, base inexistante).
    # ------------------------------------------------------------
    try:
        conn_sql = bd.ouvrir_connexion_sql()
        conn_jsonb = bd.ouvrir_connexion_jsonb()
        print("Connexion réussie aux deux bases.")
    except RuntimeError as erreur:
        print(f"\nERREUR DE CONFIGURATION : {erreur}")
        return 1
    except psycopg.OperationalError as erreur:
        print("\nERREUR DE CONNEXION à PostgreSQL.")
        print("Vérifie que le serveur est démarré, puis les valeurs de")
        print("PGHOST / PGPORT / PGUSER / PGPASSWORD / PGDATABASE_*.")
        print(f"Détail : {str(erreur).strip()}")
        if conn_sql is not None:
            conn_sql.close()
        return 1

    # ------------------------------------------------------------
    # Menu. try/finally garantit que les connexions sont fermées,
    # même en cas d'erreur ou de Ctrl+C.
    # ------------------------------------------------------------
    try:
        while True:
            print(MENU)
            choix = demander("Ton choix : ")

            try:
                if choix == "1":
                    operation_lister_livres(conn_sql)
                elif choix == "2":
                    operation_rechercher(conn_sql)
                elif choix == "3":
                    operation_jsonb(conn_jsonb)
                elif choix == "4":
                    operation_ajouter_ou_modifier(conn_sql, conn_jsonb)
                elif choix == "0":
                    print("Au revoir.")
                    break
                else:
                    print("  Choix invalide.")

            # Une requête ratée ne doit pas faire planter l'application :
            # on affiche un message clair et on revient au menu.
            except psycopg.errors.UniqueViolation:
                print("  ERREUR : ce livre existe déjà pour cet auteur")
                print("  (contrainte UNIQUE uq_livre_titre_auteur).")
            except psycopg.errors.CheckViolation as erreur:
                print(f"  ERREUR : une contrainte CHECK refuse cette valeur ({erreur.diag.constraint_name}).")
            except psycopg.Error as erreur:
                print(f"  ERREUR SQL : {str(erreur).strip()}")

    except (KeyboardInterrupt, EOFError):
        print("\nInterrompu par l'utilisateur.")
    finally:
        # Fermeture propre des deux connexions, quoi qu'il arrive.
        for nom, connexion in (("relationnelle", conn_sql), ("JSONB", conn_jsonb)):
            if connexion is not None and not connexion.closed:
                connexion.close()
                print(f"Connexion {nom} fermée.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
