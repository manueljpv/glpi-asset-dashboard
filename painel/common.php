<?php
/**
 * Funções compartilhadas: config, chamadas à API do GLPI e a mesma regra
 * de separação de Departamento a partir do campo "Grupo" que já existia
 * no JavaScript do painel (mantida idêntica, agora também em PHP porque
 * o filtro por departamento de quem NÃO é da TI precisa ser aplicado
 * aqui no servidor, não só no navegador).
 */

function glpi_config() {
    static $cfg = null;
    if ($cfg === null) {
        $path = __DIR__ . '/config.php';
        if (!file_exists($path)) {
            http_response_code(500);
            header('Content-Type: application/json; charset=utf-8');
            die(json_encode(['error' => 'config.php não encontrado. Copie config.example.php para config.php e preencha os tokens.']));
        }
        $cfg = require $path;
    }
    return $cfg;
}

/**
 * Faz uma requisição à API REST do GLPI.
 * $opts pode conter: 'query' (array), 'session_token', 'auth_user_token' (bool),
 * 'body' (array, vira JSON).
 */
function glpi_api_request($method, $path, array $opts = []) {
    $cfg = glpi_config();
    $url = rtrim($cfg['glpi_url'], '/') . '/' . ltrim($path, '/');
    if (!empty($opts['query'])) {
        $url .= '?' . http_build_query($opts['query']);
    }

    $headers = ['App-Token: ' . $cfg['app_token']];
    if (!empty($opts['session_token'])) {
        $headers[] = 'Session-Token: ' . $opts['session_token'];
    }
    if (!empty($opts['auth_user_token'])) {
        $headers[] = 'Authorization: user_token ' . $cfg['user_token'];
    }
    if (isset($opts['body'])) {
        $headers[] = 'Content-Type: application/json';
    }

    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CUSTOMREQUEST => $method,
        CURLOPT_HTTPHEADER => $headers,
        CURLOPT_TIMEOUT => 25,
        CURLOPT_SSL_VERIFYPEER => true,
    ]);
    if (isset($opts['body'])) {
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($opts['body']));
    }

    $raw = curl_exec($ch);
    if ($raw === false) {
        $err = curl_error($ch);
        curl_close($ch);
        throw new RuntimeException("Falha ao conectar na API do GLPI ($path): $err");
    }
    $status = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    return ['status' => $status, 'data' => json_decode($raw, true), 'raw' => $raw];
}

function glpi_init_session() {
    $res = glpi_api_request('GET', 'initSession', ['auth_user_token' => true]);
    if ($res['status'] !== 200 || empty($res['data']['session_token'])) {
        throw new RuntimeException('Não foi possível iniciar sessão na API do GLPI (confira app_token/user_token em config.php). Resposta: ' . $res['raw']);
    }
    return $res['data']['session_token'];
}

function glpi_kill_session($session_token) {
    try {
        glpi_api_request('GET', 'killSession', ['session_token' => $session_token]);
    } catch (Throwable $e) {
        // Não é crítico se a sessão não puder ser encerrada explicitamente
        // (ela expira sozinha no GLPI depois de um tempo).
    }
}

/** Mesma lógica de splitDepartamento() do JavaScript do painel. */
function split_departamento($grupoRaw) {
    $g = trim((string)$grupoRaw);
    if ($g === '') return ['departamento' => 'Não informado', 'subgrupo' => ''];
    $parts = array_values(array_filter(
        array_map('trim', explode('>', $g)),
        function ($p) { return $p !== ''; }
    ));
    if (count($parts) <= 1) return ['departamento' => 'Não informado', 'subgrupo' => ''];
    return ['departamento' => $parts[1], 'subgrupo' => implode(' > ', array_slice($parts, 2))];
}

/** Mesma lista SERVER_TYPES do JavaScript, para excluir servidores/VMs
 *  de quem não é da TI já no servidor (defesa em profundidade). */
function is_tipo_servidor($tipoRaw) {
    $servidores = ["QEMU", "VM", "VIRTUAL MACHINE", "SERVIDOR", "SERVER"];
    return in_array(strtoupper(trim((string)$tipoRaw)), $servidores, true);
}
