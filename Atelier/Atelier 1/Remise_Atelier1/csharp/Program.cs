// ============================================================
// Program.cs — application console C# (partie 3 de l'atelier)
//
// Elle se connecte AUX DEUX bases (relationnelle + JSONB) et offre
// les mêmes opérations que l'application Python :
//
//   1. Afficher la liste des livres           (base relationnelle)
//   2. Rechercher un livre ou un auteur       (base relationnelle)
//   3. Afficher l'information équivalente     (base JSONB)
//   4. Ajouter un livre / modifier un titre   (requêtes paramétrées)
//   0. Quitter
//
// Deux règles suivies partout :
//   - aucun mot de passe dans le code : tout vient des variables
//     d'environnement ou d'un fichier .env exclu de la remise ;
//   - toute valeur saisie par l'utilisateur passe par un PARAMÈTRE
//     (@nom), jamais par une concaténation de chaînes.
//
// Lancement :  dotnet run
// ============================================================

using System.Text;
using Npgsql;

namespace Bibliotheque;

internal static class Program
{
    // ============================================================
    // 1. CONFIGURATION — lecture des paramètres de connexion
    // ============================================================

    /// <summary>
    /// Cherche un fichier .env dans le dossier courant puis dans les
    /// dossiers parents, et charge ses valeurs comme variables
    /// d'environnement du processus.
    ///
    /// Une variable déjà définie dans le système n'est jamais écrasée :
    /// le .env sert de valeur par défaut, pas de source unique.
    /// </summary>
    private static void ChargerFichierEnv()
    {
        DirectoryInfo? dossier = new DirectoryInfo(Directory.GetCurrentDirectory());

        for (int i = 0; i < 6 && dossier != null; i++, dossier = dossier.Parent)
        {
            string chemin = Path.Combine(dossier.FullName, ".env");
            if (!File.Exists(chemin))
            {
                continue;
            }

            foreach (string ligneBrute in File.ReadAllLines(chemin))
            {
                string ligne = ligneBrute.Trim();

                // On ignore les lignes vides et les commentaires
                if (ligne.Length == 0 || ligne.StartsWith('#'))
                {
                    continue;
                }

                int position = ligne.IndexOf('=');
                if (position <= 0)
                {
                    continue;
                }

                string cle = ligne[..position].Trim();
                string valeur = ligne[(position + 1)..].Trim().Trim('"', '\'');

                if (Environment.GetEnvironmentVariable(cle) is null)
                {
                    Environment.SetEnvironmentVariable(cle, valeur);
                }
            }

            Console.WriteLine($"Configuration lue dans {chemin}");
            return;
        }

        Console.WriteLine("Configuration lue dans les variables d'environnement.");
    }

    /// <summary>
    /// Lit une variable d'environnement. Si elle est absente et qu'il n'y a
    /// pas de valeur par défaut, on lève une erreur explicite plutôt que de
    /// laisser la connexion échouer sans explication.
    /// </summary>
    private static string LireVariable(string nom, string? valeurParDefaut = null)
    {
        string? valeur = Environment.GetEnvironmentVariable(nom);

        if (string.IsNullOrWhiteSpace(valeur))
        {
            valeur = valeurParDefaut;
        }

        if (string.IsNullOrWhiteSpace(valeur))
        {
            throw new InvalidOperationException(
                $"La variable d'environnement {nom} n'est pas definie. " +
                "Copie .env.example en .env et remplis-la, ou exporte la variable dans ton terminal.");
        }

        return valeur;
    }

    /// <summary>
    /// Construit la chaîne de connexion. NpgsqlConnectionStringBuilder
    /// échappe correctement les valeurs (un mot de passe contenant un
    /// point-virgule ne casse donc pas la chaîne).
    /// </summary>
    private static string ChaineDeConnexion(string nomVariableBase, string baseParDefaut)
    {
        var constructeur = new NpgsqlConnectionStringBuilder
        {
            Host = LireVariable("PGHOST", "localhost"),
            Port = int.Parse(LireVariable("PGPORT", "5432")),
            Username = LireVariable("PGUSER", "postgres"),
            Password = LireVariable("PGPASSWORD"),
            Database = LireVariable(nomVariableBase, baseParDefaut)
        };

        return constructeur.ConnectionString;
    }

