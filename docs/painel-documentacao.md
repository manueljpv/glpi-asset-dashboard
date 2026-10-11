# Painel de Controle de Ativos (GLPI) — Documentação da atividade

## Objetivo e escopo

O painel é uma página web de consulta geral do parque de equipamentos da Empresa Exemplo, lendo dados ao vivo do GLPI 10.0.24 por uma camada PHP intermediária, para uso interno ou via VPN.

O escopo mudou durante esta etapa, a pedido da gestão:

- O login por departamento foi cancelado. O acesso é de consulta geral, sem autenticação.
- A restrição do cliente da API por IP foi descartada, já que não há mais login.
- Monitor e Celular entraram no painel, além de Computer.
- O aviso de certificado SSL já foi resolvido com o Caddy (ver Arquitetura e infraestrutura).
- A página de consulta passa por ajustes de apresentação, listados mais abaixo.

## Arquitetura e infraestrutura

O painel roda no mesmo servidor do GLPI (Rocky Linux 9.8, `10.0.0.10`), em diretório separado (`/var/www/painel-ativos/`) e com vhost Nginx próprio, sem nunca editar o vhost ou o serviço do GLPI em produção. O acesso interno é por `https://ativos.empresa.example.com/`, na porta 443, com certificado válido.

O caminho de uma consulta, da estação até o GLPI:

1. A estação (na rede interna ou via VPN, que cai na mesma rede) resolve `ativos` no DNS interno Samba-AD (`10.0.0.5`) e recebe `10.0.0.20`.
2. O Caddy (`srv-proxy01`, `10.0.0.20`) termina o TLS com certificado Let's Encrypt válido e só atende IPs privados; quem vem da internet recebe 403 "Acesso negado".
3. O Caddy repassa para `https://10.0.0.10`, onde o Nginx escolhe o vhost `ativos.conf` por SNI/Host, compartilhando a porta 443 com o GLPI.
4. O PHP-FPM (usuário `apache`) executa `api_ativos.php`, que guarda os tokens da API no servidor e nunca no navegador.
5. `glpi_client.php` abre sessão na API REST do GLPI (`/apirest.php`), busca Computer, Monitor e Phone, e devolve JSON já no formato esperado pela página.

Pontos de atenção de operação:

- O certificado renova sozinho, mas depende do registro público `ativos` (para `203.0.113.10`) continuar existindo e das portas 80/443 do Caddy abertas. Não remover esse registro.
- Se o Caddy cair, o painel sai do ar para uso interno. O vhost do Nginx continua respondendo direto por IP como contingência.
- O servidor do GLPI usa `8.8.8.8` como DNS e não resolve `ativos`. Testes feitos nele pedem `curl --resolve ativos.empresa.example.com:443:10.0.0.10`.
- O cache da camada PHP guarda a resposta por `cache_ttl_seconds` (padrão de 15 minutos); `?nocache=1` força nova consulta.

## Dados e regras de negócio

A API devolve os ativos dos três tipos (Computer, Monitor e Phone); no ambiente de origem ainda não havia Phone cadastrado. Cada registro carrega o campo `ItemType`, que o painel usa para decidir a categoria, sem depender do campo "Tipo" do GLPI (vazio nos 50 monitores).

| Itemtype | Categoria no painel | Status exibido | Classificação de CPU/RAM |
| --- | --- | --- | --- |
| Computer (notebook, desktop) | Endpoint | OK, Atenção ou Obsoleto | Sim |
| Computer (servidor, VM) | Servidor | SERVIDOR / VM, só na visão da TI | Não |
| Monitor | Periférico | PERIFÉRICO | Não |
| Phone (celular) | Periférico | PERIFÉRICO | Não |

Regras aplicadas nesta etapa:

- **Periféricos sempre visíveis.** Monitor e Celular aparecem por padrão mesmo com o Status do GLPI vazio. A regra de esconder tudo que não está com Status "Ativo" continua valendo só para Computer; o checkbox "Mostrar inativos/descartados" não afeta mais os periféricos.
- **Card Periféricos.** Segue o mesmo padrão do card Servidor/VM: filtra pelo card, sem opção no dropdown de Status.
- **Filtro por tipo.** Monitor e Celular filtram pelo `ItemType`, não pelo texto do campo Tipo.
- **Responsável normalizado.** Remove tudo a partir do `@`. Dois nomes separados por ponto viram "Nome Sobrenome" (`maria.silva@EMPRESA` vira Maria Silva). Valor único fica como está (`Joao`). `ti` e `TIEMPRESA`, com ou sem `@...`, viram `TI-EMPRESA`.
- **Periféricos agrupados.** Um Monitor ou Celular com o mesmo Responsável de um Computer visível no recorte aparece como subitem logo abaixo dele (marcado com ↪). Sem Computer correspondente, aparece como linha solta.
- **Qualidade de dados (TI).** "Tipo incomum" avalia só endpoints; Monitor e Celular ficam de fora. Os cards de qualidade continuam avaliando a empresa inteira.

A classificação de hardware dos endpoints não mudou: Intel Core 11ª geração ou mais é OK, 8ª a 10ª é Atenção, abaixo da 8ª é Obsoleto; Ryzen série 5000 ou mais é OK, 2000 a 4000 é Atenção; Pentium e Celeron são sempre Obsoleto. RAM abaixo de 15,5 GB e hostname na lista de expansão de SSD geram alerta de upgrade, só em status OK.

## Ajustes de interface desta etapa

