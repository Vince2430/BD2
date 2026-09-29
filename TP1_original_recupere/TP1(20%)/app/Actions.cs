using Npgsql;
using NpgsqlTypes;

namespace Tp1Commerce;

// Énoncé : requêtes paramétrées pour toutes les valeurs saisies (aucune concaténation dans le SQL)
public static class Actions
{
    // Énoncé : afficher une liste provenant d'une jointure ou d'une vue
    public static async Task ListerCommandesAsync()
    {
        int limite = Saisie.LireEntier("Nombre de commandes à afficher (1 à 200, Entrée = 20) : ", 1, 200, 20);

        await using var connexion = await Connexion.OuvrirAsync();
        await using var cmd = new NpgsqlCommand(
            """
            SELECT id_commande, nom_client, date_commande, nom_statut
            FROM v_commandes
            ORDER BY date_commande DESC
            LIMIT @limite
            """, connexion);
        cmd.Parameters.AddWithValue("limite", limite);

        await using var lecteur = await cmd.ExecuteReaderAsync();
        await Ecran.AfficherResultatAsync(lecteur);
    }

    // Énoncé : rechercher selon au moins deux critères fournis par l'utilisateur (requête 8)
    public static async Task RechercherCommandesAsync()
    {
        string nomClient = Saisie.LireTexte("Nom du client (ou une partie du nom) : ");

        await using var connexion = await Connexion.OuvrirAsync();
        string statut = await ChoisirStatutAsync(connexion);

        await using var cmd = new NpgsqlCommand(
            """
            SELECT cmd.id_commande,
                   cmd.date_commande,
                   cl.id_client,
                   cl.nom_client,
                   s.nom_statut,
                   cmd.adresse_livraison_commande
            FROM commande cmd
            JOIN client cl ON cl.id_client = cmd.id_client
            JOIN statut s  ON s.id_statut  = cmd.id_statut
            WHERE cl.nom_client ILIKE '%' || @nom_client || '%'
              AND s.nom_statut  = @nom_statut
            ORDER BY cl.nom_client, cmd.date_commande DESC
            """, connexion);
        cmd.Parameters.AddWithValue("nom_client", nomClient);
        cmd.Parameters.AddWithValue("nom_statut", statut);

        await using var lecteur = await cmd.ExecuteReaderAsync();
        await Ecran.AfficherResultatAsync(lecteur);
    }

    // Ajout (hors énoncé de l'application) : requête 9, recherche JSONB par contenance @>
    public static async Task RechercherProduitsParMarqueAsync()
    {
        await using var connexion = await Connexion.OuvrirAsync();
        string? marque = await ChoisirMarqueAsync(connexion);
        if (marque is null)
        {
            Console.WriteLine("Aucune marque n'est enregistrée dans le catalogue.");
            return;
        }

        await using var cmd = new NpgsqlCommand(
            """
            SELECT p.id_produit,
                   p.nom_produit,
                   sp.specifications_produit ->> 'modele'        AS modele,
                   sp.specifications_produit ->> 'garantie_mois' AS garantie_mois
            FROM produit p
            JOIN specification_produit sp ON sp.id_produit = p.id_produit
            WHERE sp.specifications_produit @> jsonb_build_object('marque', @marque::text)
            ORDER BY p.nom_produit
            """, connexion);
        cmd.Parameters.AddWithValue("marque", marque);

        await using var lecteur = await cmd.ExecuteReaderAsync();
        await Ecran.AfficherResultatAsync(lecteur);
    }

