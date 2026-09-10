"""
bibliotheque.py — toutes les fonctions qui parlent à PostgreSQL.

Deux règles suivies partout dans ce fichier :

1. La connexion et les requêtes sont isolées dans des fonctions
   (aucune requête n'est écrite directement dans le menu).
2. Toute valeur qui vient de l'utilisateur passe par un PARAMÈTRE
   (%s), jamais par une concaténation de chaînes. C'est ce qui
   empêche les injections SQL : psycopg envoie la requête et les
   valeurs séparément au serveur, donc une valeur ne peut jamais
   être interprétée comme du code SQL.
"""

import psycopg

import config


# ============================================================
# CONNEXIONS
# ============================================================

def ouvrir_connexion_sql() -> psycopg.Connection:
    """Ouvre une connexion à la base relationnelle."""
    return psycopg.connect(**config.parametres_sql())


def ouvrir_connexion_jsonb() -> psycopg.Connection:
    """Ouvre une connexion à la base documentaire JSONB."""
    return psycopg.connect(**config.parametres_jsonb())


# ============================================================
# OPÉRATION 1 — Lister les livres (base relationnelle)
# ============================================================

def lister_livres(conn: psycopg.Connection, limite: int = 20) -> list[tuple]:
    """Retourne les `limite` premiers livres avec le nom de leur auteur.

    Jointure livre -> auteur par la clé étrangère id_auteur.
    `limite` est aussi passée en paramètre, même si elle ne vient pas
    directement d'une saisie libre.
    """
    requete = """
        SELECT l.id_livre,
               l.nom       AS titre,
               a.nom       AS auteur
        FROM livre  l
        JOIN auteur a ON a.id_auteur = l.id_auteur
        ORDER BY l.nom
        LIMIT %s;
    """
    with conn.cursor() as cur:
        cur.execute(requete, (limite,))
        return cur.fetchall()


def compter_livres(conn: psycopg.Connection) -> int:
    """Nombre total de livres, pour afficher « X sur Y »."""
    with conn.cursor() as cur:
        cur.execute("SELECT count(*) FROM livre;")
        return cur.fetchone()[0]


# ============================================================
# OPÉRATION 2 — Rechercher un livre OU un auteur (relationnel)
# ============================================================

def rechercher_livre_ou_auteur(conn: psycopg.Connection, terme: str) -> list[tuple]:
    """Cherche le terme saisi dans le titre du livre ET dans le nom de l'auteur.

    ILIKE = LIKE insensible à la casse.
    Le terme est encadré de % ICI, en Python, puis envoyé comme
    PARAMÈTRE : on ne construit jamais la requête par concaténation.
    """
    requete = """
        SELECT l.id_livre,
               l.nom  AS titre,
               a.nom  AS auteur,
               count(e.id_emprunt)                                   AS nb_emprunts,
               count(e.id_emprunt) FILTER (WHERE e.date_retour IS NULL) AS nb_actifs
        FROM livre  l
        JOIN auteur a ON a.id_auteur = l.id_auteur
        LEFT JOIN emprunt e ON e.id_livre = l.id_livre
        WHERE l.nom ILIKE %s
           OR a.nom ILIKE %s
        GROUP BY l.id_livre, l.nom, a.nom
        ORDER BY l.nom;
    """
    motif = f"%{terme}%"
    with conn.cursor() as cur:
        cur.execute(requete, (motif, motif))
        return cur.fetchall()


# ============================================================
# OPÉRATION 3 — La même information, mais dans la base JSONB
# ============================================================

def rechercher_documents_livre(conn: psycopg.Connection, terme: str) -> list[tuple]:
    """Équivalent JSONB de la recherche ci-dessus.

    Ici il n'y a pas de jointure : l'auteur est IMBRIQUÉ dans le
    document du livre, et les emprunts sont un TABLEAU imbriqué.
      - donnees ->> 'titre'            : texte de la propriété titre
      - donnees -> 'auteur' ->> 'nom'  : on descend d'un niveau puis on lit le texte
      - jsonb_array_length(...)        : longueur du tableau imbriqué
    """
    requete = """
        SELECT d.id,
               d.donnees ->> 'titre'                       AS titre,
               d.donnees -> 'auteur' ->> 'nom'             AS auteur,
               jsonb_array_length(d.donnees -> 'emprunts') AS nb_emprunts
        FROM document d
        WHERE d.type_document = 'livre'
          AND (d.donnees ->> 'titre' ILIKE %s
               OR d.donnees #>> '{auteur,nom}' ILIKE %s)
        ORDER BY d.donnees ->> 'titre';
    """
    motif = f"%{terme}%"
    with conn.cursor() as cur:
        cur.execute(requete, (motif, motif))
        return cur.fetchall()


def rechercher_documents_par_auteur_exact(conn: psycopg.Connection, auteur: str) -> list[tuple]:
    """Recherche par CONTENANCE avec @> : « le document contient-il
    cet objet-là ? ».

    C'est cette forme (et non ILIKE) qui peut utiliser l'index GIN
    créé sur la colonne donnees. En contrepartie, @> exige une
    correspondance exacte : « Camus » ne trouvera rien, il faut
    « Albert Camus ».
    """
    requete = """
        SELECT d.id,
               d.donnees ->> 'titre' AS titre
        FROM document d
        WHERE d.donnees @> jsonb_build_object(
                  'auteur', jsonb_build_object('nom', %s::text)
              )
        ORDER BY d.donnees ->> 'titre';
    """
    with conn.cursor() as cur:
        cur.execute(requete, (auteur,))
        return cur.fetchall()


