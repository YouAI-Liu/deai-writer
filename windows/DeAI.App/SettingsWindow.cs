using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Automation;
using Microsoft.Win32;

namespace DeAI.App;

internal sealed class LexiconRow
{
    public string Kind { get; set; } = "replace";
    public string Term { get; set; } = "";
    public string? Replacement { get; set; } = "";
    public string MatchKind { get; set; } = "exact";
}
internal sealed record Choice(uint Value, string Label) { public override string ToString() => Label; }
internal sealed class HotkeyEditor : StackPanel
{
    private readonly ComboBox modifiers = new() { Width = 165, Margin = new Thickness(0, 0, 8, 0) };
    private readonly ComboBox keys = new() { Width = 100 };
    public HotkeyEditor(Hotkey key, string id)
    {
        Orientation = Orientation.Horizontal; Margin = new Thickness(0, 4, 0, 14);
        modifiers.ItemsSource = new[] { new Choice(3, "Ctrl + Alt"), new Choice(6, "Ctrl + Shift"), new Choice(7, "Ctrl + Alt + Shift"), new Choice(10, "Ctrl + Win") };
        keys.ItemsSource = Enumerable.Range(0x70, 12).Select(x => new Choice((uint)x, "F" + (x - 0x6f))).Concat(Enumerable.Range(0x41, 26).Select(x => new Choice((uint)x, ((char)x).ToString()))).ToArray();
        modifiers.SelectedItem = ((Choice[])modifiers.ItemsSource).FirstOrDefault(x => x.Value == key.Modifiers);
        keys.SelectedItem = ((Choice[])keys.ItemsSource).FirstOrDefault(x => x.Value == key.Key);
        AutomationProperties.SetAutomationId(modifiers, id + "Modifiers"); AutomationProperties.SetAutomationId(keys, id + "Key");
        Children.Add(modifiers); Children.Add(keys);
    }
    public Hotkey Value => modifiers.SelectedItem is Choice modifier && keys.SelectedItem is Choice key ? new(modifier.Value, key.Value) : throw new InvalidOperationException("请选择快捷键。");
}

