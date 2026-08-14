/* ============================================================================
   PROCEDURE: PR_GERENCIA_MENU  (versão final — multi-sistema)
   PROJETO:   Gerenciador de Menus Dinâmicos (Menu Manager)
   AUTORIA:   Nayra Zanini & Bruno Guida (colaboração)
   BANCO:     SQL Server / T-SQL

   ============================================================================
   O QUE MUDOU NESTA VERSÃO
   ============================================================================
   As duas procedures separadas por sistema (uma para cada convenção de
   nomenclatura) foram UNIFICADAS em uma única procedure, parametrizada por
   @SISTEMA. Hoje ela atende 4 sistemas diferentes da organização, cada um
   com sua própria regra de prefixo de perfil de acesso — mas com toda a
   validação, criação de hierarquia e tratamento de erro compartilhados.

   Isso resolve a duplicação de código que existia antes: adicionar um
   sistema novo agora significa acrescentar uma condição na definição do
   prefixo (passo 6), não copiar e colar a procedure inteira.

   ============================================================================
   O QUE ELA FAZ, EM RESUMO
   ============================================================================
   1) Valida o sistema informado (lista fixa de sistemas suportados) e o
      caminho de menu (não permite pular nível).
   2) Garante que o módulo exista no catálogo.
   3) Garante que cada nível do caminho de menu exista — cria o que faltar.
      A criação do menu raiz só acontece se @CRIAR_MENU_SE_NAO_EXISTIR = 'S'.
   4) Gera um NOVO código de perfil de acesso, seguindo a regra de prefixo
      do sistema informado, de forma segura mesmo com chamadas simultâneas
      (via sp_getapplock).
   5) Libera esse perfil em todos os níveis do caminho.
   6) Se uma lista de usuários for informada, associa ao perfil os que já
      existirem no catálogo — usuários não encontrados são simplesmente
      ignorados nesta etapa (ver nota de atenção no README sobre esse
      comportamento).

   ============================================================================
   REGRA DE PREFIXO DE PERFIL POR SISTEMA
   ============================================================================
   SISA  -> prefixo por departamento (tabela de mapeamento no passo 6),
            com um prefixo genérico como fallback para menus não mapeados.
   SISB  -> prefixo fixo único; o caminho de menu, neste sistema, NÃO leva
            o código do sistema (é gravado só como "Menu", não "SISB.Menu").
   SISC  -> prefixo fixo único.
   SISD  -> prefixo fixo único.

   ============================================================================
   PARÂMETROS
   ============================================================================
   @SISTEMA                     'SISA', 'SISB', 'SISC' ou 'SISD'.
   @MENU                        Menu raiz (nível 0).
   @CRIAR_MENU_SE_NAO_EXISTIR   'S' ou 'N' (padrão 'N' — mantenha assim até
                                 que a regra de criação automática seja
                                 formalmente aprovada para uso geral).
   @SUBMENU1                    Primeiro nível (obrigatório).
   @SUBMENU2 / @SUBMENU3        Níveis adicionais (não pode pular nível).
   @URL                         URL do último nível informado (opcional).
   @USUARIOS                    Lista de usuários separados por vírgula
                                 (opcional).
   @ID_RETORNO                  [OUTPUT] Código de retorno — ver README.
   @DESCRICAO_RETORNO           [OUTPUT] Mensagem descritiva do resultado.
   @PERFIL_ACESSO_RETORNO       [OUTPUT] Código do perfil de acesso criado.
   ============================================================================ */

