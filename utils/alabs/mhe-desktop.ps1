# alabs-mod-desktop - MOD Desktop with an emulated controller, the Dwarf, the Duo X or the Duo (Windows)
#
#   mhe-desktop.cmd [-Device dwarf|duox|duo] [-NoEmulator] [-SharedData]
#
# The package holds MOD Desktop in mod-desktop\ (built with the mod-host, mod-ui and launcher of this fork) and
# mod-hw-emulator next to it. This writes MOD Desktop's descriptor for the device, starts the emulator (unless
# -NoEmulator: one already running) and then MOD Desktop, which talk to each other over 127.0.0.1: 9900 for
# mod-ui's HMI line, 9901 for mod-host's /sys_msgs. The data (pedalboards, user files, the launcher log) is in
# data\ next to this script, or in Documents\MOD Desktop, the folder of an installed MOD Desktop, with -SharedData.

param(
    [ValidateSet('dwarf', 'duox', 'duo')]
    [string]$Device = 'dwarf',
    [switch]$NoEmulator,
    [switch]$SharedData
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$desktop = Join-Path $here 'mod-desktop'
$hmiPort = 9900
$sysPort = 9901
# the port that tells the emulator is up: the Duo has no system line, mod-host goes without /sys_msgs
$readyPort = if ($Device -eq 'duo') { $hmiPort } else { $sysPort }
# the emulator's EEPROM and settings, one per device
$state = Join-Path $here "mhe-state\$Device"
$firmware = Join-Path $here "fw-$Device.dll"
$emulator = Join-Path $here 'mod-hw-emulator.exe'

if (-not $SharedData) {
    $env:MOD_DATA_DIR = Join-Path $here 'data'
}

# MOD Desktop's descriptor keeps what tells the desktop apart (name, binaries); the device's one gives the rest
$base = Get-Content -Raw -Encoding UTF8 (Join-Path $here 'devices\mod-desktop.json') | ConvertFrom-Json
$descriptor = Get-Content -Raw -Encoding UTF8 (Join-Path $here "devices\$Device\mod-hardware-descriptor.json") | ConvertFrom-Json
foreach ($key in 'name', 'architecture', 'bin-compat') {
    if ($base.PSObject.Properties[$key]) {
        $descriptor | Add-Member -Force -NotePropertyName $key -NotePropertyValue $base.$key
    }
}
$json = $descriptor | ConvertTo-Json -Depth 20
[IO.File]::WriteAllText((Join-Path $desktop 'mod-hardware-descriptor.json'), $json, (New-Object Text.UTF8Encoding $false))

function Test-Listening([int]$port) {
    $client = New-Object Net.Sockets.TcpClient
    try {
        $client.Connect('127.0.0.1', $port)
        return $true
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

# the emulator first: mod-host connects to it when it starts
if (-not $NoEmulator) {
    if ((Test-Listening $hmiPort) -or (Test-Listening $sysPort)) {
        Write-Host "something is already on port $hmiPort or ${sysPort}: an emulator running? (-NoEmulator to use it)"
        exit 1
    }
    Start-Process -FilePath $emulator `
                  -ArgumentList '--state', ('"{0}"' -f $state), '--tcp', "webgui=$hmiPort", ('"{0}"' -f $firmware) `
                  -WorkingDirectory $here
}
$deadline = (Get-Date).AddSeconds(15)
while (-not (Test-Listening $readyPort)) {
    if ((Get-Date) -gt $deadline) {
        throw "the emulator is not listening on port $readyPort"
    }
    Start-Sleep -Milliseconds 250
}

# MOD Desktop passes its environment to jackd (mod-host) and mod-ui
$env:MOD_HMI_SERIAL_PORT = "tcp://127.0.0.1:$hmiPort"
$env:MOD_SYS_SERIAL_PORT = "tcp://127.0.0.1:$sysPort"
$env:MOD_DEV_HMI = '0'
# the launcher's "Open Emulator" button runs this, and starts MOD Desktop again if it is running
$env:MOD_HW_EMULATOR = '"{0}" --state "{1}" --tcp webgui={2} "{3}"' -f $emulator, $state, $hmiPort, $firmware
Start-Process -FilePath (Join-Path $desktop 'mod-desktop.exe') -WorkingDirectory $desktop
Write-Host "MOD Desktop started with the emulated $Device"
