/* ============================================================================
   EXEMPLOS DE USO — PR_GERENCIA_MENU_SISTEMA_A e PR_GERENCIA_MENU_SISTEMA_B
   Rode 01_criar_tabelas.sql e as duas procedures antes deste script.
   ============================================================================ */

USE MenuManagerDemo;
GO

DECLARE @ID_RETORNO INT, @DESCRICAO VARCHAR(255), @PERFIL VARCHAR(14);

/* ----------------------------------------------------------------------
   SISTEMA A — cria "TI > EAD" do zero e gera o primeiro perfil da família
   SISA_TI_ (prefixo derivado das 3 primeiras letras de "TI")
   ---------------------------------------------------------------------- */
EXEC dbo.PR_GERENCIA_MENU_SISTEMA_A
      @MENU               = 'TI'
    , @MODULO              = 'TI'
    , @DESCRICAO_PERFIL    = 'Acesso ao módulo de EAD'
    , @SUBMENU1            = 'EAD'
    , @ID_RETORNO          = @ID_RETORNO OUTPUT
    , @DESCRICAO_RETORNO   = @DESCRICAO OUTPUT
    , @PERFIL_ACESSO_RETORNO = @PERFIL OUTPUT;

SELECT @ID_RETORNO AS ID_RETORNO, @DESCRICAO AS DESCRICAO, @PERFIL AS PERFIL_CRIADO;
-- Esperado: ID_RETORNO = 1, PERFIL_CRIADO = 'SISA_TI_1'


/* ----------------------------------------------------------------------
   SISTEMA A — mesmo caminho de novo: gera um SEGUNDO perfil de acesso
   (o menu já existe, então só é criado o novo perfil)
   ---------------------------------------------------------------------- */
EXEC dbo.PR_GERENCIA_MENU_SISTEMA_A
      @MENU               = 'TI'
    , @DESCRICAO_PERFIL    = 'Acesso de leitura ao módulo de EAD'
    , @SUBMENU1            = 'EAD'
    , @ID_RETORNO          = @ID_RETORNO OUTPUT
    , @DESCRICAO_RETORNO   = @DESCRICAO OUTPUT
    , @PERFIL_ACESSO_RETORNO = @PERFIL OUTPUT;

SELECT @ID_RETORNO AS ID_RETORNO, @DESCRICAO AS DESCRICAO, @PERFIL AS PERFIL_CRIADO;
-- Esperado: PERFIL_CRIADO = 'SISA_TI_2'


/* ----------------------------------------------------------------------
   SISTEMA A — erro: pulando um nível (SUBMENU2 sem SUBMENU1)
   ---------------------------------------------------------------------- */
EXEC dbo.PR_GERENCIA_MENU_SISTEMA_A
      @MENU               = 'TI'
    , @DESCRICAO_PERFIL    = 'Teste'
    , @SUBMENU2            = 'Relatorio'
    , @ID_RETORNO          = @ID_RETORNO OUTPUT
    , @DESCRICAO_RETORNO   = @DESCRICAO OUTPUT
    , @PERFIL_ACESSO_RETORNO = @PERFIL OUTPUT;

SELECT @ID_RETORNO AS ID_RETORNO, @DESCRICAO AS DESCRICAO;
-- Esperado: ID_RETORNO = -1, "Não é possível informar o SUBMENU2 sem informar o SUBMENU1."


/* ----------------------------------------------------------------------
   SISTEMA B — cria "Homologacao > Painel" e gera um perfil sequencial
   simples (sem prefixo por menu)
   ---------------------------------------------------------------------- */
EXEC dbo.PR_GERENCIA_MENU_SISTEMA_B
      @MENU               = 'Homologacao'
    , @DESCRICAO_PERFIL    = 'Acesso ao painel de homologação'
    , @SUBMENU1            = 'Painel'
    , @URL                 = '/sistema-b/homologacao/painel'
    , @ID_RETORNO          = @ID_RETORNO OUTPUT
    , @DESCRICAO_RETORNO   = @DESCRICAO OUTPUT
    , @PERFIL_ACESSO_RETORNO = @PERFIL OUTPUT;

SELECT @ID_RETORNO AS ID_RETORNO, @DESCRICAO AS DESCRICAO, @PERFIL AS PERFIL_CRIADO;
-- Esperado: ID_RETORNO = 1, PERFIL_CRIADO = 'SISB_1'


-- Conferindo o resultado final:
SELECT M.ID, M.ID_PAI, M.SISTEMA, TT.NOME, M.ORDEM, TT.TRANSACAO, TT.URL
FROM dbo.TB_MENU M
INNER JOIN catalogo.TB_TRANSACAO_MENU TT
    ON TT.SISTEMA = M.SISTEMA AND TT.TRANSACAO = M.TRANSACAO
ORDER BY M.SISTEMA, M.ID_PAI, M.ORDEM;

SELECT * FROM catalogo.TB_PERFIL_ACESSO;
