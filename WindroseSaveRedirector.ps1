Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = "Stop"

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-LocalAppDataPath {
    return [Environment]::GetFolderPath("LocalApplicationData")
}

function Get-KnownSavePath {
    return (Join-Path (Get-LocalAppDataPath) "R5\Saved")
}

function Convert-EscapedText {
    param([string]$Text)
    return [regex]::Replace($Text, "\\u([0-9a-fA-F]{4})", {
        param($m)
        return [char]([Convert]::ToInt32($m.Groups[1].Value, 16))
    })
}

function T {
    param([string]$Key)
    $value = $script:Strings[$script:Language][$Key]
    if (-not $value) { $value = $script:Strings["EN"][$Key] }
    return (Convert-EscapedText $value)
}

function Set-TextBoxValue {
    param(
        [System.Windows.Forms.Control]$Box,
        [string]$Value
    )
    $Box.Text = $Value
    if ($Box -is [System.Windows.Forms.TextBox]) {
        $Box.Select(0, 0)
        $Box.ScrollToCaret()
    }
}

function Get-SteamRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    $regPaths = @(
        "HKCU:\Software\Valve\Steam",
        "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
        "HKLM:\SOFTWARE\Valve\Steam"
    )
    foreach ($reg in $regPaths) {
        try {
            $props = Get-ItemProperty -Path $reg -ErrorAction Stop
            foreach ($name in @("SteamPath", "InstallPath")) {
                if ($props.$name) {
                    $p = $props.$name -replace "/", "\"
                    if (Test-Path -LiteralPath $p) { $roots.Add($p) }
                }
            }
        }
        catch { }
    }

    @(
        (Join-Path ${env:ProgramFiles(x86)} "Steam"),
        (Join-Path $env:ProgramFiles "Steam")
    ) | ForEach-Object {
        if ($_ -and (Test-Path -LiteralPath $_)) { $roots.Add($_) }
    }

    return $roots | Select-Object -Unique
}

function Read-SteamLibraryPaths {
    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($root in Get-SteamRoots) {
        if (Test-Path -LiteralPath $root) {
            $paths.Add($root)
            $vdf = Join-Path $root "steamapps\libraryfolders.vdf"
            if (Test-Path -LiteralPath $vdf) {
                $text = Get-Content -LiteralPath $vdf -Raw
                [regex]::Matches($text, '"path"\s+"([^"]+)"') | ForEach-Object {
                    $p = $_.Groups[1].Value -replace "\\\\", "\"
                    if ($p -and (Test-Path -LiteralPath $p)) {
                        $paths.Add($p)
                    }
                }
            }
        }
    }

    return $paths | Select-Object -Unique
}

function Find-WindroseGame {
    foreach ($library in Read-SteamLibraryPaths) {
        $manifest = Join-Path $library "steamapps\appmanifest_3041230.acf"
        if (Test-Path -LiteralPath $manifest) {
            $text = Get-Content -LiteralPath $manifest -Raw
            $installDir = "Windrose"
            $match = [regex]::Match($text, '"installdir"\s+"([^"]+)"')
            if ($match.Success) { $installDir = $match.Groups[1].Value }
            $path = Join-Path $library ("steamapps\common\" + $installDir)
            if (Test-Path -LiteralPath $path) {
                return [PSCustomObject]@{ Path = $path; Source = "steam"; AppId = "3041230" }
            }
        }
    }

    foreach ($library in Read-SteamLibraryPaths) {
        $common = Join-Path $library "steamapps\common"
        if (Test-Path -LiteralPath $common) {
            $hit = Get-ChildItem -LiteralPath $common -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq "Windrose" } |
                Select-Object -First 1
            if ($hit) {
                return [PSCustomObject]@{ Path = $hit.FullName; Source = "folder"; AppId = "unknown" }
            }
        }
    }

    return $null
}

