using Npgsql;
using Tp1Commerce;

Console.WriteLine("TP1 - Commerce en ligne : application cliente");
Console.WriteLine();

try
{
    Connexion.Initialiser();
}
catch (InvalidOperationException ex)
{
    Console.WriteLine($"Configuration invalide : {ex.Message}");
    return 1;
}

try
{
    await using var connexion = await Connexion.OuvrirAsync();
    await using var cmd = new NpgsqlCommand("SELECT current_user, current_database()", connexion);
    await using var lecteur = await cmd.ExecuteReaderAsync();

    if (await lecteur.ReadAsync())
        Console.WriteLine($"Connecté à {lecteur.GetString(1)} en tant que {lecteur.GetString(0)}.");
}
catch (PostgresException ex)
{
    Erreurs.Afficher(ex);
    return 1;
}
catch (NpgsqlException)
{
    Console.WriteLine("Impossible de joindre le serveur de base de données.");
    return 1;
}

var options = new (string Libelle, Func<Task> Action)[]
{
    ("Lister les commandes récentes (vue v_commandes)",        Actions.ListerCommandesAsync),
    ("Rechercher des commandes (client + statut)",              Actions.RechercherCommandesAsync),
    ("Rechercher des produits par marque (JSONB)",              Actions.RechercherProduitsParMarqueAsync),
    ("Détails d'une commande (fonction details_commande)",      Actions.DetailsCommandeAsync),
    ("Faire avancer une commande (procédure avancer_commande)", Actions.AvancerCommandeAsync),
    ("Ajouter une évaluation de produit",                       Actions.AjouterEvaluationAsync),
    ("Payer une commande (transaction COMMIT / ROLLBACK)",      Actions.PayerCommandeAsync)
};

while (true)
{
    Console.WriteLine();
    Console.WriteLine("========== Menu ==========");
    for (int i = 0; i < options.Length; i++)
        Console.WriteLine($"{i + 1}. {options[i].Libelle}");
    Console.WriteLine("0. Quitter");

    int choix = Saisie.LireEntier("Votre choix : ", 0, options.Length);
    if (choix == 0)
        break;

    Console.WriteLine();
    await Erreurs.ExecuterAsync(options[choix - 1].Action);
}

Console.WriteLine("Au revoir.");
return 0;
