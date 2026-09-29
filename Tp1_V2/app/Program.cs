// =============================================================
// TP1 - Base de donnees II (420-B56)
// Etape 5 : application cliente console (C# + Npgsql)
// =============================================================
// Lancement (depuis le dossier app) :
//   export PGUSER=demo_gestionnaire
//   export PGPASSWORD=...          (jamais ecrit dans un fichier)
//   dotnet run
// Variables facultatives : PGHOST (localhost), PGPORT (5432),
// PGDATABASE (tp1_vincent_trudel).
// =============================================================

using System.Text;
using Npgsql;
using Tp1Commerce;

Console.OutputEncoding = Encoding.UTF8;
Console.WriteLine("TP1 - Commerce en ligne : application cliente");

// Énoncé : connexion par variables d'environnement.
string serveur;
try
{
    serveur = Connexion.Initialiser();
}
catch (InvalidOperationException ex)
{
    Console.WriteLine("Configuration invalide : " + ex.Message);
    return 1;
}

// Test de connexion au demarrage
try
{
    await using var connexion = await Connexion.OuvrirAsync();
    await using var cmd = new NpgsqlCommand("SELECT current_user, current_database()", connexion);
    await using var lecteur = await cmd.ExecuteReaderAsync();
    await lecteur.ReadAsync();
    Console.WriteLine($"Connecté à {lecteur.GetString(1)} en tant que {lecteur.GetString(0)}");
    Console.WriteLine("Serveur : " + serveur);
}
catch (PostgresException ex)
{
    // Énoncé : erreur affichee sans mot de passe ni chaine de connexion.
    Erreurs.Afficher(ex);
    return 1;
}
catch (NpgsqlException)
{
    Console.WriteLine("Impossible de joindre le serveur de base de données.");
    return 1;
}

var options = new (string Titre, Func<Task> Action)[]
{
    ("Lister les commandes récentes (vue v_commandes)",           Actions.ListerCommandesAsync),
    ("Rechercher des commandes (client + statut)",               Actions.RechercherCommandesAsync),
    ("Rechercher des produits par marque (JSONB)",               Actions.RechercherProduitsParMarqueAsync),
    ("Détails d'une commande (fonction details_commande)",       Actions.DetailsCommandeAsync),
    ("Faire avancer une commande (procédure avancer_commande)",  Actions.AvancerCommandeAsync),
    ("Ajouter une évaluation de produit",                        Actions.AjouterEvaluationAsync),
    ("Payer une commande (transaction COMMIT / ROLLBACK)",       Actions.PayerCommandeAsync),
};

while (true)
{
    Console.WriteLine();
    Console.WriteLine("========== Menu ==========");
    for (int i = 0; i < options.Length; i++)
    {
        Console.WriteLine($"{i + 1}. {options[i].Titre}");
    }
    Console.WriteLine("0. Quitter");

    int choix = Saisie.LireEntier("Votre choix : ", 0, options.Length);
    if (choix == 0)
    {
        break;
    }

    Console.WriteLine();
    await Erreurs.ExecuterAsync(options[choix - 1].Action);
}

Console.WriteLine("Au revoir.");
return 0;