Todos os ajustes abaixo estão no `painel_ativos.html` e já foram implantados no servidor. O cabeçalho de três linhas e a ordem das colunas foram validados visualmente; o novo layout do cabeçalho (bloco "Fonte" à direita) e o botão Limpar filtros foram implantados e conferidos por \`grep\`, e aguardam a conferência visual.

| Área | Antes | Depois |
| --- | --- | --- |
| Cabeçalho | Selo "Dados ao vivo do GLPI" e título "Painel de Controle de Ativos - EMPRESA" | Título "Painel de Controle de Ativos", sem selo, e descrição em três linhas (parque de equipamentos, classificação sugerida pela TI, apoio ao planejamento orçamentário) |
| Origem dos dados | Linha "Fonte: API do GLPI" sob a descrição | Bloco à direita, acima do botão Atualizar dados: "Fonte: glpi.empresa.example.com" e "Equipamentos: N ativos · atualizado em data e hora" |
| Filtros | Tudo numa linha só | Busca livre sozinha numa linha; Departamento, Tipo, Status, Necessita upgrade e o checkbox de inativos na linha abaixo |
| Limpar filtros | Link de texto solto ao lado da busca | Botão com borda e ícone, no fim da linha de filtros, onde ele realmente atua |
| Status (dropdown) | Incluía a opção PERIFÉRICO | Opção removida; Periféricos só pelo card |
| Colunas da tabela | Nome, Equipamento, Departamento, Tipo, Responsável, Processador... | Departamento, Responsável, Tipo, Equipamento, Nome, e o restante na mesma ordem (Processador, RAM, Status, Upgrade recomendado, Alertas TI, Observações) |
| Login | Nome do departamento e botão Sair no cabeçalho | Removidos; consulta geral sem login |

## Como implantar e atualizar

O ambiente de desenvolvimento não alcança a rede interna, então toda atualização é feita pela TI, um passo por vez, conferindo cada resultado antes do próximo.

1. Baixar o arquivo atualizado e enviá-lo ao servidor por SCP/SFTP (WinSCP, FileZilla ou `scp`), sobrescrevendo o arquivo em `/var/www/painel-ativos/`.
2. Reaplicar dono e permissão, porque o envio como root pode deixar o arquivo como `root:root`:

```bash
chown apache:nginx /var/www/painel-ativos/painel_ativos.html
chmod 644 /var/www/painel-ativos/painel_ativos.html
```

3. Conferir que o arquivo novo realmente chegou, com um `grep` por um trecho exclusivo da versão nova (e o tamanho em bytes com `ls -la`):

```bash
grep -n "Equipamentos:\|Limpar filtros" /var/www/painel-ativos/painel_ativos.html
```

4. Para arquivos PHP, validar a sintaxe com `php -l` antes de testar. Para o Nginx, rodar `nginx -t` antes de qualquer `systemctl reload nginx` (nunca `restart`).
5. Abrir o painel no navegador e conferir a tela.

Duas armadilhas já vistas nesta etapa: o cliente de SCP pode não sobrescrever o arquivo sem avisar, e reenviar uma cópia antiga do computador local instala uma versão desatualizada. O `grep` e o tamanho do arquivo pegam os dois casos.

## Pendências e próximos passos

- **Status vazio em Monitor e Celular no GLPI.** Os monitores não têm Status nem Tipo preenchidos. O painel já os exibe sem depender disso, e a TI vai investigar e corrigir os dados direto no GLPI.
- **Conferência visual do novo cabeçalho e do botão Limpar filtros.** Falta abrir o painel e validar a tela.
- **Novos ajustes de apresentação.** A gestão vai apontando mais itens da página de consulta conforme avalia o resultado.
- **Celulares.** Nenhum Phone está cadastrado no GLPI ainda; o código já trata a lista vazia sem erro.
- **Login por departamento.** Foi cancelado; o código correspondente foi removido do pacote publicado.
- **Restrição de IP do Caddy.** O bloco `ativos` só atende IPs privados. Se o painel precisar de acesso pela internet um dia, essa restrição só deve sair com algum controle de acesso no lugar.
- **Sugestões de melhoria no GLPI** (número de patrimônio estruturado, tipo de armazenamento, data de aquisição e garantia, Grupo obrigatório, auditoria de hostnames duplicados) seguem como recomendação.

## Arquivos do pacote

O pacote `painel-ativos-fase2.zip` reúne todos os arquivos abaixo, já na versão implantada. O `README_IMPLANTACAO.md` do zip foi reescrito para o estado atual (sem login, com Monitor e Phone).

| Arquivo | Função | Mudou nesta etapa |
| --- | --- | --- |
| `painel_ativos.html` | Página do painel (HTML, CSS e JS) | Sim: periféricos, cabeçalho, filtros, colunas, Responsável, agrupamento |
| `api_ativos.php` | Endpoint JSON com cache; diagnóstico em `?debug=1` | Sim: login removido, três itemtypes, cache `ativos.json` |
| `glpi_client.php` | Cliente da API REST do GLPI | Sim: Monitor e Phone, campo `ItemType`, lista vazia tratada |
| `common.php` | Config e chamadas HTTP | Não |
| `config.example.php` | Modelo do `config.php` (tokens por preencher) | Não |
| `README_IMPLANTACAO.md` | Passo a passo de implantação | Sim: reescrito |
| `cache/` | Pasta do cache, gravável pelo PHP-FPM | Não |

O pacote não inclui o `config.php` real, então não carrega tokens da API.