    // Énoncé : appeler votre fonction (details_commande, total calculé par l'application, P0002 géré par Erreurs)
    public static async Task DetailsCommandeAsync()
    {
        int idCommande = Saisie.LireEntier("Numéro de la commande : ");

        await using var connexion = await Connexion.OuvrirAsync();
        await using var cmd = new NpgsqlCommand(
            """
            SELECT produit, quantite_commandee, prix_unitaire_fige, sous_total
            FROM details_commande(@id_commande)
            """, connexion);
        cmd.Parameters.AddWithValue("id_commande", idCommande);

        var lignes = new List<string[]>();
        decimal total = 0;

        await using (var lecteur = await cmd.ExecuteReaderAsync())
        {
            while (await lecteur.ReadAsync())
            {
                decimal sousTotal = lecteur.GetDecimal(3);
                total += sousTotal;
                lignes.Add(new[]
                {
                    lecteur.GetString(0),
                    lecteur.GetInt32(1).ToString(),
                    Ecran.Montant(lecteur.GetDecimal(2)),
                    Ecran.Montant(sousTotal)
                });
            }
        }

        if (lignes.Count == 0)
        {
            Console.WriteLine($"La commande {idCommande} existe, mais n'a aucune ligne.");
            return;
        }

        Ecran.AfficherTableau(new[] { "produit", "quantite", "prix_unitaire", "sous_total" }, lignes);
        Console.WriteLine($"Total de la commande {idCommande} : {Ecran.Montant(total)} $");
    }

    // Énoncé : appeler votre procédure (avancer_commande)
    public static async Task AvancerCommandeAsync()
    {
        int idCommande = Saisie.LireEntier("Numéro de la commande : ");

        await using var connexion = await Connexion.OuvrirAsync();

        ResumeCommande? avant = await AfficherCommandeAsync(connexion, idCommande);
        if (avant is null)
        {
            Console.WriteLine($"La commande {idCommande} n'existe pas.");
            return;
        }

        // Ajout (hors énoncé) : aperçu de la prochaine étape; la procédure et le déclencheur restent seuls juges
        (string Suivant, string Effet)? etape = avant.Value.Statut switch
        {
            "En attente"     => ("Payée", "Exige des paiements complétés couvrant le total de la commande."),
            "Payée"          => ("En préparation", "Changement de statut seulement."),
            "En préparation" => ("Expédiée", "Crée une expédition pour toutes les quantités qui restent à envoyer."),
            "Expédiée"       => ("Livrée", "Marque les expéditions de la commande comme complétées."),
            _                => null
        };

        Console.WriteLine();
        if (etape is null)
        {
            Console.WriteLine($"Statut « {avant.Value.Statut} » : cette commande ne peut plus avancer.");
            return;
        }

        Console.WriteLine($"Prochaine étape : « {avant.Value.Statut} » -> « {etape.Value.Suivant} »");
        Console.WriteLine($"  {etape.Value.Effet}");

        if (etape.Value.Suivant == "Payée" && avant.Value.Paye < avant.Value.Total)
            Console.WriteLine($"  Attention : payé {Ecran.Montant(avant.Value.Paye)} $ sur {Ecran.Montant(avant.Value.Total)} $, la base refusera ce passage.");

        string? camion = null;
        if (etape.Value.Suivant == "Expédiée")
            camion = Saisie.LireTexteOptionnel("Camion (Entrée = aucun) : ");

        if (!Saisie.Confirmer("Faire avancer la commande ?"))
        {
            Console.WriteLine("Annulé, rien n'a été modifié.");
            return;
        }

        connexion.Notice += (_, e) => Console.WriteLine($"Serveur : {e.Notice.MessageText}");

        await using (var cmd = new NpgsqlCommand("CALL avancer_commande(@id_commande, @camion)", connexion))
        {
            cmd.Parameters.AddWithValue("id_commande", idCommande);
            cmd.Parameters.Add(new NpgsqlParameter("camion", NpgsqlDbType.Varchar) { Value = (object?)camion ?? DBNull.Value });
            await cmd.ExecuteNonQueryAsync();
        }

        Console.WriteLine();
        Console.WriteLine("Après :");
        await AfficherCommandeAsync(connexion, idCommande);
    }

    private readonly record struct ResumeCommande(string Statut, decimal Total, decimal Paye);

