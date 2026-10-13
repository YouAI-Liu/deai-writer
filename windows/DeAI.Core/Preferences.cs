using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Security.Cryptography;

namespace DeAI;

public sealed record Hotkey(uint Modifiers, uint Key);
public sealed record Provider(string BaseUrl = "https://api.openai.com/v1", string Model = "gpt-4o-mini", string Format = "chat", bool FreeOnly = false);
public sealed record ProviderProfile(string Id, string Name, Provider Configuration);
public sealed record Preferences
{
    public string Language { get; init; } = "zh";
    public bool AutoCheck { get; init; } = true;
    public bool BrowsersEnabled { get; init; }
    public string[] ExcludedApps { get; init; } = Array.Empty<string>();
    public string[] DisabledRules { get; init; } = Array.Empty<string>();
    public CheckOptions Options { get; init; } = new();
    public UnderlineAppearance Underline { get; init; } = new();
    public Dictionary<string, AppGroupRule> Groups { get; init; } = new();
    public AppGroupRule Group(string key) => Groups.GetValueOrDefault(key) ?? new AppGroupRule(key != "browser" || BrowsersEnabled);
    public bool AllowsProcess(string process) => Group(AppGroups.ForProcess(process)).Enabled;
    public CheckOptions OptionsForProcess(string process) => AppGroups.Intersect(Options, Group(AppGroups.ForProcess(process)).Options);
    public Hotkey CheckHotkey { get; init; } = new(3, 0x78);
    public Hotkey RewriteHotkey { get; init; } = new(3, 0x79);
    public Provider Provider { get; init; } = new();
    public string ActiveProviderId { get; init; } = "default";
    public ProviderProfile[] Providers { get; init; } = Array.Empty<ProviderProfile>();
    public string ChineseSkill { get; init; } = Skill.BuiltinId;
    public string EnglishSkill { get; init; } = Skill.BuiltinId;

    public void Validate()
    {
        Underline.Validate();
        if (Groups.Count > 5 || Groups.Any(p => !AppGroups.Keys.Contains(p.Key) || p.Value == null))
            throw new InvalidOperationException("应用组设置无效。");
        if (Language is not ("zh" or "en") || Options.Sensitivity is < 1 or > 3)
            throw new InvalidOperationException("无效的语言或灵敏度设置。");
        foreach (var key in new[] { CheckHotkey, RewriteHotkey })
            if (key.Modifiers is < 1 or > 15 || key.Key is < 0x30 or > 0x87) throw new InvalidOperationException("无效的快捷键。");
        if (CheckHotkey == RewriteHotkey) throw new InvalidOperationException("检查与改写快捷键不能相同。");
        RewriteClient.Endpoint(Provider);
        if (string.IsNullOrWhiteSpace(Provider.Model) || Provider.Model.Length > 200) throw new InvalidOperationException("请输入模型名称。");
        if (Providers.Length > 20 || Providers.Select(p => p.Id).Distinct().Count() != Providers.Length ||
            Providers.Any(p => (p.Id != "default" && !Guid.TryParseExact(p.Id, "N", out _)) || string.IsNullOrWhiteSpace(p.Name) || p.Name.Length > 100) ||
            (Providers.Length == 0 ? ActiveProviderId != "default" : !Providers.Any(p => p.Id == ActiveProviderId && p.Configuration == Provider)))
            throw new InvalidOperationException("服务配置列表无效。");
        foreach (var profile in Providers)
        {
            RewriteClient.Endpoint(profile.Configuration);
            if (string.IsNullOrWhiteSpace(profile.Configuration.Model) || profile.Configuration.Model.Length > 200)
                throw new InvalidOperationException("请输入模型名称。");
        }
    }
}

public sealed class DataStore
{
    public static string DefaultDirectory => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DeAI");
    public string DirectoryPath { get; }
    public DataStore(string? directory = null) { DirectoryPath = directory ?? DefaultDirectory; Directory.CreateDirectory(DirectoryPath); }
    public T Load<T>(string name, T fallback)
    {
        var path = Path.Combine(DirectoryPath, name);
        if (!File.Exists(path)) return fallback;
        if (new FileInfo(path).Length > 4_000_000) throw new InvalidOperationException("配置文件过大。");
        return JsonSerializer.Deserialize<T>(File.ReadAllText(path), NativeChecker.Json)
            ?? throw new InvalidOperationException("配置文件无效；未覆盖原文件。");
    }
    public void Save<T>(string name, T value) => Write(Path.Combine(DirectoryPath, name), JsonSerializer.SerializeToUtf8Bytes(value, NativeChecker.Json));
    internal static void Write(string path, byte[] bytes)
    {
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            { file.Write(bytes); file.Flush(true); }
            if (File.Exists(path)) File.Replace(temporary, path, null); else File.Move(temporary, path);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
    public static void ValidateLexicon(IReadOnlyList<PersonalEntry> entries)
    {
        if (entries.Count > 200) throw new InvalidOperationException("个人词库上限 200 条。");
        foreach (var entry in entries)
            if (entry.Kind is not ("replace" or "avoid" or "keep") || entry.MatchKind is not ("exact" or "caseInsensitive" or "wholeWord")
                || string.IsNullOrWhiteSpace(entry.Term) || entry.Term.Length > 100
                || (entry.Kind == "replace" && string.IsNullOrEmpty(entry.Replacement)) || entry.Replacement?.Length > 100)
                throw new InvalidOperationException("词条无效：term 上限 100；replace 需要 replacement；检查 kind/matchKind。");
    }
}

public sealed class SecretStore
{
    private readonly string path;
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("DeAI.Windows.Provider.v1");
    public SecretStore(DataStore store, string providerId = "default")
    {
        if (providerId != "default" && !Guid.TryParseExact(providerId, "N", out _)) throw new InvalidOperationException("无效的服务标识。");
        path = Path.Combine(store.DirectoryPath, providerId == "default" ? "provider-key.dpapi" : "provider-key-" + providerId + ".dpapi");
    }
    public bool HasKey => File.Exists(path);
    public void Save(string key)
    {
        if (string.IsNullOrWhiteSpace(key)) { Delete(); return; }
        if (key.Length > 4096 || key.Any(char.IsWhiteSpace) || key.Any(char.IsControl)) throw new InvalidOperationException("密钥格式无效；不得包含空白或控制字符。");
        var bytes = Encoding.UTF8.GetBytes(key);
        try { DataStore.Write(path, ProtectedData.Protect(bytes, Entropy, DataProtectionScope.CurrentUser)); }
        finally { CryptographicOperations.ZeroMemory(bytes); }
    }
    public string? Read()
    {
        if (!HasKey) return null;
        if (new FileInfo(path).Length > 32_000) throw new InvalidOperationException("密钥文件无效。");
        var bytes = ProtectedData.Unprotect(File.ReadAllBytes(path), Entropy, DataProtectionScope.CurrentUser);
        try { return Encoding.UTF8.GetString(bytes); }
        finally { CryptographicOperations.ZeroMemory(bytes); }
    }
    public void Delete() { if (HasKey) File.Delete(path); }
}
