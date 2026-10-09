using System;
using System.Diagnostics;
using System.Threading;
using Interop.UIAutomationClient;
using DeAI;
using DeAI.Automation;

namespace DeAI.Tests;

public static class Program
{
    private static int passed;
    private static int failed;
    public static void Check(string name, Action test)
    {
        try { test(); passed++; Console.WriteLine("PASS " + name); }
        catch (Exception e) { failed++; Console.WriteLine("FAIL " + name + ": " + e.Message); }
    }
    public static void Equal<T>(T expected, T actual) { if (!Equals(expected, actual)) throw new Exception($"Expected {expected}, got {actual}"); }
    public static void Reject(Action action) { try { action(); } catch (InvalidOperationException) { return; } throw new Exception("Unsafe operation was not rejected"); }

    [MTAThread]
    public static int Main(string[] args)
    {
        Check("UTF-16 emoji replacement", () => Equal("😀 good!", TextSafety.Replace("😀 bad!", "😀 bad!", 3, 6, "good")));
        Check("Surrogate split rejected", () => Reject(() => TextSafety.Replace("😀 bad", "😀 bad", 1, 2, "")));
        Check("Stale source rejected", () => Reject(() => TextSafety.Replace("bad", "edited", 0, 3, "good")));
        Check("Invalid range rejected", () => Reject(() => TextSafety.Replace("bad", "bad", 3, 0, "good")));
        FeatureTests.Run();
        AppearanceTests.Run();
        LayoutTests.Run(args.Length == 1 && args[0] != "--unit");
        if (args.Length == 1 && args[0] == "--unit") { Console.WriteLine($"UIA fixture not run: unit-only mode. Total: {passed} passed, {failed} failed"); return failed == 0 ? 0 : 1; }
        if (args.Length != 1) { Console.WriteLine("Pass fixture executable path to run UIA tests."); return 2; }
        using var fixture = Process.Start(new ProcessStartInfo(args[0]) { UseShellExecute = false })!;
        try
        {
            var automation = TextTarget.CreateAutomation();
            IUIAutomationElement? root = null;
            var timer = Stopwatch.StartNew();
            while (timer.Elapsed < TimeSpan.FromSeconds(20))
            {
                fixture.Refresh();
                if (fixture.MainWindowHandle != IntPtr.Zero) { root = automation.ElementFromHandle(fixture.MainWindowHandle); break; }
                Thread.Sleep(100);
            }
            if (root == null) throw new Exception("Fixture did not launch");
            IUIAutomationElement Find(string id) => root.FindFirst(TreeScope.TreeScope_Descendants, automation.CreatePropertyCondition(30011, id)) ?? throw new Exception("Missing " + id);
            var plain = Find("PlainText");
            var reset = (IUIAutomationInvokePattern)Find("Reset").GetCurrentPattern(10000);
            reset.Invoke();
            Thread.Sleep(150);
            var target = TextTarget.Capture(plain, automation)!;
            Finding? finding = null;
            Check("Rust DLL check via UIA", () => { foreach (var f in new NativeChecker().Check(target.Original, new CheckOptions(Grammar: false))) if (f.RuleId == "zh.banned_opener") finding = f; if (finding == null || finding.Start != 3) throw new Exception("Expected UTF-16 finding"); });
            Check("UIA read with emoji and CRLF", () => { if (!target.Original.StartsWith("😀 说白了，", StringComparison.Ordinal) || !target.Original.Contains("\r\n")) throw new Exception("Text changed"); });
            Check("UIA selection UTF-16", () => Equal(new TextSpan(3, 7), target.Selection));
            Check("UIA exact geometry after emoji", () => { if (target.Locate(3, 7).Count == 0) throw new Exception("No geometry"); });
            Check("UIA selection of second line", () => { var start = target.Original.IndexOf("It is", StringComparison.Ordinal); target.Select(start, start + 2); Equal(new TextSpan(start, start + 2), TextTarget.Capture(plain, automation)!.Selection); });
            Check("UIA safe write from Rust suggestion", () => { if (!target.CanWrite || finding == null) throw new Exception("Not writable / no finding"); target.Replace(finding.Start, finding.End, finding.Suggestions[0]); Equal("😀 我们需要认真检查。\r\nIt is worth noting that we delve into details.", TextTarget.Capture(plain, automation)!.Original); });
            Check("UIA stale write blocked", () => Reject(() => target.Replace(3, 7, "danger")));
            Check("UIA password not read", () => Equal<TextTarget?>(null, TextTarget.Capture(Find("Password"), automation)));
            Check("UIA rich text write blocked", () => { var rich = TextTarget.Capture(Find("RichText"), automation)!; Equal(false, rich.CanWrite); Reject(() => rich.Replace(0, 0, "danger")); });
            Check("UIA rewrite keeps selected paragraph terminator and next paragraph", () =>
            {
                const string first = "It is worth noting that our synthetic project has three steps.";
                const string second = "DO NOT CHANGE THIS SECOND PARAGRAPH.";
                ((IUIAutomationValuePattern)plain.GetCurrentPattern(10002)).SetValue(first + "\r\n" + second);
                var before = TextTarget.Capture(plain, automation)!;
                before.Select(0, first.Length + 2);
                var selected = TextTarget.Capture(plain, automation)!;
                Equal(new TextSpan(0, first.Length + 2), selected.Selection);
                var scope = RewriteScope.Compute(selected.Original, selected.Selection);
                Equal(new TextSpan(0, first.Length), scope);
                selected.Replace(scope.Start, scope.End, RewriteScope.ValidateResult("Our synthetic project has three steps.", selected.Original[scope.Start..scope.End]));
                Equal("Our synthetic project has three steps.\r\n" + second, TextTarget.Capture(plain, automation)!.Original);
            });
        }
        catch (Exception e) { failed++; Console.WriteLine("FAIL fixture: " + e); }
        finally { if (!fixture.HasExited) fixture.Kill(); }
        Console.WriteLine($"Total: {passed} passed, {failed} failed");
        return failed == 0 ? 0 : 1;
    }
}
