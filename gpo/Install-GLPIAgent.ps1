<#
    ------------------------------------------------------------------------
    Install-GLPIAgent.ps1
    Empresa Exemplo - TI
    ------------------------------------------------------------------------

    Substitui o antigo glpi-agent-deployment.vbs.

    Chamado pelo mesmo install-glpi.bat, via GPO de Inicializacao
    (Configuracao do Computador). Roda como SYSTEM.

    O que este script FAZ:
      1. Le os parametros no topo.
      2. Usa uma trava (Mutex) para nao rodar duas vezes ao mesmo tempo.
      3. Copia o script da Peca 2 (Invoke-GLPIInventory.ps1) da pasta de
         rede para uma pasta local - assim a tarefa agendada continua
         funcionando mesmo se a maquina estiver fora da rede da empresa
         num boot/login futuro (ex: notebook em casa).
      4. Descobre a versao do GLPI Agent instalada (via registro).
      5. Decide se precisa instalar (ausente OU versao < alvo).
         Se a versao instalada for igual ou MAIOR que o alvo, nao mexe.
      6. Se precisar, instala via msiexec silencioso, com AGENTMONITOR=1
         e EXECMODE=1 (icone de bandeja) e SEM RUNNOW=1 (nao dispara
         inventario aqui - quem faz isso e a tarefa agendada da Peca 2).
      7. Garante o servico glpi-agent como Automatico e Em execucao.
      8. Corrige o valor "server" no registro, removendo aspas simples
         sobrando.
      9. Garante que a tarefa agendada local (Peca 2) existe e esta
         atualizada.
     10. Grava um log simples de cada execucao.
     11. Se nao houver nada a fazer, termina rapido, sem tocar em nada.

    IMPORTANTE - privilegios:
      Os passos 6, 7, 8 e 9 exigem privilegio de administrador (instalar
      software, mexer em servico, em HKLM e criar tarefa agendada como
      SYSTEM). Via GPO isso nunca e problema, porque o script roda como
      SYSTEM. Mas se alguem rodar este script manualmente, sem ser
      administrador (ex: um teste, ou um tecnico numa maquina sem admin
      local), esses passos sao pulados e registrados no log como tal,
      em vez de o script travar com erro. O passo 3 (copia de arquivo)
      funciona normalmente mesmo sem privilegio de administrador.

    O que este script NAO faz:
      - Nao reinstala quando a versao ja esta em dia.
      - Nao forca inventario (isso e feito pela Peca 2).
      - Nao faz downgrade de versao.

    ------------------------------------------------------------------------
#>

#region PARAMETROS (ajustar aqui quando precisar)

# Versao alvo do GLPI Agent.
$TargetVersion = '1.20'

# Arquitetura do instalador: 'x86' ou 'x64'
$SetupArchitecture = 'x64'

# Pasta de rede onde ficam o instalador MSI e os scripts novos
# (Install-GLPIAgent.ps1 e Invoke-GLPIInventory.ps1 devem estar aqui,
# junto com o MSI, para o script conseguir copiar a Peca 2).
$SetupLocation = '\\empresa.local\netlogon\scripts\GLPI'

# Nome do arquivo MSI
$SetupFileName = "GLPI-Agent-$TargetVersion-$SetupArchitecture.msi"

# Endereco do servidor GLPI
$GlpiServerUrl = 'https://glpi.empresa.example.com/'

# Pasta local onde ficam o log e a copia local do script da Peca 2
$LocalDataDir = 'C:\ProgramData\GLPI-Agent-Deploy'

# Log deste script
$LogFile = Join-Path $LocalDataDir 'install-glpi-agent.log'

# Nome da tarefa agendada local (Peca 2)
$ScheduledTaskName = 'GLPI-Agent - Forcar Inventario'

# Nome do arquivo da Peca 2 (mesmo nome na rede e localmente)
$InventoryScriptFileName = 'Invoke-GLPIInventory.ps1'

