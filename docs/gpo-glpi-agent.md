# GPO de deploy do GLPI Agent — Diagnóstico, Desenho e Runbook (atualizado 2026-09-24)

Trilha paralela ao painel de ativos: melhorar a GPO que instala/mantém o GLPI Agent nas máquinas, para o inventário (fonte do painel) ficar sempre atualizado.

## STATUS: ROLLOUT CONCLUÍDO (2026-09-24) — agente na versão 1.20
A GPO de produção (`GPO - GLPI Agent`) está aplicando o `Install-GLPIAgent.ps1` (alvo `1.20`) para **todas as máquinas** das OUs de computadores (Filtragem de Segurança: `Authenticated Users`, sem restrição). Não há infraestrutura "piloto" separada — tudo roda pela GPO de produção única.

## Cenário atual (pós-rollout 1.20)
- GLPI 10.0.24, agente alvo **1.20** x64, MSI (`GLPI-Agent-1.20-x64.msi`) em `\\empresa.local\netlogon\scripts\GLPI\`, SERVER `https://glpi.empresa.example.com/`.
- GPO de produção (`GPO - GLPI Agent`), linkada em `empresa.local/Computadores/TI` (e nas demais OUs de computadores), Filtragem de Segurança: `Authenticated Users` (todas as máquinas).
- Script de Inicialização (Computador) da GPO chama um `.bat` (renomeado para o nome definitivo — antigo `install-glpi-piloto.bat`) → `Install-GLPIAgent.ps1`, chamado **direto do caminho de rede** (não copiado localmente) — qualquer edição no arquivo da rede tem efeito imediato no próximo boot de qualquer máquina.
- `glpi-agent-deployment.vbs` e o `install-glpi.bat` antigo não são mais referenciados por nenhuma GPO — podem ser removidos da pasta de rede quando desejado.
- Parque: dezenas de máquinas, recebendo a 1.20 conforme cada uma reinicia (não simultâneo).
- Frequência de inventário no GLPI: 48h → 12h (feito) — rede de segurança contra falha do script local.
- `Invoke-GLPIInventory.ps1` (Peça 2) copiado na pasta de rede junto do MSI.
- **Permissão de escrita na pasta de rede**: só `BUILTIN\Administradores` (grupo local do servidor de arquivos `srv-ad01`) e `SISTEMA` têm `FullControl`. Contas de domínio comuns (mesmo a da equipe de TI) e contas locais de estação (`ws-ti01\ti`) só têm `ReadAndExecute` via "Usuários autenticados" — **não conseguem sobrescrever os scripts**. Ficou registrado aqui porque gerou um bloqueio real durante o update da 1.20 (ver histórico abaixo); da próxima vez, já usar de cara uma conta com direito de admin nesse servidor específico.

## Diagnóstico original (coleta no notebook da equipe de TI, WS-TI01)
1. `.vbs` antigo: `Reconfigure="Yes"` + `RUNNOW=1` reinstalava a cada boot e gerava inventário duplicado.
2. Serviço `glpi-agent` sempre esteve Running/Automatic; "último contato" antigo vinha do intervalo do servidor (era 48h).
3. Script antigo só rodava no boot completo, não no login.
4. `Can't decode JSON content` no log = ruído.
5. `SERVER` no registro tinha aspas simples sobrando — corrigido automaticamente pelo novo script, confirmado repetidas vezes.
6. `http://127.0.0.1:62354/now` força inventário local sem reinstalar — validado.

## Análise inicial dos agentes
- A maior parte dos agentes contatou o servidor nas últimas 24 h, em linha com o esperado.
- Alguns ficavam dias sem contato e parte ainda estava no agente 1.7 (investigar, sem urgência).

## Decisões de desenho
- Gatilho: script de Inicialização (só garante instalação/versão/serviço) + tarefa agendada local (SYSTEM) no boot e no logon, forçando inventário via `/now`.
- Intervalo mínimo entre inventários forçados: **2 horas**.
- Tarefa agendada (Peça 2) é criada pelo próprio script de inicialização (Peça 1).
- `AGENTMONITOR=1` **e** `EXECMODE=1` em **toda** instalação/reinstalação via msiexec (ver bug corrigido em 2026-09-24 abaixo — por um tempo `Install-Agent` só passava `AGENTMONITOR=1`).
- Nunca fazer downgrade.
- Frequência de inventário do GLPI: 48h → 12h (feito).
- Se `/now` falhar, arquivo de controle da Peça 2 NÃO é atualizado.
- Peça 1 copia a Peça 2 da rede para local automaticamente (hash compara, tolera rede fora).
- Peça 1 detecta privilégio de administrador e pula etapas administrativas com aviso claro no log, sem travar, quando não tem privilégio.
- Bug de logging corrigido: `Write-Log`, `Copy-Item` e `Set-Content` usam `-ErrorAction Stop` dentro dos `try/catch` (sem isso, erros de "acesso negado" apareciam soltos na tela em vez de caírem no `catch`). Aplicado nos dois scripts.

