using Npgsql;

namespace Tp1Commerce;

public static class Ecran
{
    private const int LargeurMax = 40;

    public static async Task AfficherResultatAsync(NpgsqlDataReader lecteur)
    {
        var entetes = Enumerable.Range(0, lecteur.FieldCount).Select(lecteur.GetName).ToArray();
        var lignes = new List<string[]>();

        while (await lecteur.ReadAsync())
        {
            var ligne = new string[lecteur.FieldCount];
            for (int i = 0; i < lecteur.FieldCount; i++)
                ligne[i] = Formater(lecteur.IsDBNull(i) ? null : lecteur.GetValue(i));
            lignes.Add(ligne);
        }

        AfficherTableau(entetes, lignes);
    }

    public static void AfficherTableau(string[] entetes, List<string[]> lignes)
    {
        if (lignes.Count == 0)
        {
            Console.WriteLine("(aucun résultat)");
            return;
        }

        int[] largeurs = entetes
            .Select((e, i) => Math.Min(LargeurMax, Math.Max(e.Length, lignes.Max(l => l[i].Length))))
            .ToArray();

        Console.WriteLine(Ligne(entetes, largeurs));
        Console.WriteLine(string.Join("-+-", largeurs.Select(l => new string('-', l))));
        foreach (var ligne in lignes)
            Console.WriteLine(Ligne(ligne, largeurs));
        Console.WriteLine($"{lignes.Count} ligne(s)");
    }

    public static string Montant(decimal montant) => montant.ToString("N2");

    private static string Ligne(string[] valeurs, int[] largeurs) =>
        string.Join(" | ", valeurs.Select((v, i) => Tronquer(v, largeurs[i]).PadRight(largeurs[i])));

    private static string Tronquer(string valeur, int largeur) =>
        valeur.Length <= largeur ? valeur : valeur[..(largeur - 1)] + "…";

    private static string Formater(object? valeur) => valeur switch
    {
        null       => "",
        DateTime d => d.ToString("yyyy-MM-dd HH:mm"),
        decimal m  => Montant(m),
        bool b     => b ? "oui" : "non",
        _          => valeur.ToString() ?? ""
    };
}
