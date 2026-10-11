# Painel de Controle de Ativos (GLPI) — Plano e Status

> Nota: este é o histórico de desenvolvimento. O login por departamento (`login.php`, `require_login`, `departments`) foi implementado e depois cancelado; esse código **não faz parte do pacote publicado**.

## Contexto
- GLPI versão 10.0.24, instância em `https://glpi.empresa.example.com/`.
- Objetivo: dar à TI um controle visual do parque de ativos e permitir que **cada gestor de departamento** consulte os equipamentos do seu setor para planejar orçamento de manutenção/upgrade/troca. TI define o padrão e faz a manutenção; cada área é responsável por comprar/atualizar seus próprios equipamentos.
- Fontes recebidas originalmente: `glpi.csv` (export padrão do GLPI, ';' como separador, dezenas de linhas, consolidadas por ativo) e um HTML inicial (`relatorio_notebooks.html`) que já fazia classificação de notebooks por geração de CPU + RAM.
- Servidor de produção do GLPI: Rocky Linux 9.8, IP interno `10.0.0.10`, acesso root direto da equipe de TI. Nginx (usuário `nginx`) na frente, PHP-FPM (usuário `apache`, socket `/run/php-fpm/www.sock`) atrás. SELinux desabilitado; sem firewalld/iptables/nftables bloqueando.

## Infraestrutura de rede da empresa (mapeada em 2026-09-24/25)
- **DNS interno**: Controlador de Domínio Samba-AD (`srv-ad01`, realm `EMPRESA.LOCAL`, compilado a partir do código-fonte — binários em `/usr/local/samba/`, não pelo pacote da distro; `samba-tool` fica em `/usr/local/samba/bin/samba-tool`). Esse DC hospeda, entre outras, uma zona **primária própria para `empresa.example.com`** (split-horizon: mesmo nome de domínio da internet, mas com registros internos independentes) — já existia antes deste projeto, com registros como `glpi` → `10.0.0.10` (apontando direto para IPs internos) e outros apontando para IPs públicos, usados só por serviços expostos à internet. O DNS das estações é `10.0.0.5` (via DHCP).
  - Comandos úteis (exigem a senha da conta `administrator` do domínio, não a senha de root do Linux): `samba-tool dns zonelist <dc> -U administrator`, `samba-tool dns query <dc> <zona> <nome> ALL -U administrator`, `samba-tool dns add <dc> <zona> <nome> A <ip> -U administrator`, `samba-tool dns delete <dc> <zona> <nome> A <ip> -U administrator`, `samba-tool dns update <dc> <zona> <nome> A <ip-antigo> <ip-novo> -U administrator` (troca atômica de valor, sem deixar o nome sem resposta; usado em 2026-09-25 para o `ativos`). O TTL dos registros da zona é 900 s.
  - **Atenção**: o próprio servidor do GLPI (`10.0.0.10`) usa `8.8.8.8` como DNS (`/etc/resolv.conf`), não o Samba-AD — por isso ele NÃO resolve nomes internos como `ativos.empresa.example.com` (só resolve `glpi...` porque esse tem registro público de verdade, via Caddy). Isso é irrelevante para os usuários finais (estações da empresa usam o DNS do domínio via DHCP), mas importa para qualquer teste feito com `curl`/`nslookup` rodado a partir desse servidor — use `curl --resolve <nome>:<porta>:10.0.0.10 ...` para contornar.
  - **Cuidado ao consultar DNS a partir do `srv-proxy01`**: ele também usa o DNS interno, então `dig` sem `@` devolve a zona interna (ex.: `NS` respondeu `empresa.local.`). Para ver o que a internet enxerga, usar `@8.8.8.8` ou os servidores oficiais.
