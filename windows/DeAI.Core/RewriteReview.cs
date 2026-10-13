using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

namespace DeAI;

public sealed class RewriteReview
{
    public sealed record Edit(int Id, string Original, string Revised);
    private sealed record Segment(string Text, Edit? Edit = null);
    private readonly List<Segment> segments = new();
    public Guid Id { get; } = Guid.NewGuid();
    public IReadOnlyList<Edit> Edits { get; }
    public bool IsWholePassage { get; }

    public RewriteReview(string original, string result)
    {
        var edits = new List<Edit>();
        Edits = edits.AsReadOnly();
        if (original == result) { segments.Add(new(original)); return; }
        var a = Tokens(original); var b = Tokens(result);
        // Match Mac's work cap; oversized responses remain one lossless choice.
        if (a.Length + b.Length > 12_000 || (long)a.Length * b.Length > 16_000_000)
        {
            IsWholePassage = true;
            AddEdit(original, result);
            return;
        }
        var lcs = new ushort[a.Length + 1, b.Length + 1];
        for (var i = a.Length - 1; i >= 0; i--)
            for (var j = b.Length - 1; j >= 0; j--)
                lcs[i, j] = a[i] == b[j] ? (ushort)(lcs[i + 1, j + 1] + 1) : Math.Max(lcs[i + 1, j], lcs[i, j + 1]);
        var x = 0; var y = 0;
        var unchanged = new StringBuilder();
        while (x < a.Length || y < b.Length)
        {
            if (x < a.Length && y < b.Length && a[x] == b[y])
            {
                unchanged.Append(a[x]); x++; y++; continue;
            }
            if (unchanged.Length > 0) { segments.Add(new(unchanged.ToString())); unchanged.Clear(); }
            var from = new StringBuilder(); var to = new StringBuilder();
            while (x < a.Length || y < b.Length)
            {
                if (x < a.Length && y < b.Length && a[x] == b[y]) break;
                if (y == b.Length || (x < a.Length && lcs[x + 1, y] >= lcs[x, y + 1])) from.Append(a[x++]);
                else to.Append(b[y++]);
            }
            AddEdit(from.ToString(), to.ToString());
        }
        if (unchanged.Length > 0) segments.Add(new(unchanged.ToString()));
        void AddEdit(string from, string to)
        {
            var edit = new Edit(edits.Count, from, to);
            edits.Add(edit); segments.Add(new("", edit));
        }
    }

    public string Text(IReadOnlySet<int> accepted)
    {
        var text = new StringBuilder();
        foreach (var segment in segments)
            text.Append(segment.Edit is { } edit ? accepted.Contains(edit.Id) ? edit.Revised : edit.Original : segment.Text);
        return text.ToString();
    }

    private static string[] Tokens(string text)
    {
        var tokens = new List<string>(); var word = new StringBuilder();
        var elements = StringInfo.GetTextElementEnumerator(text);
        while (elements.MoveNext())
        {
            var element = elements.GetTextElement();
            if (element.Length == 1 && element[0] is >= 'A' and <= 'Z' or >= 'a' and <= 'z' or >= '0' and <= '9' or '\'')
                word.Append(element);
            else
            {
                if (word.Length > 0) { tokens.Add(word.ToString()); word.Clear(); }
                tokens.Add(element);
            }
        }
        if (word.Length > 0) tokens.Add(word.ToString());
        return tokens.ToArray();
    }
}

public sealed class RewriteReviewState(string original)
{
    private readonly HashSet<int> accepted = new();
    public RewriteReview? Review { get; private set; }
    public string? ReviewedText => Review?.Text(accepted);
    public bool KeepsOriginal => ReviewedText == original;
    public int AcceptedCount => accepted.Count;
    public bool IsAccepted(int id) => accepted.Contains(id);
    public void Reset() { Review = null; accepted.Clear(); }
    public void SetResult(string result)
    {
        Reset(); Review = new(original, result);
        accepted.UnionWith(Review.Edits.Select(edit => edit.Id));
    }
    public void Select(int id, bool use, Guid reviewId)
    {
        if (Review?.Id != reviewId || !Review.Edits.Any(edit => edit.Id == id)) return;
        if (use) accepted.Add(id); else accepted.Remove(id);
    }
    public void SelectAll(bool use)
    {
        accepted.Clear();
        if (use && Review != null) accepted.UnionWith(Review.Edits.Select(edit => edit.Id));
    }
}