def membres_ayant_le_livre_en_cours(conn: psycopg.Connection, titre: str) -> list[tuple]:
    """Recherche DANS UN TABLEAU JSON : quels membres ont ce titre
    dans leur tableau `emprunts_actifs` ?

    `@>` fonctionne aussi sur les tableaux : on demande si le tableau
    emprunts_actifs contient un objet ayant ce titre_livre.
    """
    requete = """
        SELECT d.donnees ->> 'nom' AS nom_membre
        FROM document d
        WHERE d.type_document = 'membre'
          AND d.donnees -> 'emprunts_actifs' @> jsonb_build_array(
                  jsonb_build_object('titre_livre', %s::text)
              )
        ORDER BY d.donnees ->> 'nom';
    """
    with conn.cursor() as cur:
        cur.execute(requete, (titre,))
        return cur.fetchall()


# ============================================================
# OPÉRATION 4a — Ajouter un livre (requêtes paramétrées)
# ============================================================

def trouver_ou_creer_auteur(conn: psycopg.Connection, nom_auteur: str) -> int:
    """Retourne l'id de l'auteur, en le créant s'il n'existe pas encore.

    Ne fait PAS de commit : c'est l'appelant qui décide, pour que
    l'auteur et le livre soient ajoutés dans la même transaction.
    """
    with conn.cursor() as cur:
        cur.execute(
            "SELECT id_auteur FROM auteur WHERE nom = %s;",
            (nom_auteur,),
        )
        ligne = cur.fetchone()
        if ligne is not None:
            return ligne[0]

        cur.execute(
            "INSERT INTO auteur (nom) VALUES (%s) RETURNING id_auteur;",
            (nom_auteur,),
        )
        return cur.fetchone()[0]


def ajouter_livre(conn: psycopg.Connection, titre: str, nom_auteur: str) -> int:
    """Ajoute un livre et retourne son id.

    Tout se fait dans UNE transaction : si l'INSERT du livre échoue
    (par exemple à cause de la contrainte UNIQUE (nom, id_auteur)),
    l'auteur créé juste avant est annulé lui aussi.
    """
    try:
        id_auteur = trouver_ou_creer_auteur(conn, nom_auteur)
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO livre (nom, id_auteur) VALUES (%s, %s) RETURNING id_livre;",
                (titre, id_auteur),
            )
            id_livre = cur.fetchone()[0]
        conn.commit()
        return id_livre
    except psycopg.Error:
        conn.rollback()   # on ne laisse jamais la transaction à moitié faite
        raise


def ajouter_document_livre(conn: psycopg.Connection, titre: str, nom_auteur: str) -> int:
    """Ajoute le MÊME livre dans la base JSONB, pour que les deux
    bases restent équivalentes.

    Le document est construit côté serveur avec jsonb_build_object :
    le titre et le nom de l'auteur restent des paramètres, ils ne
    sont jamais collés dans le texte de la requête.
    """
    requete = """
        INSERT INTO document (type_document, donnees)
        VALUES (
            'livre',
            jsonb_build_object(
                'titre',  %s::text,
                'auteur', jsonb_build_object('nom', %s::text),
                'emprunts', '[]'::jsonb
            )
        )
        RETURNING id;
    """
    try:
        with conn.cursor() as cur:
            cur.execute(requete, (titre, nom_auteur))
            id_document = cur.fetchone()[0]
        conn.commit()
        return id_document
    except psycopg.Error:
        conn.rollback()
        raise


# ============================================================
# OPÉRATION 4b — Modifier le titre d'un livre
# ============================================================

def modifier_titre_livre(conn: psycopg.Connection, id_livre: int, nouveau_titre: str) -> str | None:
    """Renomme un livre dans la base relationnelle.

    On lit d'abord l'ancien titre : ça permet de savoir si l'id existe
    vraiment (None = id introuvable) et de retrouver ensuite le
    document correspondant dans la base JSONB.
    Retourne l'ancien titre, ou None si le livre n'existe pas.
    """
    try:
        with conn.cursor() as cur:
            # On lit l'ancien titre AVANT la mise à jour.
            cur.execute("SELECT nom FROM livre WHERE id_livre = %s;", (id_livre,))
            ligne = cur.fetchone()
            if ligne is None:
                return None
            ancien_titre = ligne[0]

            cur.execute(
                "UPDATE livre SET nom = %s WHERE id_livre = %s;",
                (nouveau_titre, id_livre),
            )
        conn.commit()
        return ancien_titre
    except psycopg.Error:
        conn.rollback()
        raise


def modifier_titre_document(conn: psycopg.Connection, ancien_titre: str, nouveau_titre: str) -> int:
    """Met à jour le même titre dans la base JSONB avec jsonb_set.

    jsonb_set(donnees, '{titre}', to_jsonb(...)) remplace UNE propriété
    à l'intérieur du document sans réécrire tout le JSON à la main.
    to_jsonb(%s::text) transforme la chaîne en valeur JSON correctement
    échappée — encore une fois sans concaténation.
    """
    requete = """
        UPDATE document
        SET donnees = jsonb_set(donnees, '{titre}', to_jsonb(%s::text), false)
        WHERE type_document = 'livre'
          AND donnees ->> 'titre' = %s;
    """
    try:
        with conn.cursor() as cur:
            cur.execute(requete, (nouveau_titre, ancien_titre))
            nb_lignes = cur.rowcount
        conn.commit()
        return nb_lignes
    except psycopg.Error:
        conn.rollback()
        raise
