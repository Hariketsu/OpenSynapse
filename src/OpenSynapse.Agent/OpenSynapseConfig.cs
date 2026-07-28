using System.Text.Json;
using OpenSynapse.Core;

namespace OpenSynapse.Agent;

internal sealed class OpenSynapseConfig
{
    public const int CurrentSchemaVersion = 10;

    public int SchemaVersion { get; set; } = CurrentSchemaVersion;
    public ModeSelection Selection { get; set; } = ModeSelection.Auto;
    public int BalancedBatteryThresholdPercent { get; set; } = 50;
    public bool ManageAdvancedColor { get; set; } = true;
    public bool ManageBrightness { get; set; } = true;
    public bool ManageDisplayScaling { get; set; } = true;
    public RefreshPolicy RefreshPolicy { get; set; } = RefreshPolicy.FollowMode;
    public int InternalDisplayScalePercent { get; set; } = 150;
    public int ExternalDisplayScalePercent { get; set; } = 125;
    public int BalancedBrightnessPercent { get; set; } = 60;
    public int QuietBrightnessPercent { get; set; } = 40;
    public int BalancedRefreshRateHz { get; set; } = 120;
    public int QuietRefreshRateHz { get; set; } = 60;
    public bool ManageWakeDevices { get; set; }
    public List<string> QuietWakeDeviceNames { get; set; } = [];
    public bool SmartAutomationEnabled { get; set; } = true;
    public int SmartHighPowerCpuEnter { get; set; } = 45;
    public int SmartHighPowerCpuExit { get; set; } = 25;
    public int SmartPortableCpuEnter { get; set; } = 35;
    public int SmartPortableCpuExit { get; set; } = 18;
    public int SmartLoadEnterSamples { get; set; } = 3;
    public int SmartAppEnterSamples { get; set; } = 2;
    public int SmartExitSamples { get; set; } = 12;
    public int SmartMinimumDwellSeconds { get; set; } = 30;
    public int SmartAppCpuFloor { get; set; } = 8;
    public int SmartGpuEnter { get; set; } = 20;
    public int SmartGpuExit { get; set; } = 5;
    public bool SmartFullscreenEnabled { get; set; } = true;
    public int SmartFullscreenCpuFloor { get; set; } = 15;
    public int SmartFullscreenGpuFloor { get; set; } = 15;
    public List<string> SmartIgnoredFullscreenProcesses { get; set; } =
        ["LockApp", "LogonUI", "explorer", "ShellExperienceHost", "StartMenuExperienceHost", "SearchHost", "SearchApp", "TextInputHost", "SystemSettings", "dwm", "Idle"];
    public List<string> SmartHyperProcessNames { get; set; } =
        ["blender", "Resolve", "Adobe Premiere Pro", "AfterFX", "UnrealEditor", "UE4Editor", "Unity", "3dsmax", "maya", "Cinebench", "occt", "FurMark", "FurMark_GUI"];
    public List<string> SmartBalanceProcessNames { get; set; } =
        ["Codex", "Code", "devenv", "WINWORD", "EXCEL", "POWERPNT", "Acrobat", "AcroRd32"];
    public List<ApplicationRule> ApplicationRules { get; set; } = [];
    public int DgpuLeakMemoryMb { get; set; } = 128;
    public double DgpuLeakUtilizationPercent { get; set; } = 1;
    public int DgpuLeakMinimumSamples { get; set; } = 6;
    public double DgpuActivityDischargeThresholdW { get; set; } = 8;
    public HyperCpuPolicy HyperCpuPolicy { get; set; } = HyperCpuPolicy.Sustained;
    public bool AdaptiveQuietCpu { get; set; } = true;
    public int QuietCpuMaxHighBattery { get; set; } = 75;
    public int QuietCpuMaxMediumBattery { get; set; } = 65;
    public int QuietCpuMaxLowBattery { get; set; } = 60;
    public int QuietCpuMediumThreshold { get; set; } = 50;
    public int QuietCpuLowThreshold { get; set; } = 20;
    public bool AdaptiveQuietBrightness { get; set; } = true;
    public bool SeamlessModeSwitching { get; set; } = true;
    public int ProcessMaintenanceSeconds { get; set; } = 180;