function Find-WindroseSavePath {
    $steamRoot = Get-SteamRoots | Select-Object -First 1
    if ($steamRoot) {
        $userdata = Join-Path $steamRoot "userdata"
        if (Test-Path -LiteralPath $userdata) {
            $cache = Get-ChildItem -LiteralPath $userdata -Recurse -Filter "remotecache.vdf" -File -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match "\\3041230\\remotecache\.vdf$" } |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
            if ($cache) {
                try {
                    $text = Get-Content -LiteralPath $cache.FullName -Raw
                    $match = [regex]::Match($text, '"([^"/\\]+)[/\\]Saved[/\\]')
                    if ($match.Success) {
                        $project = $match.Groups[1].Value
                        return (Join-Path (Get-LocalAppDataPath) "$project\Saved")
                    }
                }
                catch { }
            }
        }
    }

    return Get-KnownSavePath
}

function Get-WindroseTargetPath {
    param([string]$BasePath)
    if ([string]::IsNullOrWhiteSpace($BasePath)) { return "" }
    $leaf = Split-Path -Leaf $BasePath
    if ($leaf -eq "Windrose Saves") { return $BasePath }
    return (Join-Path $BasePath "Windrose Saves")
}

function Test-ProcessRunning {
    $names = @("Windrose", "Windrose-Win64-Shipping")
    return @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $names -contains $_.ProcessName }).Count -gt 0
}

function Write-Log {
    param([string]$Message)
    $script:LogBox.AppendText(("[{0}] {1}`r`n" -f (Get-Date -Format "HH:mm:ss"), $Message))
}

function Set-Status {
    param([string]$Message, [System.Drawing.Color]$Color = $null)
    $script:StatusLabel.Text = $Message
    if ($Color) { $script:StatusLabel.ForeColor = $Color }
}

function Get-RedirectState {
    param([string]$SavePath)
    if (-not (Test-Path -LiteralPath $SavePath)) {
        return "missing"
    }
    $item = Get-Item -LiteralPath $SavePath -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq [IO.FileAttributes]::ReparsePoint) {
        return "redirected"
    }
    return "normal"
}

function Ensure-AdminOrAsk {
    if (Test-IsAdmin) { return $true }
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "Windows may require elevated rights to move saves and create a junction. Restart this utility as administrator?",
        "Captain rights required",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
        Start-Process -FilePath "powershell.exe" -ArgumentList @("-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"") -Verb RunAs
        $script:MainForm.Close()
    }
    return $false
}

