# Gerenciador de Menus Dinâmicos (Menu Manager) — SQL Server / T-SQL

Duas procedures em T-SQL, uma por sistema, que automatizam a criação de
itens de menu **e** a geração de códigos de perfil de acesso em um ambiente
corporativo com múltiplos sistemas compartilhando um catálogo central de
transações e permissões.

> 📌 Este repositório usa nomes de tabelas, sistemas e módulos
> **fictícios/genéricos** para fins de portfólio. A lógica de negócio e a
> arquitetura técnica refletem um projeto real desenvolvido no trabalho, em
> parceria com um colega de equipe.

## 🧭 O que esse projeto resolve

A empresa opera mais de um sistema, mas todos compartilham o mesmo "banco
de catálogo" — onde ficam cadastradas as transações (telas), os módulos e
os perfis de acesso. Cada sistema, porém, tem sua própria árvore de menu e
sua própria regra de como nomear um novo perfil de acesso.

Em vez de repetir manualmente, tela por tela, os passos de: cadastrar a
transação → cadastrar/achar o menu → gerar um código de perfil → liberar o
perfil nos níveis certos — cada sistema tem sua própria procedure, seguindo
o mesmo padrão geral, mas com a regra de nomenclatura de perfil adaptada à
convenção daquele sistema.

## ⚙️ As duas variantes

| | `PR_GERENCIA_MENU_SISTEMA_A` | `PR_GERENCIA_MENU_SISTEMA_B` |
|---|---|---|
| Prefixo do código de menu | Leva o código do sistema (`SISA.TI`) | Não leva (`Homologacao`) |
| Código do perfil de acesso | Prefixo calculado a partir do nome do menu (3 primeiras letras) — ex.: `SISA_TI_1` | Sequencial simples, um único prefixo fixo — ex.: `SISB_1` |
| Uso típico | Vários departamentos, cada um com sua própria família de perfis | Um sistema menor, sem necessidade de segmentar por departamento |

Nas duas, a regra de negócio central é a mesma:

1. Garante que cada nível do caminho de menu exista (cria o que faltar);
2. Não deixa pular nível (ex.: não é possível informar `@SUBMENU2` sem
   `@SUBMENU1`);
3. Gera um **novo** código de perfil de acesso a cada execução;
4. Libera esse perfil em todos os níveis do caminho;
5. Se um item já existir e ganhar uma URL nova, ela só é aplicada quando o
   item ainda não tinha nenhuma URL cadastrada ("preenche se estiver
   vazio", nunca sobrescreve).

A associação de usuários ao perfil, nesta etapa, é feita por outra rotina —
estas procedures só criam o menu e o perfil.

## 🗂️ Arquitetura do banco (representada no schema `catalogo`)

Na versão real, o catálogo (transações, módulos, perfis de acesso) fica em
um banco central, compartilhado entre os sistemas, acessado por nome de
três partes. Aqui, isso é representado com um schema separado no mesmo
banco de demonstração:

| Tabela                          | Função                                                        |
|-----------------------------------|-------------------------------------------------------------------|
| `catalogo.TB_USUARIO`             | Usuários cadastrados (compartilhado entre sistemas)               |
| `catalogo.TB_MODULO`              | Módulos cadastrados por sistema                                    |
| `catalogo.TB_TRANSACAO_MENU`      | Cadastro de cada tela/transação disponível                        |
| `catalogo.TB_PERFIL_ACESSO`       | Perfis de acesso gerados pelas procedures                          |
| `catalogo.TB_PERFIL_TRANSACAO`    | Vínculo entre um perfil de acesso e uma transação                  |
| `catalogo.TB_PERFIL_USUARIO`      | Associação entre perfis de acesso e usuários                       |
| `dbo.TB_MENU`                     | Árvore de navegação — **local a cada sistema**                     |

## ↩️ Códigos de retorno (iguais nas duas procedures)

| Código  | Significado                                                              |
|---------|------------------------------------------------------------------------|
| `1`     | Sucesso — perfil de acesso criado (e menu criado, se necessário)        |
| `-1`    | Erro de validação — parâmetro obrigatório faltando ou nível pulado      |
| outro   | Erro técnico inesperado (número do erro do SQL Server)                  |

## 🚀 Como testar localmente

```sql
-- 1. Cria o banco de demonstração e o schema de catálogo
:r database/01_criar_tabelas.sql

-- 2. Cria as duas procedures
:r procedures/PR_GERENCIA_MENU_SISTEMA_A.sql
:r procedures/PR_GERENCIA_MENU_SISTEMA_B.sql

-- 3. Roda os cenários de exemplo
:r procedures/exemplos_uso.sql
```

## 🛠️ Tecnologias e conceitos aplicados

- SQL Server / T-SQL
- Transações e tratamento de erro (`TRY/CATCH`, `XACT_ABORT`, `XACT_STATE`)
- Geração de código sequencial derivado de regras específicas por sistema
- Processamento de hierarquia dinâmica (n níveis) via `TABLE` variável + loop
- Padrão "preenche se vazio" para não sobrescrever dados já cadastrados
- Separação entre um catálogo compartilhado e dados locais por sistema

## 🔧 Melhorias feitas nesta revisão

- Corrigido um caso em que o valor do usuário/módulo inválido era capturado
  mas nunca aparecia na mensagem de erro final;
- Padronizada a construção da hierarquia de submenus em um loop único, no
  lugar de três blocos quase idênticos (um por nível);
- Adicionada a preservação do módulo já cadastrado quando o menu raiz já
  existe (antes, essa checagem só existia em uma das duas procedures).

## 🔭 Possíveis evoluções

- Extrair a lógica comum das duas procedures para uma procedure "base",
  parametrizando apenas o que muda entre os sistemas;
- Mover a geração de prefixo para uma tabela de configuração por sistema.

## 👥 Autoria

Projeto desenvolvido em colaboração por **Nayra Zanini** e **Bruno Guida**.

## 📄 Licença

Este projeto está sob a licença MIT — veja o arquivo [LICENSE](LICENSE).