    public void Validate()
    {
        if (!Enum.IsDefined(Selection))
            throw new InvalidDataException($"Unsupported mode selection {Selection}.");
        ToDisplayPolicySettings().Validate();
        ToQuietMaintenanceSettings().Validate();
        ToSmartAutomationSettings().Validate();
        if (!Enum.IsDefined(HyperCpuPolicy))
            throw new InvalidDataException($"Unsupported Hyper CPU policy {HyperCpuPolicy}.");
        ValidateRange(QuietCpuMaxHighBattery, 1, 100, nameof(QuietCpuMaxHighBattery));
        ValidateRange(QuietCpuMaxMediumBattery, 1, 100, nameof(QuietCpuMaxMediumBattery));
        ValidateRange(QuietCpuMaxLowBattery, 1, 100, nameof(QuietCpuMaxLowBattery));
        ValidateRange(QuietCpuMediumThreshold, 1, 99, nameof(QuietCpuMediumThreshold));
        ValidateRange(QuietCpuLowThreshold, 0, QuietCpuMediumThreshold - 1, nameof(QuietCpuLowThreshold));
        ValidateRange(DgpuLeakMemoryMb, 1, 16384, nameof(DgpuLeakMemoryMb));
        if (!double.IsFinite(DgpuLeakUtilizationPercent) || DgpuLeakUtilizationPercent is < 0 or > 100)
            throw new InvalidDataException($"{nameof(DgpuLeakUtilizationPercent)} must be between 0 and 100.");
        ValidateRange(DgpuLeakMinimumSamples, 1, 120, nameof(DgpuLeakMinimumSamples));
        if (!double.IsFinite(DgpuActivityDischargeThresholdW) || DgpuActivityDischargeThresholdW is < 0 or > 1000)
            throw new InvalidDataException($"{nameof(DgpuActivityDischargeThresholdW)} must be between 0 and 1000.");
        if (ProcessMaintenanceSeconds is < 30 or > 3600)
            throw new InvalidDataException("Process maintenance interval must be between 30 and 3600 seconds.");
    }

    public DisplayPolicySettings ToDisplayPolicySettings() => new(
        BalancedBatteryThresholdPercent,
        ManageAdvancedColor,
        ManageBrightness,
        ManageDisplayScaling,
        RefreshPolicy,
        InternalDisplayScalePercent,
        ExternalDisplayScalePercent,
        BalancedBrightnessPercent,
        QuietBrightnessPercent,
        BalancedRefreshRateHz,
        QuietRefreshRateHz);

    public OpenSynapseConfig WithDisplayPolicy(DisplayPolicySettings settings)
    {
        settings.Validate();
        var updated = Copy();
        updated.BalancedBatteryThresholdPercent = settings.BalancedBatteryThresholdPercent;
        updated.ManageAdvancedColor = settings.ManageAdvancedColor;
        updated.ManageBrightness = settings.ManageBrightness;
        updated.ManageDisplayScaling = settings.ManageDisplayScaling;
        updated.RefreshPolicy = settings.RefreshPolicy;
        updated.InternalDisplayScalePercent = settings.InternalDisplayScalePercent;
        updated.ExternalDisplayScalePercent = settings.ExternalDisplayScalePercent;
        updated.BalancedBrightnessPercent = settings.BalancedBrightnessPercent;
        updated.QuietBrightnessPercent = settings.QuietBrightnessPercent;
        updated.BalancedRefreshRateHz = settings.BalancedRefreshRateHz;
        updated.QuietRefreshRateHz = settings.QuietRefreshRateHz;
        return updated;
    }

    public QuietMaintenanceSettings ToQuietMaintenanceSettings() => new(
        ManageWakeDevices,
        QuietWakeDeviceNames.AsReadOnly());

    public OpenSynapseConfig WithQuietMaintenance(QuietMaintenanceSettings settings)
    {
        settings.Validate();
        var updated = Copy();
        updated.ManageWakeDevices = settings.ManageWakeDevices;
        updated.QuietWakeDeviceNames = [.. settings.WakeDeviceNames];
        return updated;
    }

    public OpenSynapseConfig WithApplicationRules(IReadOnlyList<ApplicationRule> rules)
    {
        var updated = Copy();
        updated.ApplicationRules = [.. rules];
        updated.ToSmartAutomationSettings().Validate();
        return updated;
    }

    public SmartAutomationSettings ToSmartAutomationSettings() => new(
        SmartAutomationEnabled,
        SmartHighPowerCpuEnter,
        SmartHighPowerCpuExit,
        SmartPortableCpuEnter,
        SmartPortableCpuExit,
        SmartLoadEnterSamples,
        SmartAppEnterSamples,
        SmartExitSamples,
        SmartMinimumDwellSeconds,
        SmartAppCpuFloor,
        SmartGpuEnter,
        SmartGpuExit,
        SmartFullscreenCpuFloor,
        SmartFullscreenGpuFloor,
        BalancedBatteryThresholdPercent,
        SmartHyperProcessNames.AsReadOnly(),
        SmartBalanceProcessNames.AsReadOnly(),
        SmartIgnoredFullscreenProcesses.AsReadOnly(),
        ApplicationRules.AsReadOnly());

