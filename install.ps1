#!/usr/bin/env pwsh
param(
  [Switch]$NoPathUpdate = $false,
  [Switch]$NoRegisterInstallation = $false
)

$ErrorActionPreference = "Stop"

$C_RESET  = [char]27 + "[0m"
$C_GREEN  = [char]27 + "[1;32m"
$C_CYAN   = [char]27 + "[1;36m"
$C_YELLOW = [char]27 + "[1;33m"
$C_RED    = [char]27 + "[1;31m"
$C_MAGENTA= [char]27 + "[1;35m"
$C_DIM    = [char]27 + "[2m"

function Write-Banner {
  Write-Output ""
  Write-Output "${C_CYAN}╔══════════════════════════════════════╗${C_RESET}"
  Write-Output "${C_CYAN}║  ${C_RESET}${C_GREEN}OVEC Video Auto-Complete${C_RESET}          ${C_CYAN}║${C_RESET}"
  Write-Output "${C_CYAN}║  ${C_RESET}${C_DIM}Installer v1.0.0${C_RESET}                  ${C_CYAN}║${C_RESET}"
  Write-Output "${C_CYAN}║  ${C_RESET}${C_DIM}dev by ${C_RESET}${C_MAGENTA}ntdotjsx${C_RESET}                    ${C_CYAN}║${C_RESET}"
  Write-Output "${C_CYAN}╚══════════════════════════════════════╝${C_RESET}"
  Write-Output ""
}

function Write-Step {
  param([string]$Message)
  Write-Output "${C_CYAN}  →${C_RESET} $Message"
}

function Write-Success {
  param([string]$Message)
  Write-Output "${C_GREEN}  ✔ $Message${C_RESET}"
}

function Write-Fail {
  param([string]$Message)
  Write-Output "${C_RED}  ✘ $Message${C_RESET}"
}

# ENV helpers (same pattern as bun)
function Publish-Env {
  if (-not ("Win32.NativeMethods" -as [Type])) {
    Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @"
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(
    IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
    uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
"@
  }
  $HWND_BROADCAST = [IntPtr] 0xffff
  $WM_SETTINGCHANGE = 0x1a
  $result = [UIntPtr]::Zero
  [Win32.NativeMethods]::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE,
    [UIntPtr]::Zero, "Environment", 2, 5000, [ref] $result) | Out-Null
}

function Write-Env {
  param([String]$Key, [String]$Value)
  $RegisterKey    = Get-Item -Path 'HKCU:'
  $EnvRegisterKey = $RegisterKey.OpenSubKey('Environment', $true)
  if ($null -eq $Value) {
    $EnvRegisterKey.DeleteValue($Key)
  } else {
    $Kind = if ($Value.Contains('%')) {
      [Microsoft.Win32.RegistryValueKind]::ExpandString
    } elseif ($EnvRegisterKey.GetValue($Key)) {
      $EnvRegisterKey.GetValueKind($Key)
    } else {
      [Microsoft.Win32.RegistryValueKind]::String
    }
    $EnvRegisterKey.SetValue($Key, $Value, $Kind)
  }
  Publish-Env
}

