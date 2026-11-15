# CommandShortcut.ps1 | JobsCommandShortcutCreator
# Created by Jobs on 2026年11月13日，星期五.
# 仅定义目录判定、相对入口生成、排他写入及交互；加载本文件不会运行目标脚本。

function Get-JobsCommandShortcutTarget {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Target)

    $directory = Get-Item -LiteralPath $Target -Force -ErrorAction Stop
    if ($directory.PSProvider.Name -ne 'FileSystem' -or -not $directory.PSIsContainer -or
        ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'invalidTarget' }
    $extension = [IO.Path]::GetExtension($directory.Name).ToLowerInvariant()
    if ($extension -notin @('.cmd', '.bat', '.ps1')) { throw 'invalidTarget' }
    $scriptPath = Join-Path $directory.FullName $directory.Name
    $script = Get-Item -LiteralPath $scriptPath -Force -ErrorAction Stop
    if ($script.PSIsContainer -or ($script.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        ($script.Attributes -band [IO.FileAttributes]::Device)) { throw 'invalidTarget' }
    return [pscustomobject]@{ Directory = $directory.FullName; DirectoryName = $directory.Name; Script = $script.FullName; Extension = $extension; Parent = $directory.Parent.FullName }
}

function Test-JobsCommandShortcutName {
    param([AllowEmptyString()][string]$Name, [string]$Extension)
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name.Trim() -cne $Name -or $Name.Length -gt 255 -or
        $Name -match '[<>:"/\\|?*\x00-\x1f\x7f]' -or $Name.EndsWith('.') -or
        $Name -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)' -or
        [IO.Path]::GetExtension($Name) -ine $Extension) { return $false }
    return $true
}

