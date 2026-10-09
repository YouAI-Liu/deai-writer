using System;
using System.Collections.Concurrent;
using System.Threading;
using System.Threading.Tasks;
using Interop.UIAutomationClient;

namespace DeAI.Automation;

public sealed class AutomationWorker : IDisposable
{
    private readonly BlockingCollection<Action> queue = new();
    private readonly Thread thread;
    private IUIAutomation? automation;
    public AutomationWorker()
    {
        thread = new Thread(() => { foreach (var action in queue.GetConsumingEnumerable()) action(); }) { IsBackground = true, Name = "DeAI UIA3 MTA" };
        thread.SetApartmentState(ApartmentState.MTA);
        thread.Start();
    }
    public Task<T> Run<T>(Func<IUIAutomation, T> action)
    {
        var result = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
        queue.Add(() => { try { result.SetResult(action(automation ??= TextTarget.CreateAutomation())); } catch (Exception error) { result.SetException(error); } });
        return result.Task;
    }
    public void Dispose() => queue.CompleteAdding();
}
