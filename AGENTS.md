# Instruções do projeto

- Responder em português do Brasil.
- Trabalhar na branch corrente; não criar nem trocar de branch sem pedido explícito.
- Não alterar a resolução de monitores em testes automáticos de CI.
- Executar `./scripts/build.sh` e `./scripts/test.sh` antes de publicar alterações.
- O teste de integração altera telas de verdade: só usar com autorização e com
  uma sessão gráfica local. Escolher um destino externo pelo ID retornado por
  `--list-displays`; nunca assumir que o ID é igual entre computadores.
- Preservar a restauração do monitor ao parar ou encerrar o aplicativo.
- Documentar limitações da API privada. Não adicionar dependências pagas,
  coleta de dados, permissões de gravação de tela ou serviços de rede para
  funcionalidades que podem ser realizadas localmente.
