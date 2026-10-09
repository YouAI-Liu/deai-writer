using System;
using System.Collections.Generic;
using Interop.UIAutomationClient;

namespace DeAI.Automation;

public sealed record TextSpan(int Start, int End);
public sealed record ScreenRect(double X, double Y, double Width, double Height);

public sealed class TextTarget
{
    private const int EditControl = 50004, DocumentControl = 50030, WindowControl = 50032;
    private const int TextPatternId = 10014, ValuePatternId = 10002;
    private readonly IUIAutomationElement element;
    private readonly IUIAutomationTextPattern? pattern;
    private readonly IUIAutomationValuePattern? value;
    private readonly int pid;
    private readonly int[] runtimeId;
    public string Original { get; }
    public string ProcessName { get; }
    public TextSpan? Selection { get; }
    public bool CanWrite { get; }
    public IntPtr WindowHandle { get; }

    public static IUIAutomation CreateAutomation()
    {
        var automation = new CUIAutomation8();
        ((IUIAutomation2)automation).ConnectionTimeout = 2000;
        ((IUIAutomation2)automation).TransactionTimeout = 2000;
        return automation;
    }

    private TextTarget(IUIAutomationElement element, IUIAutomation automation)
    {
        this.element = element;
        pid = element.CurrentProcessId;
        runtimeId = element.GetRuntimeId();
        ProcessName = AppPolicy.ProcessName(pid);
        pattern = element.GetCurrentPattern(TextPatternId) as IUIAutomationTextPattern;
        value = element.GetCurrentPattern(ValuePatternId) as IUIAutomationValuePattern;
        Original = Read();
        WindowHandle = OwnerWindow(element, automation);
        // Only plain Edit providers are eligible; Document/RichEdit is never flattened.
        CanWrite = Writable() && string.Equals(value!.CurrentValue, Original, StringComparison.Ordinal);
        Selection = ReadSelection();
    }

    public static TextTarget? Focused(IUIAutomation automation, bool browsersEnabled = false, IEnumerable<string>? excluded = null)
    {
        var focused = automation.GetFocusedElement();
        if (focused == null) return null;
        if (!AppPolicy.IsAllowed(focused.CurrentProcessId, browsersEnabled, excluded)) return null;
        for (var node = focused; node != null; node = automation.ControlViewWalker.GetParentElement(node))
        {
            if (node.CurrentIsPassword != 0) return null;
            if (node.CurrentControlType == WindowControl) break;
        }
        var candidate = focused;
        for (var i = 0; candidate != null && i < 6; i++)
        {
            if (candidate.CurrentProcessId != focused.CurrentProcessId) return null;
            if (candidate.CurrentControlType == EditControl || candidate.CurrentControlType == DocumentControl)
                return Capture(candidate, automation, browsersEnabled, excluded);
            if (candidate.CurrentControlType == WindowControl) break;
            candidate = automation.ControlViewWalker.GetParentElement(candidate);
        }
        return null;
    }

    public static TextTarget? Capture(IUIAutomationElement element, IUIAutomation automation, bool browsersEnabled = false, IEnumerable<string>? excluded = null)
    {
        var info = element;
        if (info.CurrentControlType != EditControl && info.CurrentControlType != DocumentControl) return null;
        if (info.CurrentIsPassword != 0 || info.CurrentIsEnabled == 0 || info.CurrentIsOffscreen != 0 || !AppPolicy.IsAllowed(info.CurrentProcessId, browsersEnabled, excluded)) return null;
        if (element.GetCurrentPattern(TextPatternId) == null && element.GetCurrentPattern(ValuePatternId) == null) return null;
        return new TextTarget(element, automation);
    }

    private string Read()
    {
        if (element.CurrentIsPassword != 0) throw new InvalidOperationException("拒绝读取密码字段。");
        var text = pattern?.DocumentRange.GetText(TextSafety.MaxTextLength + 1) ?? value?.CurrentValue
            ?? throw new InvalidOperationException("应用未提供可读文本。");
        if (text.Length > TextSafety.MaxTextLength) throw new InvalidOperationException("文本超过安全长度限制。");
        return text;
    }

    public void Validate()
    {
        if (element.CurrentProcessId != pid || !SameId(runtimeId, element.GetRuntimeId()) || element.CurrentIsEnabled == 0)
            throw new InvalidOperationException("目标已失效。");
        if (!string.Equals(Read(), Original, StringComparison.Ordinal))
            throw new InvalidOperationException("原文已变化，请重新检查。");
    }

    private static bool SameId(int[] a, int[] b) => a.AsSpan().SequenceEqual(b);

    public bool SameTarget(TextTarget other) => pid == other.pid && SameId(runtimeId, other.runtimeId);
    public bool IsAllowed(bool browsersEnabled, IEnumerable<string> excluded) => AppPolicy.IsAllowed(pid, browsersEnabled, excluded);
    private bool Writable() => value != null && value.CurrentIsReadOnly == 0 && element.CurrentControlType == EditControl
        && ((element.CurrentFrameworkId == "WPF" && element.CurrentClassName == "TextBox") || element.CurrentClassName == "Edit");

