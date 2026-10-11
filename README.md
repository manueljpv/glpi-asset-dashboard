# glpi-asset-dashboard

**Português** · [English](README.en.md) · [Español (Honduras)](README.es-HN.md)

Painel web amigável para o controle de ativos de TI, construído sobre o [GLPI](https://glpi-project.org/), mais uma GPO que mantém o GLPI Agent instalado e o inventário sempre atualizado.

O GLPI guarda tudo, mas não é a ferramenta mais prática para um gestor de departamento que só quer saber "quais equipamentos do meu setor precisam de troca ou upgrade este ano?". Este projeto responde essa pergunta com uma página de consulta simples, alimentada ao vivo pelo próprio GLPI.

> **Aviso: dados fictícios.** Todos os nomes, domínios, IPs e hostnames deste repositório (`empresa.example.com`, `empresa.local`, `10.0.0.x`, `203.0.113.x`, `WS-EX01`…) são exemplos inventados. Nada aqui vem de um ambiente real. Veja a [seção final](#aviso-dados-fictícios).

## O problema

- Gestores precisam planejar orçamento de manutenção, upgrade e troca de equipamentos, mas a interface do GLPI é voltada para a equipe de TI.
- Exportar CSV do GLPI e montar planilhas à mão envelhece rápido e dá retrabalho.
- Um inventário só é confiável se os agentes estiverem instalados e reportando em dia. Uma instalação mal feita por GPO (por exemplo, reinstalando a cada boot) gera inventário duplicado e dados velhos.

## O que o projeto entrega

**1. Painel de ativos (`painel/`)**

- Página única (HTML, CSS e JS, sem dependências externas) que consulta o GLPI por uma camada PHP. Os tokens da API ficam só no servidor, nunca no navegador.
- Cobre os itemtypes **Computer**, **Monitor** e **Phone**.
- Classifica cada endpoint pela CPU: **OK**, **Atenção** ou **Obsoleto**.
- Gera alertas de **upgrade de RAM** e de **SSD**.
- Tem categoria própria para **servidores/VMs** e para **periféricos** (sem classificação de hardware).
- Traz **indicadores de qualidade de dados** para a TI: hostnames duplicados, grupo/setor vazio, tipo incomum e equipamento sem responsável.
- Oferece busca livre, filtros por departamento, tipo, status e upgrade, cards clicáveis e ordenação por coluna.
- Agrupa o monitor ou celular sob o computador do mesmo responsável.

**2. Automação do GLPI Agent por GPO (`gpo/`)**

- Instala ou atualiza o agente **sem downgrade** e sem reinstalar quando a versão já está em dia.
- Garante que o serviço esteja ativo e corrige o valor `server` no registro.
- Cria uma tarefa agendada local que **força o inventário** no boot e no logon, com intervalo mínimo de 2 horas.
- Ativa o ícone de bandeja do agente (veja a [documentação da GPO](docs/gpo-glpi-agent.md) para o porquê de isso exigir cuidado).

## Capturas de tela

> Dados fictícios: hostnames, nomes e domínios são inventados.

![Visão geral com os cards de status e os indicadores de qualidade de dados](docs/img/01-visao-geral.png)

![Tabela de equipamentos, com status e upgrade recomendado](docs/img/02-tabela.png)

![Filtro por status: equipamentos obsoletos de todos os departamentos](docs/img/03-obsoletos.png)

## Arquitetura em alto nível

```
Navegador ──► Proxy reverso (TLS) ──► Nginx ──► PHP-FPM ──► API REST do GLPI
                                         │          │
                                         │          └─ api_ativos.php + glpi_client.php
                                         │             (tokens ficam aqui, com cache em arquivo)
                                         └─ painel_ativos.html (estático)

Estações Windows ──► GPO (Inicialização) ──► Install-GLPIAgent.ps1
                                              └─ tarefa agendada ──► Invoke-GLPIInventory.ps1
                                                                      └─ http://127.0.0.1:62354/now ──► agente ──► GLPI
```

O proxy reverso é opcional: serve para ter um certificado válido e para restringir o acesso a redes privadas. A decisão de projeto foi manter o painel **sem login**, apenas para uso interno ou via VPN. Detalhes em [`docs/painel-documentacao.md`](docs/painel-documentacao.md).

## Pré-requisitos

**Painel**

- GLPI 10.x com a **API REST** habilitada.
- Um **cliente de API** no GLPI (gera o `App-Token`) e um **usuário de serviço somente leitura** (gera o `User-Token`).
- Servidor web com **PHP** (com a extensão `curl`) e HTTPS. Os exemplos usam Nginx + PHP-FPM.
- Acesso de rede do servidor do painel à API do GLPI.

**GPO do agente**

- Active Directory com GPO de Inicialização (Configuração do Computador).
- Um compartilhamento de rede legível pelas estações (os exemplos usam `NETLOGON`).
- O instalador MSI do [GLPI Agent](https://github.com/glpi-project/glpi-agent/releases) (este repositório **não** inclui o `.msi`).

## Implantação

### 1. Painel

1. Crie um diretório **separado** da instalação do GLPI, por exemplo `/var/www/painel-ativos/`, e copie o conteúdo de `painel/` para lá. Não coloque o painel dentro da pasta do GLPI e não edite o vhost do GLPI.
2. Copie `config.example.php` para `config.php` e preencha `glpi_url`, `app_token` e `user_token`. **Nunca versione o `config.php` preenchido.**
3. Ajuste dono e permissões (exemplo com Nginx e PHP-FPM rodando como `apache`):

   ```bash
   chown -R apache:nginx /var/www/painel-ativos
   chmod 640 /var/www/painel-ativos/config.php
   chown apache:apache /var/www/painel-ativos/cache && chmod 770 /var/www/painel-ativos/cache
   ```

   Se você copiar um arquivo como root depois do `chown`, ele volta a ser `root:root`. Reaplique o `chown`/`chmod` após cada envio.
4. Valide a sintaxe do PHP: `for f in config.php glpi_client.php api_ativos.php common.php; do php -l "$f"; done`.
5. Crie um vhost próprio, num arquivo novo (por exemplo `/etc/nginx/conf.d/ativos.conf`). Este é o vhost usado no projeto, anonimizado; ele compartilha a porta 443 com o GLPI e reaproveita o certificado Let's Encrypt (ajuste os caminhos ao seu certbot ou ao seu certificado):

   ```nginx
   server {
       listen 443 ssl;
       server_name ativos.empresa.example.com;

       root /var/www/painel-ativos;
       index painel_ativos.html;

       ssl_certificate     /etc/letsencrypt/live/glpi.empresa.example.com/fullchain.pem;
       ssl_certificate_key /etc/letsencrypt/live/glpi.empresa.example.com/privkey.pem;
       include /etc/letsencrypt/options-ssl-nginx.conf;
       ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

       # Nunca servir a configuração nem o código interno, nem o cache.
       location ~* /(config\.example\.php|config\.php|common\.php|glpi_client\.php)$ {
           deny all;
           return 404;
       }
       location ~ ^/cache/ {
           deny all;
           return 404;
       }

       location ~ \.php$ {
           fastcgi_pass unix:/run/php-fpm/www.sock;
           fastcgi_split_path_info ^(.+\.php)(/.+)$;
           try_files $fastcgi_script_name =404;
           set $path_info $fastcgi_path_info;
           fastcgi_param PATH_INFO $path_info;
           fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
           include fastcgi_params;
           fastcgi_index index.php;
       }

       location / {
           try_files $uri $uri/ =404;
       }
   }
   ```

   O Nginx escolhe o vhost pelo nome (`server_name`), então vários sites dividem a porta 443 sem conflito e **sem editar** o vhost do GLPI. O caminho do socket (`/run/php-fpm/www.sock`) varia conforme a distribuição.

6. Rode `nginx -t` e só então `systemctl reload nginx` (evite `restart`).
7. Edite a lista `SSD_EXPANSION_LIST` em `painel_ativos.html` com os hostnames que fazem sentido no seu ambiente.

### 2. GPO do agente

1. Coloque no compartilhamento de rede (por exemplo `\\empresa.local\netlogon\scripts\GLPI\`): o MSI do agente, `Install-GLPIAgent.ps1`, `Invoke-GLPIInventory.ps1` e `install-glpi.bat`.
2. Em `Install-GLPIAgent.ps1`, ajuste no bloco de parâmetros: `$TargetVersion`, `$SetupLocation` e `$GlpiServerUrl`. O nome do MSI deve bater com `GLPI-Agent-<versão>-x64.msi`.
3. Crie uma GPO com um **Script de Inicialização** (Configuração do Computador) apontando para o `install-glpi.bat`, e vincule-a às OUs de computadores.
4. No GLPI, reduza o intervalo de inventário do servidor (o projeto usou 12 h) como rede de segurança caso o script local falhe.
5. Os scripts rodam como `SYSTEM` e gravam log em `C:\ProgramData\GLPI-Agent-Deploy\install-glpi-agent.log`.

## Como validar

**Painel**

- Abra `api_ativos.php?debug=1`. O esperado é `campos_faltando: []` para Computer, Monitor e Phone.
- Use `api_ativos.php?nocache=1` para ignorar o cache e consultar o GLPI de novo.
- Abra o painel no navegador e confira o total de ativos no cabeçalho e uma amostra de registros contra o GLPI.

**GPO**

- Confira o log em `C:\ProgramData\GLPI-Agent-Deploy\install-glpi-agent.log` numa estação.
- `Get-ScheduledTask -TaskName 'GLPI-Agent - Forcar Inventario'` deve mostrar a tarefa criada; `LastTaskResult` igual a `0` indica sucesso.
- A versão instalada fica em `HKLM:\SOFTWARE\GLPI-Agent\Installer` (`Version`).
- Para forçar um inventário manualmente, acesse `http://127.0.0.1:62354/now` na própria estação.

## Problemas comuns

| Sintoma | Causa provável | O que fazer |
| --- | --- | --- |
| HTTP 500 ao abrir a API | O PHP-FPM não consegue ler o `config.php` (arquivo copiado como root) | `chown apache:nginx config.php && chmod 640 config.php` |
| Erro de sintaxe no `config.php` | Tokens colados sem aspas simples | Coloque aspas ao redor de cada token e rode `php -l config.php` |
| `campos_faltando` não vazio | O GLPI usa uids compostos (`Computer.<Tipo>.<campo>`) que variam entre instalações | Abra `?debug=1&itemtype=Computer`, localize o uid real e ajuste `candidatos_de_campo()` em `glpi_client.php` |
| Nenhum ativo aparece como "precisa de RAM" | O GLPI guarda a memória em **MB** e a regra espera GB | Já tratado em `glpi_client.php` (divisão por 1024); se mexer ali, valide com `?nocache=1` |
| Dados desatualizados | Cache de 15 minutos | Use o botão "Atualizar dados" ou `?nocache=1` |
| Aviso de certificado | O certificado cobre outro nome que o do vhost | Emita certificado para o nome do painel (por exemplo via proxy reverso) |
| Testes com `curl` no próprio servidor do GLPI não resolvem o nome do painel | O servidor usa DNS público, sem os registros internos | Use `curl --resolve <nome>:443:<ip>` |
| Ícone de bandeja do agente "sumiu" logo após instalar | O autostart só dispara numa **sessão nova** | Faça logoff/logon antes de investigar |
| `msiexec` com erro 1625 depois de um reinício | Condição transitória do Windows Installer | Reinicie de novo antes de investigar mais |
| Não consegue sobrescrever os scripts no compartilhamento | Só administradores do servidor de arquivos têm escrita | Use uma conta com direito de administrador nesse servidor |

## Segurança

- O painel **não tem autenticação** (decisão de projeto). Exponha-o somente em rede interna ou VPN e/ou restrinja por IP no proxy.
- O endpoint `api_ativos.php?debug=1` mostra a estrutura de campos do GLPI e também não é autenticado. Restrinja o acesso ou remova-o em produção.
- Mantenha `config.php` e `cache/` fora do alcance do navegador (veja o vhost de exemplo) e **nunca** os versione.
- Use um usuário de serviço **somente leitura** e, se possível, restrinja o cliente de API por IP.

## Documentação e roadmap

- [`docs/painel-documentacao.md`](docs/painel-documentacao.md): arquitetura, regras de negócio e como atualizar o painel.
- [`docs/gpo-glpi-agent.md`](docs/gpo-glpi-agent.md): diagnóstico, desenho e testes da GPO.
- [`docs/historico-painel.md`](docs/historico-painel.md): histórico de decisões e bugs encontrados na implantação.
- [`ROADMAP.md`](ROADMAP.md): melhorias futuras.

A pasta `docs/` está disponível apenas em português.

## Aviso: dados fictícios

Este repositório foi derivado de um projeto real de infraestrutura e **passou por anonimização antes da publicação**. Todos os nomes de empresa, domínios, endereços IP, hostnames, contas e pessoas que aparecem aqui são **fictícios** e servem apenas de exemplo:

- Domínios: `empresa.example.com` (público) e `empresa.local` (interno).
- Redes: `10.0.0.x` (interna) e `203.0.113.x` (faixa reservada para documentação).
- Máquinas: `WS-EX01`, `srv-ad01`, `srv-proxy01` etc.

Os valores de `config.example.php` são apenas marcadores. Substitua tudo pelo seu ambiente.

## Licença

[GNU GPL v3.0](LICENSE).

Mantido por [@manueljpv](https://github.com/manueljpv).
