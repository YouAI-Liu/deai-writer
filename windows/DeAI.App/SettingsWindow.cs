using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Automation;
using System.Windows.Input;
using Microsoft.Win32;

namespace DeAI.App;

internal sealed class SettingsWindow : Window
{
    private readonly Controller controller;
    private readonly TabControl tabs = new();
    private readonly Dictionary<string, CheckBox> checks = new(), groups = new();
    private readonly Dictionary<string, Dictionary<string, CheckBox>> groupChecks = new();
    private readonly Dictionary<string, (TextBox Color, ComboBox Shape)> styles = new();
    private readonly StackPanel wordRows = new();
    private readonly ObservableCollection<LexiconEditor> wordEditors = new();
    private PersonalEntry[] wordSnapshot;
    private readonly ComboBox language = new(), zhSkill = new(), enSkill = new(), format = new();
    private readonly ListBox providers = new(), skillList = new() { DisplayMemberPath = "Name", Height = 110 };
    private readonly TextBox providerName = Ui.Text(""), url = Ui.Text("", "ProviderUrl"), model = Ui.Text("", "ProviderModel");
    private readonly PasswordBox key = new();
    private readonly CheckBox freeOnly = new(), dim = new(), fill = new();
    private readonly TextBlock keyStatus = Ui.Label("", 11, "Muted"), providerStatus = Ui.Label("", 11, "Muted"), wordStatus = Ui.Label("", 11, "Danger");
    private readonly TextBox skillBody = Ui.Text("", "SkillPreview", true);
    private readonly Slider thickness = new() { Minimum = 0.5, Maximum = 4 }, opacity = new() { Minimum = 0.2, Maximum = 1 }, offset = new() { Minimum = -2, Maximum = 4 };
    private readonly UnderlineView preview = new() { Height = 22, Category = "grammar" };
    private readonly HotkeyRecorder checkKey, rewriteKey;
    private TextBox excluded = null!, disabled = null!;
    private byte sensitivity;
    private bool ready, loadingProvider;
    public SettingsWindow(Controller controller, int initialTab = 0)
    {
        this.controller = controller; var preferences = controller.Preferences;
        wordSnapshot = controller.Lexicon.ToArray(); sensitivity = preferences.Options.Sensitivity;
        Title = "DeAI — " + Ui.L("设置", "Settings"); Ui.Style(this);
        ResizeMode = ResizeMode.CanMinimize; SizeToContent = SizeToContent.WidthAndHeight;
        var root = new Grid { Width = Ui.SettingsWidth, Height = Ui.SettingsHeight }; root.Children.Add(tabs); Content = root;
        var checkPage = Page(Ui.L("检查", "Check"), "☷", "CheckSettings");
        var appearancePage = Page(Ui.L("下划线外观", "Underlines"), "U̲", "UnderlineSettings");
        var aiPage = Page(Ui.L("AI 改写", "AI rewrite"), "✧", "AISettings");
        var personalPage = Page(Ui.L("个人", "Personal"), "▣", "PersonalSettings");
        var local = Ui.Section(checkPage, Ui.L("检查", "Check"));
        language.ItemsSource = new[] { "中文", "English" }; language.SelectedIndex = preferences.Language == "en" ? 1 : 0; language.Width = 130;
        Add(local, Ui.Row(Ui.Label(Ui.L("语言", "Language")), language));
        language.SelectionChanged += (_, _) =>
        {
            if (!ready) return;
            Save();
            if (controller.Preferences.Language == (language.SelectedIndex == 1 ? "en" : "zh"))
            { var selected = tabs.SelectedIndex; Close(); controller.ShowSettings(selected); }
        };
        var options = preferences.Options;
        AddCheck(local, "grammar", options.Grammar); AddCheck(local, "ai_tone_zh", options.AiToneZh);
        AddCheck(local, "ai_tone_en", options.AiToneEn); AddCheck(local, "markdown", options.Markdown); AddCheck(local, "personal", options.Personal);
        Add(local, Ui.Separator());
        Add(local, Ui.Label(Ui.L("敏感度", "Sensitivity"), 12));
        Add(local, Segments(new[] { Ui.L("保守", "Conservative"), Ui.L("标准", "Standard"), Ui.L("敏感", "Sensitive") }, sensitivity - 1, i => { sensitivity = (byte)(i + 1); Save(); }));
        var appSection = Ui.Section(checkPage, Ui.L("应用组", "App groups"));
        var names = new[] { Ui.L("写作", "Writing"), Ui.L("聊天", "Chat"), Ui.L("浏览器", "Browsers"), Ui.L("代码", "Code"), Ui.L("其他", "Other") };
        for (var i = 0; i < AppGroups.Keys.Length; i++)
        {
            var groupId = AppGroups.Keys[i]; var rule = preferences.Group(groupId);
            var enabled = Toggle(names[i], rule.Enabled, "Group_" + groupId); groups[groupId] = enabled; Add(appSection, enabled);
            var chips = new WrapPanel { Margin = new Thickness(0, 0, 0, 10) }; var flags = new Dictionary<string, CheckBox>(); groupChecks[groupId] = flags;
            var groupOptions = rule.Options ?? new();
            foreach (var category in Categories)
            {
                var chip = Toggle(Ui.Category(category), Option(groupOptions, category), "Group_" + groupId + "_" + category);
                chip.Style = (Style)Application.Current.FindResource("Chip"); chip.Margin = new Thickness(0, 0, 5, 5); chip.IsEnabled = rule.Enabled;
                flags[category] = chip; chips.Children.Add(chip);
            }
            enabled.Checked += (_, _) => { foreach (var chip in flags.Values) chip.IsEnabled = true; };
            enabled.Unchecked += (_, _) => { foreach (var chip in flags.Values) chip.IsEnabled = false; };
            appSection.Children.Add(chips);
            if (i < AppGroups.Keys.Length - 1) Add(appSection, Ui.Separator());
        }
        Add(appSection, Ui.Label(Ui.L("分组只控制检查规则，不代表应用兼容性；浏览器仍属实验性。", "Groups control rules, not compatibility. Browsers remain experimental."), 10, "Muted"));
        var exceptions = Ui.Section(checkPage, Ui.L("应用例外", "App exceptions"));
        Add(exceptions, Ui.Label(Ui.L("排除应用的进程名（不含 .exe，每行一个）。密码、终端和密码管理器始终排除。", "Excluded process names (one per line, without .exe). Passwords, terminals and password managers are always excluded."), 11, "Muted"));
        excluded = Ui.Text(string.Join("\n", preferences.ExcludedApps), "ExcludedApps", true); excluded.Height = 85; exceptions.Children.Add(excluded); excluded.LostKeyboardFocus += (_, _) => Save();
        var rules = Ui.Section(checkPage, Ui.L("禁用规则", "Disabled rules"));
        Add(rules, Ui.Label(Ui.L("每行一个规则 ID；删除后恢复检查。", "One rule ID per line. Remove to restore."), 11, "Muted"));
        disabled = Ui.Text(string.Join("\n", preferences.DisabledRules), "DisabledRules", true); disabled.Height = 85; rules.Children.Add(disabled); disabled.LostKeyboardFocus += (_, _) => Save();
        checkKey = new HotkeyRecorder(controller, preferences.CheckHotkey, "CheckHotkey", Save);
        var shortcuts = Ui.Section(checkPage, Ui.L("快捷键", "Shortcut")); Add(shortcuts, Ui.Row(Ui.Label(Ui.L("检查文本", "Check text")), checkKey));
        BuildAppearance(appearancePage, preferences.Underline);
        var service = Ui.Section(aiPage, Ui.L("服务配置", "Providers"));
        providers.DisplayMemberPath = "Name"; providers.Height = 100; providers.BorderThickness = new Thickness(0);
        AutomationProperties.SetAutomationId(providers, "Providers"); service.Children.Add(providers);
        var toolbar = new WrapPanel(); toolbar.Children.Add(Ui.Button(Ui.L("添加服务", "Add provider"), AddProvider, "AddProvider"));
        toolbar.Children.Add(Ui.Button(Ui.L("删除", "Remove"), RemoveProvider, "RemoveProvider", "FlatButton")); Add(service, toolbar);
        providers.SelectionChanged += (_, _) => SelectProvider();
        var detail = new StackPanel();
        Add(detail, Field(Ui.L("名称", "Name"), providerName)); Add(detail, Field("Base URL", url)); Add(detail, Field(Ui.L("模型", "Model"), model));
        format.ItemsSource = new[] { "chat", "responses", "anthropic" }; format.Width = 140; Add(detail, Ui.Row(Ui.Label("API format", 12), format));
        freeOnly.Content = Ui.L("OpenRouter 仅免费模型", "OpenRouter: free models only"); Add(detail, freeOnly);
        AutomationProperties.SetAutomationId(key, "ProviderKey"); Add(detail, Field("API Key", key)); Add(detail, keyStatus);
        var keyActions = new WrapPanel();
        keyActions.Children.Add(Ui.Button(Ui.L("保存配置与密钥", "Save configuration & key"), SaveProvider, "SaveProvider", "PrimaryButton"));
        keyActions.Children.Add(Ui.Button(Ui.L("删除密钥", "Delete key"), () => { try { controller.Secrets.Delete(); KeyStatus(); } catch (Exception error) { Ui.Error(error); } }, "DeleteProviderKey", "FlatButton"));
        Add(detail, keyActions); Add(detail, providerStatus);
        Add(detail, Ui.Label(Ui.L("密钥留空保留原值。DPAPI 按 Windows 用户及服务分别加密；不会显示已存密钥。", "Blank keeps the saved key. DPAPI encrypts keys per Windows user and provider. Saved values are never displayed."), 10, "Muted"));
        service.Children.Add(new Expander { Header = Ui.L("服务详情", "Provider details"), IsExpanded = true, Content = detail });
        ReloadProviders();
        var rewriteShortcut = Ui.Section(aiPage, Ui.L("改写快捷键", "Rewrite shortcut"));
        rewriteKey = new HotkeyRecorder(controller, preferences.RewriteHotkey, "RewriteHotkey", Save); Add(rewriteShortcut, Ui.Row(Ui.Label(Ui.L("改写选区 / 当前段落", "Rewrite selection / paragraph"), 12), rewriteKey));
        var skills = Ui.Section(aiPage, Ui.L("改写 Skills", "Rewrite Skills"));
        Add(skills, Ui.Row(Ui.Label(Ui.L("中文", "Chinese"), 12), zhSkill)); Add(skills, Ui.Row(Ui.Label(Ui.L("英文", "English"), 12), enSkill));
        zhSkill.Width = enSkill.Width = 210; zhSkill.DisplayMemberPath = enSkill.DisplayMemberPath = "Name";
        zhSkill.SelectionChanged += (_, _) => Save(); enSkill.SelectionChanged += (_, _) => Save();
        skillBody.IsReadOnly = true; skillBody.Height = 130;
        var management = new StackPanel(); management.Children.Add(skillList); management.Children.Add(skillBody);
        var skillActions = new WrapPanel();
        skillActions.Children.Add(Ui.Button(Ui.L("导入文件", "Import file"), () => ImportSkill(false), "ImportSkill"));
        skillActions.Children.Add(Ui.Button(Ui.L("导入文件夹", "Import folder"), () => ImportSkill(true), "ImportSkillFolder"));
        skillActions.Children.Add(Ui.Button(Ui.L("新建 / 编辑", "New / edit"), EditSkill, "EditSkill"));
        skillActions.Children.Add(Ui.Button(Ui.L("删除", "Delete"), () => { if (skillList.SelectedItem is Skill skill && skill.Id != Skill.BuiltinId) { controller.Skills.Delete(skill); ReloadSkills(); Save(); } }, "DeleteSkill", "FlatButton"));
        management.Children.Add(skillActions); skills.Children.Add(new Expander { Header = Ui.L("管理 Skills", "Manage Skills"), Content = management });
        skillList.SelectionChanged += (_, _) => skillBody.Text = (skillList.SelectedItem as Skill)?.Body ?? ""; ReloadSkills();
        var words = Ui.Section(personalPage, Ui.L("个人词库", "Personal lexicon")); words.Children.Add(wordRows); Add(words, wordStatus);
        var count = Ui.Label("", 10, "Muted");
        count.SetBinding(TextBlock.TextProperty, new Binding(nameof(wordEditors.Count)) { Source = wordEditors, StringFormat = "{0}/200" });
        AutomationProperties.SetAutomationId(count, "LexiconCount");
        Add(words, Ui.Row(Ui.Button(Ui.L("添加词条", "Add entry"), () => { if (wordEditors.Count < 200) AddWord(new("replace", "", "")); }, "AddLexiconEntry"), count));
        foreach (var entry in wordSnapshot) AddWord(entry);
        Add(words, Ui.Label(Ui.L("保留：不再建议；避免：提示少用；替换：记住你的说法。每条最多 100 个 UTF-16 字符。", "Keep suppresses suggestions; avoid discourages a term; replace remembers your wording. Up to 100 UTF-16 characters per field."), 11, "Muted"));
        tabs.SelectedIndex = Math.Clamp(initialTab, 0, 3); ready = true;
    }
    private static readonly string[] Categories = { "grammar", "ai_tone_zh", "ai_tone_en", "markdown", "personal" };
    public void SelectTab(int tab) => tabs.SelectedIndex = Math.Clamp(tab, 0, 3);
    private static bool Option(CheckOptions value, string category) => category switch { "grammar" => value.Grammar, "ai_tone_zh" => value.AiToneZh, "ai_tone_en" => value.AiToneEn, "markdown" => value.Markdown, _ => value.Personal };
    private StackPanel Page(string title, string icon, string id)
    {
        var header = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center }; var glyph = Ui.Label(icon, 16, "Muted"); glyph.HorizontalAlignment = HorizontalAlignment.Center; header.Children.Add(glyph);
        var label = Ui.Label(title, 11); label.Margin = new Thickness(0, 3, 0, 0); header.Children.Add(label);
        var content = new StackPanel { Margin = new Thickness(30) };
        var tab = new TabItem { Header = header, Content = new ScrollViewer { Content = content, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled } };
        AutomationProperties.SetAutomationId(tab, id); AutomationProperties.SetName(tab, title); tabs.Items.Add(tab); return content;
    }
    private static void Add(StackPanel parent, FrameworkElement child) { child.Margin = new Thickness(0, 0, 0, 12); parent.Children.Add(child); }
    private static Grid Field(string label, FrameworkElement editor)
    {
        var text = Ui.Label(label, 11, "Muted"); text.Width = 88; var grid = Ui.Row(text, editor, 12);
        grid.ColumnDefinitions[0].Width = GridLength.Auto; grid.ColumnDefinitions[1].Width = new GridLength(1, GridUnitType.Star); return grid;
    }
    private CheckBox Toggle(string title, bool value, string id, bool save = true)
    {
        var check = new CheckBox { Content = title, IsChecked = value }; AutomationProperties.SetAutomationId(check, id);
        if (save) { check.Checked += (_, _) => Save(); check.Unchecked += (_, _) => Save(); }
        return check;
    }
    private void AddCheck(StackPanel parent, string category, bool value)
    { var check = Toggle(Ui.Category(category), value, "Check_" + category); checks[category] = check; Add(parent, check); }
    private static Border Segments(string[] names, int selected, Action<int> changed)
    {
        var grid = new Grid(); var group = Guid.NewGuid().ToString();
        for (var i = 0; i < names.Length; i++)
        {
            grid.ColumnDefinitions.Add(new ColumnDefinition()); var index = i;
            var radio = new RadioButton { Content = names[i], GroupName = group, IsChecked = i == selected, Style = (Style)Application.Current.FindResource("Segment") };
            radio.Checked += (_, _) => changed(index); Grid.SetColumn(radio, i); grid.Children.Add(radio);
        }
        var border = new Border { CornerRadius = new CornerRadius(100), Padding = new Thickness(5), Child = grid }; Ui.Color(border, Border.BackgroundProperty, "Track"); return border;
    }
    private static CheckOptions ReadOptions(Dictionary<string, CheckBox> flags, byte sensitivity) => new(
        flags["grammar"].IsChecked == true, flags["ai_tone_en"].IsChecked == true, flags["ai_tone_zh"].IsChecked == true, flags["markdown"].IsChecked == true, flags["personal"].IsChecked == true, sensitivity);
    private void Save()
    {
        if (!ready) return;
        try
        {
            var preferences = controller.Preferences with
            {
                Language = language.SelectedIndex == 1 ? "en" : "zh",
                Options = ReadOptions(checks, sensitivity),
                BrowsersEnabled = groups["browser"].IsChecked == true,
                ExcludedApps = Lines(excluded),
                DisabledRules = Lines(disabled),
                Groups = groups.ToDictionary(p => p.Key, p => new AppGroupRule(p.Value.IsChecked == true, ReadOptions(groupChecks[p.Key], sensitivity))),
                Underline = ReadAppearance(),
                CheckHotkey = checkKey.Value,
                RewriteHotkey = rewriteKey.Value,
                ChineseSkill = (zhSkill.SelectedItem as Skill)?.Id ?? Skill.BuiltinId,
                EnglishSkill = (enSkill.SelectedItem as Skill)?.Id ?? Skill.BuiltinId
            };
            controller.SavePreferences(preferences);
        }
        catch (Exception error) { Ui.Error(error); }
    }
    private static string[] Lines(TextBox text) => text.Text.Split(new[] { '\r', '\n' }, StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
    private void BuildAppearance(StackPanel page, UnderlineAppearance value)
    {
        var sample = Ui.Section(page, Ui.L("预览", "Preview")); Add(sample, Ui.Label(Ui.L("这是一段用于预览的文字", "A sentence for previewing underlines"), 15)); sample.Children.Add(preview);
        var categories = Ui.Section(page, Ui.L("分类样式", "Category styles"));
        foreach (var category in Categories)
        {
            var style = value.For(category); var color = Ui.Text(style.Color, "Color_" + category); color.Width = 86; color.Padding = new Thickness(6); color.ToolTip = "#RRGGBB";
            var shape = new ComboBox
            {
                ItemsSource = new[] { new UiChoice("straight", Ui.L("直线", "Straight")), new UiChoice("wavy", Ui.L("波浪", "Wavy")), new UiChoice("dashed", Ui.L("虚线", "Dashed")), new UiChoice("dotted", Ui.L("点线", "Dotted")) },
                DisplayMemberPath = "Label",
                SelectedValuePath = "Value",
                SelectedValue = style.Shape,
                Width = 110
            };
            var controls = new StackPanel { Orientation = Orientation.Horizontal }; controls.Children.Add(color); shape.Margin = new Thickness(8, 0, 0, 0); controls.Children.Add(shape);
            Add(categories, Ui.Row(Ui.Label(Ui.Category(category), 12), controls)); styles[category] = (color, shape);
            color.LostKeyboardFocus += (_, _) => AppearanceChanged(); shape.SelectionChanged += (_, _) => AppearanceChanged();
        }
        Add(categories, Ui.Label(Ui.L("颜色留空使用 Mac 对应分类色。格式：#RRGGBB。", "Blank uses the Mac category color. Format: #RRGGBB."), 10, "Muted"));
        var globals = Ui.Section(page, Ui.L("全局设置", "Global settings"));
        thickness.Value = value.Thickness; opacity.Value = value.Opacity; offset.Value = value.Offset;
        Add(globals, Field(Ui.L("粗细", "Thickness"), thickness)); Add(globals, Field(Ui.L("透明度", "Opacity"), opacity)); Add(globals, Field(Ui.L("偏移", "Offset"), offset));
        dim.Content = Ui.L("低置信度使用虚线", "Dash low-confidence findings"); dim.IsChecked = value.DimLowConfidence;
        fill.Content = Ui.L("高亮背景", "Highlight background"); fill.IsChecked = value.HighlightFill; Add(globals, dim); Add(globals, fill);
        foreach (var slider in new[] { thickness, opacity, offset }) { Ui.Color(slider, Control.ForegroundProperty, "Accent"); slider.ValueChanged += (_, _) => AppearanceChanged(); }
        dim.Checked += (_, _) => AppearanceChanged(); dim.Unchecked += (_, _) => AppearanceChanged(); fill.Checked += (_, _) => AppearanceChanged(); fill.Unchecked += (_, _) => AppearanceChanged();
        preview.Appearance = value;
        Add(globals, Ui.Button(Ui.L("恢复默认", "Reset defaults"), () =>
        {
            var defaults = new UnderlineAppearance(); ready = false;
            foreach (var (category, controls) in styles) { controls.Color.Text = ""; controls.Shape.SelectedValue = defaults.For(category).Shape; }
            thickness.Value = defaults.Thickness; opacity.Value = defaults.Opacity; offset.Value = defaults.Offset; dim.IsChecked = true; fill.IsChecked = false; ready = true; AppearanceChanged();
        }, "ResetUnderlines", "FlatButton"));
    }
    private UnderlineAppearance ReadAppearance() => new() { Styles = styles.ToDictionary(p => p.Key, p => new UnderlineStyle(p.Value.Color.Text.Trim(), p.Value.Shape.SelectedValue as string ?? "straight")), Thickness = thickness.Value, Opacity = opacity.Value, Offset = offset.Value, DimLowConfidence = dim.IsChecked == true, HighlightFill = fill.IsChecked == true };
    private void AppearanceChanged()
    {
        if (!ready) return;
        try { var value = ReadAppearance(); value.Validate(); preview.Appearance = value; preview.InvalidateVisual(); Save(); }
        catch (Exception error) { Ui.Error(error); }
    }
    private ProviderProfile[] Profiles() => controller.Preferences.Providers.Length == 0 ? new[] { new ProviderProfile("default", "OpenAI Compatible", controller.Preferences.Provider) } : controller.Preferences.Providers;
    private void ReloadProviders()
    {
        loadingProvider = true; providers.ItemsSource = Profiles(); providers.SelectedItem = Profiles().First(p => p.Id == controller.Preferences.ActiveProviderId); loadingProvider = false; SelectProvider();
    }
    private void SelectProvider()
    {
        if (loadingProvider || providers.SelectedItem is not ProviderProfile profile) return;
        try
        {
            if (ready && profile.Id != controller.Preferences.ActiveProviderId)
                controller.SavePreferences(controller.Preferences with { Provider = profile.Configuration, ActiveProviderId = profile.Id, Providers = Profiles() });
            providerName.Text = profile.Name; url.Text = profile.Configuration.BaseUrl; model.Text = profile.Configuration.Model; format.SelectedItem = profile.Configuration.Format; freeOnly.IsChecked = profile.Configuration.FreeOnly;
            key.Clear(); providerStatus.Text = ""; KeyStatus();
        }
        catch (Exception error) { Ui.Error(error); ReloadProviders(); }
    }
    private void SaveProvider()
    {
        try
        {
            var original = controller.Preferences; var configuration = new Provider(url.Text.Trim(), model.Text.Trim(), format.SelectedItem as string ?? "chat", freeOnly.IsChecked == true);
            var profiles = Profiles().Select(p => p.Id == original.ActiveProviderId ? p with { Name = providerName.Text.Trim(), Configuration = configuration } : p).ToArray();
            var updated = original with { Provider = configuration, Providers = profiles }; updated.Validate();
            if (configuration.BaseUrl != original.Provider.BaseUrl && controller.Secrets.HasKey && key.Password.Length == 0 &&
                MessageBox.Show(this, Ui.L("服务地址已更改；继续将使用已保存密钥访问新地址。确认你信任此服务？", "Provider URL changed. The saved key will be sent to the new endpoint. Do you trust it?"), "DeAI", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
            controller.SavePreferences(updated);
            if (key.Password.Length > 0) { controller.Secrets.Save(key.Password); key.Clear(); }
            KeyStatus(); ReloadProviders(); providerStatus.Text = Ui.L("已保存", "Saved");
        }
        catch (Exception error) { Ui.Error(error); }
    }
    private void AddProvider()
    {
        var dialog = new Window { Owner = this, Title = Ui.L("添加服务", "Add provider"), Width = 330, SizeToContent = SizeToContent.Height, ResizeMode = ResizeMode.NoResize, WindowStartupLocation = WindowStartupLocation.CenterOwner }; Ui.Style(dialog);
        var panel = new StackPanel { Margin = new Thickness(22) }; var choices = new ComboBox { ItemsSource = new[] { "OpenAI", "Anthropic", "DeepSeek", "OpenRouter" }, SelectedIndex = 3 }; Add(panel, choices);
        panel.Children.Add(Ui.Button(Ui.L("添加", "Add"), () =>
        {
            try
            {
                var name = (string)choices.SelectedItem; var config = name switch
                {
                    "Anthropic" => new Provider("https://api.anthropic.com/v1", "claude-sonnet-4-20250514", "anthropic"),
                    "DeepSeek" => new Provider("https://api.deepseek.com/v1", "deepseek-chat"),
                    "OpenRouter" => new Provider("https://openrouter.ai/api/v1", "openrouter/free", "chat", true),
                    _ => new Provider()
                };
                var profile = new ProviderProfile(Guid.NewGuid().ToString("N"), name, config);
                controller.SavePreferences(controller.Preferences with { Providers = Profiles().Append(profile).ToArray(), ActiveProviderId = profile.Id, Provider = config }); ReloadProviders(); dialog.Close();
            }
            catch (Exception error) { Ui.Error(error); }
        }, "ConfirmAddProvider", "PrimaryButton")); dialog.Content = panel; dialog.ShowDialog();
    }
    private void RemoveProvider()
    {
        if (providers.SelectedItem is not ProviderProfile profile || Profiles().Length <= 1) return;
        if (MessageBox.Show(this, Ui.L("删除此服务和对应密钥？", "Remove this provider and its key?"), "DeAI", MessageBoxButton.YesNo) != MessageBoxResult.Yes) return;
        try
        {
            var remaining = Profiles().Where(p => p.Id != profile.Id).ToArray(); var next = remaining[0];
            controller.SavePreferences(controller.Preferences with { Providers = remaining, ActiveProviderId = next.Id, Provider = next.Configuration });
            new SecretStore(controller.Store, profile.Id).Delete(); ReloadProviders();
        }
        catch (Exception error) { Ui.Error(error); }
    }
    private void KeyStatus() => keyStatus.Text = controller.Secrets.HasKey ? Ui.L("密钥已保存（DPAPI）", "Key saved (DPAPI)") : Ui.L("尚未保存密钥", "No saved key");
    private void ReloadSkills()
    {
        var wasReady = ready; ready = false; var all = controller.Skills.Load(); skillList.ItemsSource = all;
        zhSkill.ItemsSource = all.Where(s => s.Language is "zh" or "any").ToArray(); enSkill.ItemsSource = all.Where(s => s.Language is "en" or "any").ToArray();
        zhSkill.SelectedItem = SkillStore.Resolve(all, controller.Preferences.ChineseSkill, "zh"); enSkill.SelectedItem = SkillStore.Resolve(all, controller.Preferences.EnglishSkill, "en"); skillList.SelectedIndex = 0; ready = wasReady;
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
        var existing = skillList.SelectedItem as Skill; if (existing?.Id == Skill.BuiltinId) existing = null;
        var dialog = new Window { Owner = this, Title = "Skill", Width = 560, SizeToContent = SizeToContent.Height, ResizeMode = ResizeMode.NoResize }; Ui.Style(dialog);
        var panel = new StackPanel { Margin = new Thickness(22) }; var name = Ui.Text(existing?.Name ?? "Custom Skill"); var body = Ui.Text(existing?.Body ?? Skill.Builtin.Body, null, true); body.Height = 260;
        var lang = new ComboBox { ItemsSource = new[] { "zh", "en", "any" }, SelectedItem = existing?.Language ?? "any" };
        Add(panel, name); Add(panel, lang); Add(panel, body);
        panel.Children.Add(Ui.Button(Ui.L("保存 Skill", "Save Skill"), () =>
        {
            try { controller.Skills.Save(new(existing?.Id ?? Guid.NewGuid().ToString("N"), name.Text, existing?.Description ?? "", (string)lang.SelectedItem, body.Text)); ReloadSkills(); dialog.Close(); }
            catch (Exception error) { Ui.Error(error); }
        }, "SaveSkill", "PrimaryButton")); dialog.Content = panel; dialog.ShowDialog();
    }
    private void AddWord(PersonalEntry entry)
    {
        var editor = new LexiconEditor(entry, SaveWords, () => { }); wordEditors.Add(editor); wordRows.Children.Add(editor);
        editor.Delete = () => { wordEditors.Remove(editor); wordRows.Children.Remove(editor); SaveWords(); };
    }
    private void SaveWords()
    {
        if (!controller.Lexicon.SequenceEqual(wordSnapshot)) { wordStatus.Text = Ui.L("词库已由其它操作更新；请重新打开设置再编辑。", "Lexicon changed elsewhere. Reopen Settings before editing."); return; }
        try
        {
            var words = wordEditors.Select(e => e.Value).ToArray(); DataStore.ValidateLexicon(words); controller.SaveLexicon(words); wordSnapshot = words; wordStatus.Text = "";
        }
        catch (Exception error) { wordStatus.Text = error is InvalidOperationException ? error.Message : Ui.L("保存失败；原词库未覆盖。", "Save failed. Original lexicon unchanged."); }
    }
}

internal sealed record UiChoice(string Value, string Label)
{
    public override string ToString() => Label;
}
internal sealed class LexiconEditor : StackPanel
{
    private readonly ComboBox kind = new() { ItemsSource = new[] { new UiChoice("replace", Ui.L("替换", "Replace")), new UiChoice("avoid", Ui.L("避免", "Avoid")), new UiChoice("keep", Ui.L("保留", "Keep")) }, DisplayMemberPath = "Label", SelectedValuePath = "Value", Width = 76 };
    private readonly ComboBox match = new() { ItemsSource = new[] { new UiChoice("exact", Ui.L("精确匹配", "Exact")), new UiChoice("caseInsensitive", Ui.L("忽略大小写", "Case-insensitive")), new UiChoice("wholeWord", Ui.L("整词匹配", "Whole word")) }, DisplayMemberPath = "Label", SelectedValuePath = "Value", Width = 140 };
    private readonly TextBox term, replacement;
    public Action Delete { get; set; }
    public PersonalEntry Value => new((string)kind.SelectedValue, term.Text, kind.SelectedValue as string == "replace" ? replacement.Text : null, (string)match.SelectedValue);
    public LexiconEditor(PersonalEntry entry, Action changed, Action delete)
    {
        Delete = delete; Margin = new Thickness(0, 0, 0, 12); kind.SelectedValue = entry.Kind; match.SelectedValue = entry.MatchKind;
        term = Ui.Text(entry.Term); replacement = Ui.Text(entry.Replacement ?? ""); term.Padding = replacement.Padding = new Thickness(8, 5, 8, 5);
        var row = new Grid(); row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto }); row.ColumnDefinitions.Add(new ColumnDefinition()); row.ColumnDefinitions.Add(new ColumnDefinition()); row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.Children.Add(kind); term.Margin = replacement.Margin = new Thickness(8, 0, 0, 0); Grid.SetColumn(term, 1); row.Children.Add(term); Grid.SetColumn(replacement, 2); row.Children.Add(replacement);
        var remove = Ui.Icon("×", Ui.L("删除词条", "Delete entry"), () => Delete()); Grid.SetColumn(remove, 3); row.Children.Add(remove); Children.Add(row);
        replacement.Visibility = entry.Kind == "replace" ? Visibility.Visible : Visibility.Collapsed;
        var advanced = new Expander { Header = Ui.L("匹配方式", "Match mode"), Content = match, FontSize = 10, Margin = new Thickness(0, 4, 0, 0) }; Children.Add(advanced);
        kind.SelectionChanged += (_, _) => { replacement.Visibility = kind.SelectedValue as string == "replace" ? Visibility.Visible : Visibility.Collapsed; changed(); };
        match.SelectionChanged += (_, _) => changed(); term.LostKeyboardFocus += (_, _) => changed(); replacement.LostKeyboardFocus += (_, _) => changed();
    }
}

