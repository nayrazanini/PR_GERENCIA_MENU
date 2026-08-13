/* ============================================================================
   PROCEDURE: PR_GERENCIA_MENU_SISTEMA_A
   PROJETO:   Gerenciador de Menus Dinâmicos (Menu Manager)
   AUTORIA:   Nayra Zanini & Bruno Guida (colaboração)
   BANCO:     SQL Server / T-SQL

   ============================================================================
   O QUE ESSA PROCEDURE FAZ, EM RESUMO
   ============================================================================
   Cria (ou reaproveita, se já existir) um caminho de menu de até 4 níveis
   para o "Sistema A", e sempre gera um NOVO perfil de acesso liberado em
   todos os níveis desse caminho. Diferente da associação de usuários — que
   não é feita aqui —, o foco é: garantir o menu e devolver um código de
   perfil pronto para ser usado por outra rotina de cadastro de usuários.

   Principais diferenças para a versão genérica (ver PR_GERENCIA_MENU no
   histórico do projeto):
     - O sistema é fixo (não é mais um parâmetro livre);
     - O prefixo do perfil de acesso é CALCULADO a partir do nome do menu
       (3 primeiras letras), em vez de vir de uma tabela de mapeamento fixa;
     - Garante a existência do módulo (catalogo.TB_MODULO) antes de
       cadastrar a transação, por causa de uma FK no banco de catálogo;
     - Se a transação de um nível já existir sem URL preenchida, a URL
       informada é aplicada de forma "preenche se estiver vazia" — não
       sobrescreve uma URL já existente.

   ============================================================================
   PARÂMETROS
   ============================================================================
   @SISTEMA              Fixo nesta versão: 'SISA'.
   @MENU                 Menu raiz (nível 0). Também define o prefixo do
                          perfil de acesso (3 primeiras letras, maiúsculas).
   @MODULO                Módulo ao qual a transação pertence. Se omitido,
                          usa o próprio nome do menu.
   @DESCRICAO_PERFIL      Descrição do perfil de acesso a ser criado.
   @SUBMENU1/2/3          Níveis adicionais. Não é permitido pular nível
                          (ex.: informar SUBMENU2 sem SUBMENU1).
   @URL                   URL do item do último nível informado (opcional).
   @ID_RETORNO             [OUTPUT] Código de retorno — ver tabela no README.
   @DESCRICAO_RETORNO      [OUTPUT] Mensagem descritiva do resultado.
   @PERFIL_ACESSO_RETORNO  [OUTPUT] Código do perfil de acesso criado.

   Ver códigos de retorno e exemplo de uso no README.md e em
   procedures/exemplos_uso.sql
   ============================================================================ */

