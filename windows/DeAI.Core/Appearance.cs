using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace DeAI;

public sealed record UnderlineStyle(string Color = "", string Shape = "straight");
public sealed record UnderlineAppearance
{
    public Dictionary<string, UnderlineStyle> Styles { get; init; } = new()
    {
        ["grammar"] = new("", "wavy"),
        ["ai_tone_zh"] = new(),
        ["ai_tone_en"] = new(),
        ["markdown"] = new(),
        ["personal"] = new()
    };
    public double Thickness { get; init; } = 1.2;
    public double Opacity { get; init; } = 1;
    public double Offset { get; init; } = 1;
    public bool DimLowConfidence { get; init; } = true;
    public bool HighlightFill { get; init; }
    public UnderlineStyle For(string category) => Styles.GetValueOrDefault(category) ?? new("", category == "grammar" ? "wavy" : "straight");
    public void Validate()
    {
        if (!double.IsFinite(Thickness) || Thickness is < 0.5 or > 4 ||
            !double.IsFinite(Opacity) || Opacity is < 0.2 or > 1 || !double.IsFinite(Offset) || Offset is < -2 or > 4 ||
            Styles.Count > 5 || Styles.Values.Any(s => s.Shape is not ("straight" or "wavy" or "dashed" or "dotted") ||
                (s.Color != "" && !Regex.IsMatch(s.Color, "^#[0-9a-fA-F]{6}$"))))
            throw new InvalidOperationException("下划线外观设置无效。");
    }
}

public sealed record AppGroupRule(bool Enabled = true, CheckOptions? Options = null);
public static class AppGroups
{
    public static readonly string[] Keys = { "writing", "chat", "browser", "code", "other" };
    private static readonly Dictionary<string, string> Processes = new(StringComparer.OrdinalIgnoreCase)
    {
        ["notepad"] = "writing",
        ["WINWORD"] = "writing",
        ["EXCEL"] = "writing",
        ["POWERPNT"] = "writing",
        ["Obsidian"] = "writing",
        ["Notion"] = "writing",
        ["WeChat"] = "chat",
        ["Weixin"] = "chat",
        ["Slack"] = "chat",
        ["Teams"] = "chat",
        ["ms-teams"] = "chat",
        ["Discord"] = "chat",
        ["Telegram"] = "chat",
        ["chrome"] = "browser",
        ["msedge"] = "browser",
        ["firefox"] = "browser",
        ["brave"] = "browser",
        ["opera"] = "browser",
        ["vivaldi"] = "browser",
        ["Code"] = "code",
        ["devenv"] = "code",
        ["idea64"] = "code",
        ["notepad++"] = "code",
        ["sublime_text"] = "code"
    };
    public static string ForProcess(string name) => Processes.GetValueOrDefault(name) ?? "other";
    public static CheckOptions Intersect(CheckOptions global, CheckOptions? group) => group == null ? global : new(
        global.Grammar && group.Grammar, global.AiToneEn && group.AiToneEn, global.AiToneZh && group.AiToneZh,
        global.Markdown && group.Markdown, global.Personal && group.Personal, global.Sensitivity);
}