internal sealed class HotkeyRecorder : Button
{
    public Hotkey Value { get; private set; }
    public void Restore(Hotkey value) { Value = value; Content = Display(value); }
    public HotkeyRecorder(Controller controller, Hotkey value, string id, Action changed)
    {
        Value = value; Content = Display(value); AutomationProperties.SetAutomationId(this, id);
        Click += (_, _) =>
        {
            using var pause = controller.PauseHotkeys();
            var dialog = new Window { Title = Ui.L("记录快捷键", "Record shortcut"), Owner = Window.GetWindow(this), Width = 320, Height = 160, ResizeMode = ResizeMode.NoResize }; Ui.Style(dialog);
            dialog.Content = Ui.Label(Ui.L("按下 Ctrl / Alt / Shift / Win + 字母或功能键。Esc 取消。", "Press Ctrl / Alt / Shift / Win + a letter or function key. Esc cancels."), 13);
            dialog.PreviewKeyDown += (_, e) =>
            {
                var pressed = e.Key == Key.System ? e.SystemKey : e.Key; if (pressed == Key.Escape) { dialog.Close(); return; }
                if (pressed is Key.LeftShift or Key.RightShift or Key.LeftCtrl or Key.RightCtrl or Key.LeftAlt or Key.RightAlt or Key.LWin or Key.RWin) return;
                var modifiers = Keyboard.Modifiers; var key = (uint)KeyInterop.VirtualKeyFromKey(pressed);
                var flags = (uint)(((modifiers & ModifierKeys.Alt) != 0 ? 1 : 0) | ((modifiers & ModifierKeys.Control) != 0 ? 2 : 0) | ((modifiers & ModifierKeys.Shift) != 0 ? 4 : 0) | ((modifiers & ModifierKeys.Windows) != 0 ? 8 : 0));
                if (flags == 0 || key is < 0x30 or > 0x87) return;
                Value = new(flags, key); Content = Display(Value); e.Handled = true; dialog.Close();
            };
            dialog.ShowDialog(); pause.Dispose(); changed();
        };
    }
    private static string Display(Hotkey key) =>
        ((key.Modifiers & 2) != 0 ? "Ctrl + " : "") + ((key.Modifiers & 1) != 0 ? "Alt + " : "") +
        ((key.Modifiers & 4) != 0 ? "Shift + " : "") + ((key.Modifiers & 8) != 0 ? "Win + " : "") +
        (key.Key is >= 0x70 and <= 0x87 ? "F" + (key.Key - 0x6F) : ((char)key.Key).ToString());
}
