<?php
/**
 * Busca os ativos dos tipos "Computer", "Monitor" e "Phone" (celular) direto
 * da API REST do GLPI e devolve registros no MESMO formato de colunas que o
 * glpi.csv usado até agora (Nome, Entidade, Status, Fabricante, Tipo, Modelo,
 * Grupo, Usuário, "Nome alternativo do usuário", Comentários,
 * "Sistema operacional - Nome", "Componentes - Processador",
 * "Componentes - Memória", "Última atualização"), mais uma coluna extra
 * "ItemType" (Computer/Monitor/Phone) para o front-end saber que Monitor e
 * Celular não têm CPU/RAM/SO e não devem entrar na classificação de
 * hardware (eles usam a categoria própria "Periférico").
 *
 * Monitor e Phone não têm os campos de CPU/RAM/SO — essas 3 colunas ficam
 * vazias para eles, sem problema, porque o front-end os trata à parte.
 *
 * IMPORTANTE — os uids de campo do Computer já foram validados contra o
 * GLPI real em 2026-09-24. Os de Monitor/Phone (adicionados em
 * 2026-09-26) seguem o MESMO padrão observado no Computer
 * ("<Itemtype>.<Tipo>.<campo>"), como primeira tentativa, mas ainda não
 * foram confirmados. Use api_ativos.php?debug=1&itemtype=Monitor (ou
 * &itemtype=Phone) para conferir "campos_faltando" antes de confiar nos
 * dados desses dois tipos.
 */

require_once __DIR__ . '/common.php';

/** itemtypes buscados, na ordem em que aparecem no resultado combinado. */
function itemtypes_suportados() {
    return ['Computer', 'Monitor', 'Phone'];
}

/**
 * uids candidatos para os campos comuns a qualquer itemtype (tudo, exceto
 * SO/CPU/RAM, que só existem em Computer). Segue o padrão
 * "<Itemtype>.<Tipo>.<campo>" confirmado para Computer.
 */
function candidatos_comuns($itemtype) {
    return [
        'nome'        => [$itemtype . '.name'],
        'entidade'    => [$itemtype . '.Entity.completename', 'Entity.completename', 'Entity.name'],
        'status'      => [$itemtype . '.State.completename', 'State.completename', 'State.name'],
        'fabricante'  => [$itemtype . '.Manufacturer.name', 'Manufacturer.name'],
        'tipo'        => [$itemtype . '.' . $itemtype . 'Type.name', $itemtype . 'Type.name'],
        'modelo'      => [$itemtype . '.' . $itemtype . 'Model.name', $itemtype . 'Model.name'],
        'grupo'       => [$itemtype . '.Group.completename', 'Group.completename'],
        'usuario'     => [$itemtype . '.User.name', 'User.name'],
        'contato'     => [$itemtype . '.contact'],
        'comentarios' => [$itemtype . '.comment'],
        'data_mod'    => [$itemtype . '.date_mod'],
    ];
}

/** uids candidatos por itemtype (Computer tem os 3 campos extras de hardware). */
function candidatos_de_campo($itemtype) {
    $comuns = candidatos_comuns($itemtype);

    if ($itemtype === 'Computer') {
        // Confirmados contra o GLPI real em 2026-09-24 (via
        // api_ativos.php?debug=1&itemtype=Computer).
        return $comuns + [
            'so'          => ['Computer.Item_OperatingSystem.OperatingSystem.name', 'OperatingSystem.name'],
            'processador' => ['Computer.Item_DeviceProcessor.DeviceProcessor.designation', 'DeviceProcessor.designation', 'Item_DeviceProcessor.designation'],
            'memoria'     => ['Computer.Item_DeviceMemory.size', 'Item_DeviceMemory.size', 'DeviceMemory.size'],
        ];
    }

    return $comuns;
}

/**
 * Resolve os IDs de campo (via listSearchOptions/<itemtype>) e, se $debug
 * for true, retorna o relatório de diagnóstico em vez de buscar os dados.
 */
