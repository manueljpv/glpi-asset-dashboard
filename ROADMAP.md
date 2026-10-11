# Roadmap

**Português** · [English](ROADMAP.en.md) · [Español (Honduras)](ROADMAP.es-HN.md)

Este documento mostra para onde o projeto pode ir e o que aprendemos até aqui. Nada abaixo é promessa de data: são intenções, em ordem aproximada de prioridade. Sugestões são bem-vindas por *issue*.

## Curto prazo

**Painel**

- **Proteger ou remover o endpoint de diagnóstico.** O `api_ativos.php?debug=1` mostra a estrutura de campos do GLPI e não exige autenticação. Restringir por IP no servidor web ou desativá-lo em produção.
- **Tirar a lista de SSD do HTML.** Hoje `SSD_EXPANSION_LIST` é uma lista de hostnames dentro da página. Mover para um arquivo de configuração e, melhor ainda, ler o tipo de armazenamento (HDD/SSD) direto do inventário do GLPI.
- **Regras de classificação configuráveis.** Limite de RAM, gerações de CPU consideradas "OK/Atenção/Obsoleto" e tipos de servidor em um arquivo de configuração, em vez de constantes no código.
- **Modo demonstração.** Um conjunto de dados fictícios para experimentar o painel sem um GLPI e para gerar as capturas de tela do README.
- **Testes automatizados** para a classificação por CPU, o alerta de RAM e a normalização do campo "Responsável", usando dados de exemplo.
- **Restringir o cliente de API por IP** no GLPI, deixando só o servidor do painel autorizado.
- **Atualizar o `cache_ttl_seconds`** conforme o uso real (hoje 15 minutos).

**Qualidade dos dados no GLPI** (o painel só mostra o que está cadastrado; a correção é na origem)

- Preencher Status e Tipo dos monitores, que chegam vazios.
- Cadastrar os celulares (o código já trata a lista vazia sem erro).
- Tornar o campo Grupo obrigatório no cadastro.
- Usar um número de patrimônio estruturado, em vez de texto solto nos comentários.
- Registrar data de aquisição e garantia na aba financeira.
- Criar uma rotina periódica de auditoria de hostnames duplicados e de ativos sem responsável.

**GPO do agente**

- **Parametrizar os scripts.** Versão alvo, servidor e pasta de rede em um arquivo de configuração ao lado do script, em vez de editar o código a cada atualização.
- **Acompanhar os logs** após cada rollout e investigar agentes que ficam dias sem contato ou ainda estão em versões antigas.
- **Reconfirmar o ícone de bandeja** a cada versão nova do agente com o teste manual descrito em [`docs/gpo-glpi-agent.md`](docs/gpo-glpi-agent.md), antes de ir para produção.
- **Limpar scripts legados** que não são mais usados da pasta de rede.
- **Documentar qual conta** tem permissão de escrita no compartilhamento, para as atualizações não esbarrarem no bloqueio de permissão.

## Longo prazo

- **Autenticação opcional por departamento**, integrada ao diretório (LDAP/Active Directory) em vez de senhas locais: cada gestor vê só o seu setor, e a TI vê tudo. Uma primeira versão com senhas locais foi feita e depois descartada por simplicidade.
- **Apoio direto ao orçamento.** Exportar a visão filtrada (CSV/Excel), projetar quantos equipamentos precisam de troca por ano e por departamento e estimar custos.
- **Classificação além da CPU:** idade do equipamento, garantia e tipo de armazenamento.
- **Histórico e tendência.** Guardar fotografias periódicas do parque para mostrar a evolução (por exemplo, o percentual de equipamentos obsoletos ao longo do tempo).
- **Alertas** para a TI quando surgir um ativo obsoleto, um hostname duplicado ou um agente sem contato há vários dias.
- **Mais tipos de ativo:** impressoras, equipamentos de rede e outros itemtypes do GLPI.
- **Interface em vários idiomas.** Hoje a documentação principal é trilíngue, mas os textos do painel estão em português. Mover os textos para um arquivo de idiomas.
- **Empacotamento** em contêiner, para instalação e demonstração mais rápidas.
- **Alternativas à GPO** para a implantação do agente (por exemplo, gerenciadores de endpoint) e suporte a estações que não são Windows.
- **Traduzir a pasta `docs/`** para inglês e espanhol de Honduras.

## Lições aprendidas

1. **Valide o primeiro dado real, não só a ausência de erro.** O GLPI guarda a memória em MB e a regra do painel esperava GB. Nada falhou: todo equipamento simplesmente passaria a parecer "sem necessidade de upgrade de RAM". Só a conferência do primeiro retorno real revelou o problema.
2. **Os campos do GLPI variam entre instalações.** Os uids da busca são compostos (`Computer.<Tipo>.<campo>`) e diferem do que a documentação sugere. Descobrir os campos dinamicamente e ter um modo de diagnóstico (`?debug=1`) economizou muito tempo.
3. **Entenda a causa raiz, não só o sintoma.** O ícone de bandeja do agente não aparecia por GPO. Ler as tabelas internas do `.msi` mostrou que o componente só entra numa instalação nova com `AGENTMONITOR=1` **e** `EXECMODE=1`; reparar ou reinstalar recursos não resolve, mas um *upgrade* de versão maior sim.
4. **Nem todo "bug" é bug.** O ícone "sumido" horas depois de instalar era só um autostart que ainda não tinha disparado, porque faltava uma sessão nova. Checar isso primeiro evita investigação desnecessária.
5. **Seja idempotente e educado com o servidor.** Uma trava (mutex), um atraso aleatório antes de agir e um intervalo mínimo entre inventários evitaram instalações duplicadas e uma enxurrada de máquinas batendo no GLPI ao mesmo tempo.
6. **Garanta que o erro apareça.** Nos scripts, usar `-ErrorAction Stop` dentro de `try/catch` faz o erro de "acesso negado" cair no log em vez de sumir em silêncio quando o script roda sem ninguém olhando.
7. **Nunca altere a produção para testar.** O painel ganhou diretório e vhost próprios; o vhost do GLPI não foi tocado. Sempre `nginx -t` antes de `reload` (nunca `restart`), e um piloto com GPO isolada antes do rollout total.
8. **Permissões de arquivo são uma fonte constante de erro.** Um arquivo copiado como root depois do `chown` volta a ser `root:root` e o PHP-FPM não consegue lê-lo (HTTP 500). Reaplicar dono e permissão após cada envio.
9. **Confira que a atualização realmente chegou.** Um `grep` por um trecho exclusivo da versão nova e o tamanho do arquivo pegam o upload que não sobrescreveu ou a cópia antiga reenviada por engano.
10. **Certificado válido não exige abrir para a internet.** Passar o painel por um proxy reverso que só atende endereços privados deu HTTPS sem aviso sem expor dados, o que importa porque o painel não tem login.
11. **O painel mostra os problemas, mas a correção é na origem.** Hostnames duplicados, grupos vazios e ativos sem responsável aparecem nos indicadores de qualidade, e só corrigir o cadastro no GLPI resolve de fato.
12. **Mudanças de escopo fazem parte.** O login por departamento foi implementado e depois cancelado a pedido da gestão. Deixá-lo atrás de uma chave de configuração tornou a mudança barata, e depois o código morto foi removido do pacote publicado.
13. **Documente enquanto faz.** Os registros de decisões, bugs e testes foram o que permitiu retomar o trabalho e, agora, publicá-lo.
