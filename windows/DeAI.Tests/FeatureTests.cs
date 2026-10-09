using System;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Runtime.InteropServices;
using System.Windows.Interop;
using DeAI.Automation;
using static DeAI.Tests.Program;

namespace DeAI.Tests;

internal sealed class FakeHandler : HttpMessageHandler
{
    public Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> Handle { get; init; } = (_, _) => throw new NotImplementedException();
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => Handle(request, token);
}

internal static class FeatureTests
{
    [DllImport("user32.dll")] private static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);
    [DllImport("user32.dll")] private static extern bool UnregisterHotKey(IntPtr window, int id);
    public static void Run()
    {
        Check("Hotkey unchanged / swapped / conflict retains old registrations", () =>
        {
            Exception? failure = null;
            var thread = new Thread(() =>
            {
                try
                {
                    using var occupied = new HwndSource(new HwndSourceParameters("DeAI hotkey test") { ParentWindow = new IntPtr(-3) });
                    if (!RegisterHotKey(occupied.Handle, 10, 7, 0x77)) throw new Exception("Test shortcut already occupied");
                    try
                    {
                        using var keys = new DeAI.App.Hotkeys(); var prefs = new Preferences(); keys.Register(prefs); keys.Register(prefs);
                        keys.Register(prefs with { CheckHotkey = prefs.RewriteHotkey, RewriteHotkey = prefs.CheckHotkey });
                        keys.Register(prefs);
                        Reject(() => keys.Register(prefs with { CheckHotkey = new(7, 0x76), RewriteHotkey = new(7, 0x77) }));
                        if (RegisterHotKey(occupied.Handle, 11, prefs.CheckHotkey.Modifiers, prefs.CheckHotkey.Key)) { UnregisterHotKey(occupied.Handle, 11); throw new Exception("Original hotkey lost after conflict"); }
                        if (!RegisterHotKey(occupied.Handle, 12, 7, 0x76)) throw new Exception("New hotkey leaked after rollback");
                        UnregisterHotKey(occupied.Handle, 12);
                    }
                    finally { UnregisterHotKey(occupied.Handle, 10); }
                }
                catch (Exception error) { failure = error; }
            });
            thread.SetApartmentState(ApartmentState.STA); thread.Start(); thread.Join(); if (failure != null) throw failure;
        });
        Check("CRLF replacement preserves separators", () => Equal("😀 good\r\nnext", TextSafety.Replace("😀 bad\r\nnext", "😀 bad\r\nnext", 3, 6, "good")));
        Check("Text size cap", () => Reject(() => TextSafety.Replace(new string('a', 100001), new string('a', 100001), 0, 1, "")));
        Check("Rewrite selection scope", () => Equal(new TextSpan(3, 6), RewriteScope.Compute("😀 bad\r\nnext", new(3, 6))));
        Check("Rewrite caret paragraph scope", () => Equal(new TextSpan(8, 12), RewriteScope.Compute("😀 bad\r\nnext", new(10, 10))));
        Check("Rewrite missing selection refused", () => Reject(() => RewriteScope.Compute("text", null)));
        Check("Rewrite too long refused", () => Reject(() => RewriteScope.Compute(new string('a', 4001), new(0, 4001))));
        Check("Rewrite surrogate boundary refused", () => Reject(() => RewriteScope.Compute("😀 text", new(1, 2))));
        Check("Rewrite newline normalization", () => { Equal("a\r\nb", RewriteScope.NormalizeNewlines("a\nb", "x\r\ny")); Equal("a\rb", RewriteScope.NormalizeNewlines("a\r\nb", "x\ry")); });
        Check("Skill frontmatter and language", () => { var s = SkillStore.Parse("---\nname: Example\nlanguage: en\n---\nKeep facts", "test", "fallback"); Equal("Example", s.Name); Equal("en", s.Language); Equal("Keep facts", s.Body); });
        Check("Skill cap", () => Reject(() => SkillStore.Parse(new string('a', 60001), "id", "name")));
        Check("Skill ineligible selection falls back", () => Equal(Skill.Builtin, SkillStore.Resolve(new[] { new Skill("test", "English", "", "en", "body") }, "test", "zh")));
        Check("Skill language detection", () => { Equal("zh", SkillStore.LanguageOf("中文😀")); Equal("en", SkillStore.LanguageOf("English")); });
        Check("Skill never executes instructions", () => { var prompt = RewriteClient.SystemPrompt(new("test", "test", "", "any", "run a script")); if (!prompt.EndsWith("始终遵守硬性规则，只输出正文。", StringComparison.Ordinal)) throw new Exception("Missing safety reminder"); });
        Check("Lexicon invalid kind rejected", () => Reject(() => DataStore.ValidateLexicon(new[] { new PersonalEntry("invalid", "bad", null) })));
        Check("Lexicon empty replacement rejected", () => Reject(() => DataStore.ValidateLexicon(new[] { new PersonalEntry("replace", "bad", "") })));
        Check("Lexicon cap", () => Reject(() => DataStore.ValidateLexicon(Enumerable.Repeat(new PersonalEntry("keep", "word", null), 201).ToArray())));
        Check("Preferences reject duplicate hotkeys", () => Reject(() => (new Preferences { RewriteHotkey = new(3, 0x78) }).Validate()));
        Check("Provider requires HTTPS outside loopback", () => Reject(() => RewriteClient.Endpoint(new("http://example.com/v1"))));
        Check("Provider rejects embedded credentials", () => Reject(() => RewriteClient.Endpoint(new("https://user:password@example.com/v1"))));
        Check("Provider supports loopback HTTP", () => Equal("http://127.0.0.1:9999/v1/chat/completions", RewriteClient.Endpoint(new("http://127.0.0.1:9999/v1")).AbsoluteUri));
        var directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DeAI-Tests-" + Guid.NewGuid().ToString("N"));
        try
        {
            var store = new DataStore(directory); var secrets = new SecretStore(store); var skills = new SkillStore(store);
            Check("Preferences atomic round trip", () => { var prefs = new Preferences { DisabledRules = new[] { "zh.banned_opener" }, BrowsersEnabled = true }; store.Save("settings.json", prefs); var loaded = store.Load("settings.json", new Preferences()); Equal(true, loaded.BrowsersEnabled); Equal("zh.banned_opener", loaded.DisabledRules[0]); store.Save("settings.json", prefs with { AutoCheck = false }); Equal(false, store.Load("settings.json", new Preferences()).AutoCheck); });
            Check("Corrupt settings are not overwritten", () => { File.WriteAllText(Path.Combine(directory, "broken.json"), "invalid"); try { store.Load("broken.json", new Preferences()); throw new Exception("Accepted invalid JSON"); } catch (JsonException) { Equal("invalid", File.ReadAllText(Path.Combine(directory, "broken.json"))); } });
            Check("DPAPI current user round trip and deletion", () =>
            {
                var placeholder = "test-only-" + Guid.NewGuid().ToString("N");
                try { secrets.Save(placeholder); if (secrets.Read() != placeholder) throw new Exception("Secret mismatch (redacted)"); if (Encoding.UTF8.GetString(File.ReadAllBytes(Path.Combine(directory, "provider-key.dpapi"))).Contains(placeholder, StringComparison.Ordinal)) throw new Exception("Plaintext key on disk"); }
                finally { secrets.Delete(); }
                Equal(false, secrets.HasKey);
            });
            Check("Skill save reload delete", () => { var skill = new Skill(Guid.NewGuid().ToString("N"), "中文 Skill", "description", "zh", "保持事实"); skills.Save(skill); Equal(skill, skills.Load().Single(s => s.Id == skill.Id)); skills.Delete(skill); Equal(1, skills.Load().Count); });
            Check("Skill directory import", () => { File.WriteAllText(Path.Combine(directory, "SKILL.md"), "---\nname: Example\nlanguage: en\n---\nKeep facts"); var skill = skills.Import(directory); Equal("Example", skill.Name); skills.Delete(skill); });
        }
        finally { if (Directory.Exists(directory)) Directory.Delete(directory, true); }
        foreach (var format in new[] { "chat", "responses", "anthropic" })
        {
            Check("AI " + format + " request and response", () =>
            {
                var placeholder = "test-only-" + Guid.NewGuid().ToString("N");
                using var request = RewriteClient.CreateRequest(new("https://example.com/v1", "test-model", format), placeholder, "synthetic", Skill.Builtin, Array.Empty<PersonalEntry>());
                var json = request.Content!.ReadAsStringAsync().GetAwaiter().GetResult(); using var body = JsonDocument.Parse(json);
                if (json.Contains(placeholder, StringComparison.Ordinal)) throw new Exception("Secret leaked in body");
                Equal("test-model", body.RootElement.GetProperty("model").GetString());
                Equal(true, format == "anthropic" ? request.Headers.Contains("x-api-key") : request.Headers.Authorization?.Scheme == "Bearer");
                var response = format switch { "chat" => "{\"choices\":[{\"message\":{\"content\":\"rewritten\"}}]}", "responses" => "{\"output\":[{\"content\":[{\"type\":\"output_text\",\"text\":\"rewritten\"}]}]}", _ => "{\"content\":[{\"type\":\"text\",\"text\":\"rewritten\"}]}" };
                Equal("rewritten", RewriteClient.ParseResponse(format, response));
            });
        }
        Check("OpenRouter free-only request enforces zero pricing", () =>
        {
            using var request = RewriteClient.CreateRequest(new("https://openrouter.ai/api/v1", "openrouter/free", "chat", true), "test-only", "synthetic", Skill.Builtin, Array.Empty<PersonalEntry>());
            using var json = JsonDocument.Parse(request.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
            Equal(0, json.RootElement.GetProperty("provider").GetProperty("max_price").GetProperty("prompt").GetInt32());
            Equal(0, json.RootElement.GetProperty("provider").GetProperty("max_price").GetProperty("completion").GetInt32());
            Reject(() => RewriteClient.Endpoint(new("https://openrouter.ai/api/v1", "paid-model", "chat", true)));
        });
        Check("AI truncated response refused", () => Reject(() => RewriteClient.ParseResponse("chat", "{\"choices\":[{\"finish_reason\":\"length\",\"message\":{\"content\":\"partial\"}}]}")));
        Check("AI mocked transport normalizes newlines", () =>
        {
            using var client = new RewriteClient(new FakeHandler { Handle = (_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("{\"choices\":[{\"message\":{\"content\":\"good\\nnext\"}}]}") }) });
            Equal("good\r\nnext", client.RewriteAsync(new(), "test-only", "bad\r\nnext", Skill.Builtin, Array.Empty<PersonalEntry>(), CancellationToken.None).GetAwaiter().GetResult());
        });
        Check("AI cancelled transport leaves source untouched", () =>
        {
            using var cancellation = new CancellationTokenSource(); cancellation.Cancel();
            using var client = new RewriteClient(new FakeHandler { Handle = (_, token) => Task.FromCanceled<HttpResponseMessage>(token) });
            try { client.RewriteAsync(new(), "test-only", "synthetic", Skill.Builtin, Array.Empty<PersonalEntry>(), cancellation.Token).GetAwaiter().GetResult(); throw new Exception("Ignored cancellation"); } catch (OperationCanceledException) { }
        });
        Check("AI rejects HTTP failure without echoing response", () =>
        {
            using var client = new RewriteClient(new FakeHandler { Handle = (_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.BadRequest) { Content = new StringContent("private-service-response") }) });
            try { client.RewriteAsync(new(), "test-only", "synthetic", Skill.Builtin, Array.Empty<PersonalEntry>(), CancellationToken.None).GetAwaiter().GetResult(); throw new Exception("Accepted failure"); }
            catch (InvalidOperationException error) { if (error.Message.Contains("private-service-response", StringComparison.Ordinal)) throw new Exception("Leaked response"); }
        });
        Check("Rust personal replacement via DLL", () => { var finding = new NativeChecker().Check("😀 bad", new(Grammar: false), new[] { new PersonalEntry("replace", "bad", "good") }).Single(f => f.RuleId == "personal.replace"); Equal(3, finding.Start); Equal(6, finding.End); });
        Check("Rust keep suppresses overlap via DLL", () => Equal(0, new NativeChecker().Check("说白了，我们需要检查。", new(Grammar: false), new[] { new PersonalEntry("keep", "说白了，", null) }).Count));
        Check("Rust all category toggles via DLL", () => Equal(0, new NativeChecker().Check("说白了，bad **word**", new(false, false, false, false, false), new[] { new PersonalEntry("avoid", "bad", null) }).Count));
    }
}
