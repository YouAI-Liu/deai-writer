using System;
using System.Linq;
using DeAI;
using DeAI.Automation;
using static DeAI.Tests.Program;

namespace DeAI.Tests;

internal static class ReviewTests
{
    public static void Run()
    {
        Check("Review all-kept/all-used exact Unicode and whitespace round trips", () =>
        {
            foreach (var (original, result) in new[]
            {
                ("He go home. We was late!", "He goes home. We were late!"),
                ("说白了，这是一个例子。", "这是例子！"),
                ("a  b\r\nc\t", "a b\nc\t\t"), ("", "new 😀"), ("delete all", ""),
                ("unchanged", "unchanged"), ("same same word", "same word same"),
                ("👨‍👩‍👧‍👦 cafe\u0301。🇨🇳", "👨‍👩‍👧‍👦 café！🇨🇳"), ("a😀b", "a👩🏽‍💻b")
            }) RoundTrip(original, result);
        });
        Check("Review mixed choices retain unselected words", () =>
        {
            var model = new RewriteReviewState("He go home. We was late!");
            model.SetResult("He goes home. We were late!");
            var review = model.Review!;
            var was = review.Edits.Single(edit => edit.Original == "was");
            model.Select(was.Id, false, review.Id);
            Equal("He goes home. We was late!", model.ReviewedText);
            Equal(false, RewriteDiff.Pairs("He go home. We was late!", model.ReviewedText!).Any(pair => pair.From == "was"));
        });
        Check("Review punctuation and whitespace are selectable", () =>
        {
            var model = new RewriteReviewState("Hello, world.\r\n");
            model.SetResult("Hello! world?\n"); model.SelectAll(false);
            var review = model.Review!;
            model.Select(review.Edits.Single(edit => edit.Original == ",").Id, true, review.Id);
            Equal("Hello! world.\r\n", model.ReviewedText);
            RoundTrip("  A\tB  ", " A B ");
        });
        Check("Review canonical Unicode spelling is not collapsed", () =>
        {
            var model = new RewriteReviewState("e\u0301");
            model.SetResult("é"); Equal(false, model.KeepsOriginal);
            Equal(1, model.Review!.Edits.Count);
            model.SelectAll(false); Equal(true, model.KeepsOriginal);
            Equal("e\u0301", model.ReviewedText);
        });
        Check("Review large response is a single lossless choice", () =>
        {
            var result = string.Concat(Enumerable.Repeat("😀。", 7000));
            var model = new RewriteReviewState("短文"); model.SetResult(result);
            Equal(true, model.Review!.IsWholePassage); Equal(1, model.Review.Edits.Count);
            Equal(result, model.ReviewedText); model.SelectAll(false); Equal("短文", model.ReviewedText);
        });
        Check("Review new result resets choices and rejects old callbacks", () =>
        {
            var model = new RewriteReviewState("old"); model.SetResult("new");
            var old = model.Review!; model.SelectAll(false);
            model.SetResult("fresh"); model.Select(0, false, old.Id);
            Equal("fresh", model.ReviewedText); Equal(1, model.AcceptedCount);
            model.Reset(); Equal(null, model.ReviewedText);
            model.Select(0, true, old.Id); Equal(0, model.AcceptedCount);
        });
        Check("Review randomized repeated Unicode round trips", () =>
        {
            var random = new Random(29);
            var tokens = new[] { "a", "b", " ", "\t", "\r\n", "\n", "，", "中", "😀", "é", "e\u0301" };
            string Generate() => string.Concat(Enumerable.Range(0, 24).Select(_ => tokens[random.Next(tokens.Length)]));
            for (var i = 0; i < 200; i++) RoundTrip(Generate(), Generate());
        });
        Check("Review mixed text uses existing safe UTF-16 replacement", () =>
        {
            const string source = "He go home. We was late!";
            var model = new RewriteReviewState(source); model.SetResult("He goes home. We were late!");
            var review = model.Review!;
            model.Select(review.Edits.Single(edit => edit.Original == "was").Id, false, review.Id);
            var document = "前😀\r\n" + source + "\r\n后";
            Equal("前😀\r\nHe goes home. We was late!\r\n后", TextSafety.Replace(document, document, 5, 5 + source.Length, model.ReviewedText!));
            Reject(() => TextSafety.Replace(document, document + "edited", 5, 5 + source.Length, model.ReviewedText!));
        });
        Check("Review partial paragraph edits cannot bypass paragraph protection", () =>
        {
            var model = new RewriteReviewState("A\r\nB C");
            model.SetResult("A B\r\nC");
            model.SelectAll(false);
            var review = model.Review!;
            model.Select(review.Edits.First(edit => edit.Original.Contains("\r\n", StringComparison.Ordinal)).Id, true, review.Id);
            Reject(() => RewriteScope.ValidateReviewedText(model.ReviewedText!, "A\r\nB C"));
            model.SelectAll(true); RewriteScope.ValidateReviewedText(model.ReviewedText!, "A\r\nB C");
        });
    }
    private static void RoundTrip(string original, string result)
    {
        var model = new RewriteReviewState(original); model.SetResult(result);
        Equal(result, model.ReviewedText);
        model.SelectAll(false); Equal(original, model.ReviewedText);
    }
}
