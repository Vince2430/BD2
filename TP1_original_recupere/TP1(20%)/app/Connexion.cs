using Npgsql;

namespace Tp1Commerce;

// Énoncé : utiliser des variables d'environnement pour la connexion
public static class Connexion
{
    private static string? _chaineConnexion;

    public static void Initialiser()
    {
        string? hote        = Environment.GetEnvironmentVariable("PGHOST");
        string? port        = Environment.GetEnvironmentVariable("PGPORT");
        string? nomBase     = Environment.GetEnvironmentVariable("PGDATABASE");
        string? utilisateur = Environment.GetEnvironmentVariable("PGUSER");
        string? motDePasse  = Environment.GetEnvironmentVariable("PGPASSWORD");

        var manquantes = new List<string>();
        if (string.IsNullOrWhiteSpace(utilisateur)) manquantes.Add("PGUSER");
        if (string.IsNullOrWhiteSpace(motDePasse))  manquantes.Add("PGPASSWORD");

        if (manquantes.Count > 0)
            throw new InvalidOperationException(
                "variable(s) d'environnement manquante(s) : " + string.Join(", ", manquantes));

        int numeroPort = 5432;
        if (!string.IsNullOrWhiteSpace(port) &&
            (!int.TryParse(port, out numeroPort) || numeroPort < 1 || numeroPort > 65535))
            throw new InvalidOperationException("PGPORT doit être un nombre entre 1 et 65535.");

        var builder = new NpgsqlConnectionStringBuilder
        {
            Host            = string.IsNullOrWhiteSpace(hote) ? "localhost" : hote,
            Port            = numeroPort,
            Database        = string.IsNullOrWhiteSpace(nomBase) ? "tp1_vincent_trudel" : nomBase,
            Username        = utilisateur,
            Password        = motDePasse,
            SearchPath      = "commerce",
            ApplicationName = "Tp1Commerce",
            Timeout         = 5
        };

        _chaineConnexion = builder.ConnectionString;
    }

    public static async Task<NpgsqlConnection> OuvrirAsync()
    {
        if (_chaineConnexion is null)
            throw new InvalidOperationException("Connexion.Initialiser() n'a pas été appelée.");

        var connexion = new NpgsqlConnection(_chaineConnexion);
        try
        {
            await connexion.OpenAsync();
            return connexion;
        }
        catch
        {
            await connexion.DisposeAsync();
            throw;
        }
    }
}