function Invoke-Redirect {
    param(
        [string]$SavePath,
        [string]$TargetPath
    )

    if (Test-ProcessRunning) {
        throw "Windrose is running. Close the game before moving saves."
    }

    if (-not (Test-Path -LiteralPath $SavePath)) {
        throw "Save folder was not found: $SavePath"
    }

    $state = Get-RedirectState -SavePath $SavePath
    if ($state -eq "redirected") {
        throw "Save folder already looks redirected."
    }

    if (Test-Path -LiteralPath $TargetPath) {
        $existing = @(Get-ChildItem -LiteralPath $TargetPath -Force -ErrorAction SilentlyContinue)
        if ($existing.Count -gt 0) {
            throw "Target folder is not empty: $TargetPath. Choose an empty folder or a new folder."
        }
    }

    $targetParent = Split-Path -Parent $TargetPath
    if (-not (Test-Path -LiteralPath $targetParent)) {
        New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
    }

    $backupRoot = Join-Path $targetParent ("WindroseBackup-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
    Write-Log "Creating backup: $backupRoot"
    Copy-Item -LiteralPath $SavePath -Destination $backupRoot -Recurse -Force

    Write-Log "Moving saves: $TargetPath"
    Move-Item -LiteralPath $SavePath -Destination $TargetPath

    try {
        Write-Log "Creating junction at the old save path."
        New-Item -ItemType Junction -Path $SavePath -Target $TargetPath | Out-Null
    }
    catch {
        Write-Log "Failed to create junction. Moving saves back."
        if (Test-Path -LiteralPath $SavePath) {
            Remove-Item -LiteralPath $SavePath -Force
        }
        Move-Item -LiteralPath $TargetPath -Destination $SavePath
        throw
    }

    $testFile = Join-Path $SavePath ".windrose_redirect_test"
    "ok" | Set-Content -LiteralPath $testFile -Encoding ASCII
    Remove-Item -LiteralPath $testFile -Force
    Write-Log "Write test through the old path passed."
}

function Invoke-Restore {
    param(
        [string]$SavePath,
        [string]$TargetPath
    )

    if (Test-ProcessRunning) {
        throw "Windrose is running. Close the game before restoring."
    }

    if ((Get-RedirectState -SavePath $SavePath) -ne "redirected") {
        throw "Old path does not look like a junction: $SavePath"
    }

    if (-not (Test-Path -LiteralPath $TargetPath)) {
        throw "Target folder was not found: $TargetPath"
    }

    Write-Log "Removing junction: $SavePath"
    Remove-Item -LiteralPath $SavePath -Force

    Write-Log "Moving saves back to the old path."
    Move-Item -LiteralPath $TargetPath -Destination $SavePath
}

$script:MainForm = New-Object System.Windows.Forms.Form
$script:MainForm.Text = "Windrose Save Redirector"
$script:MainForm.StartPosition = "CenterScreen"
$script:MainForm.Size = New-Object System.Drawing.Size(980, 700)
$script:MainForm.MinimumSize = New-Object System.Drawing.Size(920, 640)
$script:MainForm.BackColor = [System.Drawing.Color]::FromArgb(18, 27, 34)
$script:MainForm.Font = New-Object System.Drawing.Font("Segoe UI", 10)

$gold = [System.Drawing.Color]::FromArgb(226, 178, 83)
$ink = [System.Drawing.Color]::FromArgb(18, 27, 34)
$panel = [System.Drawing.Color]::FromArgb(30, 44, 52)
$panel2 = [System.Drawing.Color]::FromArgb(40, 59, 68)
$text = [System.Drawing.Color]::FromArgb(242, 234, 214)
$muted = [System.Drawing.Color]::FromArgb(178, 190, 187)
$red = [System.Drawing.Color]::FromArgb(183, 69, 58)
$green = [System.Drawing.Color]::FromArgb(96, 176, 123)
$script:Language = "EN"
$script:DriveDetectionFailed = $false
$script:Strings = @{
    EN = @{
        Subtitle = "A pirate chart for your saves: the game stays put, heavy writes sail to another drive."
        Game = "Game"
        Saves = "Saves"
        TargetDrive = "Target drive"
        TargetFolder = "Move to"
        Find = "Find"
        Browse = "Browse"
        Refresh = "Refresh chart"
        Move = "Move saves"
        Check = "Check"
        Restore = "Restore"
        Open = "Open folder"
        Lang = "RU"
        MoveHelp = "Move saves"
        CheckHelp = "Show save status"
        RestoreHelp = "Undo redirect"
        OpenHelp = "Open moved save folder"
        TargetHint = "Choose where to move saves. The save folder will be created there automatically."
        Searching = "Searching Steam libraries for Windrose."
        GameFound = "Game found: {0}"
        GameMissing = "Game was not found automatically."
        SavesFound = "Saves found. Choose a target folder."
        SaveFolderFound = "Save folder found: {0}"
        AlreadyRedirected = "Saves are already redirected."
        LinkFound = "Save folder is already a link: {0}"
        SaveMissing = "Save folder was not found. Run the game once or set the path manually."
        SaveMissingLog = "Save folder was not found: {0}"
        ChooseFolder = "Choose where to move Windrose saves"
        SaveState = "Save state: {0}"
        CheckLinked = "Check: old path already goes through a link."
        CheckNormal = "Check: saves are still a normal folder."
        CheckMissing = "Check: save folder was not found."
        ConfirmMove = "A backup will be created, then the save folder will be moved:`n`n{0}`n->`n{1}`n`nContinue?"
        ConfirmMoveTitle = "Confirm move"
        ConfirmRestore = "Move saves back to the old path and remove the junction?"
        ConfirmRestoreTitle = "Confirm restore"
        DoneMove = "Done: saves are redirected to the selected drive."
        DoneRestore = "Done: saves are restored to the old path."
        ErrorPrefix = "Error: {0}"
    }
    RU = @{
        Subtitle = "\u041f\u0438\u0440\u0430\u0442\u0441\u043a\u0430\u044f \u043a\u0430\u0440\u0442\u0430 \u0434\u043b\u044f \u0441\u0435\u0439\u0432\u043e\u0432: \u0438\u0433\u0440\u0430 \u043e\u0441\u0442\u0430\u0435\u0442\u0441\u044f \u043d\u0430 \u043c\u0435\u0441\u0442\u0435, \u0430 \u0437\u0430\u043f\u0438\u0441\u044c \u0443\u0445\u043e\u0434\u0438\u0442 \u043d\u0430 HDD."
        Game = "\u0418\u0433\u0440\u0430"
        Saves = "\u0421\u0435\u0439\u0432\u044b"
        TargetDrive = "\u0414\u0438\u0441\u043a HDD"
        TargetFolder = "\u041a\u0443\u0434\u0430 \u043f\u0435\u0440\u0435\u043d\u0435\u0441\u0442\u0438"
        Find = "\u041d\u0430\u0439\u0442\u0438"
        Browse = "\u0412\u044b\u0431\u0440\u0430\u0442\u044c"
        Refresh = "\u041e\u0431\u043d\u043e\u0432\u0438\u0442\u044c"
        Move = "\u041f\u0435\u0440\u0435\u043d\u0435\u0441\u0442\u0438"
        Check = "\u041f\u0440\u043e\u0432\u0435\u0440\u0438\u0442\u044c"
        Restore = "\u041e\u0442\u043a\u0430\u0442"
        Open = "\u041e\u0442\u043a\u0440\u044b\u0442\u044c"
        Lang = "EN"
        MoveHelp = "\u041f\u0435\u0440\u0435\u043d\u043e\u0441 \u0441\u043e\u0445\u0440\u0430\u043d\u0435\u043d\u0438\u0439"
        CheckHelp = "\u041f\u043e\u043a\u0430\u0437\u0430\u0442\u044c \u0441\u0442\u0430\u0442\u0443\u0441 \u0441\u043e\u0445\u0440\u0430\u043d\u0435\u043d\u0438\u044f"
        RestoreHelp = "\u041e\u0442\u043c\u0435\u043d\u0438\u0442\u044c \u043f\u0435\u0440\u0435\u043d\u043e\u0441"
        OpenHelp = "\u041e\u0442\u043a\u0440\u044b\u0442\u044c \u043f\u0430\u043f\u043a\u0443 \u043f\u0435\u0440\u0435\u043d\u0435\u0441\u0435\u043d\u043d\u044b\u0445 \u0441\u043e\u0445\u0440\u0430\u043d\u0435\u043d\u0438\u0439"
        TargetHint = "\u0423\u043a\u0430\u0436\u0438\u0442\u0435 \u043f\u0443\u0442\u044c \u0434\u043b\u044f \u043f\u0435\u0440\u0435\u043d\u043e\u0441\u0430 \u0441\u043e\u0445\u0440\u0430\u043d\u0435\u043d\u0438\u0439. \u041f\u0430\u043f\u043a\u0430 \u0441 \u0441\u043e\u0445\u0440\u0430\u043d\u0435\u043d\u0438\u044f\u043c\u0438 \u0431\u0443\u0434\u0435\u0442 \u0441\u043e\u0437\u0434\u0430\u043d\u0430 \u043f\u043e \u044d\u0442\u043e\u043c\u0443 \u043f\u0443\u0442\u0438 \u0430\u0432\u0442\u043e\u043c\u0430\u0442\u0438\u0447\u0435\u0441\u043a\u0438."
        Searching = "\u0418\u0449\u0443 Windrose \u0432 Steam-\u0431\u0438\u0431\u043b\u0438\u043e\u0442\u0435\u043a\u0430\u0445."
        GameFound = "\u0418\u0433\u0440\u0430 \u043d\u0430\u0439\u0434\u0435\u043d\u0430: {0}"
        GameMissing = "\u0418\u0433\u0440\u0430 \u043d\u0435 \u043d\u0430\u0439\u0434\u0435\u043d\u0430 \u0430\u0432\u0442\u043e\u043c\u0430\u0442\u0438\u0447\u0435\u0441\u043a\u0438."
        SavesFound = "\u0421\u0435\u0439\u0432\u044b \u043d\u0430\u0439\u0434\u0435\u043d\u044b. \u0412\u044b\u0431\u0435\u0440\u0438 \u043f\u0430\u043f\u043a\u0443 \u043d\u0430 HDD."
        SaveFolderFound = "\u041f\u0430\u043f\u043a\u0430 \u0441\u0435\u0439\u0432\u043e\u0432 \u043d\u0430\u0439\u0434\u0435\u043d\u0430: {0}"
        AlreadyRedirected = "\u0421\u0435\u0439\u0432\u044b \u0443\u0436\u0435 \u043f\u0435\u0440\u0435\u043d\u0430\u043f\u0440\u0430\u0432\u043b\u0435\u043d\u044b."
        LinkFound = "\u041f\u0430\u043f\u043a\u0430 \u0441\u0435\u0439\u0432\u043e\u0432 \u0443\u0436\u0435 \u0441\u0441\u044b\u043b\u043a\u0430: {0}"
        SaveMissing = "\u041f\u0430\u043f\u043a\u0430 \u0441\u0435\u0439\u0432\u043e\u0432 \u043d\u0435 \u043d\u0430\u0439\u0434\u0435\u043d\u0430. \u0417\u0430\u043f\u0443\u0441\u0442\u0438 \u0438\u0433\u0440\u0443 \u043e\u0434\u0438\u043d \u0440\u0430\u0437 \u0438\u043b\u0438 \u0443\u043a\u0430\u0436\u0438 \u043f\u0443\u0442\u044c."
        SaveMissingLog = "\u041f\u0430\u043f\u043a\u0430 \u0441\u0435\u0439\u0432\u043e\u0432 \u043d\u0435 \u043d\u0430\u0439\u0434\u0435\u043d\u0430: {0}"
        ChooseFolder = "\u0412\u044b\u0431\u0435\u0440\u0438, \u043a\u0443\u0434\u0430 \u043f\u0435\u0440\u0435\u043d\u0435\u0441\u0442\u0438 \u0441\u0435\u0439\u0432\u044b Windrose"
        SaveState = "\u0421\u043e\u0441\u0442\u043e\u044f\u043d\u0438\u0435 \u0441\u0435\u0439\u0432\u043e\u0432: {0}"
        CheckLinked = "\u041f\u0440\u043e\u0432\u0435\u0440\u043a\u0430: \u0441\u0442\u0430\u0440\u044b\u0439 \u043f\u0443\u0442\u044c \u0443\u0436\u0435 \u0432\u0435\u0434\u0435\u0442 \u0447\u0435\u0440\u0435\u0437 \u0441\u0441\u044b\u043b\u043a\u0443."
        CheckNormal = "\u041f\u0440\u043e\u0432\u0435\u0440\u043a\u0430: \u0441\u0435\u0439\u0432\u044b \u043f\u043e\u043a\u0430 \u043b\u0435\u0436\u0430\u0442 \u043e\u0431\u044b\u0447\u043d\u043e\u0439 \u043f\u0430\u043f\u043a\u043e\u0439."
        CheckMissing = "\u041f\u0440\u043e\u0432\u0435\u0440\u043a\u0430: \u043f\u0430\u043f\u043a\u0430 \u0441\u0435\u0439\u0432\u043e\u0432 \u043d\u0435 \u043d\u0430\u0439\u0434\u0435\u043d\u0430."
        ConfirmMove = "\u0411\u0443\u0434\u0435\u0442 \u0441\u043e\u0437\u0434\u0430\u043d backup, \u0437\u0430\u0442\u0435\u043c \u043f\u0430\u043f\u043a\u0430 \u0441\u0435\u0439\u0432\u043e\u0432 \u0431\u0443\u0434\u0435\u0442 \u043f\u0435\u0440\u0435\u043d\u0435\u0441\u0435\u043d\u0430:`n`n{0}`n->`n{1}`n`n\u041f\u0440\u043e\u0434\u043e\u043b\u0436\u0438\u0442\u044c?"
        ConfirmMoveTitle = "\u041f\u043e\u0434\u0442\u0432\u0435\u0440\u0434\u0438\u0442\u044c"
        ConfirmRestore = "\u0412\u0435\u0440\u043d\u0443\u0442\u044c \u0441\u0435\u0439\u0432\u044b \u043d\u0430 \u0441\u0442\u0430\u0440\u043e\u0435 \u043c\u0435\u0441\u0442\u043e \u0438 \u0443\u0434\u0430\u043b\u0438\u0442\u044c junction?"
        ConfirmRestoreTitle = "\u041f\u043e\u0434\u0442\u0432\u0435\u0440\u0434\u0438\u0442\u044c \u043e\u0442\u043a\u0430\u0442"
        DoneMove = "\u0413\u043e\u0442\u043e\u0432\u043e: \u0441\u0435\u0439\u0432\u044b \u043f\u0435\u0440\u0435\u043d\u0430\u043f\u0440\u0430\u0432\u043b\u0435\u043d\u044b \u043d\u0430 HDD."
        DoneRestore = "\u0413\u043e\u0442\u043e\u0432\u043e: \u0441\u0435\u0439\u0432\u044b \u0432\u0435\u0440\u043d\u0443\u043b\u0438\u0441\u044c \u043d\u0430 \u0441\u0442\u0430\u0440\u043e\u0435 \u043c\u0435\u0441\u0442\u043e."
        ErrorPrefix = "\u041e\u0448\u0438\u0431\u043a\u0430: {0}"
    }
}

$title = New-Object System.Windows.Forms.Label
$title.Text = "Windrose Save Redirector"
$title.Font = New-Object System.Drawing.Font("Georgia", 25, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = $gold
$title.BackColor = [System.Drawing.Color]::Transparent
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(28, 20)
$script:MainForm.Controls.Add($title)

function New-Label($caption, $x, $y) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $caption
    $label.ForeColor = $muted
    $label.BackColor = $panel
    $label.Location = New-Object System.Drawing.Point($x, $y)
    $label.Size = New-Object System.Drawing.Size(155, 24)
    return $label
}

function New-HelpLabel($caption, $x, $y, $w) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $caption
    $label.ForeColor = $muted
    $label.BackColor = $panel
    $label.Location = New-Object System.Drawing.Point($x, $y)
    $label.Size = New-Object System.Drawing.Size($w, 42)
    $label.TextAlign = "TopCenter"
    $label.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $label.AutoEllipsis = $false
    return $label
}