CREATE OR ALTER PROCEDURE dbo.PR_GERENCIA_MENU
(
      @SISTEMA                     VARCHAR(12)
    , @MENU                        VARCHAR(100)
    , @CRIAR_MENU_SE_NAO_EXISTIR   CHAR(1) = 'N'
    , @SUBMENU1                    VARCHAR(100)
    , @SUBMENU2                    VARCHAR(100) = NULL
    , @SUBMENU3                    VARCHAR(100) = NULL
    , @URL                         VARCHAR(2000) = NULL
    , @USUARIOS                    VARCHAR(MAX) = NULL
    , @ID_RETORNO                  INT OUTPUT
    , @DESCRICAO_RETORNO           VARCHAR(255) OUTPUT
    , @PERFIL_ACESSO_RETORNO       VARCHAR(14) OUTPUT
)
AS
BEGIN

    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
          @SISTEMA_REAL         VARCHAR(12)
        , @SISTEMA_UPPER        VARCHAR(12)

        , @MENU_SEGMENTO        VARCHAR(100)
        , @TRANS_SEGMENTO       VARCHAR(100)
        , @MENU_TRANS           VARCHAR(100)
        , @TRANS_ATUAL          VARCHAR(100)
        , @NOME_ATUAL           VARCHAR(100)

        , @MODULO               VARCHAR(30)

        , @PREFIXO_PERFIL       VARCHAR(14)
        , @NOVO_PERFIL          VARCHAR(14)

        , @ID_MENU              INT
        , @ID_NOVO              INT
        , @ID_PAI_ATUAL         INT

        , @ORDEM                INT
        , @NIVEL                INT

        , @NUMERO               INT
        , @MAX_NUMERO           INT

        , @URL_FINAL            VARCHAR(2000)

        , @LOCK_RESULT          INT
        , @LOCK_RESOURCE        VARCHAR(100);

    DECLARE @ACENTOS_ORIGEM VARCHAR(90) =
        'ÁÀÃÂÄÉÈÊËÍÌÎÏÓÒÕÔÖÚÙÛÜÇáàãâäéèêëíìîïóòõôöúùûüç';
    DECLARE @ACENTOS_DESTINO VARCHAR(90) =
        'AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuuc';

    DECLARE @NIVEIS TABLE (NIVEL INT, NOME VARCHAR(100), TRANS VARCHAR(100));

    SET @ID_RETORNO = 0;
    SET @DESCRICAO_RETORNO = NULL;
    SET @PERFIL_ACESSO_RETORNO = NULL;

    BEGIN TRY

        /* =====================================================
           1. NORMALIZA E VALIDA O SISTEMA

           Lista fixa nesta versão. Para adicionar um novo sistema,
           inclua o código aqui e a regra de prefixo no passo 6.
           ===================================================== */
        SET @SISTEMA_REAL = LTRIM(RTRIM(ISNULL(@SISTEMA, '')));
        SET @SISTEMA_UPPER = UPPER(@SISTEMA_REAL);

        IF @SISTEMA_UPPER NOT IN ('SISA', 'SISB', 'SISC', 'SISD')
        BEGIN
            SET @ID_RETORNO = -1;
            SET @DESCRICAO_RETORNO =
                'Sistema inválido. Utilize SISA, SISB, SISC ou SISD.';
            RETURN;
        END;

        -- normaliza a caixa do código para o padrão gravado no catálogo
        SET @SISTEMA_REAL = @SISTEMA_UPPER;

        /* =====================================================
           2. VALIDA MENU E HIERARQUIA
           ===================================================== */
        IF NULLIF(LTRIM(RTRIM(@MENU)), '') IS NULL
        BEGIN
            SET @ID_RETORNO = -1;
            SET @DESCRICAO_RETORNO = 'O menu principal deve ser informado.';
            RETURN;
        END;

        IF NULLIF(LTRIM(RTRIM(@SUBMENU1)), '') IS NULL
        BEGIN
            SET @ID_RETORNO = -1;
            SET @DESCRICAO_RETORNO = 'O SUBMENU1 deve ser informado.';
            RETURN;
        END;

        IF @SUBMENU3 IS NOT NULL AND NULLIF(LTRIM(RTRIM(@SUBMENU2)), '') IS NULL
        BEGIN
            SET @ID_RETORNO = -1;
            SET @DESCRICAO_RETORNO = 'Não é possível criar o SUBMENU3 sem informar o SUBMENU2.';
            RETURN;
        END;

        /* =====================================================
           3. DEFINE O MÓDULO (usa o nome do menu)

           A criação do módulo continua existindo na procedure,
           mas a aplicação que a consome não precisa se preocupar
           com esse detalhe.
           ===================================================== */
        SET @MODULO = LEFT(LTRIM(RTRIM(@MENU)), 30);

        /* =====================================================
           4. MONTA O CAMINHO DO MENU PRINCIPAL

           SISA / SISC / SISD -> "SISTEMA.Menu"
           SISB                -> "Menu" (sem o código do sistema)
           ===================================================== */
        SET @MENU_SEGMENTO =
            REPLACE(
                TRANSLATE(LTRIM(RTRIM(@MENU)) COLLATE Latin1_General_BIN2, @ACENTOS_ORIGEM, @ACENTOS_DESTINO),
                ' ', ''
            );

        IF @SISTEMA_UPPER = 'SISB'
            SET @MENU_TRANS = @MENU_SEGMENTO;
        ELSE
            SET @MENU_TRANS = @SISTEMA_REAL + '.' + @MENU_SEGMENTO;

        INSERT INTO @NIVEIS (NIVEL, NOME, TRANS) VALUES (0, LTRIM(RTRIM(@MENU)), @MENU_TRANS);

        /* =====================================================
           5. MONTA OS SUBMENUS INFORMADOS
           ===================================================== */
        SET @TRANS_ATUAL = @MENU_TRANS;
        SET @NIVEL = 1;

        DECLARE @SUBMENUS TABLE (NIVEL INT, VALOR VARCHAR(100));
        INSERT INTO @SUBMENUS VALUES (1, LTRIM(RTRIM(@SUBMENU1)));
        IF NULLIF(LTRIM(RTRIM(@SUBMENU2)), '') IS NOT NULL INSERT INTO @SUBMENUS VALUES (2, LTRIM(RTRIM(@SUBMENU2)));
        IF NULLIF(LTRIM(RTRIM(@SUBMENU3)), '') IS NOT NULL INSERT INTO @SUBMENUS VALUES (3, LTRIM(RTRIM(@SUBMENU3)));

        WHILE EXISTS (SELECT 1 FROM @SUBMENUS WHERE NIVEL = @NIVEL)
        BEGIN
            SELECT @NOME_ATUAL = VALOR FROM @SUBMENUS WHERE NIVEL = @NIVEL;

            SET @TRANS_SEGMENTO =
                REPLACE(
                    TRANSLATE(@NOME_ATUAL COLLATE Latin1_General_BIN2, @ACENTOS_ORIGEM, @ACENTOS_DESTINO),
                    ' ', ''
                );

            SET @TRANS_ATUAL = @TRANS_ATUAL + '.' + @TRANS_SEGMENTO;

            INSERT INTO @NIVEIS (NIVEL, NOME, TRANS) VALUES (@NIVEL, @NOME_ATUAL, @TRANS_ATUAL);
            SET @NIVEL = @NIVEL + 1;
        END;

        /* =====================================================
           6. DEFINE O PREFIXO DO PERFIL DE ACESSO POR SISTEMA
           ===================================================== */
        IF @SISTEMA_UPPER = 'SISA'
        BEGIN
            SET @PREFIXO_PERFIL =
                CASE @MENU COLLATE Latin1_General_CI_AI
                    WHEN 'Financeiro' THEN 'SISA_Fin_'
                    WHEN 'Comercial'  THEN 'SISA_Com_'
                    WHEN 'Suporte'    THEN 'SISA_Sup_'
                    WHEN 'Relatorios' THEN 'SISA_Rel_'
                    WHEN 'Cadastros'  THEN 'SISA_Cad_'
                    ELSE 'SISA_'  -- fallback para menus fora do mapeamento
                END;
        END
        ELSE IF @SISTEMA_UPPER = 'SISB'
            SET @PREFIXO_PERFIL = 'SISB_';
        ELSE IF @SISTEMA_UPPER = 'SISC'
            SET @PREFIXO_PERFIL = 'SISC_';
        ELSE IF @SISTEMA_UPPER = 'SISD'
            SET @PREFIXO_PERFIL = 'SISD_';

        /* =====================================================
           7. ABRE A TRANSAÇÃO
           ===================================================== */
        BEGIN TRAN;

        /* =====================================================
           8. GARANTE QUE O MÓDULO EXISTE
           ===================================================== */
        IF NOT EXISTS (SELECT 1 FROM catalogo.TB_MODULO WHERE SISTEMA = @SISTEMA_REAL AND MODULO = @MODULO)
            INSERT INTO catalogo.TB_MODULO (SISTEMA, MODULO) VALUES (@SISTEMA_REAL, @MODULO);

        /* =====================================================
           9. LOCK PARA GERAÇÃO SEGURA DO PERFIL DE ACESSO
           ===================================================== */
        SET @LOCK_RESOURCE = 'PR_GERENCIA_MENU_' + @SISTEMA_REAL + '_' + @PREFIXO_PERFIL;

        EXEC @LOCK_RESULT = sp_getapplock
              @Resource = @LOCK_RESOURCE
            , @LockMode = 'Exclusive'
            , @LockOwner = 'Transaction'
            , @LockTimeout = 10000;

        IF @LOCK_RESULT < 0
            THROW 50001, 'Não foi possível obter o bloqueio para gerar o perfil de acesso.', 1;

        /* =====================================================
           10. DESCOBRE O PRÓXIMO NÚMERO LIVRE PARA O PREFIXO
           ===================================================== */
        SELECT @MAX_NUMERO = ISNULL(MAX(
                TRY_CONVERT(INT, SUBSTRING(PERFIL_ACESSO, LEN(@PREFIXO_PERFIL) + 1, 14))
            ), 0)
        FROM catalogo.TB_PERFIL_ACESSO
        WHERE LEFT(PERFIL_ACESSO, LEN(@PREFIXO_PERFIL)) = @PREFIXO_PERFIL;

        SET @NUMERO = @MAX_NUMERO + 1;
        SET @NOVO_PERFIL = NULL;

        WHILE @NOVO_PERFIL IS NULL
        BEGIN
            SET @NOVO_PERFIL = @PREFIXO_PERFIL + CONVERT(VARCHAR(10), @NUMERO);

            IF LEN(@NOVO_PERFIL) > 14
                THROW 50002, 'O código de perfil ultrapassou o limite de 14 caracteres.', 1;

            IF EXISTS (SELECT 1 FROM catalogo.TB_PERFIL_ACESSO WHERE PERFIL_ACESSO = @NOVO_PERFIL)
               OR EXISTS (SELECT 1 FROM catalogo.TB_PERFIL_TRANSACAO WHERE PERFIL_ACESSO = @NOVO_PERFIL)
               OR EXISTS (SELECT 1 FROM catalogo.TB_PERFIL_USUARIO WHERE PERFIL_ACESSO = @NOVO_PERFIL)
            BEGIN
                SET @NOVO_PERFIL = NULL;
                SET @NUMERO = @NUMERO + 1;
            END;
        END;

        /* =====================================================
           11. LOCALIZA O MENU PRINCIPAL
           ===================================================== */
        SELECT TOP 1 @ID_MENU = ID
        FROM dbo.TB_MENU
        WHERE SISTEMA = @SISTEMA_REAL AND TRANSACAO = @MENU_TRANS AND ID_PAI IS NULL;

        /* =====================================================
           12. MENU NÃO EXISTE
           ===================================================== */
        IF @ID_MENU IS NULL
        BEGIN
            IF @CRIAR_MENU_SE_NAO_EXISTIR = 'N'
            BEGIN
                SET @ID_RETORNO = -3;
                SET @DESCRICAO_RETORNO = 'O menu principal ' + @MENU_TRANS + ' não existe.';
                ROLLBACK;
                RETURN;
            END;

            INSERT INTO catalogo.TB_TRANSACAO_MENU
                (SISTEMA, TRANSACAO, NOME, PUBLICA, ACESSO_ANONIMO, URL, FORMULARIO, ITEM_MENU, AUDITAR, MODULO)
            VALUES
                (@SISTEMA_REAL, @MENU_TRANS, LEFT(@MENU, 100), 'S', 'N', NULL, NULL, NULL, 'N', @MODULO);

            SELECT @ORDEM = ISNULL(MAX(ORDEM), 0) + 1
            FROM dbo.TB_MENU WHERE SISTEMA = @SISTEMA_REAL AND ID_PAI IS NULL;

            INSERT INTO dbo.TB_MENU
                (ID_PAI, SISTEMA, TRANSACAO, ORDEM, PAGINA_EXTERNA, POSSUI_PARAMETRO, ATIVO, TELA_CHEIA, FILTRO_UNIDADE)
            VALUES
                (NULL, @SISTEMA_REAL, @MENU_TRANS, @ORDEM, 'N', 'N', 'S', 'N', NULL);

            SET @ID_MENU = CONVERT(INT, SCOPE_IDENTITY());
        END
        ELSE
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM catalogo.TB_TRANSACAO_MENU WHERE SISTEMA = @SISTEMA_REAL AND TRANSACAO = @MENU_TRANS)
                THROW 50003, 'O menu existe na hierarquia, mas não existe no catálogo de transações.', 1;
        END;

        /* =====================================================
           13. PROCESSA OS SUBMENUS
           ===================================================== */
        SET @ID_PAI_ATUAL = @ID_MENU;
        SET @NIVEL = 1;

        WHILE EXISTS (SELECT 1 FROM @NIVEIS WHERE NIVEL = @NIVEL)
        BEGIN
            SELECT @NOME_ATUAL = NOME, @TRANS_ATUAL = TRANS FROM @NIVEIS WHERE NIVEL = @NIVEL;

            SET @ID_NOVO = NULL;

            SELECT TOP 1 @ID_NOVO = ID
            FROM dbo.TB_MENU
            WHERE SISTEMA = @SISTEMA_REAL AND TRANSACAO = @TRANS_ATUAL AND ID_PAI = @ID_PAI_ATUAL;

            IF @ID_NOVO IS NULL
            BEGIN
                SELECT @ORDEM = ISNULL(MAX(ORDEM), 0) + 1
                FROM dbo.TB_MENU WHERE SISTEMA = @SISTEMA_REAL AND ID_PAI = @ID_PAI_ATUAL;

                -- URL só no último nível; SISA aplica o padrão de token
                SET @URL_FINAL = NULL;

                IF @NIVEL = (SELECT MAX(NIVEL) FROM @NIVEIS) AND NULLIF(LTRIM(RTRIM(@URL)), '') IS NOT NULL
                BEGIN
                    SET @URL_FINAL = LEFT(LTRIM(RTRIM(@URL)), 2000);

                    IF @SISTEMA_UPPER = 'SISA'
                    BEGIN
                        IF RIGHT(@URL_FINAL, 1) <> '/'
                            SET @URL_FINAL = @URL_FINAL + '/';

                        SET @URL_FINAL = @URL_FINAL + '{token}?sis=sisa';
                    END;
                END;

                IF NOT EXISTS (SELECT 1 FROM catalogo.TB_TRANSACAO_MENU WHERE SISTEMA = @SISTEMA_REAL AND TRANSACAO = @TRANS_ATUAL)
                BEGIN
                    INSERT INTO catalogo.TB_TRANSACAO_MENU
                        (SISTEMA, TRANSACAO, NOME, PUBLICA, ACESSO_ANONIMO, URL, FORMULARIO, ITEM_MENU, AUDITAR, MODULO)
                    VALUES
                        (@SISTEMA_REAL, @TRANS_ATUAL, LEFT(@NOME_ATUAL, 100), 'S', 'N', @URL_FINAL, NULL, NULL, 'N', @MODULO);
                END;

                INSERT INTO dbo.TB_MENU
                    (ID_PAI, SISTEMA, TRANSACAO, ORDEM, PAGINA_EXTERNA, POSSUI_PARAMETRO, ATIVO, TELA_CHEIA, FILTRO_UNIDADE)
                VALUES
                    (@ID_PAI_ATUAL, @SISTEMA_REAL, @TRANS_ATUAL, @ORDEM, 'N', 'N', 'S', 'N', NULL);

                SET @ID_NOVO = CONVERT(INT, SCOPE_IDENTITY());
            END
            ELSE
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM catalogo.TB_TRANSACAO_MENU WHERE SISTEMA = @SISTEMA_REAL AND TRANSACAO = @TRANS_ATUAL)
                    THROW 50004, 'O submenu existe na hierarquia, mas não existe no catálogo de transações.', 1;
            END;

            SET @ID_PAI_ATUAL = @ID_NOVO;
            SET @NIVEL = @NIVEL + 1;
        END;

        /* =====================================================
           14. CRIA O NOVO PERFIL DE ACESSO
           ===================================================== */
        INSERT INTO catalogo.TB_PERFIL_ACESSO (PERFIL_ACESSO, NOME, PAGINA_INICIAL)
        VALUES (@NOVO_PERFIL, LEFT(@NOME_ATUAL, 50), @SISTEMA_REAL);

        /* =====================================================
           15. LIBERA O PERFIL EM TODOS OS NÍVEIS DO CAMINHO
           ===================================================== */
        INSERT INTO catalogo.TB_PERFIL_TRANSACAO (PERFIL_ACESSO, SISTEMA, TRANSACAO, PODE_ALTERAR, PODE_CADASTRAR, PODE_REMOVER)
        SELECT @NOVO_PERFIL, @SISTEMA_REAL, N.TRANS, 'S', NULL, NULL
        FROM @NIVEIS N
        WHERE NOT EXISTS (
            SELECT 1 FROM catalogo.TB_PERFIL_TRANSACAO P
            WHERE P.PERFIL_ACESSO = @NOVO_PERFIL AND P.SISTEMA = @SISTEMA_REAL AND P.TRANSACAO = N.TRANS
        );

        /* =====================================================
           16. USUÁRIOS — OPCIONAL

           ATENÇÃO (comportamento herdado desta versão): usuários
           informados que não existem no catálogo são simplesmente
           ignorados aqui, sem erro. Se a aplicação da organização
           precisar saber quais foram ignorados, isso deve ser
           tratado antes de chamar a procedure, ou a procedure
           precisa ser ajustada para reportar essa lista no retorno.
           ===================================================== */
        IF NULLIF(LTRIM(RTRIM(@USUARIOS)), '') IS NOT NULL
        BEGIN
            INSERT INTO catalogo.TB_PERFIL_USUARIO (PERFIL_ACESSO, USUARIO)
            SELECT @NOVO_PERFIL, LTRIM(RTRIM(S.value))
            FROM STRING_SPLIT(@USUARIOS, ',') S
            WHERE LTRIM(RTRIM(S.value)) <> ''
              AND EXISTS (SELECT 1 FROM catalogo.TB_USUARIO U WHERE U.USUARIO = LTRIM(RTRIM(S.value)))
              AND NOT EXISTS (
                  SELECT 1 FROM catalogo.TB_PERFIL_USUARIO P
                  WHERE P.PERFIL_ACESSO = @NOVO_PERFIL AND P.USUARIO = LTRIM(RTRIM(S.value))
              );
        END;

        /* =====================================================
           17. COMMIT
           ===================================================== */
        COMMIT;

        /* =====================================================
           18. RETORNO DE SUCESSO
           ===================================================== */
        SET @ID_RETORNO = 1;
        SET @PERFIL_ACESSO_RETORNO = @NOVO_PERFIL;
        SET @DESCRICAO_RETORNO =
            'Menu processado com sucesso. Sistema: ' + @SISTEMA_REAL
            + '. Caminho: ' + @TRANS_ATUAL
            + '. Perfil de acesso: ' + @NOVO_PERFIL;

    END TRY
    BEGIN CATCH

        IF XACT_STATE() <> 0
            ROLLBACK;

        SET @ID_RETORNO = ERROR_NUMBER();
        SET @PERFIL_ACESSO_RETORNO = NULL;
        SET @DESCRICAO_RETORNO =
            'Erro ao processar menu ' + ISNULL(@SISTEMA_REAL, '') + ' (linha '
            + CAST(ERROR_LINE() AS VARCHAR(10)) + '): ' + ERROR_MESSAGE();

    END CATCH;

END;
GO