function resolver_campos_glpi($session_token, $itemtype, $debug = false) {
    $opts = glpi_api_request('GET', 'listSearchOptions/' . $itemtype, ['session_token' => $session_token]);
    if ($opts['status'] !== 200 || !is_array($opts['data'])) {
        throw new RuntimeException("Não foi possível obter listSearchOptions/$itemtype. Resposta: " . $opts['raw']);
    }

    $candidatos = candidatos_de_campo($itemtype);
    $fieldIds = [];
    $encontrados = [];

    foreach ($opts['data'] as $id => $info) {
        if (!is_array($info) || !isset($info['uid'])) continue;
        foreach ($candidatos as $chave => $uids) {
            if (isset($fieldIds[$chave])) continue;
            if (in_array($info['uid'], $uids, true)) {
                $fieldIds[$chave] = (int)$id;
                $encontrados[$chave] = ['id' => (int)$id, 'uid' => $info['uid'], 'nome_exibido' => $info['name'] ?? null];
            }
        }
    }

    $faltando = array_values(array_diff(array_keys($candidatos), array_keys($fieldIds)));

    if ($debug) {
        // Lista compacta (só id/uid/nome) de TODAS as opções disponíveis,
        // para procurarmos manualmente o uid certo dos campos que não
        // bateram com nenhum candidato conhecido.
        $todas = [];
        foreach ($opts['data'] as $id => $info) {
            if (!is_array($info) || !isset($info['uid'])) continue;
            $todas[] = [
                'id' => (int)$id,
                'uid' => $info['uid'],
                'nome_exibido' => $info['name'] ?? null,
            ];
        }

        return [
            '_debug' => true,
            'itemtype' => $itemtype,
            'campos_encontrados' => $encontrados,
            'campos_faltando' => $faltando,
            'total_opcoes_disponiveis' => count($opts['data']),
            'todas_as_opcoes_compacto' => $todas,
        ];
    }

    if (!empty($faltando)) {
        throw new RuntimeException(
            "Campos não localizados em listSearchOptions/$itemtype: " . implode(', ', $faltando) .
            ". Acesse api_ativos.php?debug=1&itemtype=$itemtype para investigar os uids disponíveis."
        );
    }

    return $fieldIds;
}

/** Resumo (sem o dump gigante) do diagnóstico de campos para TODOS os itemtypes suportados. */
function resumo_diagnostico_todos_itemtypes($session_token) {
    $resumo = [];
    foreach (itemtypes_suportados() as $itemtype) {
        try {
            $r = resolver_campos_glpi($session_token, $itemtype, true);
            $resumo[$itemtype] = [
                'campos_encontrados' => array_keys($r['campos_encontrados']),
                'campos_faltando' => $r['campos_faltando'],
                'total_opcoes_disponiveis' => $r['total_opcoes_disponiveis'],
            ];
        } catch (Throwable $e) {
            $resumo[$itemtype] = ['erro' => $e->getMessage()];
        }
    }
    return $resumo;
}