    private static async Task<ResumeCommande?> AfficherCommandeAsync(NpgsqlConnection connexion, int idCommande)
    {
        ResumeCommande resume;

        await using (var cmd = new NpgsqlCommand(
            """
            SELECT cl.nom_client,
                   c.date_commande,
                   c.adresse_livraison_commande,
                   s.nom_statut,
                   COALESCE((SELECT SUM(ic.quantite * ic.prix_unitaire)
                             FROM info_commande ic
                             WHERE ic.id_commande = c.id_commande), 0),
                   COALESCE((SELECT SUM(p.montant_paiement)
                             FROM paiement p
                             WHERE p.id_commande = c.id_commande AND p.est_complete), 0)
            FROM commande c
            JOIN client cl ON cl.id_client = c.id_client
            JOIN statut s  ON s.id_statut  = c.id_statut
            WHERE c.id_commande = @id_commande
            """, connexion))
        {
            cmd.Parameters.AddWithValue("id_commande", idCommande);
            await using var lecteur = await cmd.ExecuteReaderAsync();
            if (!await lecteur.ReadAsync())
                return null;

            resume = new ResumeCommande(lecteur.GetString(3), lecteur.GetDecimal(4), lecteur.GetDecimal(5));

            Console.WriteLine($"Commande {idCommande}");
            Console.WriteLine($"  Client    : {lecteur.GetString(0)}");
            Console.WriteLine($"  Date      : {lecteur.GetDateTime(1):yyyy-MM-dd HH:mm}");
            Console.WriteLine($"  Livraison : {lecteur.GetString(2)}");
            Console.WriteLine($"  Statut    : {resume.Statut}");
            Console.WriteLine($"  Total     : {Ecran.Montant(resume.Total)} $ (payé : {Ecran.Montant(resume.Paye)} $)");
        }

        Console.WriteLine();
        Console.WriteLine("Produits :");

        await using (var cmd = new NpgsqlCommand(
            """
            SELECT p.nom_produit AS produit,
                   ic.quantite   AS commandee,
                   COALESCE(SUM(ie.quantite_expediee), 0)                               AS en_expedition,
                   COALESCE(SUM(ie.quantite_expediee) FILTER (WHERE e.est_complete), 0) AS livree
            FROM info_commande ic
            JOIN produit p              ON p.id_produit        = ic.id_produit
            LEFT JOIN info_expedition ie ON ie.id_info_commande = ic.id_info_commande
            LEFT JOIN expedition e       ON e.id_expedition     = ie.id_expedition
            WHERE ic.id_commande = @id_commande
            GROUP BY ic.id_info_commande, p.nom_produit, ic.quantite
            ORDER BY p.nom_produit
            """, connexion))
        {
            cmd.Parameters.AddWithValue("id_commande", idCommande);
            await using var lecteur = await cmd.ExecuteReaderAsync();
            await Ecran.AfficherResultatAsync(lecteur);
        }

        return resume;
    }

    // Énoncé : ajouter une donnée en respectant les contraintes
    public static async Task AjouterEvaluationAsync()
    {
        await using var connexion = await Connexion.OuvrirAsync();

        (int Id, string Nom)? client = await ChoisirClientAsync(connexion);
        if (client is null)
            return;

        var produits = new List<(int Id, string Nom)>();

        await using (var cmd = new NpgsqlCommand(
            """
            SELECT DISTINCT p.id_produit, p.nom_produit
            FROM info_commande ic
            JOIN commande c ON c.id_commande = ic.id_commande
            JOIN produit p  ON p.id_produit  = ic.id_produit
            WHERE c.id_client = @id_client
              AND NOT EXISTS (SELECT 1
                              FROM evaluation e
                              WHERE e.id_client  = c.id_client
                                AND e.id_produit = p.id_produit)
            ORDER BY p.nom_produit
            """, connexion))
        {
            cmd.Parameters.AddWithValue("id_client", client.Value.Id);
            await using var lecteur = await cmd.ExecuteReaderAsync();
            while (await lecteur.ReadAsync())
                produits.Add((lecteur.GetInt32(0), lecteur.GetString(1)));
        }

        if (produits.Count == 0)
        {
            Console.WriteLine($"{client.Value.Nom} n'a aucun produit acheté qui reste à évaluer.");
            return;
        }

        var produit = produits[Saisie.LireChoix(
            $"Produits achetés par {client.Value.Nom} et pas encore évalués :",
            produits.Select(p => p.Nom).ToList())];

        int note = Saisie.LireEntier("Note (1 à 5) : ", 1, 5);
        string? commentaire = Saisie.LireTexteOptionnel("Commentaire (Entrée = aucun) : ");

        await using (var cmd = new NpgsqlCommand(
            """
            INSERT INTO evaluation (id_produit, id_client, note_evaluation, commentaire_evaluation)
            VALUES (@id_produit, @id_client, @note, @commentaire)
            RETURNING id_evaluation, date_evaluation
            """, connexion))
        {
            cmd.Parameters.AddWithValue("id_produit", produit.Id);
            cmd.Parameters.AddWithValue("id_client", client.Value.Id);
            cmd.Parameters.AddWithValue("note", (short)note);
            cmd.Parameters.Add(new NpgsqlParameter("commentaire", NpgsqlDbType.Text) { Value = (object?)commentaire ?? DBNull.Value });

            await using var lecteur = await cmd.ExecuteReaderAsync();
            if (await lecteur.ReadAsync())
                Console.WriteLine($"Évaluation {lecteur.GetInt32(0)} ajoutée le {lecteur.GetDateTime(1):yyyy-MM-dd HH:mm} : " +
                                  $"{client.Value.Nom}, « {produit.Nom} », {note}/5.");
        }
    }