    private static void ValidateRange(int value, int minimum, int maximum, string name)
    {
        if (value < minimum || value > maximum)
            throw new InvalidDataException($"{name} must be between {minimum} and {maximum}.");
    }

    private OpenSynapseConfig Copy() => new()
    {
        SchemaVersion = SchemaVersion,
        Selection = Selection,
        BalancedBatteryThresholdPercent = BalancedBatteryThresholdPercent,
        ManageAdvancedColor = ManageAdvancedColor,
        ManageBrightness = ManageBrightness,
        ManageDisplayScaling = ManageDisplayScaling,
        RefreshPolicy = RefreshPolicy,
        InternalDisplayScalePercent = InternalDisplayScalePercent,
        ExternalDisplayScalePercent = ExternalDisplayScalePercent,
        BalancedBrightnessPercent = BalancedBrightnessPercent,
        QuietBrightnessPercent = QuietBrightnessPercent,
        BalancedRefreshRateHz = BalancedRefreshRateHz,
        QuietRefreshRateHz = QuietRefreshRateHz,
        ManageWakeDevices = ManageWakeDevices,
        QuietWakeDeviceNames = [.. QuietWakeDeviceNames],
        SmartAutomationEnabled = SmartAutomationEnabled,
        SmartHighPowerCpuEnter = SmartHighPowerCpuEnter,
        SmartHighPowerCpuExit = SmartHighPowerCpuExit,
        SmartPortableCpuEnter = SmartPortableCpuEnter,
        SmartPortableCpuExit = SmartPortableCpuExit,
        SmartLoadEnterSamples = SmartLoadEnterSamples,
        SmartAppEnterSamples = SmartAppEnterSamples,
        SmartExitSamples = SmartExitSamples,
        SmartMinimumDwellSeconds = SmartMinimumDwellSeconds,
        SmartAppCpuFloor = SmartAppCpuFloor,
        SmartGpuEnter = SmartGpuEnter,
        SmartGpuExit = SmartGpuExit,
        SmartFullscreenEnabled = SmartFullscreenEnabled,
        SmartFullscreenCpuFloor = SmartFullscreenCpuFloor,
        SmartFullscreenGpuFloor = SmartFullscreenGpuFloor,
        SmartIgnoredFullscreenProcesses = [.. SmartIgnoredFullscreenProcesses],
        SmartHyperProcessNames = [.. SmartHyperProcessNames],
        SmartBalanceProcessNames = [.. SmartBalanceProcessNames],
        ApplicationRules = [.. ApplicationRules],
        DgpuLeakMemoryMb = DgpuLeakMemoryMb,
        DgpuLeakUtilizationPercent = DgpuLeakUtilizationPercent,
        DgpuLeakMinimumSamples = DgpuLeakMinimumSamples,
        DgpuActivityDischargeThresholdW = DgpuActivityDischargeThresholdW,
        HyperCpuPolicy = HyperCpuPolicy,
        AdaptiveQuietCpu = AdaptiveQuietCpu,
        QuietCpuMaxHighBattery = QuietCpuMaxHighBattery,
        QuietCpuMaxMediumBattery = QuietCpuMaxMediumBattery,
        QuietCpuMaxLowBattery = QuietCpuMaxLowBattery,
        QuietCpuMediumThreshold = QuietCpuMediumThreshold,
        QuietCpuLowThreshold = QuietCpuLowThreshold,
        AdaptiveQuietBrightness = AdaptiveQuietBrightness,
        SeamlessModeSwitching = SeamlessModeSwitching,
        ProcessMaintenanceSeconds = ProcessMaintenanceSeconds
    };
}

internal sealed class ConfigurationStore
{
    private readonly string path;