/** Monta um registro no formato de colunas do CSV antigo, a partir de uma linha de search/<itemtype>. */
function mapear_registro($row, $fieldIds, $itemtype) {
    $registro = [
        'Nome' => (string)($row[(string)($fieldIds['nome'] ?? '')] ?? ''),
        'Entidade' => (string)($row[(string)($fieldIds['entidade'] ?? '')] ?? ''),
        'Status' => (string)($row[(string)($fieldIds['status'] ?? '')] ?? ''),
        'Fabricante' => (string)($row[(string)($fieldIds['fabricante'] ?? '')] ?? ''),
        'Tipo' => (string)($row[(string)($fieldIds['tipo'] ?? '')] ?? ''),
        'Modelo' => (string)($row[(string)($fieldIds['modelo'] ?? '')] ?? ''),
        'Grupo' => (string)($row[(string)($fieldIds['grupo'] ?? '')] ?? ''),
        'Usuário' => (string)($row[(string)($fieldIds['usuario'] ?? '')] ?? ''),
        'Nome alternativo do usuário' => (string)($row[(string)($fieldIds['contato'] ?? '')] ?? ''),
        'Comentários' => (string)($row[(string)($fieldIds['comentarios'] ?? '')] ?? ''),
        'Sistema operacional - Nome' => '',
        'Componentes - Processador' => '',
        'Componentes - Memória' => '',
        'Última atualização' => (string)($row[(string)($fieldIds['data_mod'] ?? '')] ?? ''),
        'ItemType' => $itemtype,
    ];

    if ($itemtype === 'Computer') {
        // O GLPI guarda o tamanho da memória (Item_DeviceMemory.size) em
        // MEGABYTES. O glpi.csv exportado manualmente já vinha em GIGABYTES
        // (é o que a regra de negócio no painel espera —
        // RAM_THRESHOLD_GB = 15.5). Convertendo aqui para manter o mesmo
        // formato e não ter que mexer na lógica de classificação.
        $memMB = (float)($row[(string)($fieldIds['memoria'] ?? '')] ?? 0);
        $memGB = $memMB > 0 ? rtrim(rtrim(number_format($memMB / 1024, 2, '.', ''), '0'), '.') : '';

        $registro['Sistema operacional - Nome'] = (string)($row[(string)($fieldIds['so'] ?? '')] ?? '');
        $registro['Componentes - Processador'] = (string)($row[(string)($fieldIds['processador'] ?? '')] ?? '');
        $registro['Componentes - Memória'] = $memGB;
    }

    return $registro;
}

/**
 * Busca todos os ativos (Computer + Monitor + Phone) já no formato de
 * colunas do CSV antigo (mais o campo "ItemType"). Uma sessão só, reusada
 * para os 3 itemtypes.
 *
 * $debug = true  -> devolve o relatório de diagnóstico (resumo dos 3
 *                    itemtypes, ou o relatório completo de um só, se
 *                    $apenasItemtype for informado).
 * $apenasItemtype -> restringe o diagnóstico (ou a busca) a um único
 *                     itemtype; usado por api_ativos.php?itemtype=Monitor.
 */
function buscar_ativos_glpi($debug = false, $apenasItemtype = null) {
    $session_token = glpi_init_session();
    try {
        $itemtypes = $apenasItemtype ? [$apenasItemtype] : itemtypes_suportados();

        if ($debug) {
            if ($apenasItemtype) {
                // Relatório completo (com o dump de todas as opções) de um só itemtype.
                return resolver_campos_glpi($session_token, $apenasItemtype, true);
            }
            // Resumo (sem dump gigante) dos 3 itemtypes suportados.
            return [
                '_debug' => true,
                'resumo_por_itemtype' => resumo_diagnostico_todos_itemtypes($session_token),
            ];
        }

        $registros = [];
        foreach ($itemtypes as $itemtype) {
            $fieldIds = resolver_campos_glpi($session_token, $itemtype, false);

            $query = [
                'is_deleted' => 0,
                'range' => '0-9999',
                'forcedisplay' => array_values($fieldIds),
            ];

            $search = glpi_api_request('GET', 'search/' . $itemtype, [
                'session_token' => $session_token,
                'query' => $query,
            ]);
            if ($search['status'] !== 200) {
                throw new RuntimeException("Falha ao buscar search/$itemtype (HTTP " . $search['status'] . '): ' . $search['raw']);
            }

            // Quando não há nenhum item cadastrado desse tipo (ex.: ainda
            // não existe Monitor/Phone no GLPI), a API responde HTTP 200
            // com totalcount=0 e SEM o campo "data" — isso é uma lista
            // vazia, não uma falha.
            $linhas = $search['data']['data'] ?? [];
            foreach ($linhas as $row) {
                $registros[] = mapear_registro($row, $fieldIds, $itemtype);
            }
        }
        return $registros;
    } finally {
        glpi_kill_session($session_token);
    }
}

/** Mantido por compatibilidade com código antigo que ainda chame este nome. */
function buscar_computadores_glpi($debug = false) {
    return buscar_ativos_glpi($debug, 'Computer');
}