    private static async Task<(int Id, string Nom)?> ChoisirClientAsync(NpgsqlConnection connexion)
    {
        string recherche = Saisie.LireTexte("Nom du client (ou une partie du nom) : ");
        var clients = new List<(int Id, string Nom, string Courriel)>();

        await using (var cmd = new NpgsqlCommand(
            """
            SELECT id_client, nom_client, courriel_client
            FROM client
            WHERE nom_client ILIKE '%' || @recherche || '%'
            ORDER BY nom_client
            LIMIT 20
            """, connexion))
        {
            cmd.Parameters.AddWithValue("recherche", recherche);
            await using var lecteur = await cmd.ExecuteReaderAsync();
            while (await lecteur.ReadAsync())
                clients.Add((lecteur.GetInt32(0), lecteur.GetString(1), lecteur.GetString(2)));
        }

        if (clients.Count == 0)
        {
            Console.WriteLine("Aucun client ne correspond à cette recherche.");
            return null;
        }

        var choisi = clients[Saisie.LireChoix(
            clients.Count == 20 ? "Clients trouvés (20 premiers, précisez le nom si besoin) :" : "Clients trouvés :",
            clients.Select(c => $"{c.Nom} ({c.Courriel})").ToList())];

        return (choisi.Id, choisi.Nom);
    }

    // Énoncé : modifier une donnée dans une transaction (COMMIT / ROLLBACK)
    public static async Task PayerCommandeAsync()
    {
        int idCommande = Saisie.LireEntier("Numéro de la commande : ");

        await using var connexion = await Connexion.OuvrirAsync();

        EtatPaiement? avant = await LireEtatPaiementAsync(connexion, idCommande);
        if (avant is null)
        {
            Console.WriteLine($"La commande {idCommande} n'existe pas.");
            return;
        }

        Console.WriteLine("État avant :");
        AfficherEtatPaiement(idCommande, avant.Value);

        if (avant.Value.Statut != "En attente")
        {
            Console.WriteLine("Seule une commande « En attente » peut être payée.");
            return;
        }
        if (avant.Value.Autorise == 0)
        {
            Console.WriteLine("Cette commande n'a aucun paiement autorisé à capturer.");
            return;
        }

        // Ajout (hors énoncé) : la réponse du processeur de paiement externe est simulée par l'utilisateur
        int reponse = Saisie.LireChoix("Réponse simulée du processeur de paiement :", new[]
        {
            "Approuvée (capture du montant autorisé)",
            "Partielle (seulement la moitié du montant est captée)",
            "Refusée"
        });

        await using var transaction = await connexion.BeginTransactionAsync();

        if (reponse == 2)
        {
            await transaction.RollbackAsync();
            Console.WriteLine("Paiement refusé par le processeur : ROLLBACK, rien n'a été modifié.");
        }
        else
        {
            try
            {
                await using (var capture = new NpgsqlCommand(
                    """
                    UPDATE paiement
                    SET est_complete     = TRUE,
                        date_paiement    = LOCALTIMESTAMP,
                        montant_paiement = CASE WHEN @partielle
                                                THEN ROUND(montant_paiement / 2, 2)
                                                ELSE montant_paiement END
                    WHERE id_commande = @id_commande
                      AND NOT est_complete
                    """, connexion, transaction))
                {
                    capture.Parameters.AddWithValue("partielle", reponse == 1);
                    capture.Parameters.AddWithValue("id_commande", idCommande);
                    int nombre = await capture.ExecuteNonQueryAsync();
                    Console.WriteLine($"{nombre} paiement(s) capturé(s).");
                }

                await using (var payer = new NpgsqlCommand(
                    """
                    UPDATE commande
                    SET id_statut = (SELECT id_statut FROM statut WHERE nom_statut = 'Payée')
                    WHERE id_commande = @id_commande
                    """, connexion, transaction))
                {
                    payer.Parameters.AddWithValue("id_commande", idCommande);
                    await payer.ExecuteNonQueryAsync();
                }

                await transaction.CommitAsync();
                Console.WriteLine("COMMIT : la commande est payée.");
            }
            catch (PostgresException ex)
            {
                await transaction.RollbackAsync();
                Console.WriteLine("ROLLBACK : la capture et le changement de statut sont annulés.");
                Erreurs.Afficher(ex);
            }
        }

        EtatPaiement? apres = await LireEtatPaiementAsync(connexion, idCommande);
        Console.WriteLine("État après :");
        AfficherEtatPaiement(idCommande, apres!.Value);
    }

