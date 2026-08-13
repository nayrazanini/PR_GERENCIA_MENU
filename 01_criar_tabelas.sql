/* ============================================================================
   PROJETO: Gerenciador de Menus Dinâmicos (Menu Manager) — v3
   ARQUIVO: 01_criar_tabelas.sql
   OBJETIVO: Schema de demonstração para as duas variantes de sistema da
             procedure PR_GERENCIA_MENU. Nomes de tabelas, sistemas e
             módulos são genéricos, para fins de portfólio.

   ARQUITETURA REPRESENTADA
   -------------------------
   Na versão real, os dados "de catálogo" (transações, perfis de acesso,
   módulos, usuários) ficam em um banco central, compartilhado entre vários
   sistemas, acessado via nome de três partes (BANCO.dbo.TABELA). Já a
   árvore de menu (TB_MENU) é local a cada sistema.

   Aqui, isso é representado com dois SCHEMAS no mesmo banco de demonstração:
     - catalogo.*  -> dados compartilhados entre sistemas
     - dbo.TB_MENU -> hierarquia de menu, local por sistema
   ============================================================================ */

USE MASTER;
GO

IF DB_ID('MenuManagerDemo') IS NULL
BEGIN
    CREATE DATABASE MenuManagerDemo;
END;
GO

USE MenuManagerDemo;
GO

IF SCHEMA_ID('catalogo') IS NULL
    EXEC('CREATE SCHEMA catalogo');
GO

/* ----------------------------------------------------------------------
   catalogo.TB_USUARIO — usuários cadastrados (compartilhado entre sistemas)
   ---------------------------------------------------------------------- */
IF OBJECT_ID('catalogo.TB_USUARIO', 'U') IS NOT NULL DROP TABLE catalogo.TB_USUARIO;
GO
CREATE TABLE catalogo.TB_USUARIO
(
    USUARIO     VARCHAR(15)     NOT NULL,
    NOME        VARCHAR(150)    NULL,
    CONSTRAINT PK_TB_USUARIO PRIMARY KEY (USUARIO)
);
GO

/* ----------------------------------------------------------------------
   catalogo.TB_MODULO — módulos cadastrados por sistema
   ---------------------------------------------------------------------- */
IF OBJECT_ID('catalogo.TB_MODULO', 'U') IS NOT NULL DROP TABLE catalogo.TB_MODULO;
GO
CREATE TABLE catalogo.TB_MODULO
(
    SISTEMA     VARCHAR(12)     NOT NULL,
    MODULO      VARCHAR(30)     NOT NULL,
    CONSTRAINT PK_TB_MODULO PRIMARY KEY (SISTEMA, MODULO)
);
GO

/* ----------------------------------------------------------------------
   catalogo.TB_TRANSACAO_MENU — cada item de menu/transação disponível
   ---------------------------------------------------------------------- */
IF OBJECT_ID('catalogo.TB_TRANSACAO_MENU', 'U') IS NOT NULL DROP TABLE catalogo.TB_TRANSACAO_MENU;
GO
CREATE TABLE catalogo.TB_TRANSACAO_MENU
(
    SISTEMA         VARCHAR(12)     NOT NULL,
    TRANSACAO       VARCHAR(100)    NOT NULL,
    NOME            VARCHAR(100)    NOT NULL,
    PUBLICA         CHAR(1)         NOT NULL DEFAULT 'S',
    ACESSO_ANONIMO  CHAR(1)         NOT NULL DEFAULT 'N',
    URL             VARCHAR(2000)   NULL,
    FORMULARIO      VARCHAR(100)    NULL,
    ITEM_MENU       VARCHAR(100)    NULL,
    AUDITAR         CHAR(1)         NOT NULL DEFAULT 'N',
    MODULO          VARCHAR(30)     NULL,
    CONSTRAINT PK_TB_TRANSACAO_MENU PRIMARY KEY (SISTEMA, TRANSACAO)
);
GO