function New-HintLabel($caption, $x, $y, $w) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $caption
    $label.ForeColor = $muted
    $label.BackColor = $panel
    $label.Location = New-Object System.Drawing.Point($x, $y)
    $label.Size = New-Object System.Drawing.Size($w, 34)
    $label.TextAlign = "TopLeft"
    $label.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    return $label
}

function New-TextBox($x, $y, $w) {
    $box = New-Object System.Windows.Forms.Label
    $box.Location = New-Object System.Drawing.Point($x, $y)
    $box.Size = New-Object System.Drawing.Size($w, 28)
    $box.BackColor = [System.Drawing.Color]::FromArgb(12, 19, 24)
    $box.ForeColor = $text
    $box.BorderStyle = "FixedSingle"
    $box.TextAlign = "MiddleLeft"
    $box.Padding = New-Object System.Windows.Forms.Padding(6, 0, 6, 0)
    return $box
}

function New-Button($caption, $x, $y, $w, $accent = $false) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $caption
    $button.Location = New-Object System.Drawing.Point($x, $y)
    $button.Size = New-Object System.Drawing.Size($w, 34)
    $button.FlatStyle = "Flat"
    $button.FlatAppearance.BorderColor = if ($accent) { $gold } else { $panel2 }
    $button.BackColor = if ($accent) { $gold } else { $panel2 }
    $button.ForeColor = if ($accent) { $ink } else { $text }
    $button.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    return $button
}