function Get-JobsCommandShortcutContent {
    param([Parameter(Mandatory = $true)]$Context)

    # PowerShell 单引号及批处理百分号分别引用；批处理直接尾调用，避免CALL或子cmd再次展开百分号。
    $relative = $Context.DirectoryName + '\' + $Context.DirectoryName
    if ($Context.Extension -eq '.ps1') {
        $quoted = $relative.Replace("'", "''")
        $proxy = @'
[CmdletBinding(PositionalBinding=$false)]
param([Parameter(ValueFromRemainingArguments=$true)][object[]]$jobsLauncherRemaining_0D91C59B9FAE4BC18A3053F8967DCCBA = @())
dynamicparam {
    $jobsLauncherTarget = Join-Path $PSScriptRoot '__JOBS_RELATIVE_TARGET__'
    $jobsLauncherDirectory = Get-Item -LiteralPath (Split-Path -Parent $jobsLauncherTarget) -Force -ErrorAction Stop
    $jobsLauncherScript = Get-Item -LiteralPath $jobsLauncherTarget -Force -ErrorAction Stop
    if (-not $jobsLauncherDirectory.PSIsContainer -or $jobsLauncherScript.PSIsContainer -or (($jobsLauncherDirectory.Attributes -bor $jobsLauncherScript.Attributes) -band [IO.FileAttributes]::ReparsePoint)) { throw 'The companion script is missing or is a link.' }
    $jobsLauncherDictionary = New-Object Management.Automation.RuntimeDefinedParameterDictionary
    $jobsLauncherMetadata = $ExecutionContext.InvokeCommand.GetCommand($jobsLauncherTarget, [Management.Automation.CommandTypes]::ExternalScript).Parameters
    $jobsLauncherCommon = @('Verbose','Debug','ErrorAction','WarningAction','InformationAction','ProgressAction','ErrorVariable','WarningVariable','InformationVariable','OutVariable','OutBuffer','PipelineVariable')
    foreach ($jobsLauncherEntry in $jobsLauncherMetadata.GetEnumerator()) {
        if ($jobsLauncherEntry.Key -in $jobsLauncherCommon) {
            $jobsLauncherExpectedType = if ($jobsLauncherEntry.Key -in @('Verbose','Debug')) { [Management.Automation.SwitchParameter] } elseif ($jobsLauncherEntry.Key -eq 'OutBuffer') { [int] } elseif ($jobsLauncherEntry.Key -in @('ErrorAction','WarningAction','InformationAction','ProgressAction')) { [Management.Automation.ActionPreference] } else { [string] }
            if ($jobsLauncherEntry.Value.ParameterType -ne $jobsLauncherExpectedType) { throw ('The source script declares a reserved launcher parameter with a different type: ' + $jobsLauncherEntry.Key) }
            continue
        }
        $jobsLauncherAttributes = New-Object 'Collections.ObjectModel.Collection[Attribute]'
        foreach ($jobsLauncherAttribute in $jobsLauncherEntry.Value.Attributes) {
            if ($jobsLauncherAttribute -is [Management.Automation.ParameterAttribute]) {
                $jobsLauncherCopy = New-Object Management.Automation.ParameterAttribute
                foreach ($jobsLauncherProperty in $jobsLauncherAttribute.GetType().GetProperties()) {
                    if ($jobsLauncherProperty.CanRead -and $jobsLauncherProperty.CanWrite) {
                        $jobsLauncherValue = $jobsLauncherProperty.GetValue($jobsLauncherAttribute, $null)
                        if ($null -ne $jobsLauncherValue) { $jobsLauncherProperty.SetValue($jobsLauncherCopy, $jobsLauncherValue, $null) }
                    }
                }
                if ($jobsLauncherAttribute.ValueFromRemainingArguments) {
                    # 源脚本统一绑定未命名余参；代理只保留显式命名绑定，避免抢走首个余参。
                    $jobsLauncherCopy.Position = [int]::MinValue
                    $jobsLauncherCopy.Mandatory = $false
                }
                $jobsLauncherCopy.ValueFromRemainingArguments = $false
                $jobsLauncherAttributes.Add($jobsLauncherCopy)
            } elseif ($jobsLauncherAttribute -is [Management.Automation.AliasAttribute] -or
                      $jobsLauncherAttribute -is [Management.Automation.AllowEmptyStringAttribute] -or
                      $jobsLauncherAttribute -is [Management.Automation.AllowEmptyCollectionAttribute] -or
                      $jobsLauncherAttribute -is [Management.Automation.AllowNullAttribute]) { $jobsLauncherAttributes.Add($jobsLauncherAttribute) }
        }
        $jobsLauncherParameter = New-Object Management.Automation.RuntimeDefinedParameter($jobsLauncherEntry.Key, $jobsLauncherEntry.Value.ParameterType, $jobsLauncherAttributes)
        $jobsLauncherDictionary.Add($jobsLauncherEntry.Key, $jobsLauncherParameter)
    }
    return $jobsLauncherDictionary
}
end {
    $jobsLauncherTarget = Join-Path $PSScriptRoot '__JOBS_RELATIVE_TARGET__'
    $jobsLauncherForward = @{}
    foreach ($jobsLauncherEntry in $PSBoundParameters.GetEnumerator()) {
        if ($jobsLauncherEntry.Key -cne 'jobsLauncherRemaining_0D91C59B9FAE4BC18A3053F8967DCCBA') { $jobsLauncherForward[$jobsLauncherEntry.Key] = $jobsLauncherEntry.Value }
    }
    $global:LASTEXITCODE = 0
    & $jobsLauncherTarget @jobsLauncherForward @jobsLauncherRemaining_0D91C59B9FAE4BC18A3053F8967DCCBA
    $jobsLauncherSucceeded = $?
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    if (-not $jobsLauncherSucceeded) { exit 1 }
    exit 0
}
'@
        return $proxy.Replace('__JOBS_RELATIVE_TARGET__', $quoted).Replace("`n", "`r`n") + "`r`n"
    }
    $escaped = $relative.Replace('%', '%%')
    return (@(
        '@echo off'
        'setlocal DisableDelayedExpansion'
        'for /f "tokens=2 delims=:" %%C in (''chcp'') do set "jobsLauncherCodePage=%%C"'
        'chcp 65001 >nul'
        ('set "JOBS_SCRIPT_LAUNCH_TARGET=%~dp0' + $escaped + '"')
        'powershell.exe -NoLogo -NoProfile -Command "$ErrorActionPreference=''Stop'';try{$s=Get-Item -LiteralPath $env:JOBS_SCRIPT_LAUNCH_TARGET -Force;$d=Get-Item -LiteralPath (Split-Path -Parent $s.FullName) -Force;if($s.PSIsContainer -or -not $d.PSIsContainer -or (($s.Attributes -bor $d.Attributes) -band [IO.FileAttributes]::ReparsePoint)){exit 1}}catch{exit 1}"'
        'if errorlevel 1 goto jobsLauncherMissing'
        'chcp %jobsLauncherCodePage% >nul'
        '"%JOBS_SCRIPT_LAUNCH_TARGET%" %*'
        ':jobsLauncherMissing'
        'echo The companion script is missing or is a link. 1>&2'
        'chcp %jobsLauncherCodePage% >nul'
        'exit /b 1'
    ) -join "`r`n") + "`r`n"
}