- **DNS público**: zona `empresa.example.com` gerenciada no **registrador de domínios** (painel em modo avançado, "Configurar zona DNS", ~38 entradas, listadas em ordem alfabética). **Ao criar/editar registros é preciso clicar em "Salvar alterações" e esperar a mensagem "Zona DNS atualizada com sucesso!"** — sem isso a entrada some ao fechar a janela (aconteceu em 2026-09-25 com o `ativos`: a primeira tentativa nunca foi gravada). O serial do SOA segue o formato `AAAADDDnnn` (ano + dia do ano + sequência) e sobe quando a zona é publicada — útil para confirmar publicação: `dig +short SOA empresa.example.com @<servidor-autoritativo>`. Serviços de e-mail/site ficam em provedor externo (MX/SPF), não mexer.
- **Proxy reverso público**: servidor dedicado `srv-proxy01` (Ubuntu 22.04, Caddy, `/etc/caddy/Caddyfile`), **IP interno `10.0.0.20`** (acessível por todos os dispositivos da VLAN default), **IP público `203.0.113.10`** (para onde apontam `glpi` e `ativos` no DNS público). Expõe serviços internos para a internet com certificado válido automático (Let's Encrypt, desafio HTTP-01), ex.: `glpi.empresa.example.com` → `reverse_proxy https://<ip-interno>` (com `tls_insecure_skip_verify` e `tls_server_name <nome>` porque o backend interno usa certificado autoassinado/de outro nome e roteia por SNI). O bloco `ativos` foi acrescentado em 2026-09-25 (ver abaixo). Backup do Caddyfile antes da alteração: `/etc/caddy/Caddyfile.bak-20260925`.

## Decisões do projeto
**Método de implantação**: todo comando no servidor é executado pela TI, um passo por vez, validando cada resultado antes do próximo. A configuração e o serviço do GLPI em produção nunca são alterados.

**Decisão explícita sobre login (2026-09-24)**: por enquanto o painel deve ficar de **acesso livre** (sem tela de login), tratado como se fosse a TI (vê tudo, sem filtro de departamento) — só para facilitar a etapa inicial de coleta/validação dos dados. A implementação do login por departamento fica para o **final**, só quando a equipe de TI pedir.

**Decisão sobre exposição pública — REVISADA em 2026-09-25 (tarde)**: de manhã ficou decidido não colocar o painel no Caddy, porque, com o login desativado, ele ficaria visível sem senha na internet. À tarde, a equipe de TI trouxe o problema do aviso de certificado (`NET::ERR_CERT_COMMON_NAME_INVALID`: o certificado do Nginx é Let's Encrypt só para `glpi...`) e propôs usar o Caddy. Solução adotada, que resolve o certificado **sem expor os dados**: o painel passa pelo Caddy, mas o bloco `ativos` só atende IPs privados (`@externo not remote_ip private_ranges` → `respond @externo "Acesso negado" 403`). Quem vem da internet vê só "Acesso negado". Isso **não depende mais do login por departamento** para ser seguro; se um dia o painel precisar de acesso externo, remover essa restrição só depois de ativar o login.

**Decisão sobre o nome interno (2026-09-25)**: o nome inicial `painel.empresa.example.com` foi considerado genérico demais pela equipe de TI. Trocado para **`ativos.empresa.example.com`** (combina com o nome do projeto, "Controle de Ativos"), por decisão da equipe de TI. O registro antigo (`painel`) foi removido do DNS interno.

## Fases do projeto
- **Fase 1 (concluída/aguardando validação do gestor)**: protótipo em HTML único (`painel_ativos.html` v5), com upload manual do CSV. Ainda não apresentado à gestão (aguardando agenda) — decidiu adiantar a Fase 2 em paralelo.
- **Fase 2 (pacote v1 entregue em 2026-09-24, implantado e com dados reais validados em 2026-09-24, com DNS interno e acesso sem porta desde 2026-09-25, e com certificado HTTPS válido via Caddy desde 2026-09-25)**: sai do CSV manual, busca os dados direto do GLPI via API REST, hospedado no mesmo servidor do GLPI em diretório separado, rodando em produção em modo de acesso livre (login ainda desativado por decisão da equipe de TI), acessível internamente por **`https://ativos.empresa.example.com/`** (porta padrão 443, certificado válido, sem aviso).

## DECISÃO DE ARQUITETURA — Fase 2 (confirmada 2026-09-24: "vamos seguir exatamente isso")
- **Hospedagem**: mesmo servidor do GLPI, em diretório **separado** da instalação (`/var/www/painel-ativos/`), com seu próprio `server{}` no Nginx — nunca dentro da pasta que o instalador/atualizador do GLPI gerencia, e nunca editando o vhost do GLPI em produção. (O nome do diretório no servidor, `painel-ativos`, ficou como está — só o nome de DNS usado para acessar mudou para `ativos`.)
- **Integração com a API REST do GLPI**: um script PHP intermediário no servidor guarda os tokens e fala com a API; o navegador nunca vê App-Token/User-Token.
- **Controle de acesso ao painel**: login simples por departamento já implementado no código (`login.php`/`config.php`), mas **desativado por enquanto** via chave `require_login = false` em `config.php` (toggle reversível, sem precisar mexer em código quando for hora de ligar). Enquanto desativado, todo acesso é tratado como TI (vê tudo, sem filtro).

## CREDENCIAIS DA API — preparadas no GLPI real (2026-09-24)
1. API REST já estava habilitada. URL: `https://glpi.empresa.example.com/apirest.php/`.
2. Usuário de serviço `svc-painel-ativos` criado (perfil Read-Only, entidade EMPRESA, Recursivo: Sim).
3. User-Token do `svc-painel-ativos` gerado e copiado pela equipe de TI.
4. Cliente de API "Painel de Ativos" criado, sem restrição de IP por enquanto. App-Token gerado e copiado.
5. Tokens preenchidos pela própria equipe de TI direto no `config.php` do servidor.

## ENTREGA — Pacote de código Fase 2 v1 (2026-09-24)
8 arquivos entregues via download no chat ("painel-ativos-fase2"), construídos em cima do protótipo v5 sem alterar a lógica de classificação:
- `painel_ativos.html` — mesma UI/lógica de classificação da v5, agora busca dados de `api_ativos.php` via fetch. Mostra "Logado como <departamento>" no cabeçalho, botão "Atualizar dados" e "Sair".
- `api_ativos.php` — endpoint chamado pelo painel. Aplica (ou não, conforme `require_login`) o filtro de departamento no servidor. Suporta `?debug=1` e `?nocache=1` (exclusivos de quem é TI).
- `glpi_client.php` — fala com a API REST do GLPI: abre sessão, descobre dinamicamente os IDs de campo via `listSearchOptions/Computer` (casando pelo `uid`), busca via `search/Computer` e devolve registros no formato de colunas do `glpi.csv` antigo.
- `common.php` — config loader, wrapper de chamadas HTTP (cURL), porte para PHP do `splitDepartamento()`/lista de tipos de servidor.
- `login.php` / `logout.php` — tela de login por departamento (hoje sem uso, pois `require_login=false`).
- `config.example.php` — modelo para `config.php`, incluindo a chave `require_login`.
- `README_IMPLANTACAO.md` — passo a passo de implantação e validação.

## IMPLANTAÇÃO NO SERVIDOR REAL — concluída e validada (2026-09-24)
Processo feito um passo de cada vez, sempre com confirmação da equipe de TI, sem tocar no vhost/serviço do GLPI em produção:
1. Diretório `/var/www/painel-ativos/` criado; 8 arquivos copiados; `chown apache:nginx` (750/640) nos arquivos, pasta `cache/` com `chown apache:apache` (770, precisa ser gravável pelo PHP-FPM).
2. Vhost Nginx inicial na porta 8443 (depois substituído — ver seção "Acesso sem porta" abaixo). Sempre validado com `nginx -t` antes de cada `systemctl reload nginx` (nunca `restart`). Confirmado via log e captura de tela do navegador que o GLPI (porta 443) continuou funcionando normalmente durante todo o processo.

### Bugs encontrados e corrigidos durante a implantação
1. **Permissão negada em `config.php`**: o arquivo foi criado via `cp` como root **depois** do `chown -R apache:nginx` em lote, então não herdou o dono certo — PHP-FPM (usuário `apache`) não conseguia ler o arquivo (HTTP 500). Corrigido com `chown apache:nginx config.php; chmod 640 config.php`.
2. **Erro de sintaxe em `config.php`**: os valores de `app_token`/`user_token` foram colados sem aspas simples ao redor, então o PHP tentava interpretá-los como identificadores soltos. Corrigido com `sed -i` linha a linha, verificado com `php -l`.
3. **Campos não localizados em `listSearchOptions/Computer`**: 10 dos 14 campos candidatos não bateram — este GLPI usa uids compostos no formato `Computer.<Tipo>.<campo>` (ex.: `Computer.Item_DeviceProcessor.DeviceProcessor.designation`), não a forma mais simples que havia sido usada como primeira tentativa. Resolvido adicionando um modo de diagnóstico com dump compacto de todos os uids disponíveis (`todas_as_opcoes_compacto` em `api_ativos.php?debug=1`), localizando manualmente os uids reais e atualizando `candidatos_de_campo()` em `glpi_client.php` com a lista confirmada (documentada no próprio código, com a data da validação). Resultado: `campos_faltando: []`.
4. **Memória em megabytes, não gigabytes**: o GLPI guarda `Item_DeviceMemory.size` em MB, enquanto a regra de negócio do painel (`RAM_THRESHOLD_GB = 15,5`) foi calibrada em GB a partir do CSV exportado manualmente. Sem correção, todo ativo teria sido classificado como "sem necessidade de upgrade de RAM" silenciosamente (nenhum erro visível). Identificado ao revisar o primeiro payload de dados reais (nenhum erro visível foi reportado). Corrigido em `glpi_client.php`: `$memGB = $memMB / 1024`, formatado e sem zeros à direita. Validado: valores de memória vieram corretos (`"8"`, `"16"`, etc.) após o ajuste e um `?nocache=1` para forçar o cache antigo (ainda em MB) a ser descartado.

### Validação final dos dados reais (2026-09-24)
- Contagem: **N ativos** retornados (confere com o parque conhecido — itemtype `Computer`, ainda sem Monitor/Phone).
- Registro de amostra conferido campo a campo: `Entidade: "EMPRESA"`, `Status: "Ativo"`, `Fabricante: "Dell Inc."`, `Tipo: "Notebook"`, `Grupo: "EMPRESA > Financeiro"` (formato compatível com `split_departamento`), `Sistema operacional: "Microsoft Windows 11 Pro"`, processador com geração identificável (`11th Gen Intel Core i3-1115G4`), memória `"8"` (GB, correto).
- **Conclusão: a integração de dados ao vivo GLPI → PHP → painel está validada e funcionando em produção**, em modo de acesso livre (sem login).
- Confirmação visual (2026-09-25): acessado via navegador real, painel exibindo o total de ativos no cabeçalho e o recorte da tabela com o filtro padrão, classificações de status/RAM aparecendo corretamente (ex.: `WS-EX01` com badge "STATUS OK" e alerta de upgrade de "RAM").

## DNS interno, acesso sem porta e certificado válido (2026-09-25)
- Criado registro A `painel.empresa.example.com` → `10.0.0.10` na zona interna do Samba-AD (mesma zona onde `glpi` já existia). No mesmo dia, renomeado para **`ativos.empresa.example.com`** (nome definitivo — ver decisão acima); o registro antigo `painel` foi removido.
- **Acesso sem porta**: o vhost inicial rodava numa porta separada (8443) para não mexer no vhost do GLPI (que já usa a 443). Para tirar a porta da URL sem tocar no `glpi.conf`, foi criado um **novo arquivo** de vhost (`/etc/nginx/conf.d/ativos.conf`), com `listen 443 ssl` e `server_name ativos.empresa.example.com` — o Nginx roteia por SNI/Host, então múltiplos sites dividem a porta 443 sem conflito. Reaproveita o certificado Let's Encrypt do GLPI (emitido só para `glpi...`). O vhost antigo da porta 8443 (`painel-ativos.conf`) foi removido depois de validado.
- **Certificado válido via Caddy (2026-09-25, tarde)** — problema: acessar `https://ativos...` dava `NET::ERR_CERT_COMMON_NAME_INVALID` (certificado do Nginx só cobre `glpi`). Solução, feita um passo por vez com validação:
  1. Registro A público `ativos` → `203.0.113.10` criado no registrador de domínios (necessário para o Let's Encrypt validar por HTTP-01; só o nome fica visível na internet). Publicação conferida direto nos servidores oficiais (`dig ... @<servidor-autoritativo>`) e pelo aumento do serial do SOA (`2026259000` → `2026268000`). Primeira tentativa não tinha sido salva no painel (ver nota do registrador de domínios acima).
  2. Bloco acrescentado no `/etc/caddy/Caddyfile` (após backup), validado com `caddy validate` ("Valid configuration"; avisos `Unnecessary header_up` são só estilo e aparecem também nos demais blocos) e ativado com `systemctl reload caddy` (não derruba conexões dos outros sites):
     ```
     ativos.empresa.example.com {
             @externo not remote_ip private_ranges
             respond @externo "Acesso negado" 403

             reverse_proxy https://10.0.0.10 {
                     transport http {
                             tls_insecure_skip_verify
                             tls_server_name ativos.empresa.example.com
                     }
                     header_up Host {host}
                     header_up X-Real-IP {remote_host}
                     header_up X-Forwarded-For {remote_host}
                     header_up X-Forwarded-Proto {scheme}
             }
     }
     ```
     O `tls_server_name` faz o Nginx do 10.0.0.10 escolher o vhost `ativos.conf` (e não o do GLPI). O desafio ACME é tratado antes do `respond 403`, então o bloqueio não atrapalha a emissão/renovação.
  3. Certificado Let's Encrypt emitido pelo Caddy em 2026-09-25 (`certificate obtained successfully`).
  4. Testes antes de trocar o DNS interno: `curl --resolve ativos...:443:10.0.0.20 https://ativos.../` no próprio Caddy → HTTP 200, verificação do certificado 0 (válido); pelo celular em 4G (fora da rede) → "Acesso negado" com cadeado normal.
  5. DNS interno trocado (`samba-tool dns update ... ativos A 10.0.0.10 10.0.0.20`) → `ativos` agora aponta para o Caddy (`10.0.0.20`, TTL 900 s). O vhost `ativos.conf` do Nginx permanece como backend.
  6. Validação final na estação da equipe de TI (`ipconfig /flushdns`, `nslookup` → `10.0.0.20`): painel abre em `https://ativos.empresa.example.com/` com cadeado normal, sem aviso de certificado.
- **Fluxo atual**: estação → DNS interno (`ativos` → 10.0.0.20) → Caddy (TLS válido, só IPs privados) → `https://10.0.0.10` (Nginx, vhost `ativos.conf`) → PHP-FPM → API do GLPI.
- **Manutenção**: o certificado renova sozinho, mas isso depende de o registro público `ativos` (→ 203.0.113.10) continuar existindo e das portas 80/443 do Caddy abertas para a internet — **não remover o registro público**. Se o Caddy cair, o painel fica fora do ar (agora depende dele para uso interno); o vhost do Nginx no 10.0.0.10 continua respondendo direto por IP/`--resolve` como contingência. Estações podem levar até 15 min (TTL) para enxergar a mudança de DNS; `ipconfig /flushdns` acelera.
- **A pendência anterior de certificado ("aviso Não seguro tolerado") está RESOLVIDA.**

## Próximos passos
1. Incluir os itemtypes `Monitor` e `Phone` em `glpi_client.php` (hoje só busca `Computer`).
2. Restringir o cliente de API do GLPI por IP (campo deixado em branco na criação) — usar o IP do próprio servidor do GLPI (`10.0.0.10`), já que o painel roda nele mesmo.
3. Ajustar `cache_ttl_seconds` se 15 minutos não for adequado.
4. **Por último** (decisão explícita da equipe de TI, não fazer antes de tudo o mais estar redondo): ativar `require_login = true` em `config.php` e preencher a lista `departments` com um login/senha real por departamento; depois disso, testar o fluxo de login/logout e a restrição de dados por departamento.
5. (Só se surgir necessidade de acesso externo ao painel) remover a restrição de IPs privados do bloco `ativos` no Caddy — **somente depois** do login ativo.
6. Usuário revisa o resultado final e apresenta para o gestor dele validar (sempre a solução já definida, não uma consulta sobre qual caminho seguir).
7. Avaliar as sugestões de melhoria no GLPI já levantadas na Fase 1 (ver histórico abaixo).

## Detalhes da Fase 1 / v5 (histórico, mantido como referência)

### ENTREGA v5 do protótipo (2026-09-16)
- Arquivo entregue à equipe de TI: `painel_ativos.html`, badge "Protótipo" no cabeçalho (a versão Fase 2 trocou esse badge para "Dados ao vivo do GLPI").
- v5 é a versão que serviu de base para a Fase 2 — v1 a v4 (entregues mais cedo no mesmo dia) estavam desatualizadas.
- Validado via Node.js contra o `glpi.csv` real: contagens de qualidade batem exatamente com o resultado de clicar em cada card (duplicado, grupoVazio, tipoIncomum, semResponsavel), independem do departamento selecionado, e a exclusividade de servidores/VMs para a TI continua íntegra (os demais departamentos excluem servidores).

### Redesenho da v5 — fusão dos cards/filtros/tabela de Status + Qualidade
Motivação: na v4, os cards de "Qualidade de dados (TI)" e sua tabela de detalhes ficavam separados, causando confusão de UX ao clicar num card e rolar para a tabela errada. Solução (mantida na Fase 2, sem alteração):
- Um único grid de cards (status + upgrade + qualidade, os de qualidade só visíveis com Departamento = TI).
- Uma única tabela, com coluna extra "Alertas de dados (TI)" (badges: Duplicado/Grupo vazio/Tipo incomum/Sem responsável), visível só para TI.
- Um único dropdown "Status", que ganha 4 opções de qualidade dinamicamente quando Departamento = TI.
- Cards/filtros de qualidade sempre avaliam a empresa inteira (`nonDeptScopedDevices()`), nunca só o departamento selecionado — confirmado pela equipe de TI ("A TI tem que ver tudo").

### Campo "Responsável" — "Nome alternativo da equipe de TI"
Fonte mais confiável que "Usuário" (atribuição manual). Implementado com fallback no `mapRecordToDevice()` desde a v5, e agora também no `glpi_client.php` da Fase 2 (mapeado a partir do campo `contact` do GLPI, que é onde o agente de inventário grava o última equipe de TI logado).

### Regra de classificação de hardware (status) — baseada só na CPU (inalterada na Fase 2)
- Intel Core por geração: 11ª+ → OK; 8ª–10ª → Atenção; abaixo da 8ª → Obsoleto.
- AMD Ryzen: série 5000+ → OK; série 2000–4000 → Atenção; série 1000 ou menos → Obsoleto.
- Pentium/Celeron: sempre Obsoleto. CPU não identificada: Atenção (revisão manual).
- Servidores/VMs (QEMU e afins): categoria própria "Servidor/VM", exclusiva da visão da TI.

### RAM e SSD (inalterado)
RAM < 15,5 GB e hostname na lista manual `SSD_EXPANSION_LIST` geram alerta de "Upgrade recomendado", só em ativos com status OK.

### Qualidade de dados (inalterado)
4 indicadores (Hostnames duplicados, Grupo/Setor vazio, Tipo incomum, Sem responsável), sempre avaliados na empresa inteira, visíveis só quando Departamento = TI.

### Problemas de qualidade de dados identificados no CSV original (para a TI corrigir no GLPI)
- Hostnames duplicados (alguns casos).
- Registros com o campo "Grupo" vazio.
- Um equipamento cadastrado como Tipo "Docking Station" mas com hardware de notebook.
- Cerca de um terço dos ativos sem responsável identificado.

### Sugestões de melhoria no próprio GLPI (dadas à equipe de TI na Fase 1)
1. Número de inventário/patrimônio estruturado (em vez de texto solto em "Comentários").
2. Campo/inventário automático de tipo de armazenamento (HDD/SSD).
3. Data de aquisição/garantia na aba financeira do GLPI.
4. Tornar campo "Grupo" obrigatório no cadastro.
5. Preencher manualmente "Usuário" quando o inventário automático não detectar.
6. Processo de auditoria periódica para hostnames duplicados.