    private TextSpan? ReadSelection()
    {
        if (pattern == null) return null;
        var selections = pattern.GetSelection();
        if (selections.Length != 1) return null;
        var selected = selections.GetElement(0);
        var text = selected.GetText(TextSafety.MaxTextLength + 1);
        var prefix = pattern.DocumentRange.Clone();
        prefix.MoveEndpointByRange(TextPatternRangeEndpoint.TextPatternRangeEndpoint_End, selected, TextPatternRangeEndpoint.TextPatternRangeEndpoint_Start);
        var start = prefix.GetText(TextSafety.MaxTextLength + 1).Length;
        var end = start + text.Length;
        if (end > Original.Length || !TextSafety.IsBoundary(Original, start) || !TextSafety.IsBoundary(Original, end) || !Original.AsSpan(start, text.Length).SequenceEqual(text)) return null;
        return new TextSpan(start, end);
    }

    private IUIAutomationTextRange Endpoint(int offset)
    {
        if (pattern == null || !TextSafety.IsBoundary(Original, offset)) throw new InvalidOperationException("应用未提供可定位文本范围。");
        // UIA Character units need not be UTF-16 units. Verify the exact prefix rather than assuming a 1:1 mapping.
        var low = 0;
        var high = Original.Length;
        while (low <= high)
        {
            var units = low + (high - low) / 2;
            var prefix = pattern.DocumentRange.Clone();
            prefix.MoveEndpointByRange(TextPatternRangeEndpoint.TextPatternRangeEndpoint_End, prefix, TextPatternRangeEndpoint.TextPatternRangeEndpoint_Start);
            prefix.MoveEndpointByUnit(TextPatternRangeEndpoint.TextPatternRangeEndpoint_End, TextUnit.TextUnit_Character, units);
            var text = prefix.GetText(TextSafety.MaxTextLength + 1);
            if (text.Length == offset && string.Equals(text, Original[..offset], StringComparison.Ordinal)) return prefix;
            if (text.Length < offset) low = units + 1; else high = units - 1;
        }
        throw new InvalidOperationException("无法验证应用的 UTF-16 位置映射。");
    }

    private IUIAutomationTextRange Range(int start, int end)
    {
        Validate();
        if (end < start) throw new InvalidOperationException("无效范围。");
        var from = Endpoint(start);
        var to = Endpoint(end);
        from.MoveEndpointByRange(TextPatternRangeEndpoint.TextPatternRangeEndpoint_Start, from, TextPatternRangeEndpoint.TextPatternRangeEndpoint_End);
        from.MoveEndpointByRange(TextPatternRangeEndpoint.TextPatternRangeEndpoint_End, to, TextPatternRangeEndpoint.TextPatternRangeEndpoint_End);
        if (!string.Equals(from.GetText(TextSafety.MaxTextLength + 1), Original[start..end], StringComparison.Ordinal))
            throw new InvalidOperationException("文本范围校验失败。");
        return from;
    }

    public IReadOnlyList<ScreenRect> Locate(int start, int end)
    {
        var coordinates = Range(start, end).GetBoundingRectangles();
        var result = new List<ScreenRect>();
        for (var i = 0; i + 3 < coordinates.Length; i += 4)
            if (coordinates[i + 2] > 0 && coordinates[i + 3] > 0)
                result.Add(new ScreenRect(coordinates[i], coordinates[i + 1], coordinates[i + 2], coordinates[i + 3]));
        return result;
    }

    public void Select(int start, int end)
    {
        var range = Range(start, end);
        range.Select();
    }

    public void Replace(int start, int end, string replacement)
    {
        Validate();
        if (!CanWrite || !Writable())
            throw new InvalidOperationException("此应用未提供已验证的纯文本安全写回能力；请手动复制建议。");
        var expected = TextSafety.Replace(Original, value!.CurrentValue, start, end, replacement);
        // No clipboard, simulated keystrokes or fallback on failure: never write into a different focus target.
        Validate();
        value.SetValue(expected);
        if (!string.Equals(Read(), expected, StringComparison.Ordinal))
            throw new InvalidOperationException("写回结果与预期不符；请检查文档，未尝试重试或回滚。");
    }

    private static IntPtr OwnerWindow(IUIAutomationElement node, IUIAutomation automation)
    {
        for (var i = 0; i < 20; i++)
        {
            if (node.CurrentControlType == WindowControl && node.CurrentNativeWindowHandle != IntPtr.Zero)
                return node.CurrentNativeWindowHandle;
            var parent = automation.ControlViewWalker.GetParentElement(node);
            if (parent == null) break;
            node = parent;
        }
        return IntPtr.Zero;
    }
}