    private readonly record struct EtatPaiement(string Statut, decimal Total, decimal Capture, decimal Autorise);

    private static async Task<EtatPaiement?> LireEtatPaiementAsync(NpgsqlConnection connexion, int idCommande)
    {
        await using var cmd = new NpgsqlCommand(
            """
            SELECT s.nom_statut,
                   COALESCE((SELECT SUM(ic.quantite * ic.prix_unitaire)
                             FROM info_commande ic
                             WHERE ic.id_commande = c.id_commande), 0),
                   COALESCE((SELECT SUM(p.montant_paiement)
                             FROM paiement p
                             WHERE p.id_commande = c.id_commande AND p.est_complete), 0),
                   COALESCE((SELECT SUM(p.montant_paiement)
                             FROM paiement p
                             WHERE p.id_commande = c.id_commande AND NOT p.est_complete), 0)
            FROM commande c
            JOIN statut s ON s.id_statut = c.id_statut
            WHERE c.id_commande = @id_commande
            """, connexion);
        cmd.Parameters.AddWithValue("id_commande", idCommande);

        await using var lecteur = await cmd.ExecuteReaderAsync();
        if (!await lecteur.ReadAsync())
            return null;

        return new EtatPaiement(
            lecteur.GetString(0),
            lecteur.GetDecimal(1),
            lecteur.GetDecimal(2),
            lecteur.GetDecimal(3));
    }

    private static void AfficherEtatPaiement(int idCommande, EtatPaiement etat)
    {
        Console.WriteLine($"  Commande {idCommande} : « {etat.Statut} »");
        Console.WriteLine($"  Total {Ecran.Montant(etat.Total)} $ | capturé {Ecran.Montant(etat.Capture)} $ | autorisé {Ecran.Montant(etat.Autorise)} $");
    }

    private static async Task<string?> ChoisirMarqueAsync(NpgsqlConnection connexion)
    {
        var marques = new List<string>();

        await using (var cmd = new NpgsqlCommand(
            """
            SELECT DISTINCT specifications_produit ->> 'marque' AS marque
            FROM specification_produit
            WHERE jsonb_typeof(specifications_produit -> 'marque') = 'string'
            ORDER BY marque
            """, connexion))
        await using (var lecteur = await cmd.ExecuteReaderAsync())
        {
            while (await lecteur.ReadAsync())
                marques.Add(lecteur.GetString(0));
        }

        if (marques.Count == 0)
            return null;

        return marques[Saisie.LireChoix("Marques disponibles :", marques)];
    }

    private static async Task<string> ChoisirStatutAsync(NpgsqlConnection connexion)
    {
        var statuts = new List<string>();

        await using (var cmd = new NpgsqlCommand("SELECT nom_statut FROM statut ORDER BY id_statut", connexion))
        await using (var lecteur = await cmd.ExecuteReaderAsync())
        {
            while (await lecteur.ReadAsync())
                statuts.Add(lecteur.GetString(0));
        }

        return statuts[Saisie.LireChoix("Statut recherché :", statuts)];
    }
}
