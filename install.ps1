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
  Write-Output "${C_CYAN}║  ${C_RESET}${C_GREEN}OVEC Video Auto-Complete${C_RESET}         ${C_CYAN}║${C_RESET}"
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
$ReleaseUrl = "https://github.com/ntdotjsx/ovec-bypass/releases/download/v.0.1/ovec-bypass.exe"

$null = mkdir -Force $OvecBin

# 1. ดาวน์โหลดไฟล์คอมไพล์สำเร็จ (ovec-bypass.exe)
Write-Step "กำลังดาวน์โหลด ${ExeName} จาก GitHub Releases..."
try {
  curl.exe "-#SfLo" "$ExePath" "$ReleaseUrl"
  if ($LASTEXITCODE -ne 0) { throw "curl failed" }
  Write-Success "ดาวน์โหลดสำเร็จ"
} catch {
  Write-Output "${C_YELLOW}  ! curl ล้มเหลว ลองใช้ Invoke-WebRequest...${C_RESET}"
  try {
    # กำหนดให้ใช้ TLS 1.2 เป็นอย่างน้อยสำหรับ GitHub
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $ReleaseUrl -OutFile $ExePath -UseBasicParsing
    Write-Success "ดาวน์โหลดสำเร็จ"
  } catch {
    Write-Fail "ดาวน์โหลดล้มเหลว กรุณาตรวจสอบการเชื่อมต่ออินเทอร์เน็ต"
    Write-Output $_
    exit 1
  }
}

# 2. ตรวจสอบว่าไฟล์ถูกดาวน์โหลดมาจริง
if (!(Test-Path $ExePath)) {
  Write-Fail "ไม่พบไฟล์ $ExePath หลังดาวน์โหลด"
  exit 1
}

# 3. เพิ่ม PATH
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

# 4. Register ใน Add/Remove Programs
if (-not $NoRegisterInstallation) {
  try {
    $RegKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\OvecAutoComplete"
    $null = New-Item -Path $RegKey -Force
    New-ItemProperty -Path $RegKey -Name "DisplayName"     -Value "OVEC Video Auto-Complete" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $RegKey -Name "DisplayVersion"  -Value "0.1.0"                    -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $RegKey -Name "Publisher"       -Value "ntdotjsx"                 -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $RegKey -Name "InstallLocation" -Value $OvecRoot                  -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $RegKey -Name "DisplayIcon"     -Value $ExePath                   -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $RegKey -Name "UninstallString" -Value "powershell -c `"Remove-Item '$OvecRoot' -Recurse -Force`"" -PropertyType String -Force | Out-Null
  } catch {}
}

# ─── Done ─────────────────────────────────────────────────────────────────────
Write-Output ""
Write-Output "${C_GREEN}╔══════════════════════════════════════╗${C_RESET}"
Write-Output "${C_GREEN}║    ติดตั้งสำเร็จแล้ว! 🎉               ║${C_RESET}"
Write-Output "${C_GREEN}╚══════════════════════════════════════╝${C_RESET}"
Write-Output ""
Write-Output "  ไฟล์อยู่ที่ : ${C_CYAN}${ExePath}${C_RESET}"
Write-Output "  รันโปรแกรม : ${C_YELLOW}ovec${C_RESET}  (หลัง restart terminal)"
Write-Output ""
