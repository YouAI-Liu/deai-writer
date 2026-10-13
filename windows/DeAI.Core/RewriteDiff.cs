using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

namespace DeAI;

public sealed record RewritePair(string From, string To)
{
    public PersonalEntry? Candidate()
    {
        if (From.Length == 0) return null;
        if (To.Length != 0) return new PersonalEntry("replace", From, To);
        var term = From.TrimEnd(" \t\r\n，,。．.、；;：:！!？?…—-·".ToCharArray());
        return term.Length > 0 ? new PersonalEntry("avoid", term, null) : null;
    }
}

public static class RewriteDiff
{
    private sealed record Token(string Text, int Start, int End);
    private static Token[] Tokens(string text)
    {
        var result = new List<Token>(); var i = 0;
        while (i < text.Length)
        {
            if (char.IsWhiteSpace(text, i)) { i++; continue; }
            var start = i;
            if (IsWord(text[i]))
                while (i < text.Length && IsWord(text[i])) i++;
            else i += StringInfo.GetNextTextElementLength(text, i);
            result.Add(new Token(text[start..i], start, i));
        }
        return result.ToArray();
    }
    private static bool IsWord(char c) => c is >= 'A' and <= 'Z' or >= 'a' and <= 'z' or >= '0' and <= '9' or '\'';
    public static IReadOnlyList<RewritePair> Pairs(string original, string result)
    {
        var a = Tokens(original); var b = Tokens(result);
        // Bound the quadratic table for large documents; never turn an oversized diff into a learned rule.
        if ((long)(a.Length + 1) * (b.Length + 1) > 1_000_000) return Array.Empty<RewritePair>();
        var lcs = new int[a.Length + 1, b.Length + 1];
        for (var i = a.Length - 1; i >= 0; i--)
            for (var j = b.Length - 1; j >= 0; j--)
                lcs[i, j] = a[i].Text == b[j].Text ? lcs[i + 1, j + 1] + 1 : Math.Max(lcs[i + 1, j], lcs[i, j + 1]);
        var pairs = new List<RewritePair>(); var x = 0; var y = 0;
        while (x < a.Length || y < b.Length)
        {
            if (x < a.Length && y < b.Length && a[x].Text == b[y].Text) { x++; y++; continue; }
            var startA = x; var startB = y;
            while (x < a.Length || y < b.Length)
            {
                if (x < a.Length && y < b.Length && a[x].Text == b[y].Text) break;
                if (y == b.Length || (x < a.Length && lcs[x + 1, y] >= lcs[x, y + 1])) x++; else y++;
            }
            var from = x > startA ? original[a[startA].Start..a[x - 1].End] : "";
            var to = y > startB ? result[b[startB].Start..b[y - 1].End] : "";
            if (from == to || from.EnumerateRunes().Count() > 20 || to.EnumerateRunes().Count() > 20) continue;
            pairs.Add(new RewritePair(from, to)); if (pairs.Count == 10) break;
        }
        return pairs;
    }
}