$langButton = New-Button (T "Lang") 862 28 60
$script:MainForm.Controls.Add($langButton)

$card = New-Object System.Windows.Forms.Panel
$card.Location = New-Object System.Drawing.Point(28, 108)
$card.Size = New-Object System.Drawing.Size(912, 282)
$card.BackColor = $panel
$script:MainForm.Controls.Add($card)

$gameLabel = New-Label (T "Game") 22 24
$card.Controls.Add($gameLabel)
$script:GamePathBox = New-TextBox 198 20 600
$card.Controls.Add($script:GamePathBox)
$findButton = New-Button (T "Find") 812 18 92 $true
$card.Controls.Add($findButton)

$savesLabel = New-Label (T "Saves") 22 72
$card.Controls.Add($savesLabel)
$script:SavePathBox = New-TextBox 198 68 706
Set-TextBoxValue $script:SavePathBox ""
$card.Controls.Add($script:SavePathBox)

$targetLabel = New-Label (T "TargetFolder") 22 120
$card.Controls.Add($targetLabel)
$script:TargetPathBox = New-TextBox 198 116 600
$card.Controls.Add($script:TargetPathBox)
$browseButton = New-Button (T "Browse") 812 114 92
$card.Controls.Add($browseButton)

$targetHintLabel = New-HintLabel (T "TargetHint") 198 148 706
$card.Controls.Add($targetHintLabel)

