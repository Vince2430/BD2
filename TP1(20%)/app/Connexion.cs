using Npgsql;

// 1. Lire la configuration dans l'environnement (rien d'écrit en dur)
string? hote        = Environment.GetEnvironmentVariable("BIBLIO_HOTE");
string? port        = Environment.GetEnvironmentVariable("BIBLIO_PORT");
string? nomBase     = Environment.GetEnvironmentVariable("BIBLIO_BASE");
string? utilisateur = Environment.GetEnvironmentVariable("BIBLIO_UTILISATEUR");
string? motDePasse  = Environment.GetEnvironmentVariable("BIBLIO_MDP");

if (string.IsNullOrWhiteSpace(utilisateur) || string.IsNullOrWhiteSpace(motDePasse))
{
    // On dit QUOI manque, jamais la valeur
    Console.WriteLine("Configuration incomplète : BIBLIO_UTILISATEUR et BIBLIO_MDP sont requis.");
    return;
}

// 2. Construire la chaîne de connexion avec le builder (pas de concaténation)
var builder = new NpgsqlConnectionStringBuilder
{
    Host     = hote ?? "localhost",
    Port     = int.TryParse(port, out int p) ? p : 5432,
    Database = nomBase,
    Username = utilisateur,
    Password = motDePasse
};

// 3. Ouvrir, tester, gérer les erreurs
try
{
    await using var connexion = new NpgsqlConnection(builder.ConnectionString);
    await connexion.OpenAsync();

    await using var cmd = new NpgsqlCommand("SELECT current_user", connexion);
    var qui = await cmd.ExecuteScalarAsync();
    Console.WriteLine($"Connecté en tant que {qui}");
}
catch (PostgresException ex)   // le serveur a répondu avec une erreur
{
    Console.WriteLine($"Erreur PostgreSQL {ex.SqlState} : {ex.MessageText}");
}
catch (NpgsqlException)        // serveur injoignable, réseau, etc.
{
    Console.WriteLine("Impossible de joindre le serveur de base de données.");
}