    // ============================================================
    // 2. AFFICHAGE — petits utilitaires
    // ============================================================

    private static string Demander(string question)
    {
        Console.Write(question);
        return (Console.ReadLine() ?? string.Empty).Trim();
    }

    /// <summary>
    /// Lit tout le résultat d'une commande et l'affiche en colonnes alignées.
    /// </summary>
    private static void AfficherResultat(NpgsqlCommand commande, string[] entetes)
    {
        var lignes = new List<string[]>();

        using (NpgsqlDataReader lecteur = commande.ExecuteReader())
        {
            while (lecteur.Read())
            {
                var valeurs = new string[lecteur.FieldCount];
                for (int i = 0; i < lecteur.FieldCount; i++)
                {
                    // IsDBNull : une colonne SQL NULL n'est pas une chaîne vide
                    valeurs[i] = lecteur.IsDBNull(i) ? "" : lecteur.GetValue(i).ToString() ?? "";
                }
                lignes.Add(valeurs);
            }
        }

        if (lignes.Count == 0)
        {
            Console.WriteLine("  (aucun resultat)");
            return;
        }

        var largeurs = new int[entetes.Length];
        for (int i = 0; i < entetes.Length; i++)
        {
            largeurs[i] = entetes[i].Length;
            foreach (string[] ligne in lignes)
            {
                largeurs[i] = Math.Max(largeurs[i], ligne[i].Length);
            }
        }

        Console.WriteLine("  " + string.Join("  ", entetes.Select((e, i) => e.PadRight(largeurs[i]))));
        Console.WriteLine("  " + string.Join("  ", largeurs.Select(l => new string('-', l))));
        foreach (string[] ligne in lignes)
        {
            Console.WriteLine("  " + string.Join("  ", ligne.Select((v, i) => v.PadRight(largeurs[i]))));
        }

        Console.WriteLine($"\n  {lignes.Count} ligne(s).");
    }

    // ============================================================
    // 3. OPÉRATION 1 — Liste des livres (base relationnelle)
    // ============================================================

    private static void ListerLivres(NpgsqlConnection connexionSql)
    {
        const string requete = @"
            SELECT l.id_livre,
                   l.nom  AS titre,
                   a.nom  AS auteur
            FROM livre  l
            JOIN auteur a ON a.id_auteur = l.id_auteur
            ORDER BY l.nom
            LIMIT @limite;";

        Console.WriteLine("\n--- Liste des livres (base relationnelle) ---");

        using (var commande = new NpgsqlCommand(requete, connexionSql))
        {
            commande.Parameters.AddWithValue("limite", 20);
            AfficherResultat(commande, ["ID", "TITRE", "AUTEUR"]);
        }

        using (var compte = new NpgsqlCommand("SELECT count(*) FROM livre;", connexionSql))
        {
            Console.WriteLine($"  (20 premiers sur {compte.ExecuteScalar()} livres au total)");
        }
    }

    // ============================================================
    // 4. OPÉRATION 2 — Rechercher un livre OU un auteur
    // ============================================================

