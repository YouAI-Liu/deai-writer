using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;

namespace DeAI;

public sealed record Skill(string Id, string Name, string Description, string Language, string Body)
{
    public const string BuiltinId = "builtin.deai-default";
    public static Skill Builtin => new(BuiltinId, "DeAI 默认 / Default", "", "any",
        "只修改有 AI 腔的地方；自然的句子原样保留。不改变事实、数字、日期、专有名词或限定语。去除套话、空洞开场、夸大词、刻意对比、凑数排比和对话残留。");
    public override string ToString() => Name + " [" + Language + "]";
}

public sealed class SkillStore
{
    private readonly string directory;
    public SkillStore(DataStore store) { directory = Path.Combine(store.DirectoryPath, "skills"); Directory.CreateDirectory(directory); }
    public IReadOnlyList<Skill> Load()
    {
        var result = new List<Skill> { Skill.Builtin };
        foreach (var path in Directory.EnumerateFiles(directory, "*.md").Take(200))
            result.Add(Parse(Read(path), Path.GetFileNameWithoutExtension(path), Path.GetFileNameWithoutExtension(path)));
        return result;
    }
    private static string Read(string path)
    {
        if (new FileInfo(path).Length > 300_000) throw new InvalidOperationException("Skill 文件过大。");
        return File.ReadAllText(path, Encoding.UTF8);
    }
    public Skill Import(string path)
    {
        if (Directory.Exists(path)) path = Path.Combine(path, "SKILL.md");
        if (!string.Equals(Path.GetExtension(path), ".md", StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("请选择 Markdown / SKILL.md。");
        var content = Read(path);
        var id = Guid.NewGuid().ToString("N");
        var skill = Parse(content, id, Path.GetFileNameWithoutExtension(path));
        DataStore.Write(Path.Combine(directory, id + ".md"), Encoding.UTF8.GetBytes(content));
        return skill;
    }
    public void Delete(Skill skill)
    {
        if (!Guid.TryParseExact(skill.Id, "N", out _)) throw new InvalidOperationException("内置 Skill 不可删除。");
        File.Delete(Path.Combine(directory, skill.Id + ".md"));
    }
    public void Save(Skill skill)
    {
        if (!Guid.TryParseExact(skill.Id, "N", out _)) throw new InvalidOperationException("内置 Skill 不可编辑。");
        var name = skill.Name.Replace('\r', ' ').Replace('\n', ' ').Replace('"', '\'');
        var description = skill.Description.Replace('\r', ' ').Replace('\n', ' ').Replace('"', '\'');
        var content = "---\nname: \"" + name + "\"\ndescription: \"" + description + "\"\nlanguage: " + skill.Language + "\n---\n" + skill.Body;
        Parse(content, skill.Id, name);
        DataStore.Write(Path.Combine(directory, skill.Id + ".md"), Encoding.UTF8.GetBytes(content));
    }
    public static Skill Resolve(IEnumerable<Skill> skills, string id, string language) =>
        skills.FirstOrDefault(s => s.Id == id && (s.Language == "any" || s.Language == language)) ?? Skill.Builtin;
    public static Skill Parse(string content, string id, string fallbackName)
    {
        var body = content.Replace("\r\n", "\n").TrimStart('\uFEFF');
        var name = fallbackName; var description = ""; var language = "any";
        if (body.StartsWith("---\n", StringComparison.Ordinal))
        {
            var end = body.IndexOf("\n---", 4, StringComparison.Ordinal);
            if (end < 0) throw new InvalidOperationException("Skill frontmatter 未闭合。");
            foreach (var line in body[4..end].Split('\n'))
            {
                var split = line.IndexOf(':'); if (split < 0) continue;
                var value = line[(split + 1)..].Trim().Trim('\"', '\'');
                switch (line[..split].Trim()) { case "name": name = value; break; case "description": description = value; break; case "language": language = value; break; }
            }
            body = body[(end + 4)..].TrimStart('\n');
        }
        if (string.IsNullOrWhiteSpace(name) || string.IsNullOrWhiteSpace(body)) throw new InvalidOperationException("Skill 名称和正文不能为空。");
        if (body.Length > 60_000) throw new InvalidOperationException("Skill 正文上限 60,000 UTF-16 字符。");
        if (language is not ("zh" or "en" or "any")) language = "any";
        return new Skill(id, name, description, language, body);
    }
    public static string LanguageOf(string text)
    {
        var cjk = text.Count(c => c is >= '\u4E00' and <= '\u9FFF' or >= '\u3400' and <= '\u4DBF' or >= '\uF900' and <= '\uFAFF');
        var latin = text.Count(c => c is >= 'a' and <= 'z' or >= 'A' and <= 'Z');
        return cjk > 0 && cjk * 3 >= latin ? "zh" : "en";
    }
}