## Desenho — 3 peças
1. **Install-GLPIAgent.ps1 (Peça 1)** — trava por mutex; copia `Invoke-GLPIInventory.ps1` da rede para local; checa privilégio; só instala se ausente/desatualizado (sem downgrade); garante serviço Automatic/Running; corrige `SERVER` no registro; garante a tarefa agendada; repara o ícone de bandeja quando necessário (ver seção dedicada abaixo).
2. **Invoke-GLPIInventory.ps1 (Peça 2)** — chamado pela tarefa agendada: espera aleatória 0-90s, confere se já rodou nas últimas 2h, chama `/now` (1 retry), grava horário só se deu certo.
3. **Agente** — sem mudança de mecânica; ciclo do servidor agora em 12h como rede de segurança.

## Testes realizados no notebook da equipe de TI (WS-TI01) — TODOS PASSARAM
1. Peça 1 (execução manual, admin): versão OK, corrigiu `SERVER`, criou tarefa agendada.
2. Peça 2, primeira execução (manual): esperou aleatório, chamou `/now`, sucesso, gravou controle.
3. Peça 2, regra das 2h (manual, em seguida): detectou intervalo curto, não chamou `/now` de novo.
4. Peça 2, gatilho de **boot** (reinício de verdade): disparou sozinha, `LastTaskResult: 0`.
5. Peça 2, gatilho de **logon** (logoff/login de verdade): disparou sozinha, `LastTaskResult: 0`.
6. Peça 1 v2 (cópia automática + checagem de privilégio), execução manual como administrador, pasta recriada do zero: cópia da Peça 2, versão OK, registro corrigido, tarefa confirmada.
7. Peça 1 v2, execução manual SEM privilégio de administrador: validado — aviso de execução sem privilégio, cópia da Peça 2 funcionando, versão reconhecida, PULADO sem erro na tela.
8. Reparo do ícone de bandeja (AgentMonitor) na 1.19, desinstalação + reinstalação: validado de ponta a ponta.
9. Piloto real via GPO isolada (2026-09-24): validado de ponta a ponta via reboot real, sem execução manual.
10. **Upgrade 1.19 → 1.20 (2026-09-24)**: validado de ponta a ponta manualmente — instalação concluída, `AgentMonitor=1`, arquivo do ícone e chave `Run` presentes, sem precisar do reparo especial. Ícone visual confirmado após logon novo (ver "Falso alarme" abaixo). Ver seção "Reavaliação para a 1.20" abaixo.

**Conclusão: as 3 peças estão validadas de ponta a ponta**, incluindo execução sem privilégio administrativo, reparo do ícone de bandeja, disparo real via GPO, e upgrade de versão maior (1.19→1.20) com ícone incluso.

## Investigação e solução — Ícone de bandeja (AgentMonitor)

### Sintoma
Instalação manual (usuário rodando o instalador com a tela gráfica) sempre mostrava o ícone do GLPI Agent na bandeja do Windows. Instalação via GPO (`.vbs` antigo, sempre reinstalando com `msiexec /quiet`) **nunca** mostrava o ícone, mesmo reinstalando a cada boot.