    private static void RechercherLivreOuAuteur(NpgsqlConnection connexionSql)
    {
        string terme = Demander("\nTitre ou auteur a chercher : ");
        if (terme.Length == 0)
        {
            Console.WriteLine("  Recherche annulee (rien de saisi).");
            return;
        }

        // ILIKE = LIKE insensible à la casse.
        // Les % sont ajoutés à la VALEUR, pas à la requête : la saisie
        // reste un paramètre et ne peut pas être interprétée comme du SQL.
        const string requete = @"
            SELECT l.id_livre,
                   l.nom  AS titre,
                   a.nom  AS auteur,
                   count(e.id_emprunt)                                      AS nb_emprunts,
                   count(e.id_emprunt) FILTER (WHERE e.date_retour IS NULL) AS nb_actifs
            FROM livre  l
            JOIN auteur a ON a.id_auteur = l.id_auteur
            LEFT JOIN emprunt e ON e.id_livre = l.id_livre
            WHERE l.nom ILIKE @motif
               OR a.nom ILIKE @motif
            GROUP BY l.id_livre, l.nom, a.nom
            ORDER BY l.nom;";

        Console.WriteLine($"\n--- Resultats pour « {terme} » (base relationnelle) ---");

        using var commande = new NpgsqlCommand(requete, connexionSql);
        commande.Parameters.AddWithValue("motif", $"%{terme}%");
        AfficherResultat(commande, ["ID", "TITRE", "AUTEUR", "EMPRUNTS", "EN COURS"]);
    }

    // ============================================================
    // 5. OPÉRATION 3 — La même information dans la base JSONB
    // ============================================================

