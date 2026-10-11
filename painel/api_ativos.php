<?php
/**
 * Endpoint consumido pelo painel_ativos.html. Faz o papel de "camada
 * intermediária": guarda os tokens da API do GLPI só aqui no servidor
 * (nunca no navegador) e devolve os dados já prontos para o front-end.
 *
 * Acesso: de consulta geral, sem login (decisão da gestão —
 * o painel é só para uso interno/VPN, então o login por departamento foi
 * cancelado e o código correspondente foi removido do pacote).
 *
 * GET api_ativos.php                          -> todos os ativos (Computer + Monitor + Phone)
 * GET api_ativos.php?debug=1                  -> resumo de diagnóstico de campos dos 3 itemtypes
 * GET api_ativos.php?debug=1&itemtype=Monitor -> diagnóstico completo (com dump de uids) de um só itemtype
 * GET api_ativos.php?nocache=1                -> força ignorar o cache
 */

header('Content-Type: application/json; charset=utf-8');

require_once __DIR__ . '/common.php';
require_once __DIR__ . '/glpi_client.php';

$cfg = glpi_config();

$itemtypesValidos = itemtypes_suportados();
$itemtypeParam = isset($_GET['itemtype']) && in_array($_GET['itemtype'], $itemtypesValidos, true)
    ? $_GET['itemtype']
    : null;

$debug = isset($_GET['debug']);
$forceRefresh = isset($_GET['nocache']);

try {
    if ($debug) {
        echo json_encode(buscar_ativos_glpi(true, $itemtypeParam), JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);
        exit;
    }

    $cacheFile = rtrim($cfg['cache_dir'], '/') . '/ativos.json';
    $registros = null;

    if (!$forceRefresh && is_file($cacheFile) && (time() - filemtime($cacheFile)) < (int)$cfg['cache_ttl_seconds']) {
        $registros = json_decode(file_get_contents($cacheFile), true);
    }

    if ($registros === null) {
        $registros = buscar_ativos_glpi(false);
        if (!is_dir($cfg['cache_dir'])) {
            mkdir($cfg['cache_dir'], 0775, true);
        }
        file_put_contents($cacheFile, json_encode($registros));
    }
} catch (Throwable $e) {
    http_response_code(502);
    echo json_encode(['error' => 'Falha ao consultar o GLPI: ' . $e->getMessage()]);
    exit;
}

echo json_encode([
    'meta' => [
        'isTI' => true,
        'departamento' => 'TI',
        'geradoEm' => date('c'),
    ],
    'registros' => $registros,
], JSON_UNESCAPED_UNICODE);
