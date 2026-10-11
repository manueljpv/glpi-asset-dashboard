# Painel de Controle de Ativos (GLPI) — Pacote de implantação

Painel web de consulta geral do parque de equipamentos (Computer, Monitor e Phone), lendo dados do GLPI 10.0.24 por uma camada PHP. Uso interno ou via VPN, **sem login**.

## Arquivos do pacote

| Arquivo | Função |
| --- | --- |
| `painel_ativos.html` | A página do painel (HTML, CSS e JS num arquivo só). Busca os dados em `api_ativos.php`. |
| `api_ativos.php` | Endpoint chamado pela página. Consulta o GLPI (com cache) e devolve JSON. Aceita `?debug=1`, `?debug=1&itemtype=Monitor` e `?nocache=1`. |
| `glpi_client.php` | Fala com a API REST do GLPI: abre sessão, descobre os IDs de campo por `uid`, busca Computer, Monitor e Phone e devolve os registros já no formato usado pela página. |
| `common.php` | Funções compartilhadas (carregar config, chamadas HTTP à API). |
| `config.example.php` | Modelo de configuração. Copie para `config.php` e preencha os tokens. |
| `cache/` | Pasta do cache dos dados. Precisa de escrita pelo usuário do PHP-FPM. |

## Implantação

1. Suba os arquivos para um diretório **separado** da instalação do GLPI (ex.: `/var/www/painel-ativos/`), com vhost próprio no Nginx. Não coloque dentro da pasta do GLPI e não edite o vhost do GLPI.
2. Copie `config.example.php` para `config.php` e preencha `app_token` (cliente de API "Painel de Ativos") e `user_token` (usuário de serviço de leitura). Os tokens ficam só no servidor. Não suba o `config.php` preenchido para repositório algum.
3. Dono e permissão (exemplo com Nginx + PHP-FPM como `apache`):

   ```bash
   chown -R apache:nginx /var/www/painel-ativos
   chmod 640 /var/www/painel-ativos/config.php
   chown apache:apache /var/www/painel-ativos/cache && chmod 770 /var/www/painel-ativos/cache
   ```

   Atenção: se um arquivo for copiado como root depois do `chown`, ele volta a ser `root:root`. Reaplique o `chown`/`chmod` após cada envio.
4. Confirme que o PHP tem `curl` (`php -m | grep curl`) e valide a sintaxe de cada arquivo PHP: `for f in config.php glpi_client.php api_ativos.php common.php; do php -l "$f"; done`.
5. Valide o Nginx com `nginx -t` e só então `systemctl reload nginx` (nunca `restart`).

## Conferindo os dados

- `api_ativos.php?debug=1` mostra, por itemtype, os campos encontrados e `campos_faltando`. O esperado é `campos_faltando: []` para Computer, Monitor e Phone.
- `api_ativos.php?nocache=1` ignora o cache e consulta o GLPI de novo.
- O GLPI responde HTTP 200 sem a chave `data` quando um itemtype não tem nenhum item (ex.: nenhum Phone cadastrado). O código trata isso como lista vazia.

## Regras de negócio resumidas

- **Computer** (notebook, desktop): status OK, Atenção ou Obsoleto pela geração/linha da CPU; alerta de upgrade de RAM (< 15,5 GB) e de SSD (lista manual) só para status OK.
- **Servidor/VM**: categoria própria, só na visão do departamento TI.
- **Monitor e Celular**: categoria "Periférico", sempre visíveis (independente do Status do GLPI), sem classificação de hardware.
- **Responsável**: remove tudo a partir do `@`; `nome.sobrenome` vira "Nome Sobrenome"; valor único fica como está; `ti`/`TIEMPRESA` viram `TI-EMPRESA`.
- **Agrupamento**: periférico com o mesmo Responsável de um Computer visível aparece como subitem abaixo dele.
- A correção de qualquer inconsistência de dados deve ser feita direto no GLPI.