    public ConfigurationStore(string? path = null)
    {
        this.path = path ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "OpenSynapse",
            "config.json");
    }

    public OpenSynapseConfig Load(ModeSelection? legacySelection = null)
    {
        if (!File.Exists(path))
        {
            var imported = TryImportPowerPilotConfig();
            if (imported is not null)
            {
                Save(imported);
                return imported;
            }
            var created = new OpenSynapseConfig
            {
                Selection = legacySelection ?? ModeSelection.Auto
            };
            Save(created);
            return created;
        }

        OpenSynapseConfig config;
        try
        {
            config = JsonSerializer.Deserialize<OpenSynapseConfig>(File.ReadAllText(path), AgentJson.Options)
                ?? throw new InvalidDataException("Configuration file is empty.");
        }
        catch (JsonException ex)
        {
            throw new InvalidDataException("Configuration file is not valid JSON and was not overwritten.", ex);
        }

        if (config.SchemaVersion > OpenSynapseConfig.CurrentSchemaVersion)
            throw new NotSupportedException(
                $"Configuration schema {config.SchemaVersion} is newer than supported schema {OpenSynapseConfig.CurrentSchemaVersion}.");
        var requiresMigration = config.SchemaVersion < OpenSynapseConfig.CurrentSchemaVersion;
        config.SchemaVersion = OpenSynapseConfig.CurrentSchemaVersion;
        config.QuietWakeDeviceNames ??= [];
        config.SmartIgnoredFullscreenProcesses ??= [];
        config.SmartHyperProcessNames ??= [];
        config.SmartBalanceProcessNames ??= [];
        config.ApplicationRules ??= [];
        config.Validate();
        if (requiresMigration) Save(config);
        return config;
    }

    private OpenSynapseConfig? TryImportPowerPilotConfig()
    {
        var defaultPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "OpenSynapse",
            "config.json");
        if (!string.Equals(Path.GetFullPath(path), Path.GetFullPath(defaultPath), StringComparison.OrdinalIgnoreCase))
            return null;
        var legacyPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "PowerPilot",
            "config.json");
        if (!File.Exists(legacyPath)) return null;
        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(legacyPath));
            var root = document.RootElement;
            var config = new OpenSynapseConfig();
            if (TryGetString(root, "Selection") is { } selection)
            {
                config.Selection = selection.Equals("Hyper", StringComparison.OrdinalIgnoreCase)
                    ? ModeSelection.Performance
                    : selection.Equals("Balance", StringComparison.OrdinalIgnoreCase)
                        ? ModeSelection.Balanced
                        : selection.Equals("Quiet", StringComparison.OrdinalIgnoreCase)
                            ? ModeSelection.Quiet
                            : ModeSelection.Auto;
            }
            config.SmartAutomationEnabled = TryGetBool(root, "SmartAutomationEnabled") ?? config.SmartAutomationEnabled;
            config.BalancedBatteryThresholdPercent = TryGetInt(root, "BalanceBatteryThreshold")
                ?? TryGetInt(root, "BalancedBatteryThresholdPercent")
                ?? config.BalancedBatteryThresholdPercent;
            config.ManageAdvancedColor = TryGetBool(root, "ManageAdvancedColor") ?? config.ManageAdvancedColor;
            config.ManageBrightness = TryGetBool(root, "ManageBrightness") ?? config.ManageBrightness;
            config.ManageDisplayScaling = TryGetBool(root, "DisplayScalingEnabled") ?? config.ManageDisplayScaling;
            config.InternalDisplayScalePercent = TryGetInt(root, "InternalScale") ?? config.InternalDisplayScalePercent;
            config.ExternalDisplayScalePercent = TryGetInt(root, "ExternalScale") ?? config.ExternalDisplayScalePercent;
            config.BalancedBrightnessPercent = TryGetInt(root, "BalanceBrightness") ?? config.BalancedBrightnessPercent;
            config.QuietBrightnessPercent = TryGetInt(root, "QuietBrightness") ?? config.QuietBrightnessPercent;
            config.QuietRefreshRateHz = TryGetInt(root, "QuietRefreshRate") ?? config.QuietRefreshRateHz;
            config.BalancedRefreshRateHz = TryGetInt(root, "BalanceRefreshRate") ?? config.BalancedRefreshRateHz;
            if (TryGetString(root, "RefreshPolicy") is { } refresh)
            {
                config.RefreshPolicy = refresh switch
                {
                    "DynamicNative" => RefreshPolicy.DynamicNative,
                    "Fixed60" => RefreshPolicy.Fixed60,
                    "Fixed120" => RefreshPolicy.Fixed120,
                    "Fixed240" => RefreshPolicy.Fixed240,
                    "Unmanaged" => RefreshPolicy.Unmanaged,
                    _ => RefreshPolicy.FollowMode
                };
            }
            config.SmartHighPowerCpuEnter = TryGetInt(root, "SmartHighPowerCpuEnter") ?? config.SmartHighPowerCpuEnter;
            config.SmartHighPowerCpuExit = TryGetInt(root, "SmartHighPowerCpuExit") ?? config.SmartHighPowerCpuExit;
            config.SmartPortableCpuEnter = TryGetInt(root, "SmartPortableCpuEnter") ?? config.SmartPortableCpuEnter;
            config.SmartPortableCpuExit = TryGetInt(root, "SmartPortableCpuExit") ?? config.SmartPortableCpuExit;
            config.SmartLoadEnterSamples = TryGetInt(root, "SmartLoadEnterSamples") ?? config.SmartLoadEnterSamples;
            config.SmartAppEnterSamples = TryGetInt(root, "SmartAppEnterSamples") ?? config.SmartAppEnterSamples;
            config.SmartExitSamples = TryGetInt(root, "SmartExitSamples") ?? config.SmartExitSamples;
            config.SmartMinimumDwellSeconds = TryGetInt(root, "SmartMinimumDwellSeconds") ?? config.SmartMinimumDwellSeconds;
            config.SmartAppCpuFloor = TryGetInt(root, "SmartAppCpuFloor") ?? config.SmartAppCpuFloor;
            config.SmartGpuEnter = TryGetInt(root, "SmartGpuEnter") ?? config.SmartGpuEnter;
            config.SmartGpuExit = TryGetInt(root, "SmartGpuExit") ?? config.SmartGpuExit;
            ImportNames(root, "SmartHyperProcessNames", config.SmartHyperProcessNames);
            ImportNames(root, "SmartBalanceProcessNames", config.SmartBalanceProcessNames);
            ImportRules(root, config.ApplicationRules);
            config.SchemaVersion = OpenSynapseConfig.CurrentSchemaVersion;
            config.Validate();
            return config;
        }
        catch { return null; }
    }

    private static void ImportNames(JsonElement root, string property, List<string> destination)
    {
        if (!TryGetProperty(root, property, out var value) || value.ValueKind != JsonValueKind.Array) return;
        destination.Clear();
        foreach (var item in value.EnumerateArray())
            if (item.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(item.GetString()))
                destination.Add(item.GetString()!.Trim());
    }

    private static void ImportRules(JsonElement root, List<ApplicationRule> destination)
    {
        if (!TryGetProperty(root, "ApplicationRules", out var value) || value.ValueKind != JsonValueKind.Array) return;
        foreach (var item in value.EnumerateArray())
        {
            var process = TryGetString(item, "ProcessName");
            var profile = TryGetString(item, "Profile");
            var scope = TryGetString(item, "Scope");
            if (process is null || profile is null || scope is null) continue;
            var mappedProfile = profile.Equals("Hyper", StringComparison.OrdinalIgnoreCase)
                ? ApplicationRuleProfile.Performance
                : profile.Equals("Balance", StringComparison.OrdinalIgnoreCase)
                    ? ApplicationRuleProfile.Balanced
                    : ApplicationRuleProfile.Quiet;
            if (!Enum.TryParse<ApplicationRuleScope>(scope, true, out var mappedScope)) continue;
            var enabled = TryGetBool(item, "Enabled") ?? true;
            destination.Add(new ApplicationRule(process, mappedProfile, mappedScope, enabled));
        }
    }

    private static string? TryGetString(JsonElement root, string name) =>
        TryGetProperty(root, name, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;

    private static int? TryGetInt(JsonElement root, string name) =>
        TryGetProperty(root, name, out var value) && value.TryGetInt32(out var result) ? result : null;

    private static bool? TryGetBool(JsonElement root, string name) =>
        TryGetProperty(root, name, out var value) && value.ValueKind is JsonValueKind.True or JsonValueKind.False
            ? value.GetBoolean()
            : null;

    private static bool TryGetProperty(JsonElement root, string name, out JsonElement value)
    {
        foreach (var property in root.EnumerateObject())
        {
            if (property.Name.Equals(name, StringComparison.OrdinalIgnoreCase))
            {
                value = property.Value;
                return true;
            }
        }
        value = default;
        return false;
    }

    public void Save(OpenSynapseConfig config)
    {
        if (config.SchemaVersion > OpenSynapseConfig.CurrentSchemaVersion)
            throw new NotSupportedException(
                $"Configuration schema {config.SchemaVersion} is newer than supported schema {OpenSynapseConfig.CurrentSchemaVersion}.");
        config.SchemaVersion = OpenSynapseConfig.CurrentSchemaVersion;
        config.Validate();
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temporary = path + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(config, AgentJson.Options));
        File.Move(temporary, path, true);
    }
}