$redirectButton = New-Button (T "Move") 198 196 160 $true
$checkButton = New-Button (T "Check") 370 196 160
$restoreButton = New-Button (T "Restore") 542 196 160
$openButton = New-Button (T "Open") 714 196 160
$checkButton.FlatAppearance.BorderColor = $gold
$restoreButton.FlatAppearance.BorderColor = $gold
$openButton.FlatAppearance.BorderColor = $gold
$card.Controls.AddRange(@($redirectButton, $checkButton, $restoreButton, $openButton))

$moveHelpLabel = New-HelpLabel (T "MoveHelp") 198 234 160
$checkHelpLabel = New-HelpLabel (T "CheckHelp") 370 234 160
$restoreHelpLabel = New-HelpLabel (T "RestoreHelp") 542 234 160
$openHelpLabel = New-HelpLabel (T "OpenHelp") 714 234 160
$card.Controls.AddRange(@($moveHelpLabel, $checkHelpLabel, $restoreHelpLabel, $openHelpLabel))

$script:StatusLabel = New-Object System.Windows.Forms.Label
$script:StatusLabel.Location = New-Object System.Drawing.Point(28, 410)
$script:StatusLabel.Size = New-Object System.Drawing.Size(912, 28)
$script:StatusLabel.ForeColor = $muted
$script:StatusLabel.BackColor = [System.Drawing.Color]::Transparent
$script:StatusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$script:MainForm.Controls.Add($script:StatusLabel)