internal sealed class SettingsWindow : Window
{
    private readonly Controller controller;
    private readonly Preferences original;
    private readonly CheckBox auto, browser, grammar, english, chinese, markdown, personal;
    private readonly CheckBox freeOnly = new() { Content = "OpenRouter: free models only / 仅免费模型", Margin = new Thickness(0, 10, 0, 10) };
    private readonly ComboBox sensitivity = new(), language = new(), format = new(), zhSkill = new(), enSkill = new();
    private readonly TextBox excluded, disabled, url, model;
    private readonly PasswordBox key = new() { Padding = new Thickness(8), MinHeight = 34 };
    private readonly TextBlock keyStatus = Ui.Label("");
    private readonly HotkeyEditor checkKey, rewriteKey;
    private readonly ObservableCollection<LexiconRow> entries;
    private readonly DataGrid lexicon;
    private readonly ListBox skillList = new() { MinHeight = 160 };
    private readonly TextBox skillBody = Ui.Text("", "SkillPreview", true);
    public SettingsWindow(Controller controller)
    {
        this.controller = controller; original = controller.Preferences;
        Title = "DeAI — " + Ui.L("设置", "Settings"); Width = 760; Height = 690; MinWidth = 660; MinHeight = 540; Ui.Style(this);
        var root = new DockPanel { Margin = new Thickness(24) }; var footer = new WrapPanel { Margin = new Thickness(0, 12, 0, 0) };
        footer.Children.Add(Ui.Button(Ui.L("保存设置与词库", "Save settings & lexicon"), Save, "SaveSettings"));
        footer.Children.Add(Ui.Button(Ui.L("关闭", "Close"), Close));
        DockPanel.SetDock(footer, Dock.Bottom); root.Children.Add(footer);
        var tabs = new TabControl(); root.Children.Add(tabs); Content = root;
        var checks = Panel(tabs, Ui.L("检查", "Checks"));
        checks.Children.Add(Ui.Label(Ui.L("本地检查", "Local checks"), 22));
        auto = Toggle(checks, Ui.L("自动检查当前聚焦的编辑框（不发送网络请求）", "Automatically check the focused editor (no network requests)"), original.AutoCheck);
        grammar = Toggle(checks, "English grammar / Harper", original.Options.Grammar);
        english = Toggle(checks, "English AI tone", original.Options.AiToneEn);
        chinese = Toggle(checks, "中文 AI 腔", original.Options.AiToneZh);
        markdown = Toggle(checks, "Markdown", original.Options.Markdown); personal = Toggle(checks, Ui.L("个人词库", "Personal lexicon"), original.Options.Personal);
        checks.Children.Add(Ui.Label(Ui.L("灵敏度（1 高置信 / 2 标准 / 3 敏感）", "Sensitivity (1 high confidence / 2 standard / 3 sensitive)")));
        sensitivity.ItemsSource = new[] { 1, 2, 3 }; sensitivity.SelectedItem = (int)original.Options.Sensitivity; checks.Children.Add(sensitivity);
        checks.Children.Add(Ui.Label("语言 / Language")); language.ItemsSource = new[] { "zh", "en" }; language.SelectedItem = original.Language; checks.Children.Add(language);
        checks.Children.Add(Ui.Label(Ui.L("禁用规则（每行一个 rule_id；清空可恢复）", "Disabled rules (one rule_id per line; clear to restore)")));
        disabled = Ui.Text(string.Join("\n", original.DisabledRules), "DisabledRules", true); checks.Children.Add(disabled);
        var apps = Panel(tabs, Ui.L("应用与快捷键", "Apps & hotkeys"));
        apps.Children.Add(Ui.Label(Ui.L("隐私边界", "Privacy boundaries"), 22));
        apps.Children.Add(Ui.Label(Ui.L("密码字段、DeAI 自身、终端和常见密码管理器永不读取。只访问当前焦点，不遍历其他应用。管理员窗口可能无法访问；DeAI 不请求提权。", "Password fields, DeAI, terminals and common password managers are never read. Only the focused target is accessed. Elevated apps may be inaccessible; DeAI does not request elevation.")));
        browser = Toggle(apps, Ui.L("允许浏览器（实验性；兼容性未验证，仍不开放富文本写回）", "Allow browsers (experimental; compatibility unverified; no rich-text write-back)"), original.BrowsersEnabled);
        apps.Children.Add(Ui.Label(Ui.L("排除应用（每行一个进程名，不含 .exe）", "Excluded apps (one process name per line, without .exe)")));
        excluded = Ui.Text(string.Join("\n", original.ExcludedApps), "ExcludedApps", true); apps.Children.Add(excluded);
        apps.Children.Add(Ui.Label(Ui.L("检查快捷键", "Check hotkey"))); checkKey = new HotkeyEditor(original.CheckHotkey, "CheckHotkey"); apps.Children.Add(checkKey);
        apps.Children.Add(Ui.Label(Ui.L("改写快捷键", "Rewrite hotkey"))); rewriteKey = new HotkeyEditor(original.RewriteHotkey, "RewriteHotkey"); apps.Children.Add(rewriteKey);
        var words = Panel(tabs, Ui.L("词库", "Lexicon"));
        words.Children.Add(Ui.Label(Ui.L("replace 替换 / avoid 避免 / keep 保留", "replace / avoid / keep"), 20));
        words.Children.Add(Ui.Label(Ui.L("上限 200 条，term/replacement 上限 100 UTF-16 字符。匹配模式：exact / caseInsensitive / wholeWord。keep 抑制重叠建议。", "Up to 200 entries; term/replacement up to 100 UTF-16 characters. Match: exact / caseInsensitive / wholeWord. keep suppresses overlapping findings.")));
        entries = new ObservableCollection<LexiconRow>(controller.Lexicon.Select(e => new LexiconRow { Kind = e.Kind, Term = e.Term, Replacement = e.Replacement, MatchKind = e.MatchKind }));
        lexicon = new DataGrid { ItemsSource = entries, AutoGenerateColumns = false, CanUserAddRows = true, CanUserDeleteRows = true, MinHeight = 270, MaxHeight = 380 };
        lexicon.Columns.Add(new DataGridComboBoxColumn { Header = "kind", ItemsSource = new[] { "replace", "avoid", "keep" }, SelectedItemBinding = new Binding("Kind") });
        lexicon.Columns.Add(new DataGridTextColumn { Header = "term", Binding = new Binding("Term"), Width = new DataGridLength(1, DataGridLengthUnitType.Star) });
        lexicon.Columns.Add(new DataGridTextColumn { Header = "replacement", Binding = new Binding("Replacement"), Width = new DataGridLength(1, DataGridLengthUnitType.Star) });
        lexicon.Columns.Add(new DataGridComboBoxColumn { Header = "matchKind", ItemsSource = new[] { "exact", "caseInsensitive", "wholeWord" }, SelectedItemBinding = new Binding("MatchKind") });
        AutomationProperties.SetAutomationId(lexicon, "LexiconEntries"); words.Children.Add(lexicon);
        words.Children.Add(Ui.Button(Ui.L("删除所选词条", "Delete selected entry"), () => { if (lexicon.SelectedItem is LexiconRow row) entries.Remove(row); }));
        var skills = Panel(tabs, "Skills"); skills.Children.Add(Ui.Label("SKILL.md", 22)); skills.Children.Add(skillList);
        var skillActions = new WrapPanel();
        skillActions.Children.Add(Ui.Button(Ui.L("导入文件", "Import file"), () => ImportSkill(false), "ImportSkill"));
        skillActions.Children.Add(Ui.Button(Ui.L("导入目录", "Import folder"), () => ImportSkill(true)));
        skillActions.Children.Add(Ui.Button(Ui.L("新建 / 编辑", "New / edit"), EditSkill, "EditSkill"));
        skillActions.Children.Add(Ui.Button(Ui.L("删除", "Delete"), () => { try { if (skillList.SelectedItem is Skill skill) { controller.Skills.Delete(skill); ReloadSkills(); } } catch (Exception error) { Ui.Error(error); } }));
        skills.Children.Add(skillActions); skillBody.IsReadOnly = true; skillBody.MaxHeight = 160; skills.Children.Add(skillBody);
        skills.Children.Add(Ui.Label(Ui.L("中文默认 Skill", "Chinese default Skill"))); skills.Children.Add(zhSkill);
        skills.Children.Add(Ui.Label(Ui.L("英文默认 Skill", "English default Skill"))); skills.Children.Add(enSkill);
        skillList.SelectionChanged += (_, _) => skillBody.Text = (skillList.SelectedItem as Skill)?.Body ?? ""; ReloadSkills();
        var ai = Panel(tabs, "AI"); ai.Children.Add(Ui.Label(Ui.L("服务配置", "Provider configuration"), 22));
        ai.Children.Add(Ui.Label(Ui.L("检查始终在本地运行。AI 每次发送前都显示范围和服务。API Key 通过当前 Windows 用户 DPAPI 加密，不写入设置 JSON 或日志。", "Checks always run locally. Each AI send shows its scope/provider. API keys use current-user DPAPI encryption, never settings JSON or logs.")));
        var presets = new ComboBox { ItemsSource = new[] { "OpenAI", "Anthropic", "DeepSeek", "OpenRouter" }, MinHeight = 30 }; ai.Children.Add(presets);
        ai.Children.Add(Ui.Label("Base URL")); url = Ui.Text(original.Provider.BaseUrl, "ProviderUrl"); ai.Children.Add(url);
        ai.Children.Add(Ui.Label("Model")); model = Ui.Text(original.Provider.Model, "ProviderModel"); ai.Children.Add(model);
        ai.Children.Add(Ui.Label("API format")); format.ItemsSource = new[] { "chat", "responses", "anthropic" }; format.SelectedItem = original.Provider.Format; ai.Children.Add(format);
        freeOnly.IsChecked = original.Provider.FreeOnly; ai.Children.Add(freeOnly);
        presets.SelectionChanged += (_, _) => { freeOnly.IsChecked = false; switch (presets.SelectedItem) { case "OpenAI": url.Text = "https://api.openai.com/v1"; model.Text = "gpt-4o-mini"; format.SelectedItem = "chat"; break; case "Anthropic": url.Text = "https://api.anthropic.com/v1"; model.Text = "claude-sonnet-4-20250514"; format.SelectedItem = "anthropic"; break; case "DeepSeek": url.Text = "https://api.deepseek.com/v1"; model.Text = "deepseek-chat"; format.SelectedItem = "chat"; break; case "OpenRouter": url.Text = "https://openrouter.ai/api/v1"; model.Text = "openrouter/free"; format.SelectedItem = "chat"; freeOnly.IsChecked = true; break; } };
        ai.Children.Add(Ui.Label(Ui.L("API Key（留空保留已保存密钥；不会显示原密钥）", "API key (blank keeps saved key; existing key is never displayed)")));
        AutomationProperties.SetAutomationId(key, "ProviderKey"); ai.Children.Add(key); ai.Children.Add(keyStatus);
        ai.Children.Add(Ui.Button(Ui.L("删除已保存密钥", "Delete saved key"), () => { try { controller.Secrets.Delete(); KeyStatus(); } catch (Exception error) { Ui.Error(error); } }, "DeleteProviderKey")); KeyStatus();
    }
    private static StackPanel Panel(TabControl tabs, string title)
    {
        var panel = new StackPanel { Margin = new Thickness(18) }; tabs.Items.Add(new TabItem { Header = title, Content = new ScrollViewer { Content = panel, VerticalScrollBarVisibility = ScrollBarVisibility.Auto } }); return panel;
    }
    private static CheckBox Toggle(Panel panel, string text, bool value)
    {
        var toggle = new CheckBox { Content = text, IsChecked = value, Margin = new Thickness(0, 5, 0, 10) }; panel.Children.Add(toggle); return toggle;
    }
    private void KeyStatus() => keyStatus.Text = controller.Secrets.HasKey ? Ui.L("密钥已保存（DPAPI 当前用户）", "Key saved (DPAPI current user)") : Ui.L("尚未保存密钥", "No saved key");
    private void ReloadSkills()
    {
        var all = controller.Skills.Load(); skillList.ItemsSource = all;
        var selectedZh = (zhSkill.SelectedItem as Skill)?.Id ?? original.ChineseSkill; var selectedEn = (enSkill.SelectedItem as Skill)?.Id ?? original.EnglishSkill;
        zhSkill.ItemsSource = all.Where(s => s.Language is "zh" or "any").ToArray(); enSkill.ItemsSource = all.Where(s => s.Language is "en" or "any").ToArray();
        zhSkill.SelectedItem = SkillStore.Resolve(all, selectedZh, "zh"); enSkill.SelectedItem = SkillStore.Resolve(all, selectedEn, "en"); skillList.SelectedIndex = 0;
    }
    private void ImportSkill(bool folder)
    {
        try
        {
            string? path = null;
            if (folder) { var dialog = new OpenFolderDialog(); if (dialog.ShowDialog(this) == true) path = dialog.FolderName; }
            else { var dialog = new OpenFileDialog { Filter = "Markdown|*.md" }; if (dialog.ShowDialog(this) == true) path = dialog.FileName; }
            if (path != null) { var imported = controller.Skills.Import(path); ReloadSkills(); skillList.SelectedItem = ((IReadOnlyList<Skill>)skillList.ItemsSource).First(s => s.Id == imported.Id); }
        }
        catch (Exception error) { Ui.Error(error); }
    }
    private void EditSkill()
    {
        var existing = skillList.SelectedItem as Skill;
        if (existing?.Id == Skill.BuiltinId) existing = null;
        var dialog = new Window { Owner = this, Title = "Skill", Width = 640, Height = 540, WindowStartupLocation = WindowStartupLocation.CenterOwner }; Ui.Style(dialog);
        var panel = new StackPanel { Margin = new Thickness(20) }; var name = Ui.Text(existing?.Name ?? "Custom Skill"); var body = Ui.Text(existing?.Body ?? Skill.Builtin.Body, null, true); body.Height = 280;
        var lang = new ComboBox { ItemsSource = new[] { "zh", "en", "any" }, SelectedItem = existing?.Language ?? "any" };
        panel.Children.Add(name); panel.Children.Add(lang); panel.Children.Add(body);
        panel.Children.Add(Ui.Button(Ui.L("保存 Skill", "Save Skill"), () => { try { controller.Skills.Save(new(existing?.Id ?? Guid.NewGuid().ToString("N"), name.Text, existing?.Description ?? "", (string)lang.SelectedItem, body.Text)); ReloadSkills(); dialog.Close(); } catch (Exception error) { Ui.Error(error); } })); dialog.Content = panel; dialog.ShowDialog();
    }
    private static string[] Lines(TextBox text) => text.Text.Split(new[] { '\r', '\n' }, StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
    private void Save()
    {
        try
        {
            lexicon.CommitEdit(DataGridEditingUnit.Cell, true); lexicon.CommitEdit(DataGridEditingUnit.Row, true);
            var words = entries.Select(e => new PersonalEntry(e.Kind, e.Term, e.Replacement, e.MatchKind)).ToArray(); DataStore.ValidateLexicon(words);
            var updated = original with
            {
                Language = (string)language.SelectedItem,
                AutoCheck = auto.IsChecked == true,
                BrowsersEnabled = browser.IsChecked == true,
                ExcludedApps = Lines(excluded),
                DisabledRules = Lines(disabled),
                Options = new(grammar.IsChecked == true, english.IsChecked == true, chinese.IsChecked == true, markdown.IsChecked == true, personal.IsChecked == true, (byte)(int)sensitivity.SelectedItem),
                CheckHotkey = checkKey.Value,
                RewriteHotkey = rewriteKey.Value,
                Provider = new(url.Text.Trim(), model.Text.Trim(), (string)format.SelectedItem, freeOnly.IsChecked == true),
                ChineseSkill = ((Skill)zhSkill.SelectedItem).Id,
                EnglishSkill = ((Skill)enSkill.SelectedItem).Id
            };
            updated.Validate();
            if (updated.Provider.BaseUrl != original.Provider.BaseUrl && controller.Secrets.HasKey && key.Password.Length == 0
                && MessageBox.Show(Ui.L("服务地址已更改；继续将使用已保存密钥访问新地址。确认你信任此服务？", "Provider URL changed. The saved key will be used with the new endpoint. Do you trust it?"), "DeAI", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
            controller.SavePreferences(updated); controller.SaveLexicon(words);
            if (key.Password.Length != 0) { controller.Secrets.Save(key.Password); key.Clear(); }
            KeyStatus(); MessageBox.Show(Ui.L("已保存。", "Saved."), "DeAI");
        }
        catch (Exception error) { Ui.Error(error); }
    }
}
