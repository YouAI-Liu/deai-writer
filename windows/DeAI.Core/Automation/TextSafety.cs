using System;

namespace DeAI.Automation;

public static class TextSafety
{
    public const int MaxTextLength = 100_000;

    public static bool IsBoundary(string text, int offset) => offset >= 0 && offset <= text.Length
        && !(offset > 0 && offset < text.Length && char.IsHighSurrogate(text[offset - 1]) && char.IsLowSurrogate(text[offset]));

    public static string Replace(string original, string current, int start, int end, string replacement)
    {
        if (!string.Equals(original, current, StringComparison.Ordinal))
            throw new InvalidOperationException("原文已变化，请重新检查。");
        if (end < start || !IsBoundary(original, start) || !IsBoundary(original, end))
            throw new InvalidOperationException("无效的 UTF-16 范围。");
        if (original.Length > MaxTextLength || replacement.Length > MaxTextLength)
            throw new InvalidOperationException("文本超过安全长度限制。");
        var result = original[..start] + replacement + original[end..];
        if (result.Length > MaxTextLength) throw new InvalidOperationException("结果超过安全长度限制。");
        return result;
    }
}