CREATE OR ALTER PROCEDURE dbo.PR_GERENCIA_MENU_SISTEMA_A
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

    DECLARE @SISTEMA VARCHAR(12) = 'SISA';

    DECLARE
          @MENU_TRANS          VARCHAR(100)
        , @TRANS_ATUAL         VARCHAR(100)
        , @NOME_ATUAL          VARCHAR(100)

        , @PREFIXO_PERFIL      VARCHAR(14)
        , @NOVO_PERFIL         VARCHAR(14)

        , @ID_MENU             INT
        , @ID_NOVO             INT
        , @ID_PAI_ATUAL        INT

        , @ORDEM               INT
        , @NIVEL               INT
        , @NUMERO              INT
        , @MAX_NUMERO          INT

        , @URL_FINAL           VARCHAR(2000)
        , @MODULO_EXISTENTE    VARCHAR(30);

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

        /* =====================================================
           2. NÃO PERMITE PULAR NÍVEL
           ===================================================== */
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
           3. DEFINE O MÓDULO (usa o nome do menu se não informado)
           ===================================================== */
        IF NULLIF(LTRIM(RTRIM(@MODULO)), '') IS NULL
            SET @MODULO = LEFT(@MENU, 30);

        /* =====================================================
           4. MONTA A LISTA DE NÍVEIS (menu raiz + submenus)
           Exemplo: @SISTEMA=SISA, @MENU=TI -> SISA.TI
           ===================================================== */
        SET @MENU_TRANS = @SISTEMA + '.' + @MENU;

        INSERT INTO @NIVEIS (NIVEL, NOME, TRANS) VALUES (0, @MENU, @MENU_TRANS);

        SET @TRANS_ATUAL = @MENU_TRANS;
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
           5. ABRE A TRANSAÇÃO
           ===================================================== */
        BEGIN TRAN;

        /* =====================================================
           6. GARANTE QUE O MÓDULO EXISTE (necessário por FK)
           ===================================================== */
        IF NOT EXISTS (SELECT 1 FROM catalogo.TB_MODULO WHERE SISTEMA = @SISTEMA AND MODULO = @MODULO)
            INSERT INTO catalogo.TB_MODULO (SISTEMA, MODULO) VALUES (@SISTEMA, @MODULO);

        /* =====================================================
           7. LOCALIZA O MENU RAIZ
           ===================================================== */
        SELECT TOP 1 @ID_MENU = ID
        FROM dbo.TB_MENU
        WHERE SISTEMA = @SISTEMA AND TRANSACAO = @MENU_TRANS AND ID_PAI IS NULL;

        /* =====================================================
           8. CRIA O MENU RAIZ SE NÃO EXISTIR
           ===================================================== */
        IF @ID_MENU IS NULL
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM catalogo.TB_TRANSACAO_MENU WHERE SISTEMA = @SISTEMA AND TRANSACAO = @MENU_TRANS)
            BEGIN
                INSERT INTO catalogo.TB_TRANSACAO_MENU
                    (SISTEMA, TRANSACAO, NOME, PUBLICA, ACESSO_ANONIMO, URL, FORMULARIO, ITEM_MENU, AUDITAR, MODULO)
                VALUES
                    (@SISTEMA, @MENU_TRANS, @MENU, 'S', 'N', NULL, NULL, 'Menu', 'N', @MODULO);
            END;

            SELECT @ORDEM = ISNULL(MAX(ORDEM), 0) + 1
            FROM dbo.TB_MENU WHERE SISTEMA = @SISTEMA AND ID_PAI IS NULL;

            INSERT INTO dbo.TB_MENU
                (ID_PAI, SISTEMA, TRANSACAO, ORDEM, PAGINA_EXTERNA, POSSUI_PARAMETRO, ATIVO, TELA_CHEIA, FILTRO_UNIDADE)
            VALUES
                (NULL, @SISTEMA, @MENU_TRANS, @ORDEM, 'N', 'N', 'S', 'N', NULL);

            SET @ID_MENU = CONVERT(INT, SCOPE_IDENTITY());
        END
        ELSE
        BEGIN
            -- O menu já existe: preserva o módulo já cadastrado para a
            -- transação, em vez de sobrescrevê-lo com o valor informado.
            SELECT @MODULO_EXISTENTE = MODULO
            FROM catalogo.TB_TRANSACAO_MENU
            WHERE SISTEMA = @SISTEMA AND TRANSACAO = @MENU_TRANS;

            IF ISNULL(@MODULO_EXISTENTE, '') <> ''
                SET @MODULO = @MODULO_EXISTENTE;
        END;

        /* =====================================================
           9. PERCORRE OS SUBMENUS, CRIANDO O QUE FALTAR
           Se um nível já existir, não recria — apenas segue para
           o próximo. A URL só é aplicada no último nível, e só
           se ele ainda não tiver uma URL preenchida.
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
           10. CALCULA O PREFIXO DO PERFIL DE ACESSO

           O prefixo é derivado das 3 primeiras letras do menu
           (sem espaços/underscores), em maiúsculas.
           Exemplo: "TI_LYCEUM" -> "TIL" -> "SISA_TIL_"
           ===================================================== */
        SET @PREFIXO_PERFIL =
            @SISTEMA + '_' +
            LEFT(REPLACE(REPLACE(UPPER(@MENU), '_', ''), ' ', ''), 3) + '_';

        /* =====================================================
           11. DESCOBRE O PRÓXIMO NÚMERO LIVRE DO PREFIXO
           ===================================================== */
        SELECT @MAX_NUMERO = ISNULL(MAX(
                TRY_CONVERT(INT, SUBSTRING(PERFIL_ACESSO, LEN(@PREFIXO_PERFIL) + 1, 14))
            ), 0)
        FROM
        (
            SELECT PERFIL_ACESSO FROM catalogo.TB_PERFIL_ACESSO
            UNION
            SELECT PERFIL_ACESSO FROM catalogo.TB_PERFIL_TRANSACAO
            UNION
            SELECT PERFIL_ACESSO FROM catalogo.TB_PERFIL_USUARIO
        ) P
        WHERE LEFT(P.PERFIL_ACESSO, LEN(@PREFIXO_PERFIL)) = @PREFIXO_PERFIL;

        SET @NUMERO = @MAX_NUMERO + 1;
        SET @NOVO_PERFIL = NULL;

        /* =====================================================
           12. GARANTE UM CÓDIGO ÚNICO
           ===================================================== */
        WHILE @NOVO_PERFIL IS NULL
        BEGIN
            SET @NOVO_PERFIL = @PREFIXO_PERFIL + CONVERT(VARCHAR(10), @NUMERO);

            IF LEN(@NOVO_PERFIL) > 14
                THROW 50002, 'Não foi possível gerar um código de perfil dentro do limite de 14 caracteres.', 1;

            IF EXISTS (SELECT 1 FROM catalogo.TB_PERFIL_ACESSO WHERE PERFIL_ACESSO = @NOVO_PERFIL)
               OR EXISTS (SELECT 1 FROM catalogo.TB_PERFIL_TRANSACAO WHERE PERFIL_ACESSO = @NOVO_PERFIL)
               OR EXISTS (SELECT 1 FROM catalogo.TB_PERFIL_USUARIO WHERE PERFIL_ACESSO = @NOVO_PERFIL)
            BEGIN
                SET @NOVO_PERFIL = NULL;
                SET @NUMERO = @NUMERO + 1;
            END;
        END;

        /* =====================================================
           13. CRIA O NOVO PERFIL DE ACESSO
           ===================================================== */
        INSERT INTO catalogo.TB_PERFIL_ACESSO (PERFIL_ACESSO, NOME, PAGINA_INICIAL)
        VALUES (@NOVO_PERFIL, LEFT(@DESCRICAO_PERFIL, 50), @SISTEMA);

        /* =====================================================
           14. LIBERA O PERFIL EM TODOS OS NÍVEIS DO CAMINHO
           ===================================================== */
        INSERT INTO catalogo.TB_PERFIL_TRANSACAO (PERFIL_ACESSO, SISTEMA, TRANSACAO, PODE_ALTERAR, PODE_CADASTRAR, PODE_REMOVER)
        SELECT @NOVO_PERFIL, @SISTEMA, N.TRANS, 'S', NULL, NULL
        FROM @NIVEIS N
        WHERE NOT EXISTS (
            SELECT 1 FROM catalogo.TB_PERFIL_TRANSACAO P
            WHERE P.PERFIL_ACESSO = @NOVO_PERFIL AND P.SISTEMA = @SISTEMA AND P.TRANSACAO = N.TRANS
        );

        /* =====================================================
           15. COMMIT
           ===================================================== */
        COMMIT;

        /* =====================================================
           16. RETORNO DE SUCESSO
           ===================================================== */
        SET @ID_RETORNO = 1;
        SET @PERFIL_ACESSO_RETORNO = @NOVO_PERFIL;
        SET @DESCRICAO_RETORNO =
            'Perfil de acesso criado com sucesso. Código: ' + @NOVO_PERFIL
            + ' | Menu: ' + @MENU + '. Nenhum usuário foi vinculado.';

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