function Get-Env {
  param([String]$Key)
  $RegisterKey    = Get-Item -Path 'HKCU:'
  $EnvRegisterKey = $RegisterKey.OpenSubKey('Environment')
  $EnvRegisterKey.GetValue($Key, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
}

# ─── Main ────────────────────────────────────────────────────────────────────

Write-Banner

$OvecRoot = "${Home}\.ovec"
$OvecBin  = "${OvecRoot}\bin"
$ExeName  = "ovec.exe"
$ExePath  = "${OvecBin}\${ExeName}"

$null = mkdir -Force $OvecBin

# 1. ตรวจ Python
Write-Step "ตรวจสอบ Python..."
try {
  $PyVer = & python --version 2>&1
  Write-Success "พบ $PyVer"
} catch {
  Write-Fail "ไม่พบ Python กรุณาติดตั้ง Python 3.10+ ก่อน"
  Write-Output "  ${C_DIM}https://www.python.org/downloads/${C_RESET}"
  exit 1
}

# 2. ติดตั้ง dependencies
Write-Step "ติดตั้ง dependencies (rich, isodate, requests, pyinstaller)..."
try {
  & python -m pip install --quiet --upgrade rich isodate requests pyinstaller 2>&1 | Out-Null
  Write-Success "ติดตั้ง dependencies สำเร็จ"
} catch {
  Write-Fail "ติดตั้ง dependencies ล้มเหลว"
  Write-Output $_
  exit 1
}

# 3. Download main.py จาก GitHub
$TempDir  = "${env:TEMP}\ovec_install"
$MainPy   = "${TempDir}\main.py"
$RawUrl   = "https://raw.githubusercontent.com/ntdotjsx/ovec-auto/main/main.py"

$null = mkdir -Force $TempDir
Write-Step "ดาวน์โหลด main.py..."
try {
  curl.exe "-#SfLo" "$MainPy" "$RawUrl"
  if ($LASTEXITCODE -ne 0) { throw "curl failed" }
  Write-Success "ดาวน์โหลดสำเร็จ"
} catch {
  Write-Output "${C_YELLOW}  ! curl ล้มเหลว ลองใช้ Invoke-RestMethod...${C_RESET}"
  try {
    Invoke-RestMethod -Uri $RawUrl -OutFile $MainPy
    Write-Success "ดาวน์โหลดสำเร็จ"
  } catch {
    Write-Fail "ดาวน์โหลดล้มเหลว กรุณาวาง main.py ไว้ที่: $MainPy แล้วรัน installer อีกครั้ง"
    exit 1
  }
}

# 4. Build exe ด้วย PyInstaller
Write-Step "กำลัง build ${ExeName} (อาจใช้เวลา 1-2 นาที)..."
try {
  & python -m PyInstaller --onefile --console --distpath "$OvecBin" --workpath "${TempDir}\build" --specpath "${TempDir}" --name "ovec" "$MainPy" 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "PyInstaller failed" }
  Write-Success "Build สำเร็จ → $ExePath"
} catch {
  Write-Fail "Build ล้มเหลว"
  Write-Output $_
  exit 1
}

# 5. ทดสอบว่ารันได้
if (!(Test-Path $ExePath)) {
  Write-Fail "ไม่พบ $ExePath หลัง build"
  exit 1
}

# 6. เพิ่ม PATH
if (-not $NoPathUpdate) {
  Write-Step "เพิ่ม $OvecBin เข้า PATH..."
  $CurrentPath = (Get-Env -Key "Path") -split ';'
  if ($CurrentPath -notcontains $OvecBin) {
    $CurrentPath += $OvecBin
    Write-Env -Key 'Path' -Value ($CurrentPath -join ';')
    $env:PATH = $CurrentPath -join ';'
    Write-Success "เพิ่ม PATH สำเร็จ"
  } else {
    Write-Success "มี PATH อยู่แล้ว"
  }
}

# 7. Register ใน Add/Remove Programs
if (-not $NoRegisterInstallation) {
  try {
    $RegKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\OvecAutoComplete"
    $null = New-Item -Path $RegKey -Force
    New-ItemProperty -Path $RegKey -Name "DisplayName"     -Value "OVEC Video Auto-Complete" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $RegKey -Name "DisplayVersion"  -Value "1.0.0"                    -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $RegKey -Name "Publisher"       -Value "ntdotjsx"                 -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $RegKey -Name "InstallLocation" -Value $OvecRoot                  -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $RegKey -Name "DisplayIcon"     -Value $ExePath                   -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $RegKey -Name "UninstallString" -Value "powershell -c `"Remove-Item '$OvecRoot' -Recurse -Force`"" -PropertyType String -Force | Out-Null
  } catch {}
}

# ─── Done ─────────────────────────────────────────────────────────────────────
Write-Output ""
Write-Output "${C_GREEN}╔══════════════════════════════════════╗${C_RESET}"
Write-Output "${C_GREEN}║   ติดตั้งสำเร็จแล้ว! 🎉             ║${C_RESET}"
Write-Output "${C_GREEN}╚══════════════════════════════════════╝${C_RESET}"
Write-Output ""
Write-Output "  ไฟล์อยู่ที่ : ${C_CYAN}${ExePath}${C_RESET}"
Write-Output "  รันโปรแกรม : ${C_YELLOW}ovec${C_RESET}  (หลัง restart terminal)"
Write-Output ""