function Open-JobsCommandShortcutDirectoryLease {
    param([string]$Directory)
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { return $null }
    if (-not ('Jobs.CommandShortcut.NativeDirectoryLease' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace Jobs.CommandShortcut {
    public static class NativeDirectoryLease {
        [StructLayout(LayoutKind.Sequential)] struct FileTime { public uint Low, High; }
        [StructLayout(LayoutKind.Sequential)] struct Information {
            public uint Attributes;
            public FileTime Created, Accessed, Written;
            public uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
        }
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true, ExactSpelling=true)]
        static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security, uint mode, uint flags, IntPtr template);
        [DllImport("kernel32.dll", SetLastError=true)]
        static extern bool GetFileInformationByHandle(SafeFileHandle handle, out Information information);
        public static SafeFileHandle Acquire(string directory) {
            // Omitting FILE_SHARE_DELETE freezes this directory identity for the write operation.
            SafeFileHandle handle = CreateFileW(directory, 0x80, 3, IntPtr.Zero, 3, 0x02200000, IntPtr.Zero);
            if (handle.IsInvalid) { int error = Marshal.GetLastWin32Error(); handle.Dispose(); throw new Win32Exception(error); }
            Information information;
            if (!GetFileInformationByHandle(handle, out information)) { int error = Marshal.GetLastWin32Error(); handle.Dispose(); throw new Win32Exception(error); }
            if ((information.Attributes & 0x10) == 0 || (information.Attributes & 0x400) != 0) {
                handle.Dispose(); throw new InvalidOperationException("The selected directory is not a regular directory.");
            }
            return handle;
        }
    }
}
'@
    }
    return [Jobs.CommandShortcut.NativeDirectoryLease]::Acquire($Directory)
}