# Origem (rede) e destino (local) do script da Peca 2
$InventoryScriptSourcePath = Join-Path $SetupLocation $InventoryScriptFileName
$InventoryScriptPath = Join-Path $LocalDataDir $InventoryScriptFileName

#endregion

#region FUNCOES AUXILIARES

function Write-Log {
    param([string]$Message)

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] $Message"

    try {
        if (-not (Test-Path $LocalDataDir)) {
            New-Item -Path $LocalDataDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        Add-Content -Path $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
    } catch {
        # Se nem o log der certo, nao trava o script por causa disso.
        # -ErrorAction Stop acima garante que o erro caia aqui em vez de
        # so aparecer em vermelho na tela (o que, numa GPO rodando em
        # silencio, faria o problema desaparecer sem deixar rastro).
    }
}

function Test-IsRunningElevated {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Sync-LocalInventoryScript {
    # Copia o script da Peca 2 da pasta de rede para a pasta local.
    # Funciona mesmo sem privilegio de administrador (ProgramData permite
    # criar arquivos novos por padrao). Se a rede estiver indisponivel
    # (ex: notebook fora da empresa), nao falha - so mantem a copia local
    # que ja existir de uma execucao anterior.

    if (-not (Test-Path $InventoryScriptSourcePath)) {
        if (Test-Path $InventoryScriptPath) {
            Write-Log "AVISO: origem '$InventoryScriptSourcePath' inacessivel (rede fora?). Mantendo copia local existente."
        } else {
            Write-Log "AVISO: origem '$InventoryScriptSourcePath' inacessivel e nao ha copia local ainda. A tarefa agendada nao tera o que executar por enquanto."
        }
        return
    }

    $needsCopy = $true

    if (Test-Path $InventoryScriptPath) {
        try {
            $sourceHash = (Get-FileHash -Path $InventoryScriptSourcePath -Algorithm SHA256).Hash
            $localHash = (Get-FileHash -Path $InventoryScriptPath -Algorithm SHA256).Hash
            if ($sourceHash -eq $localHash) {
                $needsCopy = $false
            }
        } catch {
            # Se nao conseguir comparar, copia por seguranca.
            $needsCopy = $true
        }
    }

    if (-not $needsCopy) {
        Write-Log 'Copia local do script de inventario (Peca 2) ja esta atualizada.'
        return
    }

    try {
        if (-not (Test-Path $LocalDataDir)) {
            New-Item -Path $LocalDataDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        Copy-Item -Path $InventoryScriptSourcePath -Destination $InventoryScriptPath -Force -ErrorAction Stop
        Write-Log "Copia local do script de inventario (Peca 2) atualizada a partir de '$InventoryScriptSourcePath'."
    } catch {
        Write-Log "ERRO: falha ao copiar '$InventoryScriptSourcePath' para '$InventoryScriptPath': $($_.Exception.Message)"
    }
}

function Get-AgentMonitorRegistryValue {
    # Le o valor "AgentMonitor" gravado pelo instalador (0 = icone de
    # bandeja desativado, 1 = ativado). Usado para saber se precisamos
    # reparar uma instalacao que ja esta na versao certa mas foi feita
    # antes de adicionarmos AGENTMONITOR=1 as opcoes.
    $paths = @(
        'HKLM:\SOFTWARE\GLPI-Agent\Installer',
        'HKLM:\SOFTWARE\Wow6432Node\GLPI-Agent\Installer'
    )

    foreach ($path in $paths) {
        if (Test-Path $path) {
            $value = (Get-ItemProperty -Path $path -Name 'AgentMonitor' -ErrorAction SilentlyContinue).AgentMonitor
            if ($null -ne $value) {
                return $value
            }
        }
    }

    return $null
}

function Get-InstalledAgentVersion {
    $paths = @(
        'HKLM:\SOFTWARE\GLPI-Agent\Installer',
        'HKLM:\SOFTWARE\Wow6432Node\GLPI-Agent\Installer'
    )

    foreach ($path in $paths) {
        if (Test-Path $path) {
            $value = (Get-ItemProperty -Path $path -Name 'Version' -ErrorAction SilentlyContinue).Version
            if ($value) {
                return $value
            }
        }
    }

    return $null
}

function Test-NeedsInstall {
    param([string]$InstalledVersion, [string]$TargetVersion)

    if ([string]::IsNullOrWhiteSpace($InstalledVersion)) {
        Write-Log "Nenhum agente instalado. Instalacao necessaria (alvo: $TargetVersion)."
        return $true
    }

    try {
        $installed = [version]$InstalledVersion
        $target = [version]$TargetVersion

        if ($installed -lt $target) {
            Write-Log "Versao instalada ($InstalledVersion) menor que o alvo ($TargetVersion). Instalacao necessaria."
            return $true
        }

        if ($installed -gt $target) {
            Write-Log "Versao instalada ($InstalledVersion) maior que o alvo ($TargetVersion). Nada sera feito (sem downgrade)."
        } else {
            Write-Log "Versao instalada ($InstalledVersion) ja e a versao alvo. Nada a instalar."
        }

        return $false
    } catch {
        Write-Log "Nao foi possivel comparar versoes numericamente ('$InstalledVersion' vs '$TargetVersion'). Comparando como texto."
        if ($InstalledVersion -ne $TargetVersion) {
            return $true
        }
        return $false
    }
}

function Install-Agent {
    $msiPath = Join-Path $SetupLocation $SetupFileName

    if (-not (Test-Path $msiPath)) {
        Write-Log "ERRO: instalador nao encontrado em '$msiPath'. Abortando instalacao."
        return $false
    }

    $arguments = @(
        '/i', "`"$msiPath`"",
        '/quiet',
        "SERVER=`"$GlpiServerUrl`"",
        'AGENTMONITOR=1',
        'EXECMODE=1'
    )

    Write-Log "Instalando GLPI Agent a partir de '$msiPath'..."
    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden

    if ($process.ExitCode -eq 0) {
        Write-Log 'Instalacao concluida com sucesso.'
        return $true
    } else {
        Write-Log "ERRO: instalacao terminou com codigo $($process.ExitCode)."
        return $false
    }
}

function Repair-AgentMonitorIcon {
    # A instalacao ja esta na versao certa, mas o icone de bandeja
    # (AgentMonitor) nao foi ativado - normalmente porque a maquina foi
    # instalada antes de AGENTMONITOR=1 entrar nas opcoes.
    #
    # Investigamos a fundo (lendo as tabelas internas do proprio .msi) e
    # confirmamos que o componente do icone so e considerado pelo
    # instalador quando as condicoes AGENTMONITOR=1 E EXECMODE=1 sao
    # satisfeitas NUMA INSTALACAO NOVA. Testamos exaustivamente reparo
    # (/fa) e reinstalacao de recursos (REINSTALL=ALL ADDLOCAL=ALL) numa
    # maquina que ja tem o produto instalado, com resultado consistente:
    # mesmo com exit code 0 (sucesso) e os parametros corretos, o
    # componente do icone NAO e adicionado - o Windows Installer nao
    # reavalia esse componente da mesma forma numa manutencao/reparo
    # como reavaliaria numa instalacao genuina.
    #
    # A unica forma confiavel de ativar o icone numa maquina que ja tem
    # o agente instalado e desinstalar e reinstalar (forcando um estado
    # de "instalacao nova" de verdade). So chegamos aqui quando a versao
    # instalada e EXATAMENTE a versao alvo (nunca mexe em versao maior -
    # ver Test-NeedsInstall), entao isso nunca causa downgrade.
    $msiPath = Join-Path $SetupLocation $SetupFileName

    if (-not (Test-Path $msiPath)) {
        Write-Log "ERRO: instalador nao encontrado em '$msiPath'. Nao foi possivel reparar o icone de bandeja (AgentMonitor)."
        return
    }

    Write-Log 'Icone de bandeja (AgentMonitor) desativado apesar da versao correta (recurso nunca instalado). Reparo/reinstalacao de recursos nao resolve isso (confirmado via testes) - desinstalando e reinstalando para ativa-lo...'

    $uninstallArguments = @(
        '/x', "`"$msiPath`"",
        '/quiet',
        '/norestart'
    )

    Write-Log 'Desinstalando GLPI Agent (etapa 1 de 2, necessaria so para ativar o icone de bandeja)...'
    $uninstallProcess = Start-Process -FilePath 'msiexec.exe' -ArgumentList $uninstallArguments -Wait -PassThru -WindowStyle Hidden

    if ($uninstallProcess.ExitCode -ne 0 -and $uninstallProcess.ExitCode -ne 3010) {
        Write-Log "ERRO: desinstalacao terminou com codigo $($uninstallProcess.ExitCode). Abortando (NAO tentando reinstalar por seguranca - maquina pode ter ficado sem o agente, verificar manualmente)."
        return
    }

    Write-Log 'Desinstalacao concluida. Reinstalando GLPI Agent (etapa 2 de 2) com AGENTMONITOR=1 e EXECMODE=1...'

    $installArguments = @(
        '/i', "`"$msiPath`"",
        '/quiet',
        "SERVER=`"$GlpiServerUrl`"",
        'AGENTMONITOR=1',
        'EXECMODE=1'
    )

    $installProcess = Start-Process -FilePath 'msiexec.exe' -ArgumentList $installArguments -Wait -PassThru -WindowStyle Hidden

    if ($installProcess.ExitCode -eq 0) {
        Write-Log 'Reinstalacao concluida - icone de bandeja (AgentMonitor) deve estar ativo apos o proximo logon.'
    } else {
        Write-Log "ERRO GRAVE: reinstalacao terminou com codigo $($installProcess.ExitCode). Maquina pode ter ficado SEM o agente instalado - verificar manualmente o quanto antes."
    }
}

function Confirm-ServiceRunning {
    $service = Get-Service -Name 'glpi-agent' -ErrorAction SilentlyContinue

    if (-not $service) {
        Write-Log 'AVISO: servico glpi-agent nao encontrado apos a instalacao.'
        return
    }

    if ($service.StartType -ne 'Automatic') {
        Write-Log "Ajustando tipo de inicializacao do servico para Automatico (estava: $($service.StartType))."
        Set-Service -Name 'glpi-agent' -StartupType Automatic
    }

    if ($service.Status -ne 'Running') {
        Write-Log "Iniciando o servico glpi-agent (estava: $($service.Status))."
        Start-Service -Name 'glpi-agent'
    }
}

function Repair-ServerRegistryValue {
    $paths = @(
        'HKLM:\SOFTWARE\GLPI-Agent',
        'HKLM:\SOFTWARE\Wow6432Node\GLPI-Agent'
    )

    foreach ($path in $paths) {
        if (Test-Path $path) {
            $current = (Get-ItemProperty -Path $path -Name 'server' -ErrorAction SilentlyContinue).server
            if ($current) {
                $cleaned = $current.Trim("'", ' ')
                if ($cleaned -ne $current) {
                    Write-Log "Corrigindo valor 'server' no registro ($path): '$current' -> '$cleaned'."
                    Set-ItemProperty -Path $path -Name 'server' -Value $cleaned
                }
            }
        }
    }
}

function Confirm-ScheduledTask {
    $existingTask = Get-ScheduledTask -TaskName $ScheduledTaskName -ErrorAction SilentlyContinue

    $expectedArgument = "-NoProfile -ExecutionPolicy Bypass -File `"$InventoryScriptPath`""
    $needsRecreate = $true

    if ($existingTask) {
        $currentArgs = $existingTask.Actions[0].Arguments
        if ($currentArgs -eq $expectedArgument) {
            $needsRecreate = $false
            Write-Log 'Tarefa agendada ja existe e esta com a configuracao esperada.'
        }
    }

    if (-not $needsRecreate) {
        return
    }

    Write-Log "Criando/atualizando a tarefa agendada '$ScheduledTaskName'..."

    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $expectedArgument

    $triggerBoot = New-ScheduledTaskTrigger -AtStartup
    $triggerBoot.Delay = 'PT2M'

    $triggerLogon = New-ScheduledTaskTrigger -AtLogOn
    $triggerLogon.Delay = 'PT1M'

    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
        -MultipleInstances IgnoreNew

    $task = New-ScheduledTask -Action $action -Trigger @($triggerBoot, $triggerLogon) -Principal $principal -Settings $settings

    Register-ScheduledTask -TaskName $ScheduledTaskName -InputObject $task -Force | Out-Null

    Write-Log 'Tarefa agendada criada/atualizada com sucesso.'
}

#endregion

#region EXECUCAO PRINCIPAL

$mutex = New-Object System.Threading.Mutex($false, 'Global\GLPIAgentInstallScript')
$acquiredLock = $false

try {
    $acquiredLock = $mutex.WaitOne(30000)

    if (-not $acquiredLock) {
        Write-Log 'Outra execucao deste script ja estava em andamento. Encerrando.'
        exit 0
    }

    Write-Log '--- Inicio da execucao ---'

    $isElevated = Test-IsRunningElevated
    if ($isElevated) {
        Write-Log 'Executando com privilegio de administrador (SYSTEM ou Admin local).'
    } else {
        Write-Log 'AVISO: executando SEM privilegio de administrador. Etapas administrativas (instalacao, servico, registro, tarefa agendada) serao PULADAS.'
    }

    # Copia de arquivo: funciona independente de privilegio.
    Sync-LocalInventoryScript

    $installedVersion = Get-InstalledAgentVersion
    $needsInstall = Test-NeedsInstall -InstalledVersion $installedVersion -TargetVersion $TargetVersion

    if (-not $isElevated) {
        if ($needsInstall) {
            Write-Log 'PULADO (requer administrador): instalacao do agente.'
        }
        Write-Log 'PULADO (requer administrador): verificacao do servico.'
        Write-Log 'PULADO (requer administrador): correcao do registro.'
        Write-Log 'PULADO (requer administrador): criacao/atualizacao da tarefa agendada.'
    } else {
        if ($needsInstall) {
            Install-Agent | Out-Null
        } else {
            # Versao ja correta - confere se o icone de bandeja (AgentMonitor)
            # esta ativo. So repara quando a versao instalada e EXATAMENTE
            # a versao alvo (nunca mexe se for maior, respeitando a regra
            # de nunca fazer downgrade/alteracao numa versao mais nova).
            $isExactTargetVersion = $false
            try {
                $isExactTargetVersion = ([version]$installedVersion) -eq ([version]$TargetVersion)
            } catch {
                $isExactTargetVersion = ($installedVersion -eq $TargetVersion)
            }

            if ($isExactTargetVersion) {
                $agentMonitorValue = Get-AgentMonitorRegistryValue
                if ($agentMonitorValue -ne '1') {
                    Repair-AgentMonitorIcon
                } else {
                    Write-Log 'Icone de bandeja (AgentMonitor) ja esta ativo.'
                }
            }
        }
        Confirm-ServiceRunning
        Repair-ServerRegistryValue
        Confirm-ScheduledTask
    }

    Write-Log '--- Fim da execucao ---'
}
catch {
    Write-Log "ERRO INESPERADO: $($_.Exception.Message)"
}
finally {
    if ($acquiredLock) {
        $mutex.ReleaseMutex() | Out-Null
    }
    $mutex.Dispose()
}

exit 0

#endregion