/* ----------------------------------------------------------------------
   dbo.TB_MENU — árvore de navegação, local por sistema
   ID_PAI = NULL indica um item raiz.
   ---------------------------------------------------------------------- */
IF OBJECT_ID('dbo.TB_MENU', 'U') IS NOT NULL DROP TABLE dbo.TB_MENU;
GO
CREATE TABLE dbo.TB_MENU
(
    ID                  INT IDENTITY(1,1) NOT NULL,
    ID_PAI              INT             NULL,
    SISTEMA             VARCHAR(12)     NOT NULL,
    TRANSACAO           VARCHAR(100)    NOT NULL,
    ORDEM               INT             NOT NULL,
    PAGINA_EXTERNA      CHAR(1)         NOT NULL DEFAULT 'N',
    POSSUI_PARAMETRO    CHAR(1)         NOT NULL DEFAULT 'N',
    ATIVO               CHAR(1)         NOT NULL DEFAULT 'S',
    TELA_CHEIA          CHAR(1)         NOT NULL DEFAULT 'N',
    FILTRO_UNIDADE      VARCHAR(50)     NULL,
    CONSTRAINT PK_TB_MENU PRIMARY KEY (ID)
);
GO

/* ----------------------------------------------------------------------
   catalogo.TB_PERFIL_ACESSO — perfis de acesso gerados pelas procedures
   ---------------------------------------------------------------------- */
IF OBJECT_ID('catalogo.TB_PERFIL_ACESSO', 'U') IS NOT NULL DROP TABLE catalogo.TB_PERFIL_ACESSO;
GO
CREATE TABLE catalogo.TB_PERFIL_ACESSO
(
    PERFIL_ACESSO   VARCHAR(14)     NOT NULL,
    NOME            VARCHAR(100)    NULL,
    PAGINA_INICIAL  VARCHAR(20)     NULL,
    CONSTRAINT PK_TB_PERFIL_ACESSO PRIMARY KEY (PERFIL_ACESSO)
);
GO

/* ----------------------------------------------------------------------
   catalogo.TB_PERFIL_TRANSACAO — vincula perfil de acesso a uma transação
   ---------------------------------------------------------------------- */
IF OBJECT_ID('catalogo.TB_PERFIL_TRANSACAO', 'U') IS NOT NULL DROP TABLE catalogo.TB_PERFIL_TRANSACAO;
GO
CREATE TABLE catalogo.TB_PERFIL_TRANSACAO
(
    PERFIL_ACESSO  VARCHAR(14)     NOT NULL,
    SISTEMA        VARCHAR(12)     NOT NULL,
    TRANSACAO      VARCHAR(100)    NOT NULL,
    PODE_ALTERAR   CHAR(1)         NULL,
    PODE_CADASTRAR CHAR(1)         NULL,
    PODE_REMOVER   CHAR(1)         NULL,
    CONSTRAINT PK_TB_PERFIL_TRANSACAO PRIMARY KEY (PERFIL_ACESSO, SISTEMA, TRANSACAO)
);
GO

/* ----------------------------------------------------------------------
   catalogo.TB_PERFIL_USUARIO — associação entre perfis e usuários
   (mantida no schema, ainda que as duas procedures desta versão não
   vinculem usuários automaticamente — apenas consultam para garantir
   códigos únicos)
   ---------------------------------------------------------------------- */
IF OBJECT_ID('catalogo.TB_PERFIL_USUARIO', 'U') IS NOT NULL DROP TABLE catalogo.TB_PERFIL_USUARIO;
GO
CREATE TABLE catalogo.TB_PERFIL_USUARIO
(
    PERFIL_ACESSO  VARCHAR(14)  NOT NULL,
    USUARIO        VARCHAR(15)  NOT NULL,
    CONSTRAINT PK_TB_PERFIL_USUARIO PRIMARY KEY (PERFIL_ACESSO, USUARIO)
);
GO