    private static void ChercherDansJsonb(NpgsqlConnection connexionJsonb)
    {
        string terme = Demander("\nTitre ou auteur a chercher dans la base JSONB : ");
        if (terme.Length == 0)
        {
            Console.WriteLine("  Recherche annulee (rien de saisi).");
            return;
        }

        // Pas de jointure ici : l'auteur est IMBRIQUÉ dans le document du
        // livre et les emprunts forment un TABLEAU imbriqué.
        //   ->   donne un JSON,  ->>  donne du texte,
        //   #>>  suit un chemin ('{auteur,nom}').
        const string requeteProprietes = @"
            SELECT d.id,
                   d.donnees ->> 'titre'                       AS titre,
                   d.donnees -> 'auteur' ->> 'nom'             AS auteur,
                   jsonb_array_length(d.donnees -> 'emprunts') AS nb_emprunts
            FROM document d
            WHERE d.type_document = 'livre'
              AND (d.donnees ->> 'titre' ILIKE @motif
                   OR d.donnees #>> '{auteur,nom}' ILIKE @motif)
            ORDER BY d.donnees ->> 'titre';";

        Console.WriteLine($"\n--- Documents 'livre' correspondant a « {terme} » ---");
        Console.WriteLine("    (operateurs ->, ->> et #>> sur la colonne JSONB)");

        string? premierTitre = null;

        using (var commande = new NpgsqlCommand(requeteProprietes, connexionJsonb))
        {
            commande.Parameters.AddWithValue("motif", $"%{terme}%");

            // On lit d'abord le premier titre pour la 3e requête,
            // puis on réexécute pour l'affichage en tableau.
            using (NpgsqlDataReader lecteur = commande.ExecuteReader())
            {
                if (lecteur.Read() && !lecteur.IsDBNull(1))
                {
                    premierTitre = lecteur.GetString(1);
                }
            }

            AfficherResultat(commande, ["ID DOC", "TITRE", "AUTEUR", "NB EMPRUNTS"]);
        }

        // Recherche par CONTENANCE (@>) : « le document contient-il cet
        // objet ? ». C'est cette forme qui peut utiliser l'index GIN,
        // mais elle exige la valeur EXACTE (« Albert Camus », pas « Camus »).
        const string requeteContenance = @"
            SELECT d.id,
                   d.donnees ->> 'titre' AS titre
            FROM document d
            WHERE d.donnees @> jsonb_build_object(
                      'auteur', jsonb_build_object('nom', @auteur::text))
            ORDER BY d.donnees ->> 'titre';";

        Console.WriteLine($"\n--- Recherche par contenance @> sur l'auteur exact « {terme} » ---");

        using (var commande = new NpgsqlCommand(requeteContenance, connexionJsonb))
        {
            commande.Parameters.AddWithValue("auteur", terme);
            AfficherResultat(commande, ["ID DOC", "TITRE"]);
        }

        // Recherche DANS UN TABLEAU JSON : quels membres ont ce titre
        // dans leur tableau emprunts_actifs ?
        if (premierTitre is not null)
        {
            const string requeteTableau = @"
                SELECT d.donnees ->> 'nom' AS nom_membre
                FROM document d
                WHERE d.type_document = 'membre'
                  AND d.donnees -> 'emprunts_actifs' @> jsonb_build_array(
                          jsonb_build_object('titre_livre', @titre::text))
                ORDER BY d.donnees ->> 'nom';";

            Console.WriteLine($"\n--- Membres ayant « {premierTitre} » dans emprunts_actifs ---");

            using var commande = new NpgsqlCommand(requeteTableau, connexionJsonb);
            commande.Parameters.AddWithValue("titre", premierTitre);
            AfficherResultat(commande, ["MEMBRE"]);
        }
    }

    // ============================================================
    // 6. OPÉRATION 4 — Ajouter un livre / modifier un titre
    // ============================================================

    private static void AjouterOuModifier(NpgsqlConnection connexionSql, NpgsqlConnection connexionJsonb)
    {
        Console.WriteLine("\n  a) Ajouter un livre");
        Console.WriteLine("  b) Modifier le titre d'un livre");
        string choix = Demander("  Choix : ").ToLowerInvariant();

        if (choix == "a")
        {
            AjouterLivre(connexionSql, connexionJsonb);
        }
        else if (choix == "b")
        {
            ModifierTitre(connexionSql, connexionJsonb);
        }
        else
        {
            Console.WriteLine("  Choix invalide.");
        }
    }

    private static void AjouterLivre(NpgsqlConnection connexionSql, NpgsqlConnection connexionJsonb)
    {
        string titre = Demander("  Titre du nouveau livre : ");
        string auteur = Demander("  Nom de l'auteur : ");

        if (titre.Length == 0 || auteur.Length == 0)
        {
            Console.WriteLine("  Ajout annule : le titre et l'auteur sont obligatoires.");
            return;
        }

        // TRANSACTION : l'auteur (s'il faut le créer) et le livre sont
        // ajoutés ensemble, ou pas du tout. Si l'INSERT du livre viole la
        // contrainte UNIQUE, le Rollback annule aussi l'auteur créé juste avant.
        using NpgsqlTransaction transaction = connexionSql.BeginTransaction();

        try
        {
            int idAuteur;

            using (var recherche = new NpgsqlCommand(
                       "SELECT id_auteur FROM auteur WHERE nom = @nom;", connexionSql, transaction))
            {
                recherche.Parameters.AddWithValue("nom", auteur);
                object? resultat = recherche.ExecuteScalar();

                if (resultat is not null)
                {
                    idAuteur = Convert.ToInt32(resultat);
                }
                else
                {
                    using var insertionAuteur = new NpgsqlCommand(
                        "INSERT INTO auteur (nom) VALUES (@nom) RETURNING id_auteur;",
                        connexionSql, transaction);
                    insertionAuteur.Parameters.AddWithValue("nom", auteur);
                    idAuteur = Convert.ToInt32(insertionAuteur.ExecuteScalar());
                    Console.WriteLine($"  Nouvel auteur cree (id_auteur = {idAuteur}).");
                }
            }

            int idLivre;
            using (var insertionLivre = new NpgsqlCommand(
                       "INSERT INTO livre (nom, id_auteur) VALUES (@titre, @idAuteur) RETURNING id_livre;",
                       connexionSql, transaction))
            {
                insertionLivre.Parameters.AddWithValue("titre", titre);
                insertionLivre.Parameters.AddWithValue("idAuteur", idAuteur);
                idLivre = Convert.ToInt32(insertionLivre.ExecuteScalar());
            }

            transaction.Commit();
            Console.WriteLine($"  Livre ajoute dans la base relationnelle (id_livre = {idLivre}).");
        }
        catch (PostgresException)
        {
            transaction.Rollback();
            throw;   // le message d'erreur est traite par le menu principal
        }

        // Le même livre est ajouté dans la base JSONB, pour que les deux
        // bases continuent de représenter les mêmes données.
        // jsonb_build_object construit le document côté serveur : le titre
        // et l'auteur restent des paramètres.
        const string requeteDocument = @"
            INSERT INTO document (type_document, donnees)
            VALUES (
                'livre',
                jsonb_build_object(
                    'titre',    @titre::text,
                    'auteur',   jsonb_build_object('nom', @auteur::text),
                    'emprunts', '[]'::jsonb))
            RETURNING id;";

        using var insertionDocument = new NpgsqlCommand(requeteDocument, connexionJsonb);
        insertionDocument.Parameters.AddWithValue("titre", titre);
        insertionDocument.Parameters.AddWithValue("auteur", auteur);
        Console.WriteLine($"  Document ajoute dans la base JSONB (id = {insertionDocument.ExecuteScalar()}).");
    }

    private static void ModifierTitre(NpgsqlConnection connexionSql, NpgsqlConnection connexionJsonb)
    {
        string saisie = Demander("  id_livre a modifier : ");
        if (!int.TryParse(saisie, out int idLivre))
        {
            Console.WriteLine("  Modification annulee : l'id doit etre un nombre entier.");
            return;
        }

        string nouveauTitre = Demander("  Nouveau titre : ");
        if (nouveauTitre.Length == 0)
        {
            Console.WriteLine("  Modification annulee : le nouveau titre est vide.");
            return;
        }

        // On lit l'ancien titre AVANT la mise à jour : il sert à vérifier
        // que l'id existe et à retrouver le document JSONB correspondant.
        string? ancienTitre;
        using (var lecture = new NpgsqlCommand(
                   "SELECT nom FROM livre WHERE id_livre = @id;", connexionSql))
        {
            lecture.Parameters.AddWithValue("id", idLivre);
            ancienTitre = lecture.ExecuteScalar() as string;
        }

        if (ancienTitre is null)
        {
            Console.WriteLine($"  Aucun livre avec l'id {idLivre}.");
            return;
        }

        using (var miseAJour = new NpgsqlCommand(
                   "UPDATE livre SET nom = @titre WHERE id_livre = @id;", connexionSql))
        {
            miseAJour.Parameters.AddWithValue("titre", nouveauTitre);
            miseAJour.Parameters.AddWithValue("id", idLivre);
            miseAJour.ExecuteNonQuery();
        }

        Console.WriteLine($"  Base relationnelle : « {ancienTitre} » -> « {nouveauTitre} ».");

        // Côté JSONB : jsonb_set remplace UNE propriété du document
        // sans réécrire tout le JSON à la main.
        const string requeteJsonbSet = @"
            UPDATE document
            SET donnees = jsonb_set(donnees, '{titre}', to_jsonb(@nouveau::text), false)
            WHERE type_document = 'livre'
              AND donnees ->> 'titre' = @ancien;";

        using var miseAJourJson = new NpgsqlCommand(requeteJsonbSet, connexionJsonb);
        miseAJourJson.Parameters.AddWithValue("nouveau", nouveauTitre);
        miseAJourJson.Parameters.AddWithValue("ancien", ancienTitre);
        int nbLignes = miseAJourJson.ExecuteNonQuery();

        Console.WriteLine($"  Base JSONB : {nbLignes} document(s) mis a jour avec jsonb_set.");
    }

    // ============================================================
    // 7. BOUCLE PRINCIPALE
    // ============================================================

    private const string Menu = """

        ============================================================
          Bibliotheque — application C# (Npgsql)
        ============================================================
          1. Afficher la liste des livres          (relationnel)
          2. Rechercher un livre ou un auteur      (relationnel)
          3. Chercher la meme information          (JSONB)
          4. Ajouter un livre / modifier un titre  (parametre)
          0. Quitter
        ------------------------------------------------------------
        """;

    /// <summary>
    /// Ouvre les deux connexions. Si la seconde échoue, la première est
    /// refermée immédiatement : on ne laisse jamais une connexion ouverte
    /// derrière soi.
    /// </summary>
    private static (NpgsqlConnection Sql, NpgsqlConnection Jsonb) OuvrirConnexions()
    {
        var connexionSql = new NpgsqlConnection(
            ChaineDeConnexion("PGDATABASE_SQL", "atelier_bibliotheque_sql"));

        try
        {
            connexionSql.Open();

            var connexionJsonb = new NpgsqlConnection(
                ChaineDeConnexion("PGDATABASE_JSONB", "atelier1_bibliotheque_jsonb"));

            try
            {
                connexionJsonb.Open();
            }
            catch
            {
                connexionJsonb.Dispose();
                throw;
            }

            return (connexionSql, connexionJsonb);
        }
        catch
        {
            connexionSql.Dispose();
            throw;
        }
    }

    private static int Main()
    {
        Console.OutputEncoding = Encoding.UTF8;   // pour les accents dans le terminal

        NpgsqlConnection connexionSql;
        NpgsqlConnection connexionJsonb;

        try
        {
            ChargerFichierEnv();
            (connexionSql, connexionJsonb) = OuvrirConnexions();
            Console.WriteLine("Connexion reussie aux deux bases.");
        }
        catch (InvalidOperationException erreur)
        {
            Console.WriteLine($"\nERREUR DE CONFIGURATION : {erreur.Message}");
            return 1;
        }
        catch (NpgsqlException erreur)
        {
            Console.WriteLine("\nERREUR DE CONNEXION a PostgreSQL.");
            Console.WriteLine("Verifie que le serveur est demarre, puis les valeurs de");
            Console.WriteLine("PGHOST / PGPORT / PGUSER / PGPASSWORD / PGDATABASE_*.");
            Console.WriteLine($"Detail : {erreur.Message}");
            return 1;
        }

        // try/finally : les connexions sont fermees quoi qu'il arrive.
        try
        {
            while (true)
            {
                Console.WriteLine(Menu);
                string choix = Demander("Ton choix : ");

                try
                {
                    switch (choix)
                    {
                        case "1":
                            ListerLivres(connexionSql);
                            break;
                        case "2":
                            RechercherLivreOuAuteur(connexionSql);
                            break;
                        case "3":
                            ChercherDansJsonb(connexionJsonb);
                            break;
                        case "4":
                            AjouterOuModifier(connexionSql, connexionJsonb);
                            break;
                        case "0":
                            Console.WriteLine("Au revoir.");
                            return 0;
                        default:
                            Console.WriteLine("  Choix invalide.");
                            break;
                    }
                }
                // Une requete refusee ne doit pas faire planter l'application :
                // on affiche un message clair et on revient au menu.
                catch (PostgresException erreur)
                {
                    switch (erreur.SqlState)
                    {
                        case "23505":   // unique_violation
                            Console.WriteLine("  ERREUR : ce livre existe deja pour cet auteur");
                            Console.WriteLine("  (contrainte UNIQUE uq_livre_titre_auteur).");
                            break;
                        case "23514":   // check_violation
                            Console.WriteLine($"  ERREUR : une contrainte CHECK refuse cette valeur ({erreur.ConstraintName}).");
                            break;
                        case "23503":   // foreign_key_violation
                            Console.WriteLine($"  ERREUR : cle etrangere invalide ({erreur.ConstraintName}).");
                            break;
                        default:
                            Console.WriteLine($"  ERREUR SQL [{erreur.SqlState}] : {erreur.MessageText}");
                            break;
                    }
                }
                catch (NpgsqlException erreur)
                {
                    Console.WriteLine($"  ERREUR DE COMMUNICATION avec PostgreSQL : {erreur.Message}");
                }
            }
        }
        finally
        {
            // Fermeture propre des deux connexions, quoi qu'il arrive
            // (choix 0, exception non prevue, Ctrl+C...).
            connexionSql.Dispose();
            Console.WriteLine("Connexion relationnelle fermee.");

            connexionJsonb.Dispose();
            Console.WriteLine("Connexion JSONB fermee.");
        }
    }
}
