# Phamani

Gestão financeira pessoal: contas, categorias, transações simples, **parceladas** e **recorrentes**, com dashboard de KPIs, fluxo de caixa e despesas por categoria.

Projeto separado do monorepo Lukisa, com banco próprio e login exclusivamente via Google.

## Stack

| Camada    | Tecnologia                                                                 |
| --------- | -------------------------------------------------------------------------- |
| Backend   | PHP 8.4, Laravel 13, Socialite (Google), spatie/laravel-data               |
| Frontend  | Inertia.js v3, React 19, TypeScript, Tailwind CSS 4, shadcn/ui (Radix), Motion, Recharts |
| Rotas TS  | Laravel Wayfinder (substitui o Ziggy: `import { store } from '@/routes/transactions'`) |
| Build     | Vite+ (`vite-plus`), React Compiler                                        |
| Banco     | PostgreSQL 17 (SQLite em memória nos testes)                               |
| Infra     | Docker Compose: `app` (php-fpm + node 24), `nginx`, `postgres`, `vite` (dev) |

Base: [starter kit oficial React do Laravel](https://github.com/laravel/react-starter-kit), sem Fortify/senha/2FA/passkeys.

## Subindo o projeto (Docker)

Pré-requisito: Docker. Não é preciso PHP, Composer nem Node na máquina.

```bash
cp .env.example .env
# ajuste UID/GID para os do seu usuário (comando `id`) e preencha GOOGLE_CLIENT_ID/SECRET

docker compose build
docker compose up -d                      # app + nginx + postgres

docker compose exec app composer install
docker compose exec app php artisan key:generate
docker compose exec app php artisan migrate
docker compose exec app npm install

# Desenvolvimento com HMR:
docker compose --profile dev up -d vite   # Vite em http://localhost:5174
# ou build de produção dos assets:
docker compose exec app npm run build
```

Acesse **http://localhost:8686**.

Portas (configuráveis no `.env`): app `8686`, Vite `5174`, Postgres `5433` (para não conflitar com o Lukisa).

> Usuário de demonstração (sem precisar do Google, só para inspecionar dados): `docker compose exec app php artisan db:seed`.

## Login com Google

1. Acesse **Google Cloud Console → APIs e serviços → Credenciais**.
2. Configure a **Tela de consentimento OAuth** (tipo *Externo*; escopos padrão `openid`, `email`, `profile` não exigem verificação).
3. **Criar credenciais → ID do cliente OAuth → Aplicativo da Web**.
4. Em **URIs de redirecionamento autorizados**, adicione:
   - `http://localhost:8686/auth/google/callback` (dev)
   - `https://SEU-DOMINIO/auth/google/callback` (produção)
5. Copie o *Client ID* e o *Client Secret* para `GOOGLE_CLIENT_ID` e `GOOGLE_CLIENT_SECRET` no `.env`.

Enquanto o app estiver em modo *Teste* no Google, só os e-mails cadastrados como "usuários de teste" conseguem entrar.

### Como funciona

- `GET /auth/google/redirect` → Google → `GET /auth/google/callback`.
- O usuário é localizado/criado por **`google_id`** (identificador estável; o e-mail pode mudar). Nome, e-mail e avatar são atualizados a cada login.
- No **primeiro login**, o evento `Registered` dispara o listener `CreateDefaultFinancialData`, que cria a conta "Carteira" e as categorias padrão.
- Se no futuro você colocar um provedor de identidade central (Authentik, Keycloak, Zitadel...), basta trocar o driver do Socialite; o restante não muda.

## Arquitetura

Mantém o padrão do Lukisa: **Controllers → Services → Repositories**, com interfaces e DTOs (`spatie/laravel-data`).

```
app/
├── DTOs/                     # Entrada validada (StoreTransactionData, StoreAccountData, StoreCategoryData)
├── Enums/                    # RecurringFrequency, Category\Color, Category\Icon
├── Http/Controllers/         # Dashboard, Transaction, Account, Category, Auth\GoogleAuth
├── Interfaces/{Repositories,Services}/
├── Listeners/                # CreateDefaultFinancialData (ao registrar usuário)
├── Models/                   # BaseModel (UUID) + Account, Category, Transaction, Installment, RecurringTransaction, Tag, User
├── Providers/RepositoryServiceProvider.php   # bindings interface → implementação
├── Repositories/             # CoreRepository + repositórios
└── Services/                 # regras de negócio (saldo, parcelas, recorrência, dashboard)

resources/js/
├── pages/                    # welcome (login), dashboard, transactions/index
├── components/phamani/       # dashboard, modal, drawer, dropdown, list, ui (Button, Card, Badge, Chart)
├── components/ui/            # shadcn (avatar, dialog, dropdown-menu, label, button)
├── hooks/                    # use-transaction-form, use-accounts-form, use-category-form, use-enums, use-auth
├── lib/                      # format, category/icons|colors, transaction-dates|math
└── types/                    # tipos de domínio e das props compartilhadas do Inertia
```

Rotas (`routes/web.php`):

| Método | URI                     | Nome                  |
| ------ | ----------------------- | --------------------- |
| GET    | `/`                     | `login`               |
| GET    | `/auth/google/redirect` | `auth.google.redirect`|
| GET    | `/auth/google/callback` | `auth.google.callback`|
| POST   | `/logout`               | `logout`              |
| GET    | `/dashboard`            | `dashboard`           |
| GET    | `/transactions`         | `transactions.index`  |
| POST   | `/transactions`         | `transactions.store`  |
| POST   | `/accounts`             | `accounts.store`      |
| POST   | `/categories`           | `categories.store`    |

## O que mudou em relação ao módulo do Lukisa

**Separação**
- Sem `nwidart/laravel-modules`: tudo em `App\…`. Tabelas no schema padrão do banco próprio (o `ModuleBaseModel`/schema `phamani` deixou de ser necessário).
- `UserObserver` + `DefaultAccountsSeeder` + `CategorySeeder` → um único listener no evento `Registered`.
- Enums compartilhados pelo `HandleInertiaRequests` do app (antes o `Inertia::share` do provider do módulo vazava para o Lukisa inteiro).

**Atualizações**
- Laravel 12 → 13, Inertia 2 → 3 (sem Axios; flash via `Inertia::flash()` + evento `flash`), Vite 6 → Vite+, Ziggy → Wayfinder, React Compiler.
- Estrutura de pastas e nomes no padrão atual do starter kit (kebab-case, `pages/`, `components/`).

**Correções**
- **Segurança:** `account_id`, `category_id` e `parent_id` agora são validados como pertencentes ao usuário logado (antes dava para lançar em conta de outro usuário).
- Saldo atualizado com `UPDATE ... balance = balance + ?` (atômico, sem condição de corrida).
- Parcelas: centavos de arredondamento vão para a última parcela (soma sempre bate com o total); nova coluna `installment_number`; datas com `addMonthsNoOverflow` (31/01 + 1 mês = 28/02, não 03/03).
- `categories.user_id` era `NOT NULL` com `nullOnDelete` (contraditório) → `cascadeOnDelete`. Categoria padrão "Outros" usava a cor `gray`, que não existe no enum → `slate`.
- `DashboardService` não tem mais `phamani.categories` fixo no SQL e a agregação ficou portável (Postgres/SQLite). Gráfico de pizza recebe a cor em hex.
- "Recentes" no dashboard ignora parcelas futuras. Trocar Mensal/Anual atualiza também o gráfico de categorias.
- Frontend: a cor/ícone das categorias eram usados como CSS direto (`backgroundColor: 'orange'`) → agora resolvidos pelo mapa; preview da transação passou a mostrar categoria e conta; datas sem bug de fuso (`new Date('2026-01-01')` virava 31/12).
- Página **Transações** usa dados reais (antes era mock), com filtros por conta, categoria, tipo e mês, paginação e linha do tempo real das parcelas.
- Removidos: métodos de controller vazios/`view('phamani::...')` inexistentes, `api.php` placeholder, contexts não usados.

## Testes e qualidade

```bash
docker compose exec app php artisan test     # PHPUnit (SQLite em memória)
docker compose exec app npm run types:check  # TypeScript
docker compose exec app npm run check        # lint + formatação (Vite+)
docker compose exec app composer lint        # Pint
```

## Próximos passos sugeridos

- Comando agendado para processar recorrências (`next_run`) e aplicar no saldo as parcelas que vencerem.
- Editar/excluir transação (com estorno do saldo).
- Gerenciar contas e categorias (editar/excluir).
- Busca por texto na página de transações.
