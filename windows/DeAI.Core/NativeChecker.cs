using System;
using System.Collections.Generic;
using System.Linq;
using DeAI.Automation;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace DeAI;

public sealed record Finding(
    string Category,
    [property: JsonPropertyName("rule_id")] string RuleId,
    string Message, int Start, int End, string[] Suggestions, byte Tier);

public sealed record CheckOptions(
    bool Grammar = true,
    [property: JsonPropertyName("ai_tone_en")] bool AiToneEn = true,
    [property: JsonPropertyName("ai_tone_zh")] bool AiToneZh = true,
    bool Markdown = true, bool Personal = true, byte Sensitivity = 2);

public sealed record PersonalEntry(string Kind, string Term, string? Replacement, string MatchKind = "exact");

public sealed class NativeChecker
{
    public static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, PropertyNameCaseInsensitive = true, WriteIndented = true };
    private sealed record Response(Finding[] Findings, string? Error);

    public IReadOnlyList<Finding> Check(string text, CheckOptions options, IReadOnlyList<PersonalEntry>? entries = null)
    {
        if (text.Length > TextSafety.MaxTextLength || options.Sensitivity is < 1 or > 3) throw new InvalidOperationException("检查参数超出安全范围。");
        DataStore.ValidateLexicon(entries ?? Array.Empty<PersonalEntry>());
        var input = JsonSerializer.SerializeToUtf8Bytes(new { text, options, entries = entries ?? Array.Empty<PersonalEntry>() }, Json);
        var pointer = CheckJson(input, (nuint)input.Length);
        if (pointer == IntPtr.Zero) throw new InvalidOperationException("Rust 检查失败。");
        try
        {
            var response = JsonSerializer.Deserialize<Response>(Marshal.PtrToStringUTF8(pointer)!, Json)
                ?? throw new InvalidOperationException("Rust 响应为空。");
            if (response.Error != null) throw new InvalidOperationException("Rust 检查失败：" + response.Error);
            if (response.Findings.Any(f => f.End < f.Start || !TextSafety.IsBoundary(text, f.Start) || !TextSafety.IsBoundary(text, f.End)))
                throw new InvalidOperationException("Rust 返回无效 UTF-16 范围。");
            return response.Findings;
        }
        finally { FreeJson(pointer); }
    }

    [DllImport("deai_native", EntryPoint = "deai_check_json", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr CheckJson(byte[] input, nuint length);
    [DllImport("deai_native", EntryPoint = "deai_free_json", CallingConvention = CallingConvention.Cdecl)]
    private static extern void FreeJson(IntPtr pointer);
}