$script:LogBox = New-Object System.Windows.Forms.TextBox
$script:LogBox.Location = New-Object System.Drawing.Point(28, 450)
$script:LogBox.Size = New-Object System.Drawing.Size(912, 180)
$script:LogBox.Multiline = $true
$script:LogBox.ScrollBars = "Vertical"
$script:LogBox.ReadOnly = $true
$script:LogBox.BackColor = [System.Drawing.Color]::FromArgb(8, 13, 16)
$script:LogBox.ForeColor = [System.Drawing.Color]::FromArgb(220, 232, 220)
$script:LogBox.BorderStyle = "FixedSingle"
$script:LogBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$script:MainForm.Controls.Add($script:LogBox)

function Apply-Language {
    $gameLabel.Text = T "Game"
    $savesLabel.Text = T "Saves"
    $targetLabel.Text = T "TargetFolder"
    $findButton.Text = T "Find"
    $browseButton.Text = T "Browse"
    $redirectButton.Text = T "Move"
    $checkButton.Text = T "Check"
    $restoreButton.Text = T "Restore"
    $openButton.Text = T "Open"
    $langButton.Text = T "Lang"
    $moveHelpLabel.Text = T "MoveHelp"
    $checkHelpLabel.Text = T "CheckHelp"
    $restoreHelpLabel.Text = T "RestoreHelp"
    $openHelpLabel.Text = T "OpenHelp"
    $targetHintLabel.Text = T "TargetHint"
}