function New-JobsCommandShortcut {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Target, [Parameter(Mandatory = $true)][string]$Name)

    $context = Get-JobsCommandShortcutTarget $Target
    if (-not (Test-JobsCommandShortcutName $Name $context.Extension)) { throw 'invalidName' }
    $destination = Join-Path $context.Parent $Name
    # File.Move 不替换已有文件、目录或悬空链接；先完成临时写入再公开入口。
    $temporary = Join-Path $context.Parent ('.jobs-command-shortcut-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $stream = $null
    $leases = @()
    try {
        # Windows保持父目录和脚本包身份，防止写入期间被正常重命名或替换。
        foreach ($directory in @($context.Parent, $context.Directory)) { $leases += Open-JobsCommandShortcutDirectoryLease $directory }
        $context = Get-JobsCommandShortcutTarget $Target
        $stream = New-Object IO.FileStream($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $encoding = New-Object Text.UTF8Encoding(($context.Extension -eq '.ps1'))
        $content = Get-JobsCommandShortcutContent $context
        $preamble = $encoding.GetPreamble()
        $bytes = $encoding.GetBytes($content)
        $stream.Write($preamble, 0, $preamble.Length)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
        $stream.Dispose()
        $stream = $null
        [IO.File]::Move($temporary, $destination)
        return $destination
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
        try { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
        finally { foreach ($lease in $leases) { if ($null -ne $lease) { $lease.Dispose() } } }
    }
}

function Get-JobsCommandShortcutTranslations {
    return @'
{
  "title": [
    "创建脚本快捷入口",
    "建立指令稿快捷入口",
    "འཕྲལ་འཇུག་ཡིག་ཆ་བཟོ།",
    "Create Script Launcher",
    "スクリプト起動ファイルを作成",
    "Créer un lanceur de script",
    "Crear acceso al script",
    "Skriptstarter erstellen",
    "Создать ярлык скрипта",
    "스크립트 실행 파일 만들기"
  ],
  "create": [
    "创建",
    "建立",
    "བཟོ།",
    "Create",
    "作成",
    "Créer",
    "Crear",
    "Erstellen",
    "Создать",
    "만들기"
  ],
  "cancel": [
    "取消",
    "取消",
    "ཕྱིར་འཐེན།",
    "Cancel",
    "キャンセル",
    "Annuler",
    "Cancelar",
    "Abbrechen",
    "Отмена",
    "취소"
  ],
  "ok": [
    "好",
    "好",
    "འགྲིག",
    "OK",
    "OK",
    "OK",
    "Aceptar",
    "OK",
    "ОК",
    "확인"
  ],
  "suffix": [
    "（快捷入口）",
    "（快捷入口）",
    "（འཕྲལ་འཇུག）",
    " (Launcher)",
    "（起動）",
    " (Lanceur)",
    " (Acceso)",
    " (Starter)",
    " (Запуск)",
    " (실행)"
  ],
  "prompt": [
    "请输入以 {0} 结尾的入口名称。文件将创建在所选文件夹旁边。",
    "請輸入以 {0} 結尾的入口名稱。檔案將建立在所選資料夾旁邊。",
    "{0} མཇུག་ཏུ་ཡོད་པའི་མིང་འཇུག འདེམས་པའི་སྣོད་ཀྱི་འགྲམ་དུ་བཟོ།",
    "Enter a launcher name ending in {0}. It will be created beside the selected folder.",
    "{0} で終わる名前を入力してください。選択したフォルダと同じ階層に作成します。",
    "Saisissez un nom se terminant par {0}. Le lanceur sera créé à côté du dossier sélectionné.",
    "Escriba un nombre terminado en {0}. Se creará junto a la carpeta seleccionada.",
    "Geben Sie einen Namen mit der Endung {0} ein. Die Datei wird neben dem gewählten Ordner erstellt.",
    "Введите имя с окончанием {0}. Файл появится рядом с выбранной папкой.",
    "{0}로 끝나는 이름을 입력하세요. 선택한 폴더 옆에 생성됩니다."
  ],
  "invalidName": [
    "名称须以 {0} 结尾，且不能含 /、:、换行或控制字符。",
    "名稱須以 {0} 結尾，且不能含 /、:、換行或控制字元。",
    "མིང་གི་མཇུག {0} དགོས། / དང་ : དང་ཚིག་ཕྲེང་གསར་པ་མི་ཆོག",
    "Use a valid name ending in {0}, without /, :, newlines or control characters.",
    "名前は {0} で終わり、/、:、改行、制御文字を含まないようにしてください。",
    "Le nom doit se terminer par {0}, sans /, :, retour à la ligne ni caractère de contrôle.",
    "El nombre debe terminar en {0} y no contener /, :, saltos de línea ni caracteres de control.",
    "Der Name muss auf {0} enden und darf keine /, :, Zeilenumbrüche oder Steuerzeichen enthalten.",
    "Имя должно оканчиваться на {0} и не содержать /, :, переводы строк или управляющие символы.",
    "이름은 {0}로 끝나야 하며 /, :, 줄바꿈, 제어 문자를 포함할 수 없습니다."
  ],
  "occupied": [
    "同名文件、文件夹或链接已存在，请换个名称。",
    "同名檔案、資料夾或連結已存在，請更換名稱。",
    "མིང་འདི་ཡོད་ཟིན། མིང་གཞན་ཞིག་འཇུག",
    "A file, folder or link with this name already exists. Choose another name.",
    "同名のファイル、フォルダ、リンクが存在します。別の名前を指定してください。",
    "Un fichier, dossier ou lien porte déjà ce nom. Choisissez un autre nom.",
    "Ya existe un archivo, carpeta o enlace con ese nombre. Elija otro.",
    "Eine Datei, ein Ordner oder Link mit diesem Namen existiert bereits. Wählen Sie einen anderen Namen.",
    "Файл, папка или ссылка с таким именем уже существует. Выберите другое имя.",
    "같은 이름의 파일, 폴더 또는 링크가 있습니다. 다른 이름을 입력하세요."
  ],
  "invalidTarget": [
    "目标须为 .cmd / .bat / .ps1 文件夹，并含有同名普通脚本；不接受符号链接。",
    "目標須為 .cmd / .bat / .ps1 資料夾，並含有同名一般指令稿；不接受符號連結。",
    ".cmd / .bat / .ps1 སྣོད་ནང་མིང་མཚུངས་པའི་ཡིག་ཆ་དགོས། མཚོན་རྟགས་སྦྲེལ་མཐུད་མི་ཆོག",
    "Select a .cmd / .bat / .ps1 folder containing a regular script with the same name. Symbolic links are not supported.",
    "同名の通常スクリプトを含む .cmd / .bat / .ps1 フォルダを選択してください。シンボリックリンクは使用できません。",
    "Choisissez un dossier .cmd / .bat / .ps1 contenant un script ordinaire du même nom, sans lien symbolique.",
    "Seleccione una carpeta .cmd / .bat / .ps1 con un script normal del mismo nombre. No se admiten enlaces simbólicos.",
    "Wählen Sie einen .cmd / .bat / .ps1-Ordner mit einem gleichnamigen regulären Skript. Symbolische Links werden nicht unterstützt.",
    "Выберите папку .cmd / .bat / .ps1 с обычным скриптом того же имени. Символические ссылки не поддерживаются.",
    "같은 이름의 일반 스크립트가 있는 .cmd / .bat / .ps1 폴더를 선택하세요. 심볼릭 링크는 지원하지 않습니다."
  ],
  "writeFailed": [
    "无法写入快捷入口，请检查目录权限和剩余空间。",
    "無法寫入快捷入口，請檢查目錄權限和剩餘空間。",
    "འཕྲལ་འཇུག་འབྲི་མ་ཐུབ། ཆོག་མཆན་དང་སྟོང་ཆ་ཞིབ་བཤེར་བྱེད།",
    "Unable to write the launcher. Check folder permissions and free space.",
    "起動ファイルを書き込めません。フォルダの権限と空き容量を確認してください。",
    "Impossible d’écrire le lanceur. Vérifiez les permissions et l’espace disponible.",
    "No se pudo escribir el acceso. Compruebe los permisos y el espacio libre.",
    "Der Starter konnte nicht geschrieben werden. Prüfen Sie Berechtigungen und freien Speicher.",
    "Не удалось записать ярлык. Проверьте права на папку и свободное место.",
    "실행 파일을 쓸 수 없습니다. 폴더 권한과 여유 공간을 확인하세요."
  ],
  "failureTitle": [
    "创建快捷入口未完成",
    "建立快捷入口未完成",
    "འཕྲལ་འཇུག་བཟོ་མ་ཐུབ།",
    "Launcher Not Created",
    "起動ファイルを作成できません",
    "Lanceur non créé",
    "Acceso no creado",
    "Starter nicht erstellt",
    "Ярлык не создан",
    "실행 파일 생성 실패"
  ],
  "expired": [
    "右键请求已失效，请重新打开菜单。",
    "右鍵請求已失效，請重新開啟選單。",
    "རེ་ཞུ་དུས་ལས་ཡོལ། འདེམས་ཐོ་ཡང་བསྐྱར་ཁ་ཕྱེ།",
    "This request has expired. Reopen the context menu.",
    "この要求は無効です。右クリックメニューを開き直してください。",
    "Cette demande a expiré. Rouvrez le menu contextuel.",
    "La solicitud ha caducado. Abra de nuevo el menú contextual.",
    "Diese Anfrage ist abgelaufen. Öffnen Sie das Kontextmenü erneut.",
    "Запрос устарел. Откройте контекстное меню заново.",
    "요청이 만료되었습니다. 메뉴를 다시 여세요."
  ],
  "hostMissing": [
    "缺少完整工具 App，请从管理面板安装 / 更新本功能。",
    "缺少完整工具 App，請從管理面板安裝 / 更新本功能。",
    "App ཆ་ཚང་མེད། དོ་དམ་ངོས་ནས་སྒྲིག་འཇུག་བྱེད།",
    "The tool app is missing. Install or update this feature in the manager.",
    "ツール App が見つかりません。管理画面からインストールまたは更新してください。",
    "L’app est introuvable. Installez ou mettez à jour cette fonction dans le gestionnaire.",
    "Falta la aplicación. Instale o actualice esta función desde el gestor.",
    "Die App fehlt. Installieren oder aktualisieren Sie die Funktion im Manager.",
    "Приложение отсутствует. Установите или обновите функцию через панель управления.",
    "도구 앱이 없습니다. 관리 패널에서 설치하거나 업데이트하세요."
  ],
  "openFailed": [
    "无法启动快捷入口工具",
    "無法啟動快捷入口工具",
    "འཕྲལ་འཇུག་ལག་ཆ་འགོ་འཛུགས་མ་ཐུབ།",
    "Unable to open the launcher tool",
    "起動ファイル作成ツールを開けません",
    "Impossible d’ouvrir l’outil",
    "No se pudo abrir la herramienta",
    "Das Werkzeug konnte nicht geöffnet werden",
    "Не удалось запустить инструмент",
    "도구를 열 수 없습니다"
  ],
  "system": [
    "跟随系统",
    "跟隨系統",
    "མ་ལག་རྗེས་འབྲང་།",
    "System",
    "システム",
    "Système",
    "Sistema",
    "System",
    "Системная",
    "시스템"
  ],
  "light": [
    "白天",
    "白天",
    "ཉིན་མོ།",
    "Light",
    "ライト",
    "Clair",
    "Claro",
    "Hell",
    "Светлая",
    "라이트"
  ],
  "dark": [
    "黑夜",
    "黑夜",
    "མཚན་མོ།",
    "Dark",
    "ダーク",
    "Sombre",
    "Oscuro",
    "Dunkel",
    "Тёмная",
    "다크"
  ],
  "language": [
    "语言",
    "語言",
    "སྐད་ཡིག",
    "Language",
    "言語",
    "Langue",
    "Idioma",
    "Sprache",
    "Язык",
    "언어"
  ],
  "theme": [
    "主题",
    "主題",
    "བརྗོད་གཞི།",
    "Theme",
    "テーマ",
    "Thème",
    "Tema",
    "Darstellung",
    "Тема",
    "테마"
  ],
  "edit": [
    "编辑",
    "編輯",
    "རྩོམ་སྒྲིག",
    "Edit",
    "編集",
    "Édition",
    "Editar",
    "Bearbeiten",
    "Правка",
    "편집"
  ],
  "cut": [
    "剪切",
    "剪下",
    "གཅོད།",
    "Cut",
    "切り取り",
    "Couper",
    "Cortar",
    "Ausschneiden",
    "Вырезать",
    "잘라내기"
  ],
  "copy": [
    "复制",
    "複製",
    "འདྲ་བཤུས།",
    "Copy",
    "コピー",
    "Copier",
    "Copiar",
    "Kopieren",
    "Копировать",
    "복사"
  ],
  "paste": [
    "粘贴",
    "貼上",
    "སྦྱར།",
    "Paste",
    "貼り付け",
    "Coller",
    "Pegar",
    "Einfügen",
    "Вставить",
    "붙여넣기"
  ],
  "selectAll": [
    "全选",
    "全選",
    "ཚང་མ་འདེམས།",
    "Select All",
    "すべて選択",
    "Tout sélectionner",
    "Seleccionar todo",
    "Alles auswählen",
    "Выбрать всё",
    "모두 선택"
  ],
  "quit": [
    "退出",
    "結束",
    "ཕྱིར་ཐོན།",
    "Quit",
    "終了",
    "Quitter",
    "Salir",
    "Beenden",
    "Выход",
    "종료"
  ]
}
'@ | ConvertFrom-Json
}

function Get-JobsCommandShortcutText {
    param([string]$Key, [string]$Language = 'zh-Hans', [string]$Extension = '.cmd')
    $languages = @('zh-Hans', 'zh-Hant', 'bo', 'en', 'ja', 'fr', 'es', 'de', 'ru', 'ko')
    $index = [array]::IndexOf($languages, $Language)
    if ($index -lt 0) { $index = 3 }
    $data = Get-JobsCommandShortcutTranslations
    if ($null -eq $data.PSObject.Properties[$Key]) { return $Key }
    return ([string]$data.$Key[$index]).Replace('{0}', $Extension)
}

function New-JobsCommandShortcutModuleInvoker {
    $owningModule = $ExecutionContext.SessionState.Module
    return {
        param([string]$Name, [object[]]$Arguments)
        if ($null -ne $owningModule) {
            & $owningModule {
                param([string]$FunctionName, [object[]]$FunctionArguments)
                & $FunctionName @FunctionArguments
            } $Name $Arguments
        } else {
            & $Name @Arguments
        }
    }.GetNewClosure()
}

function Show-JobsCommandShortcutDialog {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Target)

    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'This dialog requires Windows.' }
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $context = Get-JobsCommandShortcutTarget $Target
    $moduleCall = New-JobsCommandShortcutModuleInvoker
    $preferences = Read-JobsPanelPreferences
    $languageCodes = @('zh-Hans', 'zh-Hant', 'bo', 'en', 'ja', 'fr', 'es', 'de', 'ru', 'ko', 'system')
    $languageNames = @('简体中文', '繁體中文', 'བོད་ཡིག', 'English', '日本語', 'Français', 'Español', 'Deutsch', 'Русский', '한국어', '跟随系统')
    $themeCodes = @('system', 'light', 'dark')
    $form = New-Object Windows.Forms.Form
    $form.StartPosition = 'CenterScreen'
    $form.ClientSize = New-Object Drawing.Size(720, 330)
    $form.MinimumSize = $form.Size
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.Font = New-Object Drawing.Font('Segoe UI', 10)
    $prompt = New-Object Windows.Forms.Label
    $prompt.SetBounds(20, 20, 680, 60)
    $prompt.Anchor = 'Top,Left,Right'
    $nameBox = New-Object Windows.Forms.TextBox
    $nameBox.SetBounds(20, 86, 680, 28)
    $nameBox.Anchor = 'Top,Left,Right'
    $nameBox.MaxLength = 255
    $languageLabel = New-Object Windows.Forms.Label
    $languageLabel.SetBounds(20, 138, 80, 26)
    $languageBox = New-Object Windows.Forms.ComboBox
    $languageBox.SetBounds(104, 134, 234, 30)
    $languageBox.DropDownStyle = 'DropDownList'
    [void]$languageBox.Items.AddRange($languageNames)
    $themeLabel = New-Object Windows.Forms.Label
    $themeLabel.SetBounds(360, 138, 80, 26)
    $themeBox = New-Object Windows.Forms.ComboBox
    $themeBox.SetBounds(444, 134, 256, 30)
    $themeBox.DropDownStyle = 'DropDownList'
    $errorLabel = New-Object Windows.Forms.Label
    $errorLabel.SetBounds(20, 180, 680, 80)
    $errorLabel.Anchor = 'Top,Left,Right'
    $create = New-Object Windows.Forms.Button
    $create.SetBounds(470, 282, 110, 32)
    $create.Anchor = 'Bottom,Right'
    $cancel = New-Object Windows.Forms.Button
    $cancel.SetBounds(590, 282, 110, 32)
    $cancel.Anchor = 'Bottom,Right'
    $cancel.DialogResult = [Windows.Forms.DialogResult]::Cancel
    $form.AcceptButton = $create
    $form.CancelButton = $cancel
    $form.Controls.AddRange(@($prompt, $nameBox, $languageLabel, $languageBox, $themeLabel, $themeBox, $errorLabel, $create, $cancel))
    $state = @{ Updating = $false; Language = $preferences.Language; Theme = $preferences.Theme; LastDefault = ''; Error = ''; Context = $context; Result = $null }
    $update = {
        $state.Updating = $true
        try {
            $language = & $moduleCall -Name 'Resolve-JobsPanelLanguage' -Arguments @($state.Language)
            $extension = $state.Context.Extension
            $form.Text = & $moduleCall -Name 'Get-JobsCommandShortcutText' -Arguments @('title', $language, $extension)
            $prompt.Text = & $moduleCall -Name 'Get-JobsCommandShortcutText' -Arguments @('prompt', $language, $extension)
            $languageLabel.Text = & $moduleCall -Name 'Get-JobsCommandShortcutText' -Arguments @('language', $language)
            $themeLabel.Text = & $moduleCall -Name 'Get-JobsCommandShortcutText' -Arguments @('theme', $language)
            $create.Text = & $moduleCall -Name 'Get-JobsCommandShortcutText' -Arguments @('create', $language)
            $cancel.Text = & $moduleCall -Name 'Get-JobsCommandShortcutText' -Arguments @('cancel', $language)
            $themeBox.Items.Clear()
            foreach ($key in $themeCodes) { [void]$themeBox.Items.Add((& $moduleCall -Name 'Get-JobsCommandShortcutText' -Arguments @($key, $language))) }
            $themeBox.SelectedIndex = [array]::IndexOf($themeCodes, $state.Theme)
            $languageBox.SelectedIndex = [array]::IndexOf($languageCodes, $state.Language)
            $defaultName = [IO.Path]::GetFileNameWithoutExtension($state.Context.DirectoryName) + (& $moduleCall -Name 'Get-JobsCommandShortcutText' -Arguments @('suffix', $language)) + $extension
            if ([string]::IsNullOrEmpty($nameBox.Text) -or $nameBox.Text -ceq $state.LastDefault) { $nameBox.Text = $defaultName }
            $state.LastDefault = $defaultName
            $errorLabel.Text = if ($state.Error) { & $moduleCall -Name 'Get-JobsCommandShortcutText' -Arguments @($state.Error, $language, $extension) } else { '' }
            $dark = (& $moduleCall -Name 'Resolve-JobsPanelTheme' -Arguments @($state.Theme)) -eq 'dark'
            $background = if ($dark) { [Drawing.Color]::FromArgb(30,30,30) } else { [Drawing.Color]::White }
            $foreground = if ($dark) { [Drawing.Color]::WhiteSmoke } else { [Drawing.Color]::FromArgb(25,25,25) }
            $form.BackColor = $background
            $form.ForeColor = $foreground
            foreach ($control in $form.Controls) { $control.BackColor = $background; $control.ForeColor = $foreground }
            $errorLabel.ForeColor = if ($dark) { [Drawing.Color]::Salmon } else { [Drawing.Color]::Firebrick }
            $create.UseVisualStyleBackColor = $false
            $create.BackColor = [Drawing.Color]::FromArgb(0,92,185)
            $create.ForeColor = [Drawing.Color]::White
            $fontName = if ($language -eq 'bo') { 'Microsoft Himalaya' } else { 'Segoe UI' }
            $fontSize = if ($language -eq 'bo') { 13 } else { 10 }
            $oldFont = $form.Font
            $form.Font = New-Object Drawing.Font($fontName, $fontSize)
            $oldFont.Dispose()
        } finally { $state.Updating = $false }
    }.GetNewClosure()
    $save = {
        try { & $moduleCall -Name 'Save-JobsPanelPreferences' -Arguments @($state.Theme, $state.Language) }
        catch { $state.Error = $_.Exception.Message }
        & $update
    }.GetNewClosure()
    $languageBox.Add_SelectedIndexChanged({
        if (-not $state.Updating -and $languageBox.SelectedIndex -ge 0) { $state.Language = $languageCodes[$languageBox.SelectedIndex]; & $save }
    }.GetNewClosure())
    $themeBox.Add_SelectedIndexChanged({
        if (-not $state.Updating -and $themeBox.SelectedIndex -ge 0) { $state.Theme = $themeCodes[$themeBox.SelectedIndex]; & $save }
    }.GetNewClosure())
    $form.Add_Activated({ if (-not $state.Updating) { & $update } }.GetNewClosure())
    $create.Add_Click({
        try {
            $state.Result = & $moduleCall -Name 'New-JobsCommandShortcut' -Arguments @($Target, $nameBox.Text)
            $form.DialogResult = [Windows.Forms.DialogResult]::OK
            $form.Close()
        } catch {
            $reason = $_.Exception
            while ($null -ne $reason.InnerException) { $reason = $reason.InnerException }
            $state.Error = $reason.Message
            if ($reason -is [IO.IOException] -and ($reason.HResult -band 0xffff) -in @(17, 80, 183)) { $state.Error = 'occupied' }
            & $update
        }
    }.GetNewClosure())
    try {
        & $update
        $nameBox.SelectAll()
        $form.ActiveControl = $nameBox
        [void]$form.ShowDialog()
        if ($state.Result) {
            # 只通过进程参数选择创建结果，不通过cmd重解释路径。
            $start = New-Object Diagnostics.ProcessStartInfo
            $start.FileName = Join-Path ([Environment]::GetFolderPath('Windows')) 'explorer.exe'
            $start.Arguments = '/select,' + (& $moduleCall -Name 'Quote-JobsArgument' -Arguments @($state.Result))
            $start.UseShellExecute = $false
            [void][Diagnostics.Process]::Start($start)
        }
    } finally { $form.Dispose() }
}
