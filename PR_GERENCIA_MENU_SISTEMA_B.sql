/* ============================================================================
   PROCEDURE: PR_GERENCIA_MENU_SISTEMA_B
   PROJETO:   Gerenciador de Menus Dinâmicos (Menu Manager)
   AUTORIA:   Nayra Zanini & Bruno Guida (colaboração)
   BANCO:     SQL Server / T-SQL

   ============================================================================
   O QUE ESSA PROCEDURE FAZ, EM RESUMO
   ============================================================================
   Versão mais simples da PR_GERENCIA_MENU_SISTEMA_A, usada em um segundo
   sistema onde o perfil de acesso não precisa de um prefixo por menu — só
   de um contador sequencial único (ex.: SISB_1, SISB_2, SISB_3...).

   Principais diferenças para a versão do Sistema A:
     - O código do menu (TRANSACAO) NÃO leva o prefixo do sistema — é
       gravado só como "Homologacao", por exemplo, em vez de "SISB.Homologacao";
     - O código do perfil de acesso é sequencial simples, com o nome do
       sistema como único prefixo — não varia por menu;
     - Também preenche a URL de um item já existente, mas apenas se ele
       ainda não tiver URL cadastrada ("preenche se estiver vazia").

   ============================================================================
   PARÂMETROS
   ============================================================================
   @MENU                  Menu raiz (nível 0).
   @MODULO                Módulo da transação. Se omitido, usa o nome do menu.
   @DESCRICAO_PERFIL       Descrição do perfil de acesso a ser criado.
   @SUBMENU1/2/3           Níveis adicionais. Não permite pular nível.
   @URL                    URL do último nível informado (opcional).
   @ID_RETORNO             [OUTPUT] Código de retorno — ver README.
   @DESCRICAO_RETORNO      [OUTPUT] Mensagem descritiva do resultado.
   @PERFIL_ACESSO_RETORNO  [OUTPUT] Código do perfil de acesso criado.

   Ver códigos de retorno e exemplo de uso no README.md e em
   procedures/exemplos_uso.sql
   ============================================================================ */

