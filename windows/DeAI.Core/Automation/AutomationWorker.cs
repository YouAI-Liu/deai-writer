using System;
using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using Interop.UIAutomationClient;

namespace DeAI.Automation;

public sealed class AutomationWorker : IDisposable
{
    private readonly BlockingCollection<Action> queue = new();
    private readonly Thread thread;
    private IUIAutomation? automation;
    private readonly IUIAutomationFocusChangedEventHandler? focusHandler;
    public AutomationWorker(Action<int, int[]>? focusChanged = null)
    {
        if (focusChanged != null) focusHandler = new FocusHandler(focusChanged);
        thread = new Thread(() => { foreach (var action in queue.GetConsumingEnumerable()) action(); }) { IsBackground = true, Name = "DeAI UIA3 MTA" };
        thread.SetApartmentState(ApartmentState.MTA);
        thread.Start();
    }
    public Task<T> Run<T>(Func<IUIAutomation, T> action)
    {
        var result = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
        queue.Add(() =>
        {
            try
            {
                if (automation == null)
                {
                    var created = TextTarget.CreateAutomation();
                    if (focusHandler != null)
                    {
                        var cache = created.CreateCacheRequest(); cache.AddProperty(30002); cache.AddProperty(30000);
                        created.AddFocusChangedEventHandler(cache, focusHandler);
                    }
                    automation = created;
                }
                result.SetResult(action(automation));
            }
            catch (Exception error) { result.SetException(error); }
        });
        return result.Task;
    }
    public void Dispose()
    {
        queue.Add(() => { try { if (automation != null && focusHandler != null) automation.RemoveFocusChangedEventHandler(focusHandler); } catch { } });
        queue.CompleteAdding();
    }
    [ComVisible(true), ClassInterface(ClassInterfaceType.None)]
    public sealed class FocusHandler(Action<int, int[]> observe) : IUIAutomationFocusChangedEventHandler
    {
        public void HandleFocusChangedEvent(IUIAutomationElement sender)
        {
            try { observe(sender.CachedProcessId, sender.GetCachedPropertyValue(30000) as int[] ?? Array.Empty<int>()); }
            catch { observe(0, Array.Empty<int>()); }
        }
    }
}