### Causa raiz (confirmada lendo as tabelas internas do `.msi` via COM `WindowsInstaller.Installer`)
- O componente que contém o executável do ícone (`GLPI-AgentMonitor-x64.exe`, em `perl\bin\`) só é considerado pelo instalador quando a condição **`AGENTMONITOR=1 AND EXECMODE=1`** é satisfeita **numa instalação nova**.
- Esse componente cria: (a) o arquivo `GLPI-AgentMonitor-x64.exe`; (b) uma entrada na chave `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run` chamada `GLPI-AgentMonitor` (mecanismo de autostart).
- Testado exaustivamente na 1.19: **reparo (`/fa`)** e **reinstalação de recursos (`REINSTALL=ALL ADDLOCAL=ALL`)** numa máquina que já tem o produto instalado — mesmo com `AGENTMONITOR=1 EXECMODE=1` corretos e exit code 0, o componente do ícone **nunca** é adicionado nesse cenário de manutenção/reparo do MESMO ProductCode.
- **Solução confiável para esse cenário (mesma versão, sem ícone): desinstalar (`msiexec /x`) e reinstalar (`msiexec /i ... AGENTMONITOR=1 EXECMODE=1`) em sequência.**

### Bug encontrado e corrigido em 2026-09-24 (antes do rollout da 1.20)
Ao revisar o script para a atualização da 1.20, foi encontrado que a função `Install-Agent` (usada sempre que a versão instalada é MENOR que o alvo — ou seja, o caminho que praticamente todas as máquinas percorrem numa instalação nova ou upgrade) só passava `AGENTMONITOR=1`, **sem** `EXECMODE=1`. Só `Repair-AgentMonitorIcon` tinha os dois parâmetros. Corrigido: `Install-Agent` agora também passa `'AGENTMONITOR=1', 'EXECMODE=1'`.

### Reavaliação para a 1.20 (2026-09-24) — resultado do teste de upgrade
Quando saiu a versão 1.20 do agente, a equipe de TI pediu para reavaliar se a rotina de desinstalar+reinstalar ainda seria necessária (combinado desde a implementação da 1.19). Teste manual no notebook da equipe de TI (que já estava na 1.19 com ícone ativo, simulando exatamente o que as máquinas do parque vão passar):
- `Test-NeedsInstall` detectou `1.19 < 1.20` → chamou `Install-Agent` (agora com `AGENTMONITOR=1 EXECMODE=1` corrigido) → `msiexec /i GLPI-Agent-1.20-x64.msi ...` → **sucesso**.
- Verificado depois: `AgentMonitor = 1` no registro, `Version = 1.20`, arquivo `GLPI-AgentMonitor-x64.exe` presente, chave `Run\GLPI-AgentMonitor` presente.
- **Conclusão confirmada empiricamente: um upgrade de versão maior (major upgrade, ProductCode novo) É tratado pelo Windows Installer como instalação genuinamente nova para fins do componente do ícone — diferente de um reparo/reinstalação da MESMA versão/ProductCode.** Por isso o upgrade sozinho já resolveu o ícone, sem precisar do `Repair-AgentMonitorIcon`.
- `Repair-AgentMonitorIcon` continua no script como rede de segurança (só dispara quando a versão instalada já é EXATAMENTE a versão alvo e o ícone ainda está ausente — cenário que não deveria mais ocorrer com o bug do `EXECMODE=1` corrigido, mas fica como proteção).

### Falso alarme pós-upgrade (2026-09-24): ícone "sumido" horas depois
Algumas horas após o teste de upgrade da 1.20 (mesma sessão de trabalho, sem logoff), a equipe de TI reportou que o ícone não estava na bandeja. Diagnóstico: `AgentMonitor=1` no registro, arquivo e chave `Run` presentes, "Habilitado"/"Ativado" no Gerenciador de Tarefas e nas Configurações — tudo certo. Mas `Get-Process -Name "GLPI-AgentMonitor-x64"` não retornava nada: o processo simplesmente **ainda não tinha sido lançado nessa sessão**, porque não houve logoff/logon (nem reinício) desde a instalação — um desbloqueio de tela não conta como sessão nova. Após logoff/logon de teste, o ícone apareceu imediatamente. **Não é bug — é o comportamento já documentado (autostart só dispara numa sessão nova), só reforça que vale checar isso antes de investigar mais a fundo quando alguém reportar "ícone sumiu" logo após uma instalação/atualização.**

### Implementação atual no script (Peça 1 — `Install-GLPIAgent.ps1`)

```powershell
function Install-Agent {
    $msiPath = Join-Path $SetupLocation $SetupFileName
    $arguments = @('/i', "`"$msiPath`"", '/quiet', "SERVER=`"$GlpiServerUrl`"", 'AGENTMONITOR=1', 'EXECMODE=1')
    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
    # ... loga sucesso/erro
}

function Repair-AgentMonitorIcon {
    # So roda quando a versao instalada e EXATAMENTE a versao alvo e o
    # icone ainda esta ausente (rede de seguranca - nao deveria mais
    # disparar apos a correcao do EXECMODE=1 em Install-Agent).
    $msiPath = Join-Path $SetupLocation $SetupFileName

    $uninstallArguments = @('/x', "`"$msiPath`"", '/quiet', '/norestart')
    $uninstallProcess = Start-Process -FilePath 'msiexec.exe' -ArgumentList $uninstallArguments -Wait -PassThru -WindowStyle Hidden
    if ($uninstallProcess.ExitCode -ne 0 -and $uninstallProcess.ExitCode -ne 3010) { return } # aborta sem reinstalar, por seguranca

    $installArguments = @('/i', "`"$msiPath`"", '/quiet', "SERVER=`"$GlpiServerUrl`"", 'AGENTMONITOR=1', 'EXECMODE=1')
    Start-Process -FilePath 'msiexec.exe' -ArgumentList $installArguments -Wait -PassThru -WindowStyle Hidden
}
```

Como `Repair-AgentMonitorIcon` só roda quando `AgentMonitor` no registro ainda não é `1` E a versão já é exatamente a alvo, e agora `Install-Agent` já entrega o ícone corretamente em qualquer instalação/upgrade, essa rotina de desinstalar+reinstalar deve, na prática, quase nunca mais disparar — mas foi mantida como proteção (custo zero enquanto não é necessária).

### Armadilha lateral encontrada durante os testes da 1.19 (não é bug do nosso script)
Durante os testes de reparo/reinstalação da 1.19, apareceu uma vez o erro `1625` do Windows Installer ("instalação proibida pela política do sistema") em toda tentativa de `msiexec`, logo depois de um reinício. Investigação (GPO, Diretiva de Restrição de Software, AppLocker, antivírus) não achou causa definitiva. Um segundo reinício resolveu sozinho. Tratado como condição transitória; se reaparecer, reiniciar antes de investigar mais.

### ⚠️ Nota para a próxima versão do agente
Já reavaliado uma vez (1.19→1.20) e confirmado que upgrades de versão maior não precisam do reparo especial. Se sair uma versão ainda mais nova, o comportamento esperado é o mesmo (upgrade = instalação nova do ponto de vista do MSI) — mas vale só confirmar rapidamente com o mesmo teste manual antes de ir para produção, por segurança. E lembrar: se o ícone parecer ausente logo depois do teste, checar primeiro se já houve logoff/logon novo antes de assumir que é bug (ver "Falso alarme" acima).

## Histórico — Piloto em GPO isolada (concluído e desmontado em 2026-09-24, antes do rollout da 1.19)

Etapa intermediária usada para validar em produção real antes do rollout total da 1.19, hoje já desfeita:
- Grupo de segurança AD `GPO-GLPI-Agent-Piloto` (só com `WS-TI01`) e GPO separada `GPO - GLPI Agent - Piloto`, com ACE de Negar na GPO de produção para a máquina piloto não rodar as duas ao mesmo tempo.
- Teste via reboot real de `WS-TI01`: log mostrou execução às 08:17:49 de 24/09/2026 como SYSTEM, sem erros; `gpresult /r` elevado confirmou a GPO piloto aplicada e a `GPO - GLPI Agent` antiga corretamente filtrada.
- Rollout total feito reapontando o próprio script de Inicialização da GPO de produção (`GPO - GLPI Agent`) do `.bat` antigo para o novo, e removendo o ACE de Negar.
- Limpeza final: GPO piloto e grupo `GPO-GLPI-Agent-Piloto` **excluídos** (preferência por não manter objetos inativos no AD).

## Histórico — Upgrade para 1.20 (2026-09-24)
- MSI novo (`GLPI-Agent-1.20-x64.msi`) colocado pela equipe de TI na pasta de rede.
- Script atualizado: `$TargetVersion = '1.20'` + correção do bug `EXECMODE=1` faltando em `Install-Agent`.
- Testado manualmente no WS-TI01 (que estava na 1.19) — sucesso, ícone confirmado (ver seção de investigação acima).
- **Bloqueio de permissão ao tentar sobrescrever o arquivo na rede**: a conta local `ws-ti01\ti` e até a conta de domínio pessoal da equipe de TI (conta de administrador de TI) não têm permissão de escrita na pasta (`\\empresa.local\netlogon\scripts\GLPI\`) — só `BUILTIN\Administradores` do servidor de arquivos e `SISTEMA`. A equipe de TI resolveu copiando o arquivo por outro meio . **Anotar para a próxima vez: já usar de cara uma conta com direito de admin nesse servidor específico**, para não perder tempo com `net use`/`Copy-Item` negado.
- Arquivo de produção confirmado atualizado (via `Get-Content ... | Select-String`) com `TargetVersion = '1.20'` e as 3 ocorrências esperadas de `EXECMODE=1`.
- Algumas horas depois, "susto" de ícone ausente — investigado e confirmado como falso alarme (processo não lançado por falta de logon novo na sessão, não bug). Ver "Falso alarme pós-upgrade" acima.

## Pendências
- **Acompanhar o rollout da 1.20 nos próximos dias**: conferir o `install-glpi-agent.log` em algumas máquinas variadas e o painel/CSV de agentes do GLPI, de olho em erros (exit codes de `msiexec` diferentes de 0/3010).
- Remover `glpi-agent-deployment.vbs`, `install-glpi.bat` antigo e `Inspect-GLPIAgentMSI.ps1` da pasta de rede quando desejado (não são mais usados por nenhuma GPO, sem pressa).
- Descobrir/documentar qual conta tem permissão de admin no servidor de arquivos `srv-ad01`, para as próximas atualizações de versão não esbarrarem de novo nesse bloqueio.
- Quando sair a próxima versão do agente: reconfirmar rapidamente que o upgrade continua trazendo o ícone sozinho (ver nota acima).
- Opcional/à parte: investigar exposição do endpoint do GLPI à internet; investigar as máquinas ainda em agente 1.7.