CREATE OR ALTER PROCEDURE dbo.PR_GERENCIA_MENU_SISTEMA_B
(
      @MENU                   VARCHAR(100)
    , @MODULO                 VARCHAR(30) = NULL
    , @DESCRICAO_PERFIL       VARCHAR(100)
    , @SUBMENU1               VARCHAR(100) = NULL
    , @SUBMENU2               VARCHAR(100) = NULL
    , @SUBMENU3               VARCHAR(100) = NULL
    , @URL                    VARCHAR(2000) = NULL
    , @ID_RETORNO             INT OUTPUT
    , @DESCRICAO_RETORNO      VARCHAR(255) OUTPUT
    , @PERFIL_ACESSO_RETORNO  VARCHAR(14) OUTPUT
)
AS
BEGIN

    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @SISTEMA VARCHAR(12) = 'SISB';
    DECLARE @PREFIXO_PERFIL VARCHAR(14) = 'SISB_';

    DECLARE
          @TRANS_ATUAL         VARCHAR(100)
        , @NOME_ATUAL          VARCHAR(100)

        , @ID_MENU             INT
        , @ID_NOVO             INT
        , @ID_PAI_ATUAL        INT

        , @ORDEM               INT
        , @NIVEL               INT
        , @NUMERO_PERFIL       INT

        , @URL_FINAL           VARCHAR(2000)
        , @MODULO_EXISTENTE    VARCHAR(30)

        , @NOVO_PERFIL         VARCHAR(14);

    DECLARE @NIVEIS TABLE (NIVEL INT, NOME VARCHAR(100), TRANS VARCHAR(100));

    SET @ID_RETORNO = 0;
    SET @DESCRICAO_RETORNO = NULL;
    SET @PERFIL_ACESSO_RETORNO = NULL;

    SET @MENU = LTRIM(RTRIM(ISNULL(@MENU, '')));
    SET @SUBMENU1 = NULLIF(LTRIM(RTRIM(ISNULL(@SUBMENU1, ''))), '');
    SET @SUBMENU2 = NULLIF(LTRIM(RTRIM(ISNULL(@SUBMENU2, ''))), '');
    SET @SUBMENU3 = NULLIF(LTRIM(RTRIM(ISNULL(@SUBMENU3, ''))), '');

    BEGIN TRY

        /* =====================================================
           1. VALIDAÇÕES BÁSICAS
           ===================================================== */
        IF @MENU = ''
        BEGIN
            SET @ID_RETORNO = -1;
            SET @DESCRICAO_RETORNO = 'O menu principal deve ser informado.';
            RETURN;
        END;

        IF NULLIF(LTRIM(RTRIM(@DESCRICAO_PERFIL)), '') IS NULL
        BEGIN
            SET @ID_RETORNO = -1;
            SET @DESCRICAO_RETORNO = 'A descrição do perfil de acesso deve ser informada.';
            RETURN;
        END;

        IF @SUBMENU2 IS NOT NULL AND @SUBMENU1 IS NULL
        BEGIN
            SET @ID_RETORNO = -1;
            SET @DESCRICAO_RETORNO = 'Não é possível informar o SUBMENU2 sem informar o SUBMENU1.';
            RETURN;
        END;

        IF @SUBMENU3 IS NOT NULL AND @SUBMENU2 IS NULL
        BEGIN
            SET @ID_RETORNO = -1;
            SET @DESCRICAO_RETORNO = 'Não é possível informar o SUBMENU3 sem informar o SUBMENU2.';
            RETURN;
        END;

        /* =====================================================
           2. DEFINE O MÓDULO (usa o nome do menu se não informado)
           ===================================================== */
        IF NULLIF(LTRIM(RTRIM(@MODULO)), '') IS NULL
            SET @MODULO = LEFT(@MENU, 30);

        /* =====================================================
           3. MONTA A LISTA DE NÍVEIS

           IMPORTANTE: aqui o código do sistema NÃO entra na TRANS
           (diferente do Sistema A). O nível raiz é só o nome do menu.
           ===================================================== */
        INSERT INTO @NIVEIS (NIVEL, NOME, TRANS) VALUES (0, @MENU, @MENU);

        SET @TRANS_ATUAL = @MENU;
        SET @NIVEL = 1;

        DECLARE @SUBMENUS TABLE (NIVEL INT, VALOR VARCHAR(100));
        IF @SUBMENU1 IS NOT NULL INSERT INTO @SUBMENUS VALUES (1, @SUBMENU1);
        IF @SUBMENU2 IS NOT NULL INSERT INTO @SUBMENUS VALUES (2, @SUBMENU2);
        IF @SUBMENU3 IS NOT NULL INSERT INTO @SUBMENUS VALUES (3, @SUBMENU3);

        WHILE EXISTS (SELECT 1 FROM @SUBMENUS WHERE NIVEL = @NIVEL)
        BEGIN
            SELECT @NOME_ATUAL = VALOR FROM @SUBMENUS WHERE NIVEL = @NIVEL;
            SET @TRANS_ATUAL = @TRANS_ATUAL + '.' + @NOME_ATUAL;
            INSERT INTO @NIVEIS (NIVEL, NOME, TRANS) VALUES (@NIVEL, @NOME_ATUAL, @TRANS_ATUAL);
            SET @NIVEL = @NIVEL + 1;
        END;

        /* =====================================================
           4. ABRE A TRANSAÇÃO
           ===================================================== */
        BEGIN TRAN;

        /* =====================================================
           5. GARANTE QUE O MÓDULO EXISTE
           ===================================================== */
        IF NOT EXISTS (SELECT 1 FROM catalogo.TB_MODULO WHERE SISTEMA = @SISTEMA AND MODULO = @MODULO)
            INSERT INTO catalogo.TB_MODULO (SISTEMA, MODULO) VALUES (@SISTEMA, @MODULO);

        /* =====================================================
           6. LOCALIZA O MENU RAIZ
           ===================================================== */
        SELECT TOP 1 @ID_MENU = ID
        FROM dbo.TB_MENU
        WHERE SISTEMA = @SISTEMA AND TRANSACAO = @MENU AND ID_PAI IS NULL;

        /* =====================================================
           7. CRIA O MENU RAIZ SE NÃO EXISTIR
           ===================================================== */
        IF @ID_MENU IS NULL
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM catalogo.TB_TRANSACAO_MENU WHERE SISTEMA = @SISTEMA AND TRANSACAO = @MENU)
            BEGIN
                INSERT INTO catalogo.TB_TRANSACAO_MENU
                    (SISTEMA, TRANSACAO, NOME, PUBLICA, ACESSO_ANONIMO, URL, FORMULARIO, ITEM_MENU, AUDITAR, MODULO)
                VALUES
                    (@SISTEMA, @MENU, @MENU, 'S', 'N', NULL, NULL, 'Menu', 'N', @MODULO);
            END;

            SELECT @ORDEM = ISNULL(MAX(ORDEM), 0) + 1
            FROM dbo.TB_MENU WHERE SISTEMA = @SISTEMA AND ID_PAI IS NULL;

            INSERT INTO dbo.TB_MENU
                (ID_PAI, SISTEMA, TRANSACAO, ORDEM, PAGINA_EXTERNA, POSSUI_PARAMETRO, ATIVO, TELA_CHEIA, FILTRO_UNIDADE)
            VALUES
                (NULL, @SISTEMA, @MENU, @ORDEM, 'N', 'N', 'S', 'N', NULL);

            SET @ID_MENU = CONVERT(INT, SCOPE_IDENTITY());
        END
        ELSE
        BEGIN
            -- (melhoria) preserva o módulo já cadastrado, em vez de
            -- simplesmente ignorar a informação — igual ao Sistema A.
            SELECT @MODULO_EXISTENTE = MODULO
            FROM catalogo.TB_TRANSACAO_MENU
            WHERE SISTEMA = @SISTEMA AND TRANSACAO = @MENU;

            IF ISNULL(@MODULO_EXISTENTE, '') <> ''
                SET @MODULO = @MODULO_EXISTENTE;
        END;

        /* =====================================================
           8. PERCORRE OS SUBMENUS, CRIANDO O QUE FALTAR
           ===================================================== */
        SET @ID_PAI_ATUAL = @ID_MENU;
        SET @NIVEL = 1;

        WHILE EXISTS (SELECT 1 FROM @NIVEIS WHERE NIVEL = @NIVEL)
        BEGIN
            SELECT @NOME_ATUAL = NOME, @TRANS_ATUAL = TRANS FROM @NIVEIS WHERE NIVEL = @NIVEL;

            SET @ID_NOVO = NULL;

            SELECT TOP 1 @ID_NOVO = ID
            FROM dbo.TB_MENU
            WHERE SISTEMA = @SISTEMA AND TRANSACAO = @TRANS_ATUAL AND ID_PAI = @ID_PAI_ATUAL;

            SET @URL_FINAL = NULL;
            IF @NIVEL = (SELECT MAX(NIVEL) FROM @NIVEIS) AND @URL IS NOT NULL AND LTRIM(RTRIM(@URL)) <> ''
                SET @URL_FINAL = LTRIM(RTRIM(@URL));

            IF @ID_NOVO IS NULL
            BEGIN
                SELECT @ORDEM = ISNULL(MAX(ORDEM), 0) + 1
                FROM dbo.TB_MENU WHERE SISTEMA = @SISTEMA AND ID_PAI = @ID_PAI_ATUAL;

                IF NOT EXISTS (SELECT 1 FROM catalogo.TB_TRANSACAO_MENU WHERE SISTEMA = @SISTEMA AND TRANSACAO = @TRANS_ATUAL)
                BEGIN
                    INSERT INTO catalogo.TB_TRANSACAO_MENU
                        (SISTEMA, TRANSACAO, NOME, PUBLICA, ACESSO_ANONIMO, URL, FORMULARIO, ITEM_MENU, AUDITAR, MODULO)
                    VALUES
                        (@SISTEMA, @TRANS_ATUAL, @NOME_ATUAL, 'S', 'N', @URL_FINAL, NULL, NULL, 'N', @MODULO);
                END
                ELSE IF @URL_FINAL IS NOT NULL
                BEGIN
                    UPDATE catalogo.TB_TRANSACAO_MENU
                    SET URL = @URL_FINAL
                    WHERE SISTEMA = @SISTEMA AND TRANSACAO = @TRANS_ATUAL AND ISNULL(URL, '') = '';
                END;

                INSERT INTO dbo.TB_MENU
                    (ID_PAI, SISTEMA, TRANSACAO, ORDEM, PAGINA_EXTERNA, POSSUI_PARAMETRO, ATIVO, TELA_CHEIA, FILTRO_UNIDADE)
                VALUES
                    (@ID_PAI_ATUAL, @SISTEMA, @TRANS_ATUAL, @ORDEM, 'N', 'N', 'S', 'N', NULL);

                SET @ID_NOVO = CONVERT(INT, SCOPE_IDENTITY());
            END
            ELSE
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM catalogo.TB_TRANSACAO_MENU WHERE SISTEMA = @SISTEMA AND TRANSACAO = @TRANS_ATUAL)
                BEGIN
                    THROW 50001, 'O item já existe na hierarquia, mas sua transação não existe no catálogo.', 1;
                END;

                IF @URL_FINAL IS NOT NULL
                BEGIN
                    UPDATE catalogo.TB_TRANSACAO_MENU
                    SET URL = @URL_FINAL
                    WHERE SISTEMA = @SISTEMA AND TRANSACAO = @TRANS_ATUAL AND ISNULL(URL, '') = '';
                END;
            END;

            SET @ID_PAI_ATUAL = @ID_NOVO;
            SET @NIVEL = @NIVEL + 1;
        END;

        /* =====================================================
           9. GERA O CÓDIGO DO PERFIL DE ACESSO

           Formato: SISB_1, SISB_2, SISB_3... Considera apenas
           códigos que terminam em número (SISB_Adm, por exemplo,
           é ignorado no cálculo do próximo número).
           ===================================================== */
        SELECT @NUMERO_PERFIL = ISNULL(MAX(
                TRY_CONVERT(INT, SUBSTRING(PERFIL_ACESSO, LEN(@PREFIXO_PERFIL) + 1, 10))
            ), 0)
        FROM catalogo.TB_PERFIL_ACESSO
        WHERE LEFT(PERFIL_ACESSO, LEN(@PREFIXO_PERFIL)) = @PREFIXO_PERFIL
          AND TRY_CONVERT(INT, SUBSTRING(PERFIL_ACESSO, LEN(@PREFIXO_PERFIL) + 1, 10)) IS NOT NULL;

        SET @NUMERO_PERFIL = @NUMERO_PERFIL + 1;
        SET @NOVO_PERFIL = NULL;

        WHILE @NOVO_PERFIL IS NULL
        BEGIN
            SET @NOVO_PERFIL = @PREFIXO_PERFIL + CONVERT(VARCHAR(10), @NUMERO_PERFIL);

            IF LEN(@NOVO_PERFIL) > 14
                THROW 50002, 'O código de perfil ultrapassou o limite de 14 caracteres.', 1;

            IF EXISTS (SELECT 1 FROM catalogo.TB_PERFIL_ACESSO WHERE PERFIL_ACESSO = @NOVO_PERFIL)
            BEGIN
                SET @NOVO_PERFIL = NULL;
                SET @NUMERO_PERFIL = @NUMERO_PERFIL + 1;
            END;
        END;

        /* =====================================================
           10. CRIA O PERFIL DE ACESSO (não vincula usuário)
           ===================================================== */
        INSERT INTO catalogo.TB_PERFIL_ACESSO (PERFIL_ACESSO, NOME, PAGINA_INICIAL)
        VALUES (@NOVO_PERFIL, LEFT(@DESCRICAO_PERFIL, 100), @SISTEMA);

        /* =====================================================
           11. LIBERA O PERFIL EM TODOS OS NÍVEIS DA ÁRVORE
           ===================================================== */
        INSERT INTO catalogo.TB_PERFIL_TRANSACAO (PERFIL_ACESSO, SISTEMA, TRANSACAO, PODE_ALTERAR, PODE_CADASTRAR, PODE_REMOVER)
        SELECT @NOVO_PERFIL, @SISTEMA, N.TRANS, 'S', NULL, NULL
        FROM @NIVEIS N
        WHERE NOT EXISTS (
            SELECT 1 FROM catalogo.TB_PERFIL_TRANSACAO P
            WHERE P.PERFIL_ACESSO = @NOVO_PERFIL AND P.SISTEMA = @SISTEMA AND P.TRANSACAO = N.TRANS
        );

        /* =====================================================
           12. COMMIT
           ===================================================== */
        COMMIT;

        /* =====================================================
           13. RETORNO DE SUCESSO
           ===================================================== */
        SET @ID_RETORNO = 1;
        SET @PERFIL_ACESSO_RETORNO = @NOVO_PERFIL;
        SET @DESCRICAO_RETORNO =
            'Menu processado com sucesso. Perfil de acesso: ' + @NOVO_PERFIL
            + '. Nenhum usuário foi vinculado.';

    END TRY
    BEGIN CATCH

        IF XACT_STATE() <> 0
            ROLLBACK;

        SET @ID_RETORNO = ERROR_NUMBER();
        SET @PERFIL_ACESSO_RETORNO = NULL;
        SET @DESCRICAO_RETORNO =
            'Erro ao processar menu (linha ' + CAST(ERROR_LINE() AS VARCHAR(10))
            + '): ' + ERROR_MESSAGE();

    END CATCH;

END;
GO