function Refresh-Discovery {
    Write-Log (T "Searching")
    $game = Find-WindroseGame
    if ($game) {
        Set-TextBoxValue $script:GamePathBox $game.Path
        Write-Log ([string]::Format((T "GameFound"), $game.Path))
    }
    else {
        Set-TextBoxValue $script:GamePathBox ""
        Write-Log (T "GameMissing")
    }

    $savePath = Find-WindroseSavePath
    Set-TextBoxValue $script:SavePathBox $savePath
    $state = Get-RedirectState -SavePath $savePath
    if ($state -eq "normal") {
        Set-Status (T "SavesFound") $green
        Write-Log ([string]::Format((T "SaveFolderFound"), $savePath))
    }
    elseif ($state -eq "redirected") {
        Set-Status (T "AlreadyRedirected") $gold
        Write-Log ([string]::Format((T "LinkFound"), $savePath))
    }
    else {
        Set-Status (T "SaveMissing") $red
        Write-Log ([string]::Format((T "SaveMissingLog"), $savePath))
    }
}

$findButton.Add_Click({ Refresh-Discovery })
$browseButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = T "ChooseFolder"
    $dialog.ShowNewFolderButton = $true
    if ($dialog.ShowDialog($script:MainForm) -eq [System.Windows.Forms.DialogResult]::OK) {
        Set-TextBoxValue $script:TargetPathBox (Get-WindroseTargetPath $dialog.SelectedPath)
    }
})

$checkButton.Add_Click({
    try {
        $state = Get-RedirectState -SavePath $script:SavePathBox.Text
        Write-Log ([string]::Format((T "SaveState"), $state))
        if ($state -eq "redirected") {
            Set-Status (T "CheckLinked") $gold
        }
        elseif ($state -eq "normal") {
            Set-Status (T "CheckNormal") $green
        }
        else {
            Set-Status (T "CheckMissing") $red
        }
    }
    catch {
        Set-Status $_.Exception.Message $red
        Write-Log $_.Exception.Message
    }
})

$openButton.Add_Click({
    try {
        $path = $script:TargetPathBox.Text
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            if (-not (Test-Path -LiteralPath $path)) {
                New-Item -ItemType Directory -Path $path -Force | Out-Null
            }
            Start-Process -FilePath explorer.exe -ArgumentList @($path)
        }
    }
    catch {
        Set-Status $_.Exception.Message $red
        Write-Log ([string]::Format((T "ErrorPrefix"), $_.Exception.Message))
    }
})

$redirectButton.Add_Click({
    try {
        if (-not (Ensure-AdminOrAsk)) { return }
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            ([string]::Format((T "ConfirmMove"), $script:SavePathBox.Text, $script:TargetPathBox.Text)),
            (T "ConfirmMoveTitle"),
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        Invoke-Redirect -SavePath $script:SavePathBox.Text -TargetPath $script:TargetPathBox.Text
        Set-Status (T "DoneMove") $green
    }
    catch {
        Set-Status $_.Exception.Message $red
        Write-Log ([string]::Format((T "ErrorPrefix"), $_.Exception.Message))
    }
})

$restoreButton.Add_Click({
    try {
        if (-not (Ensure-AdminOrAsk)) { return }
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            (T "ConfirmRestore"),
            (T "ConfirmRestoreTitle"),
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        Invoke-Restore -SavePath $script:SavePathBox.Text -TargetPath $script:TargetPathBox.Text
        Set-Status (T "DoneRestore") $green
    }
    catch {
        Set-Status $_.Exception.Message $red
        Write-Log ([string]::Format((T "ErrorPrefix"), $_.Exception.Message))
    }
})

$langButton.Add_Click({
    if ($script:Language -eq "EN") { $script:Language = "RU" } else { $script:Language = "EN" }
    Apply-Language
})

Apply-Language

[void]$script:MainForm.ShowDialog()

