# Gerenciador de Menus Dinâmicos (Menu Manager) — SQL Server / T-SQL

Procedure em T-SQL, **unificada para múltiplos sistemas**, que automatiza a
criação de itens de menu e a geração de códigos de perfil de acesso em um
ambiente corporativo onde vários sistemas compartilham o mesmo catálogo
central de transações e permissões.

> 📌 Este repositório usa nomes de tabelas, sistemas e módulos
> **fictícios/genéricos** para fins de portfólio. A lógica de negócio e a
> arquitetura técnica refletem um projeto real desenvolvido no trabalho, em
> parceria com um colega de equipe.

## 🚧 Status do projeto

Esta é a versão **final e unificada** da procedure, atualmente usada por
**4 sistemas diferentes** da organização (representados aqui como `SISA`,
`SISB`, `SISC` e `SISD`). Ela substitui as versões anteriores, que tinham
uma procedure separada por sistema — reduzindo duplicação de código.

**Próximo passo planejado:** adaptar a procedure para ser chamada
diretamente pela aplicação da organização (hoje ela é executada via script
T-SQL) — o que deve envolver ajustes de contrato de chamada e,
possivelmente, uma camada de serviço/API entre a aplicação e o banco.

## 🧭 O que esse projeto resolve

Vários sistemas da empresa compartilham o mesmo catálogo de transações,
módulos e perfis de acesso, mas cada um tem sua própria regra de como
nomear um novo perfil e sua própria árvore de menu. Antes, cada sistema
tinha sua própria cópia quase idêntica da procedure — o que significava
manter (e corrigir bugs em) várias versões da mesma lógica.

Esta versão final resolve isso: existe **uma única procedure**,
parametrizada por `@SISTEMA`, com toda a validação, criação de hierarquia
de menu e tratamento de erro compartilhados. Adicionar um sistema novo
significa acrescentar uma condição na regra de prefixo — não copiar a
procedure inteira.

## ⚙️ Como funciona, por sistema

| Sistema | Prefixo de menu (`TRANSACAO`) | Prefixo de perfil de acesso |
|---------|-------------------------------|-------------------------------|
| `SISA`  | `SISA.Menu`                   | Por departamento (ex.: `SISA_Fin_1`), com um prefixo genérico de fallback |
| `SISB`  | `Menu` (sem o código do sistema) | Fixo e único (ex.: `SISB_1`) |
| `SISC`  | `SISC.Menu`                    | Fixo e único (ex.: `SISC_1`) |
| `SISD`  | `SISD.Menu`                    | Fixo e único (ex.: `SISD_1`) |

O restante da regra é igual para todos os sistemas:

1. Valida sistema e hierarquia (não permite pular nível — ex.: não é
   possível informar `@SUBMENU3` sem `@SUBMENU2`);
2. Garante que o módulo exista no catálogo;
3. Garante que cada nível do caminho de menu exista, criando o que faltar
   (o menu raiz só é criado se `@CRIAR_MENU_SE_NAO_EXISTIR = 'S'`);
4. Gera um **novo** código de perfil de acesso, de forma segura mesmo com
   chamadas simultâneas (`sp_getapplock`);
5. Libera esse perfil em todos os níveis do caminho;
6. Se uma lista de usuários for informada, associa ao perfil os que já
   existirem no catálogo.

> ⚠️ **Atenção (comportamento a revisar):** usuários informados que não
> existem no catálogo são simplesmente ignorados nesta versão, sem gerar
> erro nem aviso. Se a aplicação da organização precisar saber quais
> usuários foram ignorados, isso deve ser tratado antes de chamar a
> procedure, ou ela precisa ser ajustada para reportar essa lista no
> retorno — um dos itens do próximo ciclo de ajustes.

## 🗂️ Arquitetura do banco

| Tabela                          | Função                                                        |
|-----------------------------------|-------------------------------------------------------------------|
| `catalogo.TB_USUARIO`             | Usuários cadastrados (compartilhado entre sistemas)               |
| `catalogo.TB_MODULO`              | Módulos cadastrados por sistema                                    |
| `catalogo.TB_TRANSACAO_MENU`      | Cadastro de cada tela/transação disponível                        |
| `catalogo.TB_PERFIL_ACESSO`       | Perfis de acesso gerados pela procedure                            |
| `catalogo.TB_PERFIL_TRANSACAO`    | Vínculo entre um perfil de acesso e uma transação                  |
| `catalogo.TB_PERFIL_USUARIO`      | Associação entre perfis de acesso e usuários                       |
| `dbo.TB_MENU`                     | Árvore de navegação — local a cada sistema                         |

## ↩️ Códigos de retorno

| Código  | Significado                                                              |
|---------|---------------------------------------------------------------------------|
| `1`     | Sucesso — perfil de acesso criado (e menu criado, se necessário)          |
| `-1`    | Erro de validação — sistema inválido, parâmetro faltando ou nível pulado |
| `-3`    | O menu raiz não existe e a criação não foi autorizada                    |
| outro   | Erro técnico inesperado (número do erro do SQL Server)                   |

## 🚀 Como testar localmente

\`\`\`sql
-- 1. Cria o banco de demonstração e o schema de catálogo
:r database/01_criar_tabelas.sql

-- 2. Cria a procedure
:r procedures/PR_GERENCIA_MENU.sql

-- 3. Roda os cenários de exemplo (4 sistemas + casos de erro)
:r procedures/exemplos_uso.sql
\`\`\`

## 🛠️ Tecnologias e conceitos aplicados

- SQL Server / T-SQL
- Transações e tratamento de erro (\`TRY/CATCH\`, \`XACT_ABORT\`, \`XACT_STATE\`)
- Controle de concorrência com \`sp_getapplock\`
- Regras de negócio parametrizadas por sistema, com lógica comum reutilizada
- Processamento de hierarquia dinâmica via \`TABLE\` variável + loop
- Separação entre um catálogo compartilhado e dados locais por sistema

## 👥 Autoria

Projeto desenvolvido em colaboração por **Nayra Zanini** e **Bruno Guida**.

## 📄 Licença

Este projeto está sob a licença MIT — veja o arquivo [LICENSE](LICENSE).
