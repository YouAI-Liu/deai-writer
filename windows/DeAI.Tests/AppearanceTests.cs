using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using DeAI;
using static DeAI.Tests.Program;

namespace DeAI.Tests;

internal static class AppearanceTests
{
    public static void Run()
    {
        Check("Rust category names map to localized UI labels and color keys", () =>
        {
            DeAI.App.Ui.Language = "zh";
            foreach (var (native, key) in new[] { ("Grammar", "grammar"), ("AiToneZh", "ai_tone_zh"), ("AiToneEn", "ai_tone_en"), ("Markdown", "markdown"), ("Personal", "personal") })
            {
                Equal(key, DeAI.App.Ui.CategoryKey(native)); Equal(key, DeAI.App.Ui.CategoryKey(key));
                Equal(DeAI.App.Ui.Category(key), DeAI.App.Ui.Category(native));
            }
            var finding = new NativeChecker().Check("说白了，我们需要检查。", new(Grammar: false)).First();
            Equal("中文 AI 腔", DeAI.App.Ui.Category(finding.Category));
            DeAI.App.Ui.Language = "en"; Equal("Chinese AI tone", DeAI.App.Ui.Category("AiToneZh")); DeAI.App.Ui.Language = "zh";
        });
        Check("Legacy settings retain Mac appearance defaults and current key identity", () =>
        {
            var value = JsonSerializer.Deserialize<Preferences>("{\"language\":\"en\",\"options\":{\"sensitivity\":2}}", NativeChecker.Json)!;
            value.Validate(); Equal(1.2, value.Underline.Thickness); Equal("wavy", value.Underline.For("grammar").Shape); Equal("default", value.ActiveProviderId);
            Equal(0, value.Providers.Length); Equal(false, value.Group("browser").Enabled); Equal(true, value.Group("writing").Enabled);
        });
        Check("Underline appearance round-trip", () =>
        {
            var value = new Preferences { Underline = new UnderlineAppearance { Thickness = 2, Opacity = 0.5, Offset = -1, HighlightFill = true } };
            var copy = JsonSerializer.Deserialize<Preferences>(JsonSerializer.Serialize(value, NativeChecker.Json), NativeChecker.Json)!;
            copy.Validate(); Equal(value.Underline.Thickness, copy.Underline.Thickness); Equal(true, copy.Underline.HighlightFill);
        });
        Check("Invalid underline styles and nonfinite values rejected", () =>
        {
            Reject(() => new UnderlineAppearance { Thickness = double.NaN }.Validate());
            Reject(() => new UnderlineAppearance { Opacity = 1.2 }.Validate());
            Reject(() => new UnderlineAppearance { Offset = -3 }.Validate());
            Reject(() => new UnderlineAppearance { Styles = new() { ["grammar"] = new("red") } }.Validate());
            Reject(() => new UnderlineAppearance { Styles = new() { ["grammar"] = new("#123456", "unknown") } }.Validate());
        });
        Check("App group intersection cannot reenable globally disabled checks", () =>
        {
            var global = new CheckOptions(Grammar: false, Sensitivity: 1);
            var result = AppGroups.Intersect(global, new CheckOptions(AiToneZh: false, Sensitivity: 3));
            Equal(false, result.Grammar); Equal(false, result.AiToneZh); Equal((byte)1, result.Sensitivity);
            var preferences = new Preferences { Groups = new() { ["writing"] = new(false) } };
            Equal(false, preferences.AllowsProcess("NOTEPAD")); Equal(true, preferences.AllowsProcess("unknown-editor"));
        });
        Check("Invalid app groups and mismatched active provider rejected", () =>
        {
            Reject(() => new Preferences { Groups = new() { ["unknown"] = new() } }.Validate());
            Reject(() => new Preferences { ActiveProviderId = "../outside" }.Validate());
            Reject(() => new Preferences { Providers = new[] { new ProviderProfile("default", "Service", new("https://api.example.com/v1", "other")) } }.Validate());
        });
        Check("Provider profiles and DPAPI keys remain isolated", () =>
        {
            var path = Path.Combine(Path.GetTempPath(), "deai-profiles-" + Guid.NewGuid().ToString("N"));
            try
            {
                var store = new DataStore(path); var id = Guid.NewGuid().ToString("N");
                var first = new SecretStore(store); var second = new SecretStore(store, id);
                var a = Guid.NewGuid().ToString("N"); var b = Guid.NewGuid().ToString("N"); first.Save(a); second.Save(b);
                Equal(a, first.Read()); Equal(b, second.Read()); second.Delete(); Equal(true, first.HasKey); Equal(false, second.HasKey);
                Reject(() => new SecretStore(store, "../outside"));
                var preferences = new Preferences { Providers = new[] { new ProviderProfile("default", "Old", new()), new ProviderProfile(id, "Free", new("https://openrouter.ai/api/v1", "openrouter/free", "chat", true)) }, ActiveProviderId = id, Provider = new("https://openrouter.ai/api/v1", "openrouter/free", "chat", true) };
                store.Save("settings.json", preferences); store.Load("settings.json", new Preferences()).Validate();
                if (File.ReadAllText(Path.Combine(path, "settings.json")).Contains(a, StringComparison.Ordinal) || File.ReadAllText(Path.Combine(path, "settings.json")).Contains(b, StringComparison.Ordinal)) throw new Exception("Key leaked into settings");
            }
            finally { Directory.Delete(path, true); }
        });
        Check("English word diff produces safe replace pairs", () =>
        {
            var pair = RewriteDiff.Pairs("We delve into this.", "We explore this.").Single();
            Equal("delve into", pair.From); Equal("explore", pair.To); Equal(new PersonalEntry("replace", "delve into", "explore"), pair.Candidate());
        });
        Check("CJK diff preserves graphemes and pure deletions trim punctuation", () =>
        {
            var pair = RewriteDiff.Pairs("😀我们深入探讨问题。", "😀我们研究问题。").Single();
            Equal("深入探讨", pair.From); Equal("研究", pair.To);
            Equal(new PersonalEntry("avoid", "说白了", null), new RewritePair("说白了，", "").Candidate());
            Equal(null, new RewritePair("", "new").Candidate());
        });
        Check("Rewrite diff does not learn long document fragments", () =>
        {
            Equal(0, RewriteDiff.Pairs(new string('甲', 2000), new string('乙', 2000)).Count);
            Equal(0, RewriteDiff.Pairs("Already natural.", "Already natural.").Count);
        });
    }
}
