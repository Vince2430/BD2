using Npgsql;

namespace Tp1Commerce;

// Affichage des resultats sous forme de tableau texte.
public static class Ecran
{
    private const int LargeurMax = 40;

    public static void AfficherTableau(IReadOnlyList<string> entetes, IReadOnlyList<string[]> lignes)
    {
        if (lignes.Count == 0)
        {
            Console.WriteLine("(aucun résultat)");
            return;
        }

        int[] largeurs = entetes
            .Select((entete, i) => Math.Min(LargeurMax,
                                            Math.Max(entete.Length, lignes.Max(l => l[i].Length))))
            .ToArray();

        Console.WriteLine(Ligne(entetes, largeurs));
        Console.WriteLine(string.Join("-+-", largeurs.Select(l => new string('-', l))));
        foreach (string[] ligne in lignes)
        {
            Console.WriteLine(Ligne(ligne, largeurs));
        }
        Console.WriteLine($"{lignes.Count} ligne(s)");
    }

    // Lit tout le resultat d'une requete et l'affiche (noms de colonnes = en-tetes).
    public static async Task AfficherResultatAsync(NpgsqlDataReader lecteur)
    {
        string[] entetes = Enumerable.Range(0, lecteur.FieldCount).Select(lecteur.GetName).ToArray();
        var lignes = new List<string[]>();

        while (await lecteur.ReadAsync())
        {
            var valeurs = new string[lecteur.FieldCount];
            for (int i = 0; i < lecteur.FieldCount; i++)
            {
                valeurs[i] = Formater(lecteur.GetValue(i));
            }
            lignes.Add(valeurs);
        }

        AfficherTableau(entetes, lignes);
    }

    public static string Formater(object? valeur) => valeur switch
    {
        null or DBNull => "",
        decimal d      => d.ToString("N2"),
        DateTime dt    => dt.ToString("yyyy-MM-dd HH:mm"),
        bool b         => b ? "oui" : "non",
        _              => valeur.ToString() ?? ""
    };

    public static string Montant(decimal montant) => montant.ToString("N2");

    public static string Tronquer(string valeur, int max) =>
        valeur.Length <= max ? valeur : valeur[..(max - 1)] + "…";

    private static string Ligne(IReadOnlyList<string> valeurs, int[] largeurs) =>
        string.Join(" | ", valeurs.Select((v, i) => Tronquer(v, largeurs[i]).PadRight(largeurs[i])));
}
