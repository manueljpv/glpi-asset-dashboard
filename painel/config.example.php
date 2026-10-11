<?php
/**
 * Configuração do painel integrado ao GLPI.
 *
 * COMO USAR:
 * 1. Copie este arquivo para "config.php" (mesma pasta).
 * 2. Preencha app_token e user_token com os valores gerados no GLPI
 *    (Configurar > Geral > API > Clientes de API, e Minhas configurações
 *    > Chaves de acesso remoto do usuário de serviço svc-painel-ativos).
 * 3. NUNCA suba o "config.php" preenchido para um repositório.
 */

return [
    // URL base da API REST do GLPI (sem barra no final).
    'glpi_url' => 'https://glpi.empresa.example.com/apirest.php',

    // Gerado em Configurar > Geral > API > Clientes de API > "Painel de Ativos".
    'app_token' => 'SEU_APP_TOKEN_AQUI',

    // Gerado no usuário de serviço svc-painel-ativos (Minhas configurações > API).
    'user_token' => 'SEU_USER_TOKEN_AQUI',

    // Por quanto tempo os dados buscados do GLPI ficam em cache local
    // (arquivo em cache_dir) antes de consultar a API de novo.
    'cache_ttl_seconds' => 900, // 15 minutos

    // Pasta onde o cache é gravado. Precisa ter permissão de escrita
    // para o usuário do servidor web (www-data, apache, etc.).
    'cache_dir' => __DIR__ . '/cache',
];
