<#
    ------------------------------------------------------------------------
    Invoke-GLPIInventory.ps1
    Empresa Exemplo - TI
    ------------------------------------------------------------------------

    Peca 2 do novo fluxo do GLPI Agent.

    Chamado pela tarefa agendada local "GLPI-Agent - Forcar Inventario"
    (criada pelo Install-GLPIAgent.ps1 / Peca 1), 2 minutos apos o boot
    e 1 minuto apos o login de qualquer usuario.

    O que este script FAZ:
      1. Espera um tempo aleatorio (0 a 90s) antes de fazer qualquer coisa,
         para as maquinas nao baterem todas no GLPI ao mesmo tempo.
      2. Le um arquivo de controle local com a hora do ultimo inventario
         forcado por este script.
      3. Se o ultimo inventario forcado foi ha menos de 2 horas, encerra
         sem fazer nada (evita duplicar boot + login proximos).
      4. Caso contrario, pede ao agente (que ja esta rodando local) para
         inventariar agora, chamando http://127.0.0.1:62354/now.
         Se a primeira tentativa falhar, tenta mais uma vez.
      5. Atualiza o arquivo de controle com o horario de agora.

    Este script NAO instala nada e NAO reinicia o servico - ele so
    "cutuca" o agente que ja esta rodando.

    ------------------------------------------------------------------------
#>

#region PARAMETROS

$MinIntervalHours = 2
$MaxRandomDelaySeconds = 90
$AgentNowUrl = 'http://127.0.0.1:62354/now'
$LocalDataDir = 'C:\ProgramData\GLPI-Agent-Deploy'
$LogFile = Join-Path $LocalDataDir 'install-glpi-agent.log'
$StateFile = Join-Path $LocalDataDir 'last-forced-inventory.txt'

#endregion

#region FUNCOES AUXILIARES

function Write-Log {
    param([string]$Message)

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] [Inventario] $Message"

    try {
        if (-not (Test-Path $LocalDataDir)) {
            New-Item -Path $LocalDataDir -ItemType Directory -Force | Out-Null
        }
        Add-Content -Path $LogFile -Value $line -Encoding UTF8
    } catch {}
}

function Get-LastForcedInventoryTime {
    if (Test-Path $StateFile) {
        $content = (Get-Content -Path $StateFile -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($content) {
            try { return [datetime]::Parse($content) } catch { return $null }
        }
    }
    return $null
}

function Set-LastForcedInventoryTime {
    param([datetime]$Time)
    try {
        if (-not (Test-Path $LocalDataDir)) {
            New-Item -Path $LocalDataDir -ItemType Directory -Force | Out-Null
        }
        Set-Content -Path $StateFile -Value $Time.ToString('o') -Encoding UTF8
    } catch {
        Write-Log "AVISO: nao foi possivel gravar o arquivo de controle '$StateFile'."
    }
}

function Invoke-ForcedInventory {
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        try {
            $response = Invoke-WebRequest -Uri $AgentNowUrl -UseBasicParsing -TimeoutSec 15
            if ($response.Content -match 'OK') {
                Write-Log "Inventario forcado com sucesso (tentativa $attempt)."
                return $true
            } else {
                Write-Log "AVISO: resposta inesperada do agente na tentativa $attempt`: $($response.Content)"
            }
        } catch {
            Write-Log "AVISO: falha ao chamar '$AgentNowUrl' na tentativa $attempt`: $($_.Exception.Message)"
        }
        if ($attempt -lt 2) { Start-Sleep -Seconds 5 }
    }
    return $false
}

#endregion

#region EXECUCAO PRINCIPAL

Write-Log '--- Inicio da execucao (tarefa agendada) ---'

$randomDelay = Get-Random -Minimum 0 -Maximum ($MaxRandomDelaySeconds + 1)
Write-Log "Aguardando $randomDelay segundos antes de continuar."
Start-Sleep -Seconds $randomDelay

$lastRun = Get-LastForcedInventoryTime
$now = Get-Date

if ($lastRun) {
    $hoursSinceLastRun = ($now - $lastRun).TotalHours
    if ($hoursSinceLastRun -lt $MinIntervalHours) {
        $roundedHours = [math]::Round($hoursSinceLastRun, 1)
        Write-Log "Ultimo inventario forcado ha $roundedHours h (menos que o minimo de $MinIntervalHours h). Nada a fazer."
        Write-Log '--- Fim da execucao ---'
        exit 0
    }
}

$success = Invoke-ForcedInventory

if ($success) {
    Set-LastForcedInventoryTime -Time $now
} else {
    Write-Log 'Inventario nao foi confirmado apos as tentativas. Arquivo de controle NAO atualizado.'
}

Write-Log '--- Fim da execucao ---'

exit 0

#endregion