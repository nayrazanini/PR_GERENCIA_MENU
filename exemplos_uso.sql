/* ============================================================================
   EXEMPLOS DE USO — PR_GERENCIA_MENU (versão final, multi-sistema)
   Rode 01_criar_tabelas.sql e a procedure antes deste script.
   ============================================================================ */

USE MenuManagerDemo;
GO

DECLARE @ID_RETORNO INT, @DESCRICAO VARCHAR(255), @PERFIL VARCHAR(14);

/* ----------------------------------------------------------------------
   Cadastro mínimo para os exemplos abaixo
   ---------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM catalogo.TB_USUARIO WHERE USUARIO = 'jsilva')
    INSERT INTO catalogo.TB_USUARIO (USUARIO, NOME) VALUES ('jsilva', 'João Silva');

IF NOT EXISTS (SELECT 1 FROM dbo.TB_MENU WHERE SISTEMA = 'SISA' AND TRANSACAO = 'SISA.Financeiro')
BEGIN
    INSERT INTO catalogo.TB_TRANSACAO_MENU (SISTEMA, TRANSACAO, NOME, MODULO) VALUES ('SISA', 'SISA.Financeiro', 'Financeiro', 'Financeiro');
    INSERT INTO dbo.TB_MENU (ID_PAI, SISTEMA, TRANSACAO, ORDEM) VALUES (NULL, 'SISA', 'SISA.Financeiro', 1);
END;


/* ----------------------------------------------------------------------
   1) SISA — menu já existe, gera perfil com prefixo por departamento
   ---------------------------------------------------------------------- */
EXEC dbo.PR_GERENCIA_MENU
      @SISTEMA                   = 'SISA'
    , @MENU                      = 'Financeiro'
    , @CRIAR_MENU_SE_NAO_EXISTIR = 'N'
    , @SUBMENU1                  = 'Boletos'
    , @USUARIOS                  = 'jsilva'
    , @ID_RETORNO                = @ID_RETORNO OUTPUT
    , @DESCRICAO_RETORNO         = @DESCRICAO OUTPUT
    , @PERFIL_ACESSO_RETORNO     = @PERFIL OUTPUT;

SELECT @ID_RETORNO AS ID_RETORNO, @DESCRICAO AS DESCRICAO, @PERFIL AS PERFIL_CRIADO;
-- Esperado: PERFIL_CRIADO = 'SISA_Fin_1'


/* ----------------------------------------------------------------------
   2) SISB — sistema sem prefixo de sistema na TRANS, cria menu novo
   ---------------------------------------------------------------------- */
EXEC dbo.PR_GERENCIA_MENU
      @SISTEMA                   = 'SISB'
    , @MENU                      = 'Homologacao'
    , @CRIAR_MENU_SE_NAO_EXISTIR = 'S'
    , @SUBMENU1                  = 'Painel'
    , @URL                       = '/sisb/homologacao/painel'
    , @ID_RETORNO                = @ID_RETORNO OUTPUT
    , @DESCRICAO_RETORNO         = @DESCRICAO OUTPUT
    , @PERFIL_ACESSO_RETORNO     = @PERFIL OUTPUT;

SELECT @ID_RETORNO AS ID_RETORNO, @DESCRICAO AS DESCRICAO, @PERFIL AS PERFIL_CRIADO;
-- Esperado: PERFIL_CRIADO = 'SISB_1'


/* ----------------------------------------------------------------------
   3) SISC — sistema novo, com 3 níveis de submenu
   ---------------------------------------------------------------------- */
EXEC dbo.PR_GERENCIA_MENU
      @SISTEMA                   = 'SISC'
    , @MENU                      = 'TI'
    , @CRIAR_MENU_SE_NAO_EXISTIR = 'S'
    , @SUBMENU1                  = 'Integracoes'
    , @SUBMENU2                  = 'Relatorio'
    , @SUBMENU3                  = 'Consulta'
    , @ID_RETORNO                = @ID_RETORNO OUTPUT
    , @DESCRICAO_RETORNO         = @DESCRICAO OUTPUT
    , @PERFIL_ACESSO_RETORNO     = @PERFIL OUTPUT;

SELECT @ID_RETORNO AS ID_RETORNO, @DESCRICAO AS DESCRICAO, @PERFIL AS PERFIL_CRIADO;
-- Esperado: PERFIL_CRIADO = 'SISC_1'


/* ----------------------------------------------------------------------
   4) ERRO: sistema inválido
   ---------------------------------------------------------------------- */
EXEC dbo.PR_GERENCIA_MENU
      @SISTEMA                   = 'SISX'
    , @MENU                      = 'TI'
    , @SUBMENU1                  = 'Teste'
    , @ID_RETORNO                = @ID_RETORNO OUTPUT
    , @DESCRICAO_RETORNO         = @DESCRICAO OUTPUT
    , @PERFIL_ACESSO_RETORNO     = @PERFIL OUTPUT;

SELECT @ID_RETORNO AS ID_RETORNO, @DESCRICAO AS DESCRICAO;
-- Esperado: ID_RETORNO = -1, "Sistema inválido..."


/* ----------------------------------------------------------------------
   5) ERRO: menu raiz não existe e criação não foi autorizada (SISD)
   ---------------------------------------------------------------------- */
EXEC dbo.PR_GERENCIA_MENU
      @SISTEMA                   = 'SISD'
    , @MENU                      = 'Comercial'
    , @CRIAR_MENU_SE_NAO_EXISTIR = 'N'
    , @SUBMENU1                  = 'Propostas'
    , @ID_RETORNO                = @ID_RETORNO OUTPUT
    , @DESCRICAO_RETORNO         = @DESCRICAO OUTPUT
    , @PERFIL_ACESSO_RETORNO     = @PERFIL OUTPUT;

SELECT @ID_RETORNO AS ID_RETORNO, @DESCRICAO AS DESCRICAO;
-- Esperado: ID_RETORNO = -3, "O menu principal ... não existe."


-- Conferindo o resultado final:
SELECT M.SISTEMA, M.ID, M.ID_PAI, TT.NOME, M.ORDEM, TT.TRANSACAO
FROM dbo.TB_MENU M
INNER JOIN catalogo.TB_TRANSACAO_MENU TT
    ON TT.SISTEMA = M.SISTEMA AND TT.TRANSACAO = M.TRANSACAO
ORDER BY M.SISTEMA, M.ID_PAI, M.ORDEM;

SELECT * FROM catalogo.TB_PERFIL_ACESSO;
