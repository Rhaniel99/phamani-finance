#!/usr/bin/env bash
# Phamani — Tags livres nas transações (ex.: "iFood", "Amazon", "viagem-floripa")
#  - Campo "Tags" no formulário (abaixo da descrição): Enter/vírgula vira chip, sugestões das que você já usa.
#    "ifood", "iFood" e "IFOOD" são a mesma tag (comparação sem maiúsculas/acentos).
#  - Parcelado: todas as parcelas recebem as tags. Recorrente: as próximas ocorrências copiam da última.
#  - Lista de transações: chips nas linhas e filtro "Tag" (o resumo do mês segue o filtro).
#  - Drawer e pré-visualização mostram as tags.
#  - Menu do avatar → "Tags": renomear, juntar (renomeando para um nome existente) e apagar.
#  - Pessoais: não vão junto nas divisões compartilhadas.
# Migration: tags ganham "slug" (as tabelas já existiam, sem uso).
# Uso: na raiz do projeto ->  bash tags.sh
set -euo pipefail
[ -f artisan ] && [ -f app/Models/Tag.php ] || { echo "Rode na raiz do projeto Phamani."; exit 1; }
BACKUP=".backup-$(date +%Y%m%d%H%M%S)"
backup() { if [ -f "$1" ]; then mkdir -p "$BACKUP/$(dirname "$1")"; cp "$1" "$BACKUP/$1"; fi; }
write() { backup "$1"; mkdir -p "$(dirname "$1")"; cat > "$1"; echo "  ok  $1"; }
echo "Aplicando arquivos (backup em $BACKUP/):"

write 'app/DTOs/Transaction/StoreTransactionData.php' <<'PHAMANI_EOF'
<?php

namespace App\DTOs\Transaction;

use App\Enums\RecurringFrequency;
use Illuminate\Support\Facades\Auth;
use Illuminate\Validation\Rule;
use Spatie\LaravelData\Attributes\Validation\Date;
use Spatie\LaravelData\Attributes\Validation\In;
use Spatie\LaravelData\Attributes\Validation\Max;
use Spatie\LaravelData\Attributes\Validation\Min;
use Spatie\LaravelData\Attributes\Validation\RequiredIf;
use Spatie\LaravelData\Data;

class StoreTransactionData extends Data
{
    public function __construct(
        #[Max(255)]
        public string $description,

        #[Min(0.01)]
        public float $amount,

        #[In(['income', 'expense'])]
        public string $type,

        public string $category_id,

        /** Null quando outra pessoa pagou (divisão). */
        public ?string $account_id,

        #[Date]
        public string $date,

        public bool $is_installment = false,

        #[RequiredIf('is_installment', true), Min(2), Max(360)]
        public ?int $installments_count = null,

        /** Número da primeira parcela a lançar (ex.: 15 num parcelamento já na 15/24). */
        #[Min(1), Max(360)]
        public int $installment_start = 1,

        /** 'total' = valor informado é o total; 'installment' = é o valor de cada parcela. */
        #[In(['total', 'installment'])]
        public string $amount_mode = 'total',

        /** Divisão com contatos (null = sem divisão). */
        public ?SplitData $split = null,

        /** Débito automático (parcelado/recorrente): no vencimento já marca como pago. */
        public bool $auto_pay = false,

        public bool $is_recurring = false,

        #[RequiredIf('is_recurring', true)]
        public ?RecurringFrequency $frequency = null,

        /** Tags livres (ex.: "iFood"). Criadas na hora se não existirem. @var list<string> */
        public array $tags = [],
    ) {}

    /**
     * Conta e categoria precisam pertencer ao usuário autenticado.
     *
     * @return array<string, array<int, mixed>>
     */
    public static function rules(): array
    {
        return [
            'category_id' => [
                'required', 'uuid',
                Rule::exists('categories', 'id')->where('user_id', Auth::id()),
            ],
            // Obrigatória, a não ser que outra pessoa tenha pago (divisão com "quem pagou").
            'account_id' => [
                Rule::requiredIf(fn () => ! filled(request()->input('split.paid_by_contact_id'))),
                'nullable', 'uuid',
                Rule::exists('accounts', 'id')->where('user_id', Auth::id()),
            ],
            'tags' => ['array', 'max:10'],
            'tags.*' => ['string', 'max:40'],
        ];
    }
}
PHAMANI_EOF

write 'app/DTOs/Transaction/UpdateTransactionData.php' <<'PHAMANI_EOF'
<?php

namespace App\DTOs\Transaction;

use Illuminate\Support\Facades\Auth;
use Illuminate\Validation\Rule;
use Spatie\LaravelData\Attributes\Validation\Date;
use Spatie\LaravelData\Attributes\Validation\In;
use Spatie\LaravelData\Attributes\Validation\Max;
use Spatie\LaravelData\Attributes\Validation\Min;
use Spatie\LaravelData\Data;

/**
 * Edição de uma única transação (ou de uma parcela isolada).
 * Parcelamento e recorrência não são alterados por aqui.
 */
class UpdateTransactionData extends Data
{
    public function __construct(
        #[Max(255)]
        public string $description,

        #[Min(0.01)]
        public float $amount,

        #[In(['income', 'expense'])]
        public string $type,

        public string $category_id,

        /** Null quando outra pessoa pagou (divisão). */
        public ?string $account_id,

        #[Date]
        public string $date,

        /** Só para parcelas: repete o novo valor nas parcelas seguintes. */
        public bool $apply_to_following = false,

        /** Divisão com contatos (null = sem divisão). */
        public ?SplitData $split = null,

        /** Tags livres. Null = não mexe nas tags. @var list<string>|null */
        public ?array $tags = null,
    ) {}

    /**
     * Conta e categoria precisam pertencer ao usuário autenticado.
     *
     * @return array<string, array<int, mixed>>
     */
    public static function rules(): array
    {
        return [
            'category_id' => [
                'required', 'uuid',
                Rule::exists('categories', 'id')->where('user_id', Auth::id()),
            ],
            // Obrigatória, a não ser que outra pessoa tenha pago (divisão com "quem pagou").
            'account_id' => [
                Rule::requiredIf(fn () => ! filled(request()->input('split.paid_by_contact_id'))),
                'nullable', 'uuid',
                Rule::exists('accounts', 'id')->where('user_id', Auth::id()),
            ],
            'tags' => ['nullable', 'array', 'max:10'],
            'tags.*' => ['string', 'max:40'],
        ];
    }
}
PHAMANI_EOF

write 'app/Http/Controllers/CreditCardController.php' <<'PHAMANI_EOF'
<?php

namespace App\Http\Controllers;

use App\DTOs\CreditCard\PayInvoiceData;
use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\ICategoryService;
use App\Interfaces\Services\ICreditCardService;
use App\Models\Account;
use App\Models\CreditCardInvoice;
use App\Models\Transaction;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

class CreditCardController extends Controller
{
    public function __construct(
        protected ICreditCardService $cards,
        protected IAccountService $accountService,
        protected ICategoryService $categoryService,
    ) {}

    /**
     * Página do cartão: limite, faturas e as compras da fatura selecionada.
     */
    public function show(Request $request, Account $account): Response
    {
        $userId = $this->ensureOwner($request, $account->user_id);
        abort_unless($account->isCreditCard(), 404);

        $invoices = $this->cards->invoicesFor($account);
        $summary = $this->cards->summary($account);

        // Seleção: ?invoice=… ou a fatura atual (ou a mais recente, se a atual ainda não existir).
        $selectedId = $request->string('invoice')->toString()
            ?: ($summary['current_invoice']['id'] ?? null)
            ?: ($invoices[0]['id'] ?? null);

        $selected = collect($invoices)->firstWhere('id', $selectedId);

        return Inertia::render('cards/show', [
            'card' => [
                ...$account->only(['id', 'name', 'type', 'credit_limit', 'closing_day', 'due_day', 'payment_account_id']),
                'card' => $summary,
            ],
            'invoices' => $invoices,
            'selectedInvoice' => $selected,
            'transactions' => fn () => $selected === null ? [] : Transaction::query()
                ->where('user_id', $userId)
                ->where('invoice_id', $selected['id'])
                ->with([
                    'account:id,name,type',
                    'category:id,name,color,icon',
                'splits:id,transaction_id,contact_id,amount,reimbursed_at,reimbursement_account_id,reimbursed_amount',
                'splits.contact:id,name',
                'splits.reimbursementAccount:id,name',
                'tags:id,name',
                'paidBy:id,name,linked_user_id',
                'mirroredFrom:id,user_id,total_amount,paid_by_contact_id',
                'mirroredFrom.user:id,name,avatar',
                'mirroredFrom.paidBy:id,name,linked_user_id',
                'mirroredFrom.splits:id,transaction_id,contact_id,amount',
                'mirroredFrom.splits.contact:id,name,linked_user_id',
                'shareLinks:id,share_id,source_transaction_id,mirror_transaction_id',
                'shareLinks.share:id,status,owner_contact_id',
                    'recurring:id,frequency,end_date,auto_pay',
                    'installment:id,name,installments,installment_amount,total_amount,auto_pay',
                    'installment.transactions:id,installment_id,installment_number,date,amount',
                ])
                ->orderByDesc('date')
                ->orderByDesc('created_at')
                ->get(),
            'accounts' => fn () => $this->accountService->listForUser($userId),
            'categories' => fn () => $this->categoryService->listForUser($userId),
        ]);
    }

    public function pay(Request $request, CreditCardInvoice $invoice, PayInvoiceData $data): RedirectResponse
    {
        $this->ensureOwner($request, $invoice->user_id);

        $this->cards->pay($invoice, $data->account_id, $data->date);

        Inertia::flash('toast', ['type' => 'success', 'message' => 'Fatura paga!']);

        return back();
    }

    public function undo(Request $request, CreditCardInvoice $invoice): RedirectResponse
    {
        $this->ensureOwner($request, $invoice->user_id);

        $this->cards->undoPayment($invoice);

        Inertia::flash('toast', ['type' => 'success', 'message' => 'Pagamento desfeito.']);

        return back();
    }

    /**
     * 404 (e não 403) para não revelar que o recurso de outro usuário existe.
     */
    private function ensureOwner(Request $request, string $ownerId): string
    {
        $userId = (string) $request->user()?->getAuthIdentifier();

        abort_unless($ownerId === $userId, 404);

        return $userId;
    }
}
PHAMANI_EOF

write 'app/Http/Controllers/TagController.php' <<'PHAMANI_EOF'
<?php

namespace App\Http\Controllers;

use App\Interfaces\Services\ITagService;
use App\Models\Tag;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;

/**
 * Gerenciar tags: renomear (ou juntar duas) e apagar. Criar é pelo formulário da transação.
 */
class TagController extends Controller
{
    public function __construct(
        protected ITagService $tags,
    ) {}

    public function update(Request $request, Tag $tag): RedirectResponse
    {
        $this->ensureOwner($request, $tag);

        $data = $request->validate(['name' => ['required', 'string', 'max:40']]);

        $merged = $this->tags->slug($data['name']) !== $tag->slug
            && Tag::query()->where('user_id', $tag->user_id)->where('slug', $this->tags->slug($data['name']))->exists();

        $this->tags->rename($tag, $data['name']);

        Inertia::flash('toast', ['type' => 'success', 'message' => $merged ? 'Tags juntadas!' : 'Tag renomeada!']);

        return back();
    }

    public function destroy(Request $request, Tag $tag): RedirectResponse
    {
        $this->ensureOwner($request, $tag);

        $this->tags->delete($tag);

        Inertia::flash('toast', ['type' => 'success', 'message' => 'Tag apagada (as transações continuam).']);

        return back();
    }

    private function ensureOwner(Request $request, Tag $tag): void
    {
        abort_unless($tag->user_id === (string) $request->user()?->getAuthIdentifier(), 404);
    }
}
PHAMANI_EOF

write 'app/Http/Controllers/TransactionController.php' <<'PHAMANI_EOF'
<?php

namespace App\Http\Controllers;

use App\DTOs\Transaction\StoreTransactionData;
use App\DTOs\Transaction\UpdateTransactionData;
use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\ICategoryService;
use App\Interfaces\Services\IPaymentService;
use App\Interfaces\Services\ITransactionService;
use App\Models\Transaction;
use App\Models\User;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Inertia\Inertia;
use Inertia\Response;

class TransactionController extends Controller
{
    public function __construct(
        protected ITransactionService $service,
        protected IAccountService $accountService,
        protected ICategoryService $categoryService,
    ) {}

    public function index(Request $request): Response
    {
        $userId = (string) $request->user()?->getAuthIdentifier();

        $filters = $request->validate([
            'account_id' => ['nullable', 'uuid'],
            'category_id' => ['nullable', 'uuid'],
            'tag_id' => ['nullable', 'uuid'],
            'type' => ['nullable', Rule::in(['income', 'expense'])],
            'month' => ['nullable', 'date_format:Y-m'],
            'all' => ['nullable', 'boolean'],
            'search' => ['nullable', 'string', 'max:100'],
            'kind' => ['nullable', Rule::in(['split', 'installment', 'recurring', 'shared'])],
            'status' => ['nullable', Rule::in(['paid', 'pending', 'overdue'])],
        ]);

        // Padrão: um mês por vez (o atual). "Todo o período" só com all=1.
        $all = (bool) ($filters['all'] ?? false);
        if ($all) {
            unset($filters['month']);
        } else {
            $filters['month'] ??= now()->format('Y-m');
        }
        unset($filters['all']);

        return Inertia::render('transactions/index', [
            'filters' => (object) array_filter([...$filters, 'all' => $all ? '1' : null]),
            // Um mês cabe inteiro; "todo o período" vem em páginas de 50 ("carregar mais").
            'transactions' => fn () => $this->service->paginateForUser($userId, $filters, $all ? 50 : 500),
            'summary' => fn () => $all ? null : $this->service->summaryForUser($userId, $filters),
            'accounts' => fn () => $this->accountService->listForUser($userId),
            'categories' => fn () => $this->categoryService->listForUser($userId),
        ]);
    }

    public function store(Request $request, StoreTransactionData $data): RedirectResponse
    {
        $this->service->create((string) $request->user()?->getAuthIdentifier(), $data);

        Inertia::flash('toast', ['type' => 'success', 'message' => 'Transação criada com sucesso!']);

        return back();
    }

    public function update(Request $request, Transaction $transaction, UpdateTransactionData $data): RedirectResponse
    {
        $this->ensureOwner($request, $transaction);

        if ($redirect = $this->rejectMirror($transaction)) {
            return $redirect;
        }

        $this->service->update($transaction, $data);

        Inertia::flash('toast', ['type' => 'success', 'message' => 'Transação atualizada!']);

        return back();
    }

    /**
     * Marca como paga (ou recebida). Só quem pagou pode marcar; vale para todos da divisão.
     */
    public function pay(Request $request, Transaction $transaction, IPaymentService $payments): RedirectResponse
    {
        $this->ensureOwner($request, $transaction);

        /** @var User $user */
        $user = $request->user();
        $payments->markPaid($transaction, $user);

        Inertia::flash('toast', [
            'type' => 'success',
            'message' => $transaction->type === 'income' ? 'Marcada como recebida.' : 'Marcada como paga.',
        ]);

        return back();
    }

    public function unpay(Request $request, Transaction $transaction, IPaymentService $payments): RedirectResponse
    {
        $this->ensureOwner($request, $transaction);

        /** @var User $user */
        $user = $request->user();
        $payments->markUnpaid($transaction, $user);

        Inertia::flash('toast', ['type' => 'success', 'message' => 'Voltou para pendente.']);

        return back();
    }

    public function destroy(Request $request, Transaction $transaction): RedirectResponse
    {
        $this->ensureOwner($request, $transaction);

        if ($redirect = $this->rejectMirror($transaction)) {
            return $redirect;
        }

        $isInstallment = $transaction->installment_id !== null;

        $this->service->delete($transaction);

        Inertia::flash('toast', [
            'type' => 'success',
            'message' => $isInstallment ? 'Parcelamento excluído.' : 'Transação excluída.',
        ]);

        return back();
    }

    /**
     * Cópia de divisão compartilhada: só quem criou edita. Quem recebeu pode sair da divisão em Pendências.
     */
    private function rejectMirror(Transaction $transaction): ?RedirectResponse
    {
        if (! $transaction->isMirror()) {
            return null;
        }

        Inertia::flash('toast', [
            'type' => 'error',
            'message' => 'Esta divisão foi compartilhada com você: só quem criou pode alterar. Você pode sair dela em Pendências.',
        ]);

        return back();
    }

    /**
     * Responde 404 (e não 403) para não revelar que a transação de outro usuário existe.
     */
    private function ensureOwner(Request $request, Transaction $transaction): void
    {
        abort_unless($transaction->user_id === (string) $request->user()?->getAuthIdentifier(), 404);
    }
}
PHAMANI_EOF

write 'app/Http/Middleware/HandleInertiaRequests.php' <<'PHAMANI_EOF'
<?php

namespace App\Http\Middleware;

use App\Enums\Category\Color;
use App\Enums\Category\Icon;
use App\Enums\EnumOptions;
use App\Enums\RecurringFrequency;
use App\Interfaces\Services\IContactService;
use App\Interfaces\Services\IInvitationService;
use App\Interfaces\Services\ITagService;
use App\Models\Share;
use Illuminate\Http\Request;
use Inertia\Middleware;

class HandleInertiaRequests extends Middleware
{
    /**
     * @var string
     */
    protected $rootView = 'app';

    public function version(Request $request): ?string
    {
        return parent::version($request);
    }

    /**
     * @return array<string, mixed>
     */
    public function share(Request $request): array
    {
        $user = $request->user();

        return [
            ...parent::share($request),
            'name' => config('app.name'),
            'auth' => [
                'user' => $user ? [
                    'id' => $user->id,
                    'name' => $user->name,
                    'email' => $user->email,
                    'avatar' => $user->avatar,
                ] : null,
            ],
            // Contatos para a divisão de contas (usados no formulário de transação em várias páginas).
            'contacts' => fn () => $user ? app(IContactService::class)->listForUser((string) $user->id) : [],
            // Tags do usuário: sugestões no formulário, filtro da lista e "Gerenciar tags".
            'tags' => fn () => $user ? app(ITagService::class)->listForUser((string) $user->id) : [],
            // Sino do cabeçalho. Hoje atualizado por polling (usePoll); com Reverb, um listener do Echo
            // só precisa recarregar esta mesma prop.
            'notifications' => fn () => $user ? [
                'unread' => $user->unreadNotifications()->count(),
                'pending' => app(IInvitationService::class)->pendingFor($user)->count()
                    + Share::query()->where('recipient_user_id', $user->id)->where('status', 'pending')->count(),
                'latest' => $user->notifications()->latest()->limit(8)->get(['id', 'data', 'read_at', 'created_at']),
            ] : null,
            // Listas de enums usadas pelos formulários (antes eram compartilhadas pelo provider do módulo).
            'enums' => fn () => $user ? [
                'recurringFrequencies' => EnumOptions::from(RecurringFrequency::class),
                'categoryIcons' => EnumOptions::from(Icon::class),
                'categoryColors' => EnumOptions::from(Color::class, fn (Color $c) => ['hex' => $c->hex()]),
            ] : null,
        ];
    }
}
PHAMANI_EOF

write 'app/Interfaces/Services/ITagService.php' <<'PHAMANI_EOF'
<?php

namespace App\Interfaces\Services;

use App\Models\Tag;
use App\Models\Transaction;
use Illuminate\Support\Collection;

/**
 * Tags livres das transações. Pessoais de cada usuário; comparação sem maiúsculas/acentos.
 */
interface ITagService
{
    /**
     * Tags do usuário com quantas transações cada uma tem.
     *
     * @return Collection<int, Tag>
     */
    public function listForUser(string $userId): Collection;

    /**
     * Define as tags das transações (cria as que não existem).
     *
     * @param  iterable<Transaction>  $transactions
     * @param  list<string>  $names
     */
    public function syncFor(iterable $transactions, string $userId, array $names): void;

    /** Copia as tags de uma ocorrência para a próxima (recorrências). */
    public function copy(Transaction $from, Transaction $to): void;

    /** Renomeia; se já existir outra com o mesmo nome, as duas viram uma só. */
    public function rename(Tag $tag, string $name): Tag;

    public function delete(Tag $tag): void;

    /** Nome normalizado usado na comparação ("Ifood" = "iFood" = "ifood"). */
    public function slug(string $name): string;
}
PHAMANI_EOF

write 'app/Models/Tag.php' <<'PHAMANI_EOF'
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Relations\BelongsToMany;

/**
 * Tag livre de uma transação (pessoal: não vai junto nas divisões compartilhadas).
 * slug = nome normalizado, usado para não duplicar "iFood"/"ifood".
 *
 * @property string $id
 * @property string $user_id
 * @property string $name
 * @property string|null $slug
 * @property string|null $color
 */
class Tag extends BaseModel
{
    protected $fillable = [
        'user_id',
        'name',
        'slug',
        'color',
    ];

    protected $hidden = ['pivot'];

    /** @return BelongsToMany<Transaction, $this> */
    public function transactions(): BelongsToMany
    {
        return $this->belongsToMany(Transaction::class, 'transaction_tags');
    }
}
PHAMANI_EOF

write 'app/Providers/RepositoryServiceProvider.php' <<'PHAMANI_EOF'
<?php

namespace App\Providers;

use App\Interfaces\Repositories\IAccountRepository;
use App\Interfaces\Repositories\ICategoryRepository;
use App\Interfaces\Repositories\IContactRepository;
use App\Interfaces\Repositories\IInstallmentRepository;
use App\Interfaces\Repositories\IRecurringTransactionRepository;
use App\Interfaces\Repositories\ITransactionRepository;
use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\IBalanceService;
use App\Interfaces\Services\ICategoryService;
use App\Interfaces\Services\IContactService;
use App\Interfaces\Services\ICreditCardService;
use App\Interfaces\Services\IDashboardService;
use App\Interfaces\Services\IInstallmentService;
use App\Interfaces\Services\IInvitationService;
use App\Interfaces\Services\IPaymentService;
use App\Interfaces\Services\IRecurringTransactionService;
use App\Interfaces\Services\IReimbursementService;
use App\Interfaces\Services\ITagService;
use App\Interfaces\Services\IShareService;
use App\Interfaces\Services\ISplitService;
use App\Interfaces\Services\ITransactionService;
use App\Repositories\AccountRepository;
use App\Repositories\CategoryRepository;
use App\Repositories\ContactRepository;
use App\Repositories\InstallmentRepository;
use App\Repositories\RecurringTransactionRepository;
use App\Repositories\TransactionRepository;
use App\Services\AccountService;
use App\Services\BalanceService;
use App\Services\CategoryService;
use App\Services\ContactService;
use App\Services\CreditCardService;
use App\Services\DashboardService;
use App\Services\InstallmentService;
use App\Services\InvitationService;
use App\Services\PaymentService;
use App\Services\RecurringTransactionService;
use App\Services\ReimbursementService;
use App\Services\TagService;
use App\Services\ShareService;
use App\Services\SplitService;
use App\Services\TransactionService;
use Illuminate\Support\ServiceProvider;

/**
 * Liga as interfaces (contratos) às implementações de Services e Repositories.
 */
class RepositoryServiceProvider extends ServiceProvider
{
    /**
     * @var array<class-string, class-string>
     */
    public array $bindings = [
        // Services
        IAccountService::class => AccountService::class,
        IBalanceService::class => BalanceService::class,
        ICategoryService::class => CategoryService::class,
        IContactService::class => ContactService::class,
        ICreditCardService::class => CreditCardService::class,
        IDashboardService::class => DashboardService::class,
        IInstallmentService::class => InstallmentService::class,
        IInvitationService::class => InvitationService::class,
        IPaymentService::class => PaymentService::class,
        IRecurringTransactionService::class => RecurringTransactionService::class,
        IReimbursementService::class => ReimbursementService::class,
        ITagService::class => TagService::class,
        IShareService::class => ShareService::class,
        ISplitService::class => SplitService::class,
        ITransactionService::class => TransactionService::class,

        // Repositories
        IAccountRepository::class => AccountRepository::class,
        ICategoryRepository::class => CategoryRepository::class,
        IContactRepository::class => ContactRepository::class,
        IInstallmentRepository::class => InstallmentRepository::class,
        IRecurringTransactionRepository::class => RecurringTransactionRepository::class,
        ITransactionRepository::class => TransactionRepository::class,
    ];
}
PHAMANI_EOF

write 'app/Repositories/TransactionRepository.php' <<'PHAMANI_EOF'
<?php

namespace App\Repositories;

use App\Interfaces\Repositories\ITransactionRepository;
use App\Models\Transaction;
use App\Repositories\Base\CoreRepository;
use Carbon\CarbonImmutable;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Collection;

class TransactionRepository extends CoreRepository implements ITransactionRepository
{
    public function __construct(Transaction $model)
    {
        parent::__construct($model);
    }

    public function getLatestForUser(string $userId, int $limit = 5): Collection
    {
        // "Recentes" = últimas lançadas, inclusive com data futura (agendadas).
        // De um parcelamento entra só a 1ª parcela lançada (que pode ser a 15/24),
        // para não lotar a lista com as futuras.
        return $this->query()
            ->where('user_id', $userId)
            ->where(fn ($q) => $q
                ->whereNull('installment_id')
                ->orWhere('installment_number', '=', fn ($sub) => $sub
                    ->selectRaw('min(t2.installment_number)')
                    ->from('transactions as t2')
                    ->whereColumn('t2.installment_id', 'transactions.installment_id')))
            ->with([
                'account:id,name,type',
                'category:id,name,color,icon',
                'splits:id,transaction_id,contact_id,amount,reimbursed_at,reimbursement_account_id,reimbursed_amount',
                'splits.contact:id,name',
                'splits.reimbursementAccount:id,name',
                'tags:id,name',
                'paidBy:id,name,linked_user_id',
            ])
            ->orderByDesc('created_at')
            ->orderByDesc('date')
            ->limit($limit)
            ->get();
    }

    public function deleteByInstallment(string $installmentId): void
    {
        $this->query()->where('installment_id', $installmentId)->delete();
    }

    /**
     * Filtros da tela de transações, compartilhados pela lista e pelo resumo do mês.
     *
     * @param  array{account_id?: ?string, category_id?: ?string, tag_id?: ?string, type?: ?string, month?: ?string, search?: ?string, kind?: ?string}  $filters
     */
    private function filtered(string $userId, array $filters): Builder
    {
        return $this->query()
            ->where('user_id', $userId)
            ->when($filters['account_id'] ?? null, fn ($q, $id) => $q->where('account_id', $id))
            ->when($filters['category_id'] ?? null, fn ($q, $id) => $q->where('category_id', $id))
            ->when($filters['tag_id'] ?? null, fn ($q, $id) => $q->whereHas('tags', fn ($t) => $t->whereKey($id)))
            ->when($filters['type'] ?? null, fn ($q, $type) => $q->where('type', $type))
            ->when($filters['month'] ?? null, function ($q, string $month) {
                $start = CarbonImmutable::createFromFormat('!Y-m', $month);

                // whereDate: compara só a data em qualquer banco (inclui o último dia do mês).
                $q->whereDate('date', '>=', $start->startOfMonth()->toDateString())
                    ->whereDate('date', '<=', $start->endOfMonth()->toDateString());
            })
            ->when($filters['search'] ?? null, function ($q, string $search) {
                $term = '%'.mb_strtolower(trim($search)).'%';

                $q->where(fn ($w) => $w
                    ->whereRaw('lower(name) like ?', [$term])
                    ->orWhereRaw('lower(description) like ?', [$term]));
            })
            ->when($filters['status'] ?? null, function ($q, string $status) {
                $today = now()->toDateString();

                match ($status) {
                    'paid' => $q->whereNotNull('paid_at'),
                    'pending' => $q->whereNull('paid_at')->whereDate('date', '>=', $today),
                    'overdue' => $q->whereNull('paid_at')->whereDate('date', '<', $today),
                    default => null,
                };
            })
            ->when($filters['kind'] ?? null, fn ($q, string $kind) => match ($kind) {
                'split' => $q->whereNotNull('total_amount'),
                'installment' => $q->whereNotNull('installment_id'),
                'recurring' => $q->whereNotNull('recurring_id'),
                'shared' => $q->whereNotNull('mirrored_from_id'),
                default => $q,
            });
    }

    public function summaryForUser(string $userId, array $filters): array
    {
        $today = now()->toDateString();

        $income = (float) $this->filtered($userId, $filters)->where('type', 'income')->sum('amount');
        $expense = (float) $this->filtered($userId, $filters)->where('type', 'expense')->sum('amount');
        // Não pagas (cartão fica de fora: a dívida está na fatura).
        $unpaid = fn () => $this->filtered($userId, $filters)
            ->where('type', 'expense')
            ->whereNull('paid_at');

        $due = $unpaid()->whereDate('date', '>=', $today);
        $overdue = $unpaid()->whereDate('date', '<', $today);

        return [
            'income' => round($income, 2),
            'expense' => round($expense, 2),
            'balance' => round($income - $expense, 2),
            'due' => round((float) (clone $due)->sum('amount'), 2),
            'due_count' => (clone $due)->count(),
            'overdue' => round((float) (clone $overdue)->sum('amount'), 2),
            'overdue_count' => (clone $overdue)->count(),
            'count' => $this->filtered($userId, $filters)->count(),
        ];
    }

    public function paginateForUser(string $userId, array $filters = [], int $perPage = 20): LengthAwarePaginator
    {
        return $this->filtered($userId, $filters)
            ->with([
                'account:id,name,type',
                'category:id,name,color,icon',
                'splits:id,transaction_id,contact_id,amount,reimbursed_at,reimbursement_account_id,reimbursed_amount',
                'splits.contact:id,name',
                'splits.reimbursementAccount:id,name',
                'tags:id,name',
                'paidBy:id,name,linked_user_id',
                'mirroredFrom:id,user_id,total_amount,paid_by_contact_id',
                'mirroredFrom.user:id,name,avatar',
                'mirroredFrom.paidBy:id,name,linked_user_id',
                'mirroredFrom.splits:id,transaction_id,contact_id,amount',
                'mirroredFrom.splits.contact:id,name,linked_user_id',
                'shareLinks:id,share_id,source_transaction_id,mirror_transaction_id',
                'shareLinks.share:id,status,owner_contact_id',
                'recurring:id,frequency,end_date,auto_pay',
                'installment:id,name,installments,installment_amount,total_amount,auto_pay',
                'installment.transactions:id,installment_id,installment_number,date,amount',
            ])
            ->orderByDesc('date')
            ->orderByDesc('created_at')
            ->paginate($perPage)
            ->withQueryString();
    }
}
PHAMANI_EOF

write 'app/Services/RecurringTransactionService.php' <<'PHAMANI_EOF'
<?php

namespace App\Services;

use App\DTOs\Transaction\StoreTransactionData;
use App\Interfaces\Repositories\IRecurringTransactionRepository;
use App\Interfaces\Repositories\ITransactionRepository;
use App\Interfaces\Services\IBalanceService;
use App\Interfaces\Services\IRecurringTransactionService;
use App\Interfaces\Services\ISplitService;
use App\Interfaces\Services\ITagService;
use App\Models\RecurringTransaction;
use App\Models\Transaction;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;

class RecurringTransactionService implements IRecurringTransactionService
{
    public function __construct(
        protected IRecurringTransactionRepository $recurrings,
        protected ITransactionRepository $transactions,
        protected IBalanceService $balance,
        protected ISplitService $splits,
        protected ITagService $tags,
    ) {}

    public function createRecurringTransaction(string $userId, StoreTransactionData $dto): RecurringTransaction
    {
        return DB::transaction(function () use ($userId, $dto) {
            $frequency = $dto->frequency;
            $date = CarbonImmutable::parse($dto->date);
            $parts = $this->splits->compute($dto->amount, $dto->split);
            $accountId = $parts['paid_by_contact_id'] === null ? $dto->account_id : null;

            /** @var RecurringTransaction $recurring */
            $recurring = $this->recurrings->create([
                'user_id' => $userId,
                'account_id' => $accountId,
                'category_id' => $dto->category_id,
                'name' => $dto->description,
                'amount' => $parts['amount'],
                'type' => $dto->type,
                'frequency' => $frequency,
                'auto_pay' => $dto->auto_pay,
                'anchor_date' => $date->toDateString(),
                'next_run' => $frequency->nth($date, 1)->toDateString(),
            ]);

            // Primeira ocorrência
            /** @var Transaction $first */
            $first = $this->transactions->create([
                'user_id' => $userId,
                'account_id' => $accountId,
                'category_id' => $dto->category_id,
                'recurring_id' => $recurring->id,
                'name' => $dto->description,
                'description' => $dto->description,
                'type' => $dto->type,
                'amount' => $parts['amount'],
                'total_amount' => $parts['total_amount'],
                'paid_by_contact_id' => $parts['paid_by_contact_id'],
                'date' => $date->toDateString(),
            ]);

            $this->splits->sync($first, $parts['shares']);

            $this->balance->applyIfDue($first);

            // Se a 1ª data ficou no passado, já gera as ocorrências que faltam até hoje
            // (como é histórico que você está lançando agora, entram como pagas).
            $this->generateDue($recurring, markPaid: true);

            return $recurring;
        });
    }

    public function generateDue(RecurringTransaction $recurring, bool $markPaid = false): int
    {
        $today = now()->toDateString();
        $created = 0;

        while ($this->shouldRun($recurring, $today)) {
            DB::transaction(function () use ($recurring, $markPaid) {
                $runDate = $recurring->next_run->toImmutable();

                // "Último valor": conta, categoria, nome, valor, divisão e quem pagou seguem a ocorrência
                // mais recente, então uma correção feita num mês vira a base do mês seguinte.
                $last = Transaction::query()
                    ->where('recurring_id', $recurring->id)
                    ->orderByDesc('date')
                    ->orderByDesc('created_at')
                    ->first();

                $amount = $last !== null ? (float) $last->amount : (float) $recurring->amount;

                /** @var Transaction $occurrence */
                $occurrence = $this->transactions->create([
                    'user_id' => $recurring->user_id,
                    'account_id' => $last !== null ? $last->account_id : $recurring->account_id,
                    'category_id' => $last->category_id ?? $recurring->category_id,
                    'recurring_id' => $recurring->id,
                    'name' => $last->name ?? $recurring->name,
                    'description' => $last->description ?? $recurring->name,
                    'type' => $last->type ?? $recurring->type,
                    'amount' => $amount,
                    'total_amount' => $last?->total_amount,
                    'paid_by_contact_id' => $last?->paid_by_contact_id,
                    'date' => $runDate->toDateString(),
                    // Lançada no vencimento: pendente até alguém pagar (ou paga, com débito automático).
                    'paid_at' => $markPaid || $recurring->auto_pay ? $runDate->toDateString() : null,
                ]);

                if ($last !== null) {
                    $this->splits->copy($last, $occurrence);
                    $this->tags->copy($last, $occurrence);
                }

                $this->balance->applyIfDue($occurrence);

                $anchor = ($recurring->anchor_date ?? $runDate)->toImmutable();

                $recurring->forceFill([
                    'amount' => $amount,
                    'next_run' => $recurring->frequency->nextFromAnchor($anchor, $runDate)->toDateString(),
                ])->save();
            });

            $created++;
        }

        return $created;
    }

    public function generateAllDue(): int
    {
        $created = 0;

        RecurringTransaction::query()
            ->whereDate('next_run', '<=', now()->toDateString())
            ->where(fn ($q) => $q->whereNull('end_date')->orWhereColumn('end_date', '>=', 'next_run'))
            ->lazyById()
            ->each(function (RecurringTransaction $recurring) use (&$created) {
                $created += $this->generateDue($recurring);
            });

        return $created;
    }

    public function end(RecurringTransaction $recurring): void
    {
        $recurring->forceFill(['end_date' => now()->toDateString()])->save();
    }

    private function shouldRun(RecurringTransaction $recurring, string $today): bool
    {
        $next = $recurring->next_run->toDateString();

        if ($next > $today) {
            return false;
        }

        return $recurring->end_date === null || $next <= $recurring->end_date->toDateString();
    }
}
PHAMANI_EOF

write 'app/Services/TagService.php' <<'PHAMANI_EOF'
<?php

namespace App\Services;

use App\Interfaces\Services\ITagService;
use App\Models\Tag;
use App\Models\Transaction;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class TagService implements ITagService
{
    public function listForUser(string $userId): Collection
    {
        return Tag::query()
            ->where('user_id', $userId)
            ->withCount('transactions')
            ->orderBy('name')
            ->get(['id', 'name']);
    }

    public function syncFor(iterable $transactions, string $userId, array $names): void
    {
        $ids = $this->resolve($userId, $names);

        foreach ($transactions as $transaction) {
            $transaction->tags()->sync($ids);
        }
    }

    public function copy(Transaction $from, Transaction $to): void
    {
        $to->tags()->sync($from->tags()->pluck('tags.id')->all());
    }

    public function rename(Tag $tag, string $name): Tag
    {
        $name = $this->clean($name);
        $slug = $this->slug($name);

        $existing = Tag::query()
            ->where('user_id', $tag->user_id)
            ->where('slug', $slug)
            ->whereKeyNot($tag->id)
            ->first();

        if ($existing === null) {
            $tag->update(['name' => $name, 'slug' => $slug]);

            return $tag;
        }

        // Mesmo nome de outra tag: junta as duas (as transações passam para a existente).
        return DB::transaction(function () use ($tag, $existing, $name) {
            $transactionIds = DB::table('transaction_tags')->where('tag_id', $tag->id)->pluck('transaction_id');

            DB::table('transaction_tags')->insertOrIgnore(
                $transactionIds->map(fn ($id) => ['transaction_id' => $id, 'tag_id' => $existing->id])->all(),
            );

            $tag->delete();
            $existing->update(['name' => $name]);

            return $existing;
        });
    }

    public function delete(Tag $tag): void
    {
        $tag->delete();
    }

    public function slug(string $name): string
    {
        return Str::of($name)->ascii()->lower()->squish()->value();
    }

    /**
     * Ids das tags com esses nomes (cria as novas). Repetidas e vazias são ignoradas.
     *
     * @param  list<string>  $names
     * @return list<string>
     */
    private function resolve(string $userId, array $names): array
    {
        $bySlug = [];
        foreach ($names as $name) {
            $name = $this->clean($name);
            $slug = $this->slug($name);
            if ($slug !== '' && ! isset($bySlug[$slug])) {
                $bySlug[$slug] = $name;
            }
        }

        $ids = [];
        foreach ($bySlug as $slug => $name) {
            $ids[] = Tag::query()->firstOrCreate(
                ['user_id' => $userId, 'slug' => $slug],
                ['name' => $name],
            )->id;
        }

        return $ids;
    }

    private function clean(string $name): string
    {
        return Str::of($name)->squish()->limit(40, '')->value();
    }
}
PHAMANI_EOF

write 'app/Services/TransactionService.php' <<'PHAMANI_EOF'
<?php

namespace App\Services;

use App\DTOs\Transaction\StoreTransactionData;
use App\DTOs\Transaction\UpdateTransactionData;
use App\Interfaces\Repositories\ITransactionRepository;
use App\Interfaces\Services\IBalanceService;
use App\Interfaces\Services\IInstallmentService;
use App\Interfaces\Services\IRecurringTransactionService;
use App\Interfaces\Services\IReimbursementService;
use App\Interfaces\Services\IShareService;
use App\Interfaces\Services\ISplitService;
use App\Interfaces\Services\ITagService;
use App\Interfaces\Services\ITransactionService;
use App\Models\Account;
use App\Models\Installment;
use App\Models\RecurringTransaction;
use App\Models\Transaction;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

class TransactionService implements ITransactionService
{
    public function __construct(
        protected ITransactionRepository $repository,
        protected IBalanceService $balance,
        protected IInstallmentService $installmentService,
        protected IRecurringTransactionService $recurringService,
        protected ISplitService $splits,
        protected IShareService $shares,
        protected IReimbursementService $reimbursements,
        protected ITagService $tags,
    ) {}

    public function create(string $userId, StoreTransactionData $dto): Model
    {
        $this->splits->validate($dto->split, $dto->amount, $dto->type);

        return DB::transaction(function () use ($userId, $dto) {
            $created = $this->createRecord($userId, $dto);

            // Tags: na transação, em todas as parcelas ou na primeira ocorrência (as próximas copiam).
            if ($dto->tags !== []) {
                $this->tags->syncFor(match (true) {
                    $created instanceof Installment => Transaction::query()->where('installment_id', $created->id)->get(),
                    $created instanceof RecurringTransaction => Transaction::query()->where('recurring_id', $created->id)->get(),
                    default => [$created],
                }, $userId, $dto->tags);
            }

            return $created;
        });
    }

    private function createRecord(string $userId, StoreTransactionData $dto): Model
    {
        if ($dto->is_installment) {
            return $this->installmentService->createInstallment($userId, $dto);
        }

        if ($dto->is_recurring) {
            return $this->recurringService->createRecurringTransaction($userId, $dto);
        }

        return DB::transaction(function () use ($userId, $dto) {
            $parts = $this->splits->compute($dto->amount, $dto->split);

            /** @var Transaction $transaction */
            $transaction = $this->repository->create([
                'user_id' => $userId,
                // Se outra pessoa pagou, nenhuma conta sua é afetada.
                'account_id' => $parts['paid_by_contact_id'] === null ? $dto->account_id : null,
                'category_id' => $dto->category_id,
                'name' => $dto->description,
                'description' => $dto->description,
                'type' => $dto->type,
                'amount' => $parts['amount'],
                'total_amount' => $parts['total_amount'],
                'paid_by_contact_id' => $parts['paid_by_contact_id'],
                'date' => $dto->date,
            ]);

            $this->splits->sync($transaction, $parts['shares']);

            // Data futura: fica "agendada" e só entra no saldo quando a data chegar.
            $this->balance->applyIfDue($transaction);

            return $transaction;
        });
    }

    public function update(Transaction $transaction, UpdateTransactionData $dto): Transaction
    {
        $this->splits->validate($dto->split, $dto->amount, $dto->type);

        return DB::transaction(function () use ($transaction, $dto) {
            // Tira o efeito antigo (se havia) e reaplica com os dados novos, se a data já chegou.
            // Cobre troca de valor, de tipo, de conta e de data.
            $this->balance->revert($transaction);

            // Parcelas mantêm o sufixo "(n/total)" no nome.
            $name = $dto->description;
            if ($transaction->installment_id !== null && $transaction->installment !== null) {
                $name = "{$dto->description} ({$transaction->installment_number}/{$transaction->installment->installments})";
            }

            $parts = $this->splits->compute($dto->amount, $dto->split);
            $accountId = $parts['paid_by_contact_id'] === null ? $dto->account_id : null;

            $this->repository->update($transaction->id, [
                'account_id' => $accountId,
                'category_id' => $dto->category_id,
                'name' => $name,
                'description' => $dto->description,
                'type' => $dto->type,
                'amount' => $parts['amount'],
                'total_amount' => $parts['total_amount'],
                'paid_by_contact_id' => $parts['paid_by_contact_id'],
                'date' => $dto->date,
                'paid_at' => $this->paidAtAfterEdit($transaction, $dto->date, $accountId),
            ]);

            $transaction->refresh();
            $this->splits->sync($transaction, $parts['shares']);
            $this->balance->applyIfDue($transaction);

            $following = [];
            if ($dto->apply_to_following && $transaction->installment_id !== null) {
                $this->installmentService->updateFollowingParcels($transaction, $dto->amount, $dto->split);

                $following = Transaction::query()
                    ->where('installment_id', $transaction->installment_id)
                    ->where('installment_number', '>', $transaction->installment_number)
                    ->get()
                    ->all();
            }

            if ($dto->tags !== null) {
                $this->tags->syncFor([$transaction, ...$following], $transaction->user_id, $dto->tags);
            }

            return $transaction;
        });
    }

    /**
     * Ao mudar a data, o status volta à regra de criação:
     * data futura → pendente (não mexe no saldo); hoje/passada → paga na nova data; cartão → sempre paga.
     * Sem mudança de data, o status fica como está.
     */
    private function paidAtAfterEdit(Transaction $transaction, string $newDate, ?string $accountId): ?string
    {
        $newDate = Carbon::parse($newDate)->toDateString();
        $current = $transaction->paid_at?->toDateString();

        if ($transaction->date->toDateString() === $newDate) {
            return $current;
        }

        $isCard = $accountId !== null && Account::query()->whereKey($accountId)->value('type') === 'credit';

        return $isCard || $newDate <= now()->toDateString() ? $newDate : null;
    }

    public function delete(Transaction $transaction): void
    {
        if ($transaction->installment_id !== null && $transaction->installment !== null) {
            $this->installmentService->deleteInstallment($transaction->installment);

            return;
        }

        DB::transaction(function () use ($transaction) {
            // Quem aceitou a divisão perde a cópia.
            $this->shares->removeFor($transaction);
            $this->balance->revert($transaction);
            // Reembolsos já recebidos saem da conta junto com a compra.
            $this->reimbursements->revertFor($transaction);
            $this->repository->delete($transaction->id);
        });
    }

    public function getRecentForDashboard(string $userId, int $limit = 5): Collection
    {
        return $this->repository->getLatestForUser($userId, $limit);
    }

    public function paginateForUser(string $userId, array $filters = [], int $perPage = 20): LengthAwarePaginator
    {
        return $this->repository->paginateForUser($userId, $filters, $perPage);
    }

    public function summaryForUser(string $userId, array $filters): array
    {
        return $this->repository->summaryForUser($userId, $filters);
    }
}
PHAMANI_EOF

write 'database/migrations/2026_11_21_000100_add_slug_to_tags.php' <<'PHAMANI_EOF'
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

/**
 * Tags livres (ex.: "iFood", "Amazon", "viagem-floripa"), pessoais de cada usuário.
 * As tabelas já existiam (vieram do Lukisa, sem uso); aqui ganham o slug:
 * nome normalizado (minúsculas, sem acento) — evita "ifood", "iFood" e "IFOOD" separados.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tags', function (Blueprint $table) {
            $table->string('slug', 40)->nullable()->after('name');
        });

        foreach (DB::table('tags')->get(['id', 'name']) as $tag) {
            DB::table('tags')->where('id', $tag->id)->update([
                'slug' => Str::of($tag->name)->ascii()->lower()->squish()->limit(40, '')->value(),
            ]);
        }

        Schema::table('tags', function (Blueprint $table) {
            $table->dropUnique(['user_id', 'name']);
            $table->unique(['user_id', 'slug']);
        });

        Schema::table('transaction_tags', function (Blueprint $table) {
            $table->index('tag_id');
        });
    }

    public function down(): void
    {
        Schema::table('transaction_tags', function (Blueprint $table) {
            $table->dropIndex(['tag_id']);
        });

        Schema::table('tags', function (Blueprint $table) {
            $table->dropUnique(['user_id', 'slug']);
            $table->unique(['user_id', 'name']);
            $table->dropColumn('slug');
        });
    }
};
PHAMANI_EOF

write 'resources/js/components/phamani/dashboard/dashboard-header.tsx' <<'PHAMANI_EOF'
import { Link } from '@inertiajs/react';
import { ArrowLeft, Hash, Inbox, LogOut, Users, Wallet } from 'lucide-react';
import { useState } from 'react';
import type { ReactNode } from 'react';
import { ContactsModal } from '@/components/phamani/modal/contacts-modal';
import { TagsModal } from '@/components/phamani/modal/tags-modal';
import { NotificationsBell } from '@/components/phamani/notifications-bell';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import {
    DropdownMenu,
    DropdownMenuContent,
    DropdownMenuItem,
    DropdownMenuLabel,
    DropdownMenuSeparator,
    DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { useAuth } from '@/hooks/use-auth';
import { inbox } from '@/routes';

interface DashboardHeaderProps {
    title: string;
    subtitle?: string;
    onBack?: () => void;
    actions?: ReactNode;
}

export function DashboardHeader({
    title,
    subtitle,
    onBack,
    actions,
}: DashboardHeaderProps) {
    const { user, avatarUrl, name, logout } = useAuth();
    const [contactsOpen, setContactsOpen] = useState(false);
    const [tagsOpen, setTagsOpen] = useState(false);

    return (
        <header className="mb-10 flex items-center justify-between gap-4">
            <div className="flex items-center gap-4">
                {onBack && (
                    <button
                        type="button"
                        onClick={onBack}
                        aria-label="Voltar"
                        className="-ml-2 rounded-xl border-2 border-transparent p-2 text-[#6B4F3A] transition-colors hover:border-[#E8DCC4] hover:bg-[#E8DCC4]"
                    >
                        <ArrowLeft className="h-6 w-6" />
                    </button>
                )}

                <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-[#6B4F3A] text-[#F5EFE6] shadow-lg">
                    <Wallet className="h-6 w-6" />
                </div>

                <div>
                    <h1 className="text-2xl font-bold text-[#3D2817]">
                        {title}
                    </h1>
                    {subtitle && (
                        <p className="text-sm text-[#8B7355]">{subtitle}</p>
                    )}
                </div>
            </div>

            <div className="flex items-center gap-4">
                {actions}

                <NotificationsBell />

                <DropdownMenu>
                    <DropdownMenuTrigger asChild>
                        <button
                            type="button"
                            aria-label="Menu do usuário"
                            className="rounded-full"
                        >
                            <Avatar className="h-12 w-12 border-2 border-[#E8DCC4]">
                                <AvatarImage
                                    src={avatarUrl ?? undefined}
                                    alt={name ?? ''}
                                    referrerPolicy="no-referrer"
                                />
                                <AvatarFallback className="bg-[#E8DCC4] font-bold text-[#6B4F3A]">
                                    {name?.charAt(0).toUpperCase() ?? 'U'}
                                </AvatarFallback>
                            </Avatar>
                        </button>
                    </DropdownMenuTrigger>

                    <DropdownMenuContent
                        align="end"
                        className="w-56 rounded-xl"
                    >
                        <DropdownMenuLabel className="font-normal">
                            <p className="text-sm font-semibold text-[#3D2817]">
                                {user?.name}
                            </p>
                            <p className="truncate text-xs text-[#8B7355]">
                                {user?.email}
                            </p>
                        </DropdownMenuLabel>
                        <DropdownMenuSeparator />
                        <DropdownMenuItem asChild className="cursor-pointer">
                            <Link href={inbox.url()}>
                                <Inbox className="mr-2" />
                                Pendências
                            </Link>
                        </DropdownMenuItem>
                        <DropdownMenuItem
                            onSelect={() => setContactsOpen(true)}
                            className="cursor-pointer"
                        >
                            <Users className="mr-2" />
                            Contatos
                        </DropdownMenuItem>
                        <DropdownMenuItem
                            onSelect={() => setTagsOpen(true)}
                            className="cursor-pointer"
                        >
                            <Hash className="mr-2" />
                            Tags
                        </DropdownMenuItem>
                        <DropdownMenuItem
                            onSelect={logout}
                            className="cursor-pointer"
                        >
                            <LogOut className="mr-2" />
                            Sair
                        </DropdownMenuItem>
                    </DropdownMenuContent>
                </DropdownMenu>
            </div>
            <ContactsModal open={contactsOpen} onOpenChange={setContactsOpen} />
            <TagsModal open={tagsOpen} onOpenChange={setTagsOpen} />
        </header>
    );
}
PHAMANI_EOF

write 'resources/js/components/phamani/drawer/show-transaction-drawer.tsx' <<'PHAMANI_EOF'
import { Link, router } from '@inertiajs/react';
import {
    ArrowRight,
    Calendar,
    Check,
    CreditCard,
    Pencil,
    Repeat,
    Tag,
    Trash2,
    X,
} from 'lucide-react';
import { AnimatePresence, motion } from 'motion/react';
import { useState } from 'react';
import { SplitDetails } from '@/components/phamani/drawer/split-details';
import { PaymentStatusBadge } from '@/components/phamani/payment-status-badge';
import { canMarkPaid, payerName, paymentStatus } from '@/lib/payment';
import { InstallmentModal } from '@/components/phamani/modal/installment-modal';
import { useEnums } from '@/hooks/use-enums';
import { resolveEnumLabel } from '@/lib/enum-helpers';
import { displayAmount, isThirdParty } from '@/lib/split';
import { TagChips } from '@/components/phamani/tag-input';
import { formatCurrency, formatDate } from '@/lib/format';
import { cn } from '@/lib/utils';
import { inbox } from '@/routes';
import { autoPay as installmentAutoPay } from '@/routes/installments';
import {
    autoPay as recurringAutoPay,
    end as endRecurring,
} from '@/routes/recurring';
import {
    destroy,
    pay as payTransaction,
    unpay as unpayTransaction,
} from '@/routes/transactions';
import type { Transaction } from '@/types/phamani';

interface ShowTransactionDrawerProps {
    transaction: Transaction | null;
    onClose: () => void;
    onEdit: (transaction: Transaction) => void;
}

export function ShowTransactionDrawer({
    transaction,
    onClose,
    onEdit,
}: ShowTransactionDrawerProps) {
    const [showInstallments, setShowInstallments] = useState(false);
    // Guarda o id da transação em confirmação: trocar de transação cancela a confirmação.
    const [confirmingId, setConfirmingId] = useState<string | null>(null);
    const [deleting, setDeleting] = useState(false);
    const [endingId, setEndingId] = useState<string | null>(null);
    const { recurringFrequencies } = useEnums();

    const isIncome = transaction?.type === 'income';
    const isInstallment = !!transaction?.installment_id;
    const isMirror = !!transaction?.mirrored_from_id;
    const confirming = !!transaction && confirmingId === transaction.id;

    const recurringEnded = !!transaction?.recurring?.end_date;
    const confirmingEnd =
        !!transaction?.recurring && endingId === transaction.recurring.id;

    function handleEndRecurring() {
        const recurring = transaction?.recurring;
        if (!recurring) return;

        router.post(
            endRecurring.url(recurring.id),
            {},
            {
                preserveScroll: true,
                onSuccess: () => {
                    setEndingId(null);
                    onClose();
                },
            },
        );
    }

    function handleDelete() {
        if (!transaction) return;

        router.delete(destroy.url(transaction.id), {
            preserveScroll: true,
            onStart: () => setDeleting(true),
            onFinish: () => setDeleting(false),
            onSuccess: () => {
                setConfirmingId(null);
                onClose();
            },
        });
    }

    return (
        <>
            <AnimatePresence>
                {transaction && (
                    <>
                        <motion.div
                            initial={{ opacity: 0 }}
                            animate={{ opacity: 1 }}
                            exit={{ opacity: 0 }}
                            onClick={onClose}
                            className="fixed inset-0 z-50 bg-[#3D2817]/20 backdrop-blur-[1px]"
                        />
                        <motion.div
                            role="dialog"
                            aria-modal="true"
                            aria-label="Detalhes da transação"
                            initial={{ x: '100%' }}
                            animate={{ x: 0 }}
                            exit={{ x: '100%' }}
                            transition={{
                                type: 'spring',
                                damping: 25,
                                stiffness: 200,
                            }}
                            className="fixed top-0 right-0 z-[60] flex h-full w-full flex-col border-l-2 border-[#E8DCC4] bg-[#F5EFE6] shadow-2xl md:w-[480px]"
                        >
                            <div className="border-b border-[#D4C5A9] bg-[#F5EFE6] p-8">
                                <div className="mb-6 flex items-start justify-between">
                                    <div
                                        className={`rounded-2xl p-3 ${isIncome ? 'bg-[#E3F9E5] text-[#1F5428]' : 'bg-[#FCE7E7] text-[#D4183D]'}`}
                                    >
                                        <ArrowRight
                                            className={`h-6 w-6 ${isIncome ? '-rotate-45' : 'rotate-45'}`}
                                        />
                                    </div>
                                    <button
                                        type="button"
                                        onClick={onClose}
                                        aria-label="Fechar"
                                        className="rounded-xl p-2 text-[#6B4E3D] transition-colors hover:bg-[#E8DCC4]"
                                    >
                                        <X className="h-6 w-6" />
                                    </button>
                                </div>

                                <h2 className="mb-1 text-3xl font-bold text-[#3D2817]">
                                    {isIncome ? '+' : '-'}{' '}
                                    {formatCurrency(displayAmount(transaction))}
                                </h2>
                                {isThirdParty(transaction) ? (
                                    <p className="mb-1 text-sm text-[#8B7355]">
                                        Compra para outra pessoa · não entra nas
                                        suas despesas
                                    </p>
                                ) : (
                                    transaction.total_amount != null && (
                                        <p className="mb-1 text-sm text-[#8B7355]">
                                            Sua parte de{' '}
                                            {formatCurrency(
                                                transaction.total_amount,
                                            )}
                                        </p>
                                    )
                                )}
                                <p className="text-lg text-[#6B4E3D]">
                                    {transaction.name}
                                </p>
                                <TagChips
                                    tags={transaction.tags}
                                    className="mt-2"
                                />
                            </div>

                            <div className="flex-1 space-y-8 overflow-y-auto p-8">
                                <div className="grid grid-cols-2 gap-4">
                                    <MetaCard
                                        icon={<Tag className="h-4 w-4" />}
                                        label="Categoria"
                                        value={
                                            transaction.category?.name ?? '—'
                                        }
                                    />
                                    <MetaCard
                                        icon={
                                            <CreditCard className="h-4 w-4" />
                                        }
                                        label="Conta"
                                        value={
                                            transaction.account?.name ??
                                            (transaction.paid_by
                                                ? `Pago por ${transaction.paid_by.name}`
                                                : '—')
                                        }
                                    />
                                    <MetaCard
                                        icon={<Calendar className="h-4 w-4" />}
                                        label="Data"
                                        value={formatDate(transaction.date)}
                                    />

                                    {transaction.recurring && (
                                        <div className="rounded-2xl border border-[#6B4E3D] bg-[#6B4E3D] p-4 shadow-sm">
                                            <div className="mb-2 flex items-center gap-2 text-[#F5EFE6]/70">
                                                <Repeat className="h-4 w-4" />
                                                <span className="text-xs font-bold tracking-wider uppercase">
                                                    Recorrência
                                                </span>
                                            </div>
                                            <p className="font-medium text-[#F5EFE6]">
                                                {resolveEnumLabel(
                                                    recurringFrequencies,
                                                    transaction.recurring
                                                        .frequency,
                                                )}
                                            </p>
                                            {recurringEnded && (
                                                <p className="mt-1 text-xs text-[#F5EFE6]/70">
                                                    Encerrada em{' '}
                                                    {formatDate(
                                                        transaction.recurring
                                                            .end_date,
                                                    )}
                                                </p>
                                            )}
                                        </div>
                                    )}
                                </div>

                                <PaymentStatusBlock
                                    transaction={transaction}
                                    onDone={onClose}
                                />

                                <SplitDetails transaction={transaction} />

                                {!isMirror && (
                                    <AutoPaySwitch transaction={transaction} />
                                )}

                                {transaction.recurring && !recurringEnded && (
                                    <div className="rounded-3xl border border-[#D4C5A9] bg-[#E8DCC4]/50 p-6">
                                        <p className="mb-4 text-sm text-[#6B4E3D]">
                                            Todo vencimento o Phamani lança esta
                                            transação repetindo o último valor.
                                            Se mudar num mês, é só editar a
                                            ocorrência daquele mês.
                                        </p>
                                        {confirmingEnd ? (
                                            <div className="flex gap-3">
                                                <button
                                                    type="button"
                                                    onClick={() =>
                                                        setEndingId(null)
                                                    }
                                                    className="flex-1 rounded-xl border-2 border-[#D4C5A9] py-2 text-sm font-medium text-[#6B4E3D] hover:bg-[#E8DCC4]"
                                                >
                                                    Cancelar
                                                </button>
                                                <button
                                                    type="button"
                                                    onClick={handleEndRecurring}
                                                    className="flex-1 rounded-xl bg-[#6B4E3D] py-2 text-sm font-medium text-[#F5EFE6] hover:bg-[#3D2817]"
                                                >
                                                    Confirmar
                                                </button>
                                            </div>
                                        ) : (
                                            <button
                                                type="button"
                                                onClick={() =>
                                                    setEndingId(
                                                        transaction.recurring
                                                            ?.id ?? null,
                                                    )
                                                }
                                                className="w-full rounded-xl border-2 border-[#6B4E3D] py-2 text-sm font-medium text-[#6B4E3D] transition-colors hover:bg-[#6B4E3D] hover:text-[#F5EFE6]"
                                            >
                                                Encerrar recorrência
                                            </button>
                                        )}
                                    </div>
                                )}

                                {transaction.installment && (
                                    <div className="flex items-center justify-between rounded-3xl border border-[#D4C5A9] bg-[#E8DCC4]/50 p-6">
                                        <div>
                                            <h4 className="mb-1 font-bold text-[#3D2817]">
                                                Parcelamento
                                            </h4>
                                            <p className="text-sm text-[#6B4E3D]">
                                                Parcela{' '}
                                                {transaction.installment_number}
                                                /
                                                {
                                                    transaction.installment
                                                        .installments
                                                }
                                            </p>
                                        </div>
                                        <button
                                            type="button"
                                            onClick={() =>
                                                setShowInstallments(true)
                                            }
                                            className="rounded-xl bg-[#6B4E3D] px-4 py-2 text-sm font-medium text-[#F5EFE6] shadow-md transition-colors hover:bg-[#3D2817]"
                                        >
                                            Ver Linha do Tempo
                                        </button>
                                    </div>
                                )}
                            </div>

                            <div className="border-t border-[#D4C5A9] bg-[#FAF7F1] p-6 md:p-8">
                                {isMirror ? (
                                    <div className="space-y-2 text-sm text-[#6B4E3D]">
                                        <p>
                                            Divisão compartilhada por{' '}
                                            <strong>
                                                {transaction.mirrored_from?.user
                                                    ?.name ?? 'outra pessoa'}
                                            </strong>
                                            . Só quem criou pode alterar os
                                            valores.
                                        </p>
                                        <Link
                                            href={inbox.url()}
                                            className="font-medium text-[#3D2817] underline"
                                        >
                                            Sair da divisão em Pendências
                                        </Link>
                                    </div>
                                ) : confirming ? (
                                    <div className="space-y-4">
                                        <p className="text-sm text-[#6B4E3D]">
                                            {isInstallment
                                                ? 'Excluir o parcelamento inteiro (todas as parcelas)? Essa ação não pode ser desfeita.'
                                                : 'Excluir esta transação? Essa ação não pode ser desfeita.'}
                                        </p>
                                        <div className="flex gap-4">
                                            <button
                                                type="button"
                                                onClick={() =>
                                                    setConfirmingId(null)
                                                }
                                                disabled={deleting}
                                                className="flex-1 rounded-xl border-2 border-[#D4C5A9] py-3 font-medium text-[#6B4E3D] transition-colors hover:bg-[#E8DCC4] disabled:opacity-50"
                                            >
                                                Cancelar
                                            </button>
                                            <button
                                                type="button"
                                                onClick={handleDelete}
                                                disabled={deleting}
                                                className="flex flex-1 items-center justify-center gap-2 rounded-xl bg-[#A65D57] py-3 font-medium text-white transition-colors hover:bg-[#8B4543] disabled:opacity-50"
                                            >
                                                <Trash2 className="h-4 w-4" />
                                                {deleting
                                                    ? 'Excluindo...'
                                                    : 'Excluir'}
                                            </button>
                                        </div>
                                    </div>
                                ) : (
                                    <div className="flex gap-4">
                                        <button
                                            type="button"
                                            onClick={() => onEdit(transaction)}
                                            className="flex flex-1 items-center justify-center gap-2 rounded-xl border-2 border-[#D4C5A9] py-3 font-medium text-[#6B4E3D] transition-colors hover:bg-[#E8DCC4]"
                                        >
                                            <Pencil className="h-4 w-4" />
                                            Editar
                                        </button>
                                        <button
                                            type="button"
                                            onClick={() =>
                                                setConfirmingId(transaction.id)
                                            }
                                            className="flex flex-1 items-center justify-center gap-2 rounded-xl bg-[#D4C5A9] py-3 font-medium text-[#3D2817] transition-colors hover:bg-[#C9B59A]"
                                        >
                                            <Trash2 className="h-4 w-4" />
                                            Excluir
                                        </button>
                                    </div>
                                )}
                            </div>
                        </motion.div>
                    </>
                )}
            </AnimatePresence>

            {transaction?.installment && (
                <InstallmentModal
                    isOpen={showInstallments}
                    onClose={() => setShowInstallments(false)}
                    installment={transaction.installment}
                />
            )}
        </>
    );
}

function MetaCard({
    icon,
    label,
    value,
}: {
    icon: React.ReactNode;
    label: string;
    value: string;
}) {
    return (
        <div className="rounded-2xl border border-[#E8DCC4] bg-white p-4 shadow-sm">
            <div className="mb-2 flex items-center gap-2 text-[#8B7355]">
                {icon}
                <span className="text-xs font-bold tracking-wider uppercase">
                    {label}
                </span>
            </div>
            <p className="font-medium text-[#3D2817]">{value}</p>
        </div>
    );
}

/** Status de pagamento + ação de marcar como pago/pendente (só quem pagou). */
function PaymentStatusBlock({
    transaction,
    onDone,
}: {
    transaction: Transaction;
    onDone: () => void;
}) {
    const [busy, setBusy] = useState(false);
    const status = paymentStatus(transaction);
    if (!status) return null;

    const isIncome = transaction.type === 'income';
    const canMark = canMarkPaid(transaction);
    const opts = {
        preserveScroll: true,
        onStart: () => setBusy(true),
        onFinish: () => setBusy(false),
        onSuccess: onDone,
    };

    return (
        <div
            className={cn(
                'flex flex-wrap items-center justify-between gap-3 rounded-3xl border p-5',
                status === 'overdue'
                    ? 'border-[#A65D57] bg-[#FDF3F2]'
                    : 'border-[#D4C5A9] bg-white',
            )}
        >
            <div>
                <div className="flex items-center gap-2">
                    <PaymentStatusBadge status={status} isIncome={isIncome} />
                    {transaction.paid_at && (
                        <span className="text-xs text-[#8B7355]">
                            em {formatDate(transaction.paid_at)}
                        </span>
                    )}
                </div>
                {!canMark && (
                    <p className="mt-1 text-xs text-[#8B7355]">
                        Quem marca é quem pagou
                        {payerName(transaction)
                            ? ` (${payerName(transaction)})`
                            : ''}
                        .
                    </p>
                )}
            </div>

            {canMark &&
                (status === 'paid' ? (
                    <button
                        type="button"
                        disabled={busy}
                        onClick={() =>
                            router.delete(
                                unpayTransaction.url(transaction.id),
                                opts,
                            )
                        }
                        className="rounded-xl border-2 border-[#D4C5A9] px-4 py-2 text-sm font-medium text-[#6B4E3D] hover:bg-[#E8DCC4] disabled:opacity-50"
                    >
                        Voltar para pendente
                    </button>
                ) : (
                    <button
                        type="button"
                        disabled={busy}
                        onClick={() =>
                            router.post(
                                payTransaction.url(transaction.id),
                                {},
                                opts,
                            )
                        }
                        className="flex items-center gap-2 rounded-xl bg-[#1F5428] px-4 py-2 text-sm font-medium text-white hover:bg-[#173F1E] disabled:opacity-50"
                    >
                        <Check className="h-4 w-4" />
                        {isIncome ? 'Marcar como recebida' : 'Marcar como paga'}
                    </button>
                ))}
        </div>
    );
}

/** Débito automático da série (recorrência ou parcelamento) desta transação. */
function AutoPaySwitch({ transaction }: { transaction: Transaction }) {
    const [busy, setBusy] = useState(false);
    const series = transaction.recurring
        ? {
              enabled: !!transaction.recurring.auto_pay,
              url: recurringAutoPay.url(transaction.recurring.id),
              label: 'recorrência',
          }
        : transaction.installment && transaction.installment_id
          ? {
                enabled: !!transaction.installment.auto_pay,
                url: installmentAutoPay.url(transaction.installment_id),
                label: 'parcelamento',
            }
          : null;

    if (!series || transaction.account?.type === 'credit') return null;

    return (
        <label className="flex cursor-pointer items-start gap-3 rounded-3xl border border-[#D4C5A9] bg-white p-5">
            <input
                type="checkbox"
                checked={series.enabled}
                disabled={busy}
                onChange={(e) =>
                    router.post(
                        series.url,
                        { enabled: e.target.checked },
                        {
                            preserveScroll: true,
                            onStart: () => setBusy(true),
                            onFinish: () => setBusy(false),
                        },
                    )
                }
                className="mt-0.5 h-4 w-4 accent-[#3D2817]"
            />
            <span className="text-sm text-[#3D2817]">
                Débito automático
                <span className="block text-xs text-[#8B7355]">
                    Vale para todo o {series.label}: no vencimento já entra como
                    pago. Ao ligar, o que já venceu e está em aberto é marcado
                    como pago.
                </span>
            </span>
        </label>
    );
}
PHAMANI_EOF

write 'resources/js/components/phamani/modal/tags-modal.tsx' <<'PHAMANI_EOF'
import { router } from '@inertiajs/react';
import { Check, Hash, Pencil, Trash2, X } from 'lucide-react';
import { useState } from 'react';
import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogHeader,
    DialogTitle,
} from '@/components/ui/dialog';
import { tagSlug, useTags } from '@/hooks/use-tags';
import { destroy, update } from '@/routes/tags';
import type { Tag } from '@/types/phamani';

interface TagsModalProps {
    open: boolean;
    onOpenChange: (open: boolean) => void;
}

/**
 * Gerenciar tags: renomear (se o nome já existir, as duas viram uma só) e apagar.
 * Criar é direto no formulário da transação.
 */
export function TagsModal({ open, onOpenChange }: TagsModalProps) {
    const tags = useTags();

    return (
        <Dialog open={open} onOpenChange={onOpenChange}>
            <DialogContent
                onOpenAutoFocus={(e) => e.preventDefault()}
                className="max-w-md overflow-hidden border-[#E8DCC4] bg-[#F5EFE6] p-0"
            >
                <DialogHeader className="border-b border-[#E8DCC4] px-6 pt-6 pb-4">
                    <DialogTitle className="text-xl text-[#3D2817]">
                        Tags
                    </DialogTitle>
                    <DialogDescription className="mt-1 text-sm text-[#8B7355]">
                        Crie tags direto na transação. Aqui você renomeia, junta
                        (renomeando para um nome que já existe) ou apaga.
                    </DialogDescription>
                </DialogHeader>

                <div className="max-h-[60vh] space-y-2 overflow-y-auto px-4 py-4">
                    {tags.length === 0 ? (
                        <p className="rounded-2xl border border-dashed border-[#D4C5A9] p-6 text-center text-sm text-[#8B7355]">
                            Nenhuma tag ainda.
                        </p>
                    ) : (
                        tags.map((tag) => (
                            <TagRow key={tag.id} tag={tag} all={tags} />
                        ))
                    )}
                </div>
            </DialogContent>
        </Dialog>
    );
}

function TagRow({ tag, all }: { tag: Tag; all: Tag[] }) {
    const [editing, setEditing] = useState(false);
    const [confirming, setConfirming] = useState(false);
    const [name, setName] = useState(tag.name);

    const target = all.find(
        (t) => t.id !== tag.id && tagSlug(t.name) === tagSlug(name),
    );

    function save() {
        const trimmed = name.trim();
        if (!trimmed || trimmed === tag.name) {
            setEditing(false);
            setName(tag.name);
            return;
        }

        router.put(
            update.url(tag.id),
            { name: trimmed },
            {
                preserveScroll: true,
                preserveState: true,
                onSuccess: () => setEditing(false),
            },
        );
    }

    function remove() {
        router.delete(destroy.url(tag.id), {
            preserveScroll: true,
            preserveState: true,
        });
    }

    const count = tag.transactions_count ?? 0;

    return (
        <div className="rounded-2xl border border-[#E8DCC4] bg-white p-3">
            {editing ? (
                <div className="space-y-1">
                    <div className="flex items-center gap-2">
                        <input
                            value={name}
                            onChange={(e) => setName(e.target.value)}
                            onKeyDown={(e) => {
                                if (e.key === 'Enter') save();
                                if (e.key === 'Escape') {
                                    setEditing(false);
                                    setName(tag.name);
                                }
                            }}
                            maxLength={40}
                            autoFocus
                            aria-label="Novo nome da tag"
                            className="flex-1 rounded-lg border-2 border-[#E8DCC4] px-2 py-1 text-sm text-[#3D2817] focus:border-[#6B4E3D] focus:outline-none"
                        />
                        <button
                            type="button"
                            onClick={save}
                            aria-label="Salvar"
                            className="rounded-md p-1.5 text-[#1F5428] hover:bg-[#E3F1E6]"
                        >
                            <Check className="h-4 w-4" />
                        </button>
                        <button
                            type="button"
                            onClick={() => {
                                setEditing(false);
                                setName(tag.name);
                            }}
                            aria-label="Cancelar"
                            className="rounded-md p-1.5 text-[#8B7355] hover:bg-[#E8DCC4]"
                        >
                            <X className="h-4 w-4" />
                        </button>
                    </div>
                    {target && (
                        <p className="ml-1 text-xs text-[#8B7355]">
                            Já existe “{target.name}”: as duas tags vão virar
                            uma só.
                        </p>
                    )}
                </div>
            ) : (
                <div className="flex items-center justify-between gap-2">
                    <span className="flex min-w-0 items-center gap-2">
                        <Hash className="h-4 w-4 shrink-0 text-[#8B7355]" />
                        <span className="truncate text-sm font-semibold text-[#3D2817]">
                            {tag.name}
                        </span>
                        <span className="shrink-0 text-xs text-[#8B7355]">
                            {count} {count === 1 ? 'transação' : 'transações'}
                        </span>
                    </span>

                    {confirming ? (
                        <span className="flex shrink-0 items-center gap-1 text-xs">
                            <button
                                type="button"
                                onClick={remove}
                                className="rounded-md bg-[#A65D57] px-2 py-1 font-semibold text-white"
                            >
                                Apagar
                            </button>
                            <button
                                type="button"
                                onClick={() => setConfirming(false)}
                                className="rounded-md px-2 py-1 text-[#8B7355] hover:bg-[#E8DCC4]"
                            >
                                Não
                            </button>
                        </span>
                    ) : (
                        <span className="flex shrink-0 items-center">
                            <button
                                type="button"
                                onClick={() => setEditing(true)}
                                aria-label={`Renomear ${tag.name}`}
                                className="rounded-md p-1.5 text-[#8B7355] hover:bg-[#E8DCC4] hover:text-[#3D2817]"
                            >
                                <Pencil className="h-3.5 w-3.5" />
                            </button>
                            <button
                                type="button"
                                onClick={() => setConfirming(true)}
                                aria-label={`Apagar ${tag.name}`}
                                className="rounded-md p-1.5 text-[#8B7355] hover:bg-[#FCE7E7] hover:text-[#A65D57]"
                            >
                                <Trash2 className="h-3.5 w-3.5" />
                            </button>
                        </span>
                    )}
                </div>
            )}
        </div>
    );
}
PHAMANI_EOF

write 'resources/js/components/phamani/modal/transaction-form.tsx' <<'PHAMANI_EOF'
import type { InertiaFormProps } from '@inertiajs/react';
import { Layers, Repeat } from 'lucide-react';
import { useEffect, useState } from 'react';
import type { ReactNode } from 'react';
import { Form } from '@/components/form';
import { AccountDropdown } from '@/components/phamani/dropdown/account-dropdown';
import { CategoryDropdown } from '@/components/phamani/dropdown/category-dropdown';
import { TagInput } from '@/components/phamani/tag-input';
import { SplitSection } from '@/components/phamani/modal/split-section';
import { ToggleField } from '@/components/toggle-field';
import { useEnums } from '@/hooks/use-enums';
import { formatCurrency } from '@/lib/format';
import { myShare } from '@/lib/split';
import { getInstallmentValue } from '@/lib/transaction-math';
import { cn } from '@/lib/utils';
import type { Account, Category, TransactionFormData } from '@/types/phamani';

interface TransactionFormProps {
    form: InertiaFormProps<TransactionFormData>;
    categories: Category[];
    accounts: Account[];
    onSubmit: () => void;
    onCreateCategory: () => void;
    onCreateAccount: () => void;
    onEditCategory?: (category: Category) => void;
    onEditAccount?: (account: Account) => void;
    /** Em edição não dá para transformar em parcelado/recorrente. */
    isEditing?: boolean;
    /** Editando uma parcela: oferece repetir o valor nas próximas. */
    isInstallmentParcel?: boolean;
}

const inputClass =
    'w-full rounded-xl border-2 border-[#E8DCC4] bg-white px-4 py-3 text-[#3D2817] focus:border-[#6B4E3D] focus:outline-none';
const labelClass = 'mb-2 ml-1 block font-serif text-sm text-[#6B4E3D]';

function FieldError({ message }: { message?: string }) {
    return message ? (
        <p className="mt-1 ml-1 text-xs text-[#D4183D]">{message}</p>
    ) : null;
}

export function TransactionForm({
    form,
    categories,
    accounts,
    onSubmit,
    onCreateCategory,
    onCreateAccount,
    onEditCategory,
    onEditAccount,
    isEditing = false,
    isInstallmentParcel = false,
}: TransactionFormProps) {
    const { data, setData, processing, errors } = form;
    const { recurringFrequencies } = useEnums();

    const filteredCategories = categories.filter(
        (c) => c.type === data.type || c.type === 'both',
    );
    const selectedCategory =
        categories.find((c) => c.id === data.category_id) ?? null;
    const selectedAccount =
        accounts.find((a) => a.id === data.account_id) ?? null;

    // Outra pessoa pagou: a conta não se aplica.
    const paidByOther = !!data.split?.paid_by_contact_id;

    // "Estou digitando: valor cheio | minha parte" (só em partes iguais com contatos).
    // O formulário sempre envia o valor cheio; em "minha parte" ele é calculado = parte × pessoas.
    const contactsInSplit =
        data.split?.participants.filter((p) => p.contact_id !== null).length ??
        0;
    const people = contactsInSplit + 1;
    const canEnterMine =
        !!data.split &&
        data.split.include_me !== false &&
        data.split.mode === 'equal' &&
        contactsInSplit > 0;
    const [enteredAs, setEnteredAs] = useState<'full' | 'mine'>('full');
    const [mineInput, setMineInput] = useState<number | ''>('');
    const mineMode = canEnterMine && enteredAs === 'mine';

    function toCents(value: number) {
        return Math.round(value * 100) / 100;
    }

    function switchEnteredAs(mode: 'full' | 'mine') {
        if (mode === 'mine') {
            setMineInput(
                data.amount ? toCents(Number(data.amount) / people) : '',
            );
        }
        setEnteredAs(mode);
    }

    // Mudou quem participa: recalcula o valor cheio a partir da sua parte.
    useEffect(() => {
        if (mineMode && mineInput !== '') {
            setData('amount', toCents(mineInput * people));
        }
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [people, mineMode]);

    // Ao trocar receita/despesa, invalida a categoria se ela não servir mais
    // (e desfaz a divisão: só despesas são divididas).
    useEffect(() => {
        if (data.type === 'income' && data.split) {
            setData('split', null);
        }
        if (
            selectedCategory &&
            selectedCategory.type !== data.type &&
            selectedCategory.type !== 'both'
        ) {
            setData('category_id', '');
        }
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [data.type]);

    // Pré-seleciona a primeira conta disponível.
    useEffect(() => {
        if (!data.account_id && accounts.length > 0) {
            setData('account_id', accounts[0].id);
        }
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [accounts]);

    return (
        <Form
            onSubmit={onSubmit}
            className="w-full overflow-y-auto bg-[#F5EFE6] p-8 md:w-[58%] md:p-12"
        >
            <h2 className="mb-8 text-2xl font-bold text-[#3D2817]">
                {isEditing ? 'Editar Transação' : 'Nova Transação'}
            </h2>

            <div className="space-y-6">
                <div className="flex rounded-xl bg-[#E8DCC4] p-1">
                    {(['expense', 'income'] as const).map((type) => (
                        <button
                            key={type}
                            type="button"
                            onClick={() => setData('type', type)}
                            className={cn(
                                'flex-1 rounded-lg py-3 text-sm font-bold transition-all',
                                data.type === type
                                    ? type === 'expense'
                                        ? 'bg-[#FCE7E7] text-[#D4183D] shadow-sm'
                                        : 'bg-[#E3F9E5] text-[#1F5428] shadow-sm'
                                    : 'text-[#6B4E3D] hover:bg-[#D4C5A9]/50',
                            )}
                        >
                            {type === 'expense' ? 'Despesa' : 'Receita'}
                        </button>
                    ))}
                </div>

                <div>
                    <label htmlFor="amount" className={labelClass}>
                        {mineMode
                            ? data.is_installment &&
                              data.amount_mode === 'installment'
                                ? 'Sua parte da parcela'
                                : 'Sua parte'
                            : data.is_installment
                              ? data.amount_mode === 'installment'
                                  ? 'Valor da parcela'
                                  : 'Valor total da compra'
                              : 'Valor'}
                    </label>
                    <div className="relative">
                        <span className="absolute top-1/2 left-4 -translate-y-1/2 font-bold text-[#8B7355]">
                            R$
                        </span>
                        <input
                            id="amount"
                            type="number"
                            inputMode="decimal"
                            step="0.01"
                            min="0.01"
                            value={mineMode ? mineInput : data.amount}
                            onChange={(e) => {
                                const v =
                                    e.target.value === ''
                                        ? ''
                                        : Number(e.target.value);
                                if (mineMode) {
                                    setMineInput(v);
                                    setData(
                                        'amount',
                                        v === '' ? '' : toCents(v * people),
                                    );
                                } else {
                                    setData('amount', v);
                                }
                            }}
                            placeholder="0,00"
                            className="w-full rounded-xl border-2 border-[#E8DCC4] bg-white py-4 pr-4 pl-12 text-2xl font-bold text-[#3D2817] placeholder:text-[#D4C5A9] focus:border-[#6B4E3D] focus:outline-none"
                        />
                    </div>
                    {canEnterMine && (
                        <div className="mt-2 flex items-center gap-2">
                            <span className="ml-1 text-xs text-[#8B7355]">
                                Estou digitando:
                            </span>
                            <div className="flex rounded-lg bg-[#E8DCC4] p-0.5">
                                {(
                                    [
                                        ['full', 'Valor cheio'],
                                        ['mine', 'Minha parte'],
                                    ] as const
                                ).map(([mode, label]) => (
                                    <button
                                        key={mode}
                                        type="button"
                                        onClick={() => switchEnteredAs(mode)}
                                        aria-pressed={enteredAs === mode}
                                        className={cn(
                                            'rounded-md px-3 py-1 text-xs font-bold transition-all',
                                            enteredAs === mode
                                                ? 'bg-white text-[#3D2817] shadow-sm'
                                                : 'text-[#6B4E3D] hover:bg-[#D4C5A9]/50',
                                        )}
                                    >
                                        {label}
                                    </button>
                                ))}
                            </div>
                        </div>
                    )}
                    <FieldError message={errors.amount} />
                </div>

                <div>
                    <label htmlFor="description" className={labelClass}>
                        Descrição
                    </label>
                    <input
                        id="description"
                        value={data.description}
                        onChange={(e) => setData('description', e.target.value)}
                        placeholder="Ex: Compras do mês"
                        className={inputClass}
                    />
                    <FieldError message={errors.description} />
                </div>

                <div>
                    <span className={labelClass}>Tags</span>
                    <TagInput
                        value={data.tags}
                        onChange={(tags) => setData('tags', tags)}
                        error={
                            errors.tags ??
                            Object.entries(errors).find(([k]) =>
                                k.startsWith('tags.'),
                            )?.[1]
                        }
                    />
                </div>

                <div
                    className={cn(
                        'grid gap-4',
                        paidByOther ? 'grid-cols-1' : 'grid-cols-2',
                    )}
                >
                    <div>
                        <span className={labelClass}>Categoria</span>
                        <CategoryDropdown
                            value={selectedCategory}
                            categories={filteredCategories}
                            onChange={(c) => setData('category_id', c.id)}
                            onCreate={onCreateCategory}
                            onEdit={onEditCategory}
                        />
                        <FieldError message={errors.category_id} />
                    </div>
                    {!paidByOther && (
                        <div>
                            <span className={labelClass}>Conta</span>
                            <AccountDropdown
                                value={selectedAccount}
                                accounts={accounts}
                                onChange={(a) => setData('account_id', a.id)}
                                onCreate={onCreateAccount}
                                onEdit={onEditAccount}
                            />
                            <FieldError message={errors.account_id} />
                        </div>
                    )}
                </div>

                <div>
                    <label htmlFor="date" className={labelClass}>
                        Data
                    </label>
                    <input
                        id="date"
                        type="date"
                        value={data.date}
                        onChange={(e) => setData('date', e.target.value)}
                        className={inputClass}
                    />
                    <FieldError message={errors.date} />
                </div>

                {data.type === 'expense' && (
                    <div className="border-t border-[#E8DCC4] pt-4">
                        <SplitSection
                            split={data.split}
                            onChange={(split) => setData('split', split)}
                            // Parcelado: a divisão é de cada parcela.
                            amount={
                                data.is_installment
                                    ? (getInstallmentValue(
                                          Number(data.amount || 0),
                                          data.installments_count,
                                          data.installment_start,
                                          data.amount_mode,
                                      ) ?? 0)
                                    : Number(data.amount || 0)
                            }
                            errors={errors as Record<string, string>}
                        />
                    </div>
                )}

                {isEditing && isInstallmentParcel && (
                    <div className="border-t border-[#E8DCC4] pt-4">
                        <ToggleField
                            label="Aplicar este valor às próximas parcelas"
                            icon={<Layers className="h-5 w-5" />}
                            active={data.apply_to_following}
                            onToggle={() =>
                                setData(
                                    'apply_to_following',
                                    !data.apply_to_following,
                                )
                            }
                        />
                    </div>
                )}

                {!isEditing && (
                    <div className="space-y-4 border-t border-[#E8DCC4] pt-4">
                        <ToggleField
                            label="Parcelado?"
                            icon={<Layers className="h-5 w-5" />}
                            active={data.is_installment}
                            onToggle={() =>
                                setData((prev) => ({
                                    ...prev,
                                    is_installment: !prev.is_installment,
                                    is_recurring: false,
                                }))
                            }
                        />

                        {data.is_installment && (
                            <div className="space-y-4 border-l-2 border-[#6B4E3D] pl-4">
                                <div>
                                    <span className={labelClass}>
                                        O valor informado é
                                    </span>
                                    <div className="flex rounded-xl bg-[#E8DCC4] p-1">
                                        {(
                                            [
                                                ['installment', 'Da parcela'],
                                                ['total', 'Total da compra'],
                                            ] as const
                                        ).map(([mode, label]) => (
                                            <button
                                                key={mode}
                                                type="button"
                                                onClick={() =>
                                                    setData('amount_mode', mode)
                                                }
                                                className={cn(
                                                    'flex-1 rounded-lg py-2 text-sm font-bold transition-all',
                                                    data.amount_mode === mode
                                                        ? 'bg-white text-[#3D2817] shadow-sm'
                                                        : 'text-[#6B4E3D] hover:bg-[#D4C5A9]/50',
                                                )}
                                            >
                                                {label}
                                            </button>
                                        ))}
                                    </div>
                                    <FieldError message={errors.amount_mode} />
                                </div>

                                <div className="grid grid-cols-2 gap-4">
                                    <div>
                                        <label
                                            htmlFor="installments_count"
                                            className={labelClass}
                                        >
                                            Nº de parcelas
                                        </label>
                                        <input
                                            id="installments_count"
                                            type="number"
                                            min={2}
                                            max={360}
                                            value={data.installments_count}
                                            onChange={(e) =>
                                                setData(
                                                    'installments_count',
                                                    Number(e.target.value),
                                                )
                                            }
                                            className="w-full rounded-xl border-2 border-[#E8DCC4] bg-white px-4 py-2 text-[#3D2817]"
                                        />
                                        <FieldError
                                            message={errors.installments_count}
                                        />
                                    </div>
                                    <div>
                                        <label
                                            htmlFor="installment_start"
                                            className={labelClass}
                                        >
                                            Começar da parcela
                                        </label>
                                        <input
                                            id="installment_start"
                                            type="number"
                                            min={1}
                                            max={data.installments_count}
                                            value={data.installment_start}
                                            onChange={(e) =>
                                                setData(
                                                    'installment_start',
                                                    Number(e.target.value),
                                                )
                                            }
                                            className="w-full rounded-xl border-2 border-[#E8DCC4] bg-white px-4 py-2 text-[#3D2817]"
                                        />
                                        <FieldError
                                            message={errors.installment_start}
                                        />
                                    </div>
                                </div>
                                <AutoPayToggle
                                    value={data.auto_pay}
                                    onChange={(v) => setData('auto_pay', v)}
                                />
                            </div>
                        )}

                        <ToggleField
                            label="Recorrente?"
                            icon={<Repeat className="h-5 w-5" />}
                            active={data.is_recurring}
                            onToggle={() =>
                                setData((prev) => ({
                                    ...prev,
                                    is_recurring: !prev.is_recurring,
                                    is_installment: false,
                                }))
                            }
                        />

                        {data.is_recurring && (
                            <div className="border-l-2 border-[#6B4E3D] pl-4">
                                <label
                                    htmlFor="frequency"
                                    className={labelClass}
                                >
                                    Frequência
                                </label>
                                <select
                                    id="frequency"
                                    value={data.frequency}
                                    onChange={(e) =>
                                        setData(
                                            'frequency',
                                            e.target
                                                .value as TransactionFormData['frequency'],
                                        )
                                    }
                                    className="w-full rounded-xl border-2 border-[#E8DCC4] bg-white px-4 py-2 text-[#3D2817]"
                                >
                                    {recurringFrequencies.map((freq) => (
                                        <option
                                            key={freq.value}
                                            value={freq.value}
                                        >
                                            {freq.label}
                                        </option>
                                    ))}
                                </select>
                                <FieldError message={errors.frequency} />
                                <AutoPayToggle
                                    value={data.auto_pay}
                                    onChange={(v) => setData('auto_pay', v)}
                                />
                            </div>
                        )}
                    </div>
                )}

                <TransactionSummary data={data} />

                <button
                    type="submit"
                    disabled={processing}
                    className="mt-8 w-full rounded-xl bg-[#3D2817] py-4 text-lg font-medium text-[#F5EFE6] shadow-lg transition-colors hover:bg-[#543924] disabled:opacity-50"
                >
                    {processing
                        ? 'Salvando...'
                        : isEditing
                          ? 'Salvar Alterações'
                          : 'Salvar Transação'}
                </button>
            </div>
        </Form>
    );
}

/**
 * Resumo fixo antes de salvar: quais parcelas serão lançadas, valor por parcela,
 * a sua parte (se dividida) e o total. Evita surpresa com "total × parcela × minha parte".
 */
function TransactionSummary({ data }: { data: TransactionFormData }) {
    const amount = Number(data.amount || 0);
    const hasSplit =
        !!data.split &&
        data.split.participants.some((p) => p.contact_id !== null);

    if (!amount || (!data.is_installment && !hasSplit)) return null;

    const parts: ReactNode[] = [];

    if (data.is_installment) {
        const count = data.installments_count || 0;
        const start = Math.min(Math.max(1, data.installment_start || 1), count);
        const launched = Math.max(0, count - start + 1);
        const perParcel =
            getInstallmentValue(amount, count, start, data.amount_mode) ?? 0;

        const which =
            launched <= 3
                ? Array.from(
                      { length: launched },
                      (_, i) => `${start + i}/${count}`,
                  ).join(', ')
                : `${start}/${count} a ${count}/${count} (${launched} parcelas)`;

        parts.push(
            <>
                Lança <strong>{which}</strong>
            </>,
            <>
                <strong>{formatCurrency(perParcel)}</strong> por parcela
            </>,
        );
        if (hasSplit) {
            parts.push(
                data.split?.include_me === false ? (
                    <>
                        <strong>tudo a receber</strong>
                    </>
                ) : (
                    <>
                        sua parte{' '}
                        <strong>
                            {formatCurrency(myShare(perParcel, data.split))}
                        </strong>{' '}
                        por parcela
                    </>
                ),
            );
        }
        parts.push(
            <>
                {formatCurrency(perParcel * launched)} no total
                {start > 1 ? ' (das parcelas lançadas)' : ''}
            </>,
        );
    } else {
        parts.push(
            <>
                Valor cheio <strong>{formatCurrency(amount)}</strong>
            </>,
            data.split?.include_me === false ? (
                <>
                    <strong>tudo a receber</strong> (não entra nas suas
                    despesas)
                </>
            ) : (
                <>
                    sua parte{' '}
                    <strong>
                        {formatCurrency(myShare(amount, data.split))}
                    </strong>
                </>
            ),
        );
    }

    return (
        <div className="mt-6 rounded-2xl border border-[#D4C5A9] bg-[#FBF7F1] px-4 py-3 text-sm text-[#3D2817]">
            {parts.map((part, i) => (
                <span key={i}>
                    {i > 0 && <span className="text-[#8B7355]"> · </span>}
                    {part}
                </span>
            ))}
        </div>
    );
}

/** "Débito automático": no vencimento já marca como pago (senão fica pendente/atrasado). */
function AutoPayToggle({
    value,
    onChange,
}: {
    value: boolean;
    onChange: (value: boolean) => void;
}) {
    return (
        <label className="mt-3 flex cursor-pointer items-start gap-3 rounded-xl bg-white/60 p-3">
            <input
                type="checkbox"
                checked={value}
                onChange={(e) => onChange(e.target.checked)}
                className="mt-0.5 h-4 w-4 accent-[#3D2817]"
            />
            <span className="text-sm text-[#3D2817]">
                Débito automático
                <span className="block text-xs text-[#8B7355]">
                    No vencimento já entra como pago. Desligado, fica pendente
                    até você marcar (e aparece como atrasado se passar do dia).
                </span>
            </span>
        </label>
    );
}
PHAMANI_EOF

write 'resources/js/components/phamani/modal/transaction-preview.tsx' <<'PHAMANI_EOF'
import { Calendar, Receipt, Users } from 'lucide-react';
import { motion } from 'motion/react';
import { CategoryIcon } from '@/components/phamani/category-icon';
import { useEnums } from '@/hooks/use-enums';
import { resolveEnumLabel } from '@/lib/enum-helpers';
import { formatCurrency, formatDate } from '@/lib/format';
import { getNextTransactionDate } from '@/lib/transaction-dates';
import { ContactAvatar } from '@/components/phamani/contact-avatar';
import { TagChips } from '@/components/phamani/tag-input';
import { useAuth } from '@/hooks/use-auth';
import { useContacts } from '@/hooks/use-contacts';
import { splitBreakdown } from '@/lib/split';
import { getInstallmentValue } from '@/lib/transaction-math';
import { ACCOUNT_TYPE_LABELS } from '@/types/phamani';
import type { Account, Category, TransactionFormData } from '@/types/phamani';

interface TransactionPreviewProps {
    data: TransactionFormData;
    categories: Category[];
    accounts: Account[];
}

export function TransactionPreview({
    data,
    categories,
    accounts,
}: TransactionPreviewProps) {
    const { recurringFrequencies } = useEnums();
    const contacts = useContacts();
    const { avatarUrl } = useAuth();

    const category = categories.find((c) => c.id === data.category_id) ?? null;
    const account = accounts.find((a) => a.id === data.account_id) ?? null;
    const amount = Number(data.amount || 0);
    const installmentValue = getInstallmentValue(
        amount,
        data.installments_count,
        data.installment_start,
        data.amount_mode,
    );
    const nextDate = getNextTransactionDate(data);
    const frequencyLabel = resolveEnumLabel(
        recurringFrequencies,
        data.frequency,
    )?.toLowerCase();
    const isIncome = data.type === 'income';

    // Divisão: no parcelado é por parcela.
    const splitBase =
        data.is_installment && installmentValue ? installmentValue : amount;
    const breakdown = splitBreakdown(splitBase, data.split);
    const nameOf = (id: string | null) =>
        id === null ? 'Você' : (contacts.find((c) => c.id === id)?.name ?? '—');
    const payerName = nameOf(data.split?.paid_by_contact_id ?? null);
    // Compra para outra pessoa: só os contatos aparecem, com o valor a receber.
    const forOthers = data.split?.include_me === false;
    const rows = forOthers
        ? breakdown.filter((b) => b.contact_id !== null)
        : breakdown;

    return (
        <div className="relative hidden w-[42%] flex-col items-center justify-center overflow-hidden border-l-2 border-[#D4C5A9] bg-[#E8DCC4]/50 p-12 md:flex">
            <div className="absolute top-0 right-0 h-64 w-64 rounded-full bg-[#D4C5A9]/20 blur-3xl" />
            <div className="absolute bottom-0 left-0 h-64 w-64 rounded-full bg-[#6B4E3D]/10 blur-3xl" />

            <p className="z-10 mt-12 mb-8 text-sm font-bold tracking-widest text-[#6B4E3D] uppercase">
                Pré-visualização
            </p>

            <motion.div
                key={data.type}
                initial={{ scale: 0.95, opacity: 0.8 }}
                animate={{ scale: 1, opacity: 1 }}
                className="z-10 w-full max-w-sm rounded-[2rem] border border-white/50 bg-[#F5EFE6] p-8 shadow-2xl"
            >
                <div className="mb-8 flex items-start justify-between">
                    <div
                        className={`rounded-2xl p-4 ${isIncome ? 'bg-[#E3F9E5] text-[#1F5428]' : 'bg-[#FCE7E7] text-[#D4183D]'}`}
                    >
                        <Receipt className="h-8 w-8" />
                    </div>

                    <div className="text-right">
                        <p className="mb-1 text-sm font-medium text-[#8B7355]">
                            {account?.name ?? '—'}
                        </p>
                        <p className="text-xs font-bold text-[#3D2817] uppercase opacity-60">
                            {account
                                ? ACCOUNT_TYPE_LABELS[account.type]
                                : 'Conta'}
                        </p>
                    </div>
                </div>

                <div className="mb-8">
                    <p className="mb-2 text-sm font-medium text-[#8B7355]">
                        Valor
                    </p>
                    <h3
                        className={`text-4xl font-bold ${isIncome ? 'text-[#1F5428]' : 'text-[#D4183D]'}`}
                    >
                        {isIncome ? '+' : '-'} {formatCurrency(amount)}
                    </h3>
                </div>

                <div className="space-y-4">
                    {rows.length > 0 && (
                        <div className="rounded-xl bg-white/50 p-3">
                            <div className="mb-2 flex items-center justify-between">
                                <span className="flex items-center gap-2 text-sm font-bold text-[#3D2817]">
                                    <Users className="h-4 w-4 text-[#6B4E3D]" />
                                    {forOthers ? 'Compra para' : 'Divisão'}
                                    {data.is_installment && (
                                        <span className="text-xs font-normal text-[#8B7355]">
                                            por parcela
                                        </span>
                                    )}
                                </span>
                                <span className="text-xs text-[#8B7355]">
                                    {forOthers ? (
                                        <strong className="text-[#3D2817]">
                                            A receber
                                        </strong>
                                    ) : (
                                        <>
                                            Pago por{' '}
                                            <strong className="text-[#3D2817]">
                                                {payerName === 'Você'
                                                    ? 'você'
                                                    : payerName}
                                            </strong>
                                        </>
                                    )}
                                </span>
                            </div>
                            <ul className="space-y-1">
                                {rows.map((b) => (
                                    <li
                                        key={b.contact_id ?? 'me'}
                                        className="flex items-center justify-between text-sm"
                                    >
                                        <span
                                            className={
                                                b.contact_id === null
                                                    ? 'flex items-center gap-2 font-semibold text-[#3D2817]'
                                                    : 'flex items-center gap-2 text-[#6B4E3D]'
                                            }
                                        >
                                            <ContactAvatar
                                                name={nameOf(b.contact_id)}
                                                avatar={
                                                    b.contact_id === null
                                                        ? avatarUrl
                                                        : contacts.find(
                                                              (c) =>
                                                                  c.id ===
                                                                  b.contact_id,
                                                          )?.linked_user?.avatar
                                                }
                                                className="h-6 w-6 text-[10px]"
                                            />
                                            {nameOf(b.contact_id)}
                                        </span>
                                        <span className="font-bold text-[#3D2817]">
                                            {formatCurrency(b.amount)}
                                        </span>
                                    </li>
                                ))}
                            </ul>
                        </div>
                    )}

                    <div className="flex items-center gap-4 rounded-xl bg-white/50 p-3">
                        {category ? (
                            <CategoryIcon
                                category={category}
                                className="h-9 w-9"
                                iconClassName="h-5 w-5"
                            />
                        ) : (
                            <div className="rounded-lg bg-[#E8DCC4] p-2">
                                <Receipt className="h-5 w-5 text-[#6B4E3D]" />
                            </div>
                        )}
                        <div>
                            <p className="text-sm font-bold text-[#3D2817]">
                                {data.description || 'Sem descrição'}
                            </p>
                            <p className="text-xs text-[#8B7355]">
                                {category?.name ?? 'Sem categoria'}
                            </p>
                            <TagChips
                                tags={data.tags.map((name) => ({ name }))}
                                className="mt-1"
                            />
                        </div>
                    </div>

                    <div className="flex items-center gap-4 rounded-xl bg-white/50 p-3">
                        <div className="rounded-lg bg-[#E8DCC4] p-2 text-[#6B4E3D]">
                            <Calendar className="h-5 w-5" />
                        </div>
                        <div>
                            <p className="text-sm font-bold text-[#3D2817]">
                                {formatDate(data.date)}
                            </p>

                            {data.is_recurring && (
                                <>
                                    <p className="text-xs text-[#8B7355]">
                                        Repete: {frequencyLabel}
                                    </p>
                                    <p className="text-xs font-medium text-[#6B4E3D]">
                                        Próxima: {nextDate}
                                    </p>
                                </>
                            )}

                            {data.is_installment && (
                                <>
                                    <p className="text-xs text-[#8B7355]">
                                        Parcela {data.installment_start || 1} de{' '}
                                        {data.installments_count}
                                    </p>
                                    <p className="text-xs text-[#8B7355]">
                                        {formatCurrency(installmentValue)} por
                                        parcela
                                    </p>
                                    <p className="text-xs font-medium text-[#6B4E3D]">
                                        Próxima: {nextDate}
                                    </p>
                                </>
                            )}
                        </div>
                    </div>
                </div>
            </motion.div>
        </div>
    );
}
PHAMANI_EOF

write 'resources/js/components/phamani/tag-input.tsx' <<'PHAMANI_EOF'
import { Hash, X } from 'lucide-react';
import { useMemo, useRef, useState } from 'react';
import type { KeyboardEvent } from 'react';
import { tagSlug, useTags } from '@/hooks/use-tags';
import { cn } from '@/lib/utils';

const MAX_TAGS = 10;

interface TagInputProps {
    value: string[];
    onChange: (tags: string[]) => void;
    error?: string;
}

/**
 * Tags livres: digite e Enter (ou vírgula) vira um chip; aparecem sugestões das tags
 * que você já usa. "ifood" e "iFood" são a mesma tag (usa o nome já existente).
 */
export function TagInput({ value, onChange, error }: TagInputProps) {
    const existing = useTags();
    const [text, setText] = useState('');
    const [focused, setFocused] = useState(false);
    const [highlight, setHighlight] = useState(0);
    const inputRef = useRef<HTMLInputElement>(null);

    const chosen = useMemo(() => new Set(value.map(tagSlug)), [value]);

    const suggestions = useMemo(() => {
        const q = tagSlug(text);
        return existing
            .filter((t) => !chosen.has(tagSlug(t.name)))
            .filter((t) => !q || tagSlug(t.name).includes(q))
            .slice(0, 6);
    }, [existing, chosen, text]);

    function add(raw: string) {
        const name = raw.replace(/\s+/g, ' ').trim().slice(0, 40);
        if (!name || value.length >= MAX_TAGS) return;

        const slug = tagSlug(name);
        if (chosen.has(slug)) {
            setText('');
            return;
        }

        // Já existe com outra grafia? Usa o nome que você já tem.
        const match = existing.find((t) => tagSlug(t.name) === slug);
        onChange([...value, match?.name ?? name]);
        setText('');
        setHighlight(0);
    }

    function remove(index: number) {
        onChange(value.filter((_, i) => i !== index));
    }

    function onKeyDown(e: KeyboardEvent<HTMLInputElement>) {
        const open = focused && suggestions.length > 0;

        if (e.key === 'Enter' || e.key === ',') {
            e.preventDefault();
            if (open && text && suggestions[highlight]) {
                add(suggestions[highlight].name);
            } else if (text) {
                add(text);
            } else if (open && suggestions[highlight] && e.key === 'Enter') {
                add(suggestions[highlight].name);
            }
        } else if (e.key === 'Backspace' && !text && value.length > 0) {
            remove(value.length - 1);
        } else if (e.key === 'ArrowDown' && open) {
            e.preventDefault();
            setHighlight((h) => (h + 1) % suggestions.length);
        } else if (e.key === 'ArrowUp' && open) {
            e.preventDefault();
            setHighlight(
                (h) => (h - 1 + suggestions.length) % suggestions.length,
            );
        } else if (e.key === 'Escape') {
            inputRef.current?.blur();
        }
    }

    return (
        <div className="relative">
            <div
                onClick={() => inputRef.current?.focus()}
                className={cn(
                    'flex min-h-12 w-full cursor-text flex-wrap items-center gap-1.5 rounded-xl border-2 bg-white px-3 py-2 transition-colors',
                    focused ? 'border-[#6B4E3D]' : 'border-[#E8DCC4]',
                )}
            >
                {value.map((tag, i) => (
                    <span
                        key={`${tag}-${i}`}
                        className="inline-flex items-center gap-1 rounded-full bg-[#E8DCC4] py-0.5 pr-1 pl-2.5 text-sm text-[#3D2817]"
                    >
                        {tag}
                        <button
                            type="button"
                            aria-label={`Remover ${tag}`}
                            onClick={(e) => {
                                e.stopPropagation();
                                remove(i);
                            }}
                            className="rounded-full p-0.5 text-[#8B7355] hover:bg-[#D4C5A9] hover:text-[#3D2817]"
                        >
                            <X className="h-3 w-3" />
                        </button>
                    </span>
                ))}
                {value.length < MAX_TAGS && (
                    <input
                        ref={inputRef}
                        value={text}
                        onChange={(e) => {
                            setText(e.target.value);
                            setHighlight(0);
                        }}
                        onKeyDown={onKeyDown}
                        onFocus={() => setFocused(true)}
                        // Atraso para o clique numa sugestão contar antes de fechar a lista.
                        onBlur={() => {
                            setTimeout(() => setFocused(false), 120);
                            if (text) add(text);
                        }}
                        placeholder={
                            value.length === 0
                                ? 'Ex.: iFood, Amazon, viagem… (opcional)'
                                : ''
                        }
                        aria-label="Adicionar tag"
                        className="min-w-[8rem] flex-1 bg-transparent py-1 text-sm text-[#3D2817] placeholder:text-[#B8A88A] focus:outline-none"
                    />
                )}
            </div>

            {focused && suggestions.length > 0 && (
                <ul
                    role="listbox"
                    className="absolute z-30 mt-1 w-full overflow-hidden rounded-xl border border-[#E8DCC4] bg-[#F5EFE6] py-1 shadow-xl"
                >
                    {suggestions.map((t, i) => (
                        <li
                            key={t.id}
                            role="option"
                            aria-selected={i === highlight}
                        >
                            <button
                                type="button"
                                onMouseDown={(e) => {
                                    e.preventDefault();
                                    add(t.name);
                                }}
                                onMouseEnter={() => setHighlight(i)}
                                className={cn(
                                    'flex w-full items-center gap-2 px-3 py-2 text-left text-sm text-[#3D2817]',
                                    i === highlight && 'bg-[#E8DCC4]',
                                )}
                            >
                                <Hash className="h-3.5 w-3.5 text-[#8B7355]" />
                                {t.name}
                            </button>
                        </li>
                    ))}
                </ul>
            )}

            {error && (
                <p className="mt-1 ml-1 text-xs text-[#D4183D]">{error}</p>
            )}
        </div>
    );
}

/** Chips de tags (somente leitura) para listas e drawer. */
export function TagChips({
    tags,
    className,
}: {
    tags?: { id?: string; name: string }[];
    className?: string;
}) {
    if (!tags || tags.length === 0) return null;

    return (
        <span className={cn('inline-flex flex-wrap gap-1', className)}>
            {tags.map((t) => (
                <span
                    key={t.id ?? t.name}
                    className="inline-flex items-center gap-0.5 rounded-md border border-[#E8DCC4] bg-white px-1.5 py-0.5 text-[10px] font-medium text-[#6B4E3D]"
                >
                    <Hash className="h-2.5 w-2.5 opacity-60" />
                    {t.name}
                </span>
            ))}
        </span>
    );
}
PHAMANI_EOF

write 'resources/js/hooks/use-tags.ts' <<'PHAMANI_EOF'
import { usePage } from '@inertiajs/react';
import type { Tag } from '@/types/phamani';

/** Tags do usuário (prop compartilhada em todas as páginas). */
export function useTags(): Tag[] {
    return (usePage().props.tags as Tag[] | undefined) ?? [];
}

/** Mesma normalização do back-end: minúsculas, sem acento, espaços simples. */
export function tagSlug(name: string): string {
    return name
        .normalize('NFD')
        .replace(/[̀-ͯ]/g, '')
        .toLowerCase()
        .replace(/\s+/g, ' ')
        .trim();
}
PHAMANI_EOF

write 'resources/js/hooks/use-transaction-form.ts' <<'PHAMANI_EOF'
import { useForm } from '@inertiajs/react';
import { today } from '@/lib/format';
import { splitFromTransaction } from '@/lib/split';
import { store, update } from '@/routes/transactions';
import type { Transaction, TransactionFormData } from '@/types/phamani';

function initialData(
    transaction?: Transaction | null,
    defaultAccountId?: string,
): TransactionFormData {
    return {
        // Parcelas guardam o nome com "(n/total)"; a descrição é o nome limpo.
        description: transaction
            ? (transaction.description ?? transaction.name)
            : '',
        // Numa divisão o campo "valor" é o total; a sua parte é calculada.
        amount: transaction
            ? Number(transaction.total_amount ?? transaction.amount)
            : '',
        type: transaction?.type ?? 'expense',
        category_id: transaction?.category_id ?? '',
        account_id: transaction?.account_id ?? defaultAccountId ?? '',
        date: transaction ? transaction.date.slice(0, 10) : today(),

        is_installment: false,
        installments_count: 2,
        installment_start: 1,
        // Padrão: valor da parcela (o número que aparece no boleto/fatura).
        amount_mode: 'installment',
        apply_to_following: false,
        split: transaction ? splitFromTransaction(transaction) : null,
        auto_pay: false,
        is_recurring: false,
        frequency: 'monthly',
        tags: transaction?.tags?.map((t) => t.name) ?? [],
    };
}

/**
 * Formulário de transação. Sem `transaction` cria uma nova;
 * com `transaction` edita a existente.
 */
export function useTransactionForm(
    transaction?: Transaction | null,
    onSuccess?: () => void,
    defaultAccountId?: string,
) {
    const form = useForm<TransactionFormData>(
        initialData(transaction, defaultAccountId),
    );

    function submit() {
        // O redirect "back" do Laravel recarrega a página atual com KPIs, gráficos e listas atualizados.
        form.submit(transaction ? update(transaction.id) : store(), {
            preserveScroll: true,
            onSuccess: () => {
                form.reset();
                onSuccess?.();
            },
        });
    }

    return { form, submit, isEditing: !!transaction };
}
PHAMANI_EOF

write 'resources/js/pages/transactions/index.tsx' <<'PHAMANI_EOF'
import { Head, router } from '@inertiajs/react';
import {
    Check,
    ChevronDown,
    ChevronLeft,
    ChevronRight,
    Plus,
    Search,
    X,
} from 'lucide-react';
import { useEffect, useState } from 'react';
import type { ReactNode } from 'react';
import { CategoryIcon } from '@/components/phamani/category-icon';
import { DashboardHeader } from '@/components/phamani/dashboard/dashboard-header';
import { ShowTransactionDrawer } from '@/components/phamani/drawer/show-transaction-drawer';
import { NewTransactionModal } from '@/components/phamani/modal/new-transaction-modal';
import { PaymentStatusBadge } from '@/components/phamani/payment-status-badge';
import { TagChips } from '@/components/phamani/tag-input';
import { Button } from '@/components/phamani/ui/button';
import {
    DropdownMenu,
    DropdownMenuContent,
    DropdownMenuItem,
    DropdownMenuSeparator,
    DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { useTags } from '@/hooks/use-tags';
import { formatCurrency, formatMonth, today } from '@/lib/format';
import { canMarkPaid, paymentStatus } from '@/lib/payment';
import {
    displayAmount,
    isFullyReimbursed,
    isThirdParty,
    receivableSplits,
} from '@/lib/split';
import { cn } from '@/lib/utils';
import { dashboard } from '@/routes';
import {
    index as transactionsIndex,
    pay as payTransaction,
} from '@/routes/transactions';
import type {
    Account,
    Category,
    Paginated,
    Transaction,
    TransactionFilters,
    TransactionKind,
    TransactionsSummary,
} from '@/types/phamani';

interface TransactionsPageProps {
    transactions: Paginated<Transaction>;
    summary: TransactionsSummary | null;
    filters: TransactionFilters;
    accounts: Account[];
    categories: Category[];
}

const STATUSES: Array<{
    value: NonNullable<TransactionFilters['status']>;
    label: string;
}> = [
    { value: 'overdue', label: 'Atrasadas' },
    { value: 'pending', label: 'Pendentes' },
    { value: 'paid', label: 'Pagas' },
];

const KINDS: Array<{ value: TransactionKind; label: string }> = [
    { value: 'split', label: 'Divididas' },
    { value: 'installment', label: 'Parceladas' },
    { value: 'recurring', label: 'Recorrentes' },
    { value: 'shared', label: 'Compartilhadas comigo' },
];

function currentMonth(): string {
    return today().slice(0, 7);
}

function shiftMonth(month: string, delta: number): string {
    const [y, m] = month.split('-').map(Number);
    const d = new Date(y, m - 1 + delta, 1);

    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
}

/** "Telefone (3/4)" → "Telefone" (a parcela já aparece na etiqueta). */
function cleanName(name: string): string {
    return name.replace(/\s\(\d+\/\d+\)$/, '');
}

/** Cabeçalho do dia: Hoje, Ontem, Amanhã ou "qui, 04 dez" (+ ano se não for o atual). */
function dayLabel(date: string): string {
    const todayStr = today();
    const [y, m, d] = date.split('-').map(Number);
    const value = new Date(y, m - 1, d);
    const base = new Date(`${todayStr}T00:00:00`);
    const diff = Math.round((value.getTime() - base.getTime()) / 86_400_000);

    if (diff === 0) return 'Hoje';
    if (diff === -1) return 'Ontem';
    if (diff === 1) return 'Amanhã';

    const label = value.toLocaleDateString('pt-BR', {
        weekday: 'short',
        day: '2-digit',
        month: 'short',
        ...(y !== base.getFullYear() ? { year: 'numeric' } : {}),
    });

    return label.charAt(0).toUpperCase() + label.slice(1).replace(/\./g, '');
}

function groupByDay(items: Transaction[]) {
    const groups: Array<{ date: string; items: Transaction[]; net: number }> =
        [];

    for (const t of items) {
        const date = t.date.slice(0, 10);
        let group = groups.at(-1);

        if (!group || group.date !== date) {
            group = { date, items: [], net: 0 };
            groups.push(group);
        }

        group.items.push(t);
        group.net += (t.type === 'income' ? 1 : -1) * Number(t.amount);
    }

    return groups;
}

export default function TransactionsIndex({
    transactions,
    summary,
    filters,
    accounts,
    categories,
}: TransactionsPageProps) {
    const [selected, setSelected] = useState<Transaction | null>(null);
    const [isNewTransactionOpen, setIsNewTransactionOpen] = useState(false);
    const [editing, setEditing] = useState<Transaction | null>(null);
    const [search, setSearch] = useState(filters.search ?? '');
    const [loadingMore, setLoadingMore] = useState(false);

    const isAll = filters.all === '1';
    const month = filters.month ?? currentMonth();
    const todayStr = today();

    // "Carregar mais": páginas seguintes são somadas às já exibidas; a 1ª página
    // (nova busca/filtro ou depois de salvar) recomeça a lista.
    const [list, setList] = useState({
        source: transactions,
        items: transactions.data,
    });
    if (list.source !== transactions) {
        const items =
            transactions.current_page > 1
                ? [
                      ...list.items,
                      ...transactions.data.filter(
                          (t) => !list.items.some((i) => i.id === t.id),
                      ),
                  ]
                : transactions.data;
        setList({ source: transactions, items });
    }

    function visit(next: TransactionFilters) {
        const clean = Object.fromEntries(
            Object.entries(next).filter(([, v]) => v),
        );

        router.get(transactionsIndex.url(), clean, {
            preserveState: true,
            preserveScroll: true,
            replace: true,
            only: ['transactions', 'summary', 'filters'],
        });
    }

    const tags = useTags();

    function applyFilter<K extends keyof TransactionFilters>(
        key: K,
        value?: TransactionFilters[K],
    ) {
        visit({ ...filters, [key]: value });
    }

    function goToMonth(next: string) {
        visit({ ...filters, month: next, all: undefined });
    }

    // Busca com pequeno atraso para não recarregar a cada tecla.
    useEffect(() => {
        if ((filters.search ?? '') === search) return;

        const timer = setTimeout(() => applyFilter('search', search), 350);

        return () => clearTimeout(timer);
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [search]);

    function loadMore() {
        if (!transactions.next_page_url) return;

        router.get(
            transactions.next_page_url,
            {},
            {
                preserveState: true,
                preserveScroll: true,
                only: ['transactions'],
                onStart: () => setLoadingMore(true),
                onFinish: () => setLoadingMore(false),
            },
        );
    }

    const hasFilters = !!(
        filters.account_id ||
        filters.category_id ||
        filters.tag_id ||
        filters.type ||
        filters.search ||
        filters.kind ||
        filters.status
    );
    const groups = groupByDay(list.items);

    return (
        <>
            <Head title="Transações" />

            <div className="mx-auto max-w-5xl p-6 md:p-8">
                <DashboardHeader
                    title="Transações"
                    subtitle={isAll ? 'Todo o período' : 'Mês a mês'}
                    onBack={() => router.visit(dashboard.url())}
                    actions={
                        <Button
                            variant="primary"
                            onClick={() => setIsNewTransactionOpen(true)}
                            className="h-12"
                        >
                            <Plus className="h-5 w-5 md:mr-2" />
                            <span className="hidden md:inline">
                                Nova Transação
                            </span>
                        </Button>
                    }
                />

                {/* Mês */}
                <div className="mb-6 flex flex-wrap items-center justify-between gap-3">
                    <div className="flex items-center gap-2">
                        <button
                            type="button"
                            onClick={() =>
                                goToMonth(
                                    shiftMonth(
                                        isAll ? currentMonth() : month,
                                        -1,
                                    ),
                                )
                            }
                            aria-label="Mês anterior"
                            className="rounded-xl border border-[#E8DCC4] bg-white p-2 text-[#6B4E3D] hover:bg-[#FBF7F1]"
                        >
                            <ChevronLeft className="h-5 w-5" />
                        </button>
                        <h2 className="min-w-48 text-center text-xl font-bold text-[#3D2817] capitalize">
                            {isAll ? 'Todo o período' : formatMonth(month)}
                        </h2>
                        <button
                            type="button"
                            onClick={() =>
                                goToMonth(
                                    shiftMonth(
                                        isAll ? currentMonth() : month,
                                        1,
                                    ),
                                )
                            }
                            aria-label="Próximo mês"
                            className="rounded-xl border border-[#E8DCC4] bg-white p-2 text-[#6B4E3D] hover:bg-[#FBF7F1]"
                        >
                            <ChevronRight className="h-5 w-5" />
                        </button>
                        {(isAll || month !== currentMonth()) && (
                            <button
                                type="button"
                                onClick={() => goToMonth(currentMonth())}
                                className="ml-1 rounded-xl px-3 py-2 text-sm font-medium text-[#6B4F3A] hover:bg-[#E8DCC4]"
                            >
                                Este mês
                            </button>
                        )}
                    </div>

                    <button
                        type="button"
                        onClick={() =>
                            visit({
                                ...filters,
                                all: isAll ? undefined : '1',
                                month: isAll ? currentMonth() : undefined,
                            })
                        }
                        aria-pressed={isAll}
                        className={cn(
                            'rounded-2xl border px-4 py-2 text-sm font-medium transition-colors',
                            isAll
                                ? 'border-[#3D2817] bg-[#3D2817] text-[#F5EFE6]'
                                : 'border-[#E8DCC4] bg-white text-[#3D2817] hover:bg-[#FBF7F1]',
                        )}
                    >
                        Todo o período
                    </button>
                </div>

                {/* Resumo do mês */}
                {summary && (
                    <div
                        className={cn(
                            'mb-6 grid grid-cols-2 gap-3',
                            summary.overdue_count > 0
                                ? 'md:grid-cols-5'
                                : 'md:grid-cols-4',
                        )}
                    >
                        <SummaryCard
                            label="Receitas"
                            value={summary.income}
                            tone="income"
                        />
                        <SummaryCard
                            label="Despesas"
                            value={summary.expense}
                            tone="expense"
                        />
                        <SummaryCard
                            label="Saldo do mês"
                            value={summary.balance}
                            tone={summary.balance >= 0 ? 'income' : 'expense'}
                        />
                        <SummaryCard
                            label={`A vencer${summary.due_count ? ` (${summary.due_count})` : ''}`}
                            value={summary.due}
                            tone="muted"
                        />
                        {summary.overdue_count > 0 && (
                            <button
                                type="button"
                                onClick={() => applyFilter('status', 'overdue')}
                                className="text-left"
                            >
                                <SummaryCard
                                    label={`Atrasadas (${summary.overdue_count})`}
                                    value={summary.overdue}
                                    tone="expense"
                                    highlight
                                />
                            </button>
                        )}
                    </div>
                )}

                {/* Busca e filtros */}
                <div className="sticky top-0 z-10 -mx-6 mb-4 space-y-3 bg-[#F5EFE6]/95 px-6 py-3 backdrop-blur-sm md:-mx-8 md:px-8">
                    <div className="relative">
                        <Search className="absolute top-1/2 left-4 h-4 w-4 -translate-y-1/2 text-[#8B7355]" />
                        <label htmlFor="tx-search" className="sr-only">
                            Buscar transações
                        </label>
                        <input
                            id="tx-search"
                            type="search"
                            value={search}
                            onChange={(e) => setSearch(e.target.value)}
                            placeholder="Buscar por descrição (ex.: Uber, Caixa…)"
                            className="w-full rounded-2xl border-2 border-[#E8DCC4] bg-white py-3 pr-4 pl-11 text-[#3D2817] placeholder:text-[#B8A48A] focus:border-[#6B4E3D] focus:outline-none"
                        />
                    </div>

                    <div className="scrollbar-hide flex items-center gap-2 overflow-x-auto pb-1">
                        <FilterPill
                            label={
                                accounts.find(
                                    (a) => a.id === filters.account_id,
                                )?.name ?? 'Conta'
                            }
                            active={!!filters.account_id}
                            options={accounts.map((a) => ({
                                value: a.id,
                                label: a.name,
                            }))}
                            allLabel="Todas as contas"
                            onSelect={(v) => applyFilter('account_id', v)}
                        />
                        <FilterPill
                            label={
                                categories.find(
                                    (c) => c.id === filters.category_id,
                                )?.name ?? 'Categoria'
                            }
                            active={!!filters.category_id}
                            options={categories.map((c) => ({
                                value: c.id,
                                label: c.name,
                            }))}
                            allLabel="Todas as categorias"
                            onSelect={(v) => applyFilter('category_id', v)}
                        />
                        {tags.length > 0 && (
                            <FilterPill
                                label={
                                    tags.find((t) => t.id === filters.tag_id)
                                        ?.name ?? 'Tag'
                                }
                                active={!!filters.tag_id}
                                options={tags.map((t) => ({
                                    value: t.id,
                                    label: t.name,
                                }))}
                                allLabel="Todas as tags"
                                onSelect={(v) => applyFilter('tag_id', v)}
                            />
                        )}
                        <FilterPill
                            label={
                                filters.type === 'income'
                                    ? 'Receitas'
                                    : filters.type === 'expense'
                                      ? 'Despesas'
                                      : 'Tipo'
                            }
                            active={!!filters.type}
                            options={[
                                { value: 'income', label: 'Receitas' },
                                { value: 'expense', label: 'Despesas' },
                            ]}
                            allLabel="Receitas e despesas"
                            onSelect={(v) =>
                                applyFilter(
                                    'type',
                                    v as TransactionFilters['type'],
                                )
                            }
                        />

                        <span className="mx-1 h-6 w-px shrink-0 bg-[#D4C5A9]" />

                        {STATUSES.map((st) => (
                            <Chip
                                key={st.value}
                                active={filters.status === st.value}
                                onClick={() =>
                                    applyFilter(
                                        'status',
                                        filters.status === st.value
                                            ? undefined
                                            : st.value,
                                    )
                                }
                            >
                                {st.label}
                            </Chip>
                        ))}

                        <span className="mx-1 h-6 w-px shrink-0 bg-[#D4C5A9]" />

                        {KINDS.map((k) => (
                            <Chip
                                key={k.value}
                                active={filters.kind === k.value}
                                onClick={() =>
                                    applyFilter(
                                        'kind',
                                        filters.kind === k.value
                                            ? undefined
                                            : k.value,
                                    )
                                }
                            >
                                {k.label}
                            </Chip>
                        ))}

                        {hasFilters && (
                            <button
                                type="button"
                                onClick={() => {
                                    setSearch('');
                                    visit({
                                        month: filters.month,
                                        all: filters.all,
                                    });
                                }}
                                className="flex shrink-0 items-center gap-1 px-3 py-2 text-sm whitespace-nowrap text-[#8B7355] hover:text-[#3D2817]"
                            >
                                <X className="h-4 w-4" /> Limpar
                            </button>
                        )}
                    </div>
                </div>

                {/* Lista agrupada por dia */}
                {groups.length === 0 ? (
                    <p className="rounded-3xl border border-dashed border-[#D4C5A9] p-12 text-center text-[#8B7355]">
                        {hasFilters
                            ? 'Nenhuma transação com esses filtros.'
                            : isAll
                              ? 'Nenhuma transação ainda.'
                              : 'Nenhuma transação neste mês.'}
                    </p>
                ) : (
                    <div className="space-y-6">
                        {groups.map((group) => (
                            <section key={group.date}>
                                <div className="mb-2 flex items-baseline justify-between px-2">
                                    <h3 className="text-sm font-bold text-[#6B4E3D]">
                                        {dayLabel(group.date)}
                                        {group.date > todayStr && (
                                            <span className="ml-2 text-xs font-medium text-[#8B7355]">
                                                agendado
                                            </span>
                                        )}
                                    </h3>
                                    <span
                                        className={cn(
                                            'text-xs font-bold',
                                            group.net >= 0
                                                ? 'text-[#1F5428]'
                                                : 'text-[#8B7355]',
                                        )}
                                    >
                                        {group.net >= 0 ? '+' : '-'}{' '}
                                        {formatCurrency(Math.abs(group.net))}
                                    </span>
                                </div>
                                <ul className="divide-y divide-[#E8DCC4] overflow-hidden rounded-3xl border border-[#E8DCC4] bg-white shadow-sm">
                                    {group.items.map((t) => (
                                        <TransactionRow
                                            key={t.id}
                                            transaction={t}
                                            scheduled={
                                                t.date.slice(0, 10) > todayStr
                                            }
                                            onClick={() => setSelected(t)}
                                        />
                                    ))}
                                </ul>
                            </section>
                        ))}
                    </div>
                )}

                {transactions.next_page_url && (
                    <div className="mt-6 flex justify-center">
                        <button
                            type="button"
                            onClick={loadMore}
                            disabled={loadingMore}
                            className="rounded-2xl border-2 border-[#D4C5A9] bg-white px-6 py-3 text-sm font-medium text-[#6B4E3D] hover:bg-[#FBF7F1] disabled:opacity-50"
                        >
                            {loadingMore
                                ? 'Carregando…'
                                : `Carregar mais (${list.items.length} de ${transactions.total})`}
                        </button>
                    </div>
                )}

                <ShowTransactionDrawer
                    transaction={selected}
                    onClose={() => setSelected(null)}
                    onEdit={(t) => {
                        setSelected(null);
                        setEditing(t);
                    }}
                />

                <NewTransactionModal
                    isOpen={!!editing}
                    onClose={() => setEditing(null)}
                    categories={categories}
                    accounts={accounts}
                    transaction={editing}
                />

                <NewTransactionModal
                    isOpen={isNewTransactionOpen}
                    onClose={() => setIsNewTransactionOpen(false)}
                    categories={categories}
                    accounts={accounts}
                />
            </div>
        </>
    );
}

function TransactionRow({
    transaction: t,
    scheduled,
    onClick,
}: {
    transaction: Transaction;
    scheduled: boolean;
    onClick: () => void;
}) {
    const [paying, setPaying] = useState(false);
    const isIncome = t.type === 'income';
    const status = paymentStatus(t);
    const where = t.account?.name
        ? t.account.name
        : t.paid_by
          ? `Pago por ${t.paid_by.name}`
          : t.mirrored_from?.user
            ? `De ${t.mirrored_from.user.name}`
            : null;

    const canPay = status !== null && status !== 'paid' && canMarkPaid(t);

    function pay() {
        router.post(
            payTransaction.url(t.id),
            {},
            {
                preserveScroll: true,
                preserveState: true,
                onStart: () => setPaying(true),
                onFinish: () => setPaying(false),
            },
        );
    }

    return (
        <li className="flex items-center">
            <button
                type="button"
                onClick={onClick}
                className={cn(
                    'flex min-w-0 flex-1 items-center gap-4 px-4 py-3 text-left transition-colors hover:bg-[#F5EFE6] md:px-6',
                    scheduled &&
                        status !== 'overdue' &&
                        'opacity-60 hover:opacity-100',
                )}
            >
                <CategoryIcon
                    category={t.category}
                    className="h-10 w-10 shrink-0 rounded-xl"
                    iconClassName="h-5 w-5"
                />

                <div className="min-w-0 flex-1">
                    <p className="truncate font-bold text-[#3D2817]">
                        {cleanName(t.name)}
                    </p>
                    <div className="mt-0.5 flex flex-wrap items-center gap-1 text-xs text-[#8B7355]">
                        <span>{t.category?.name}</span>
                        {where && (
                            <>
                                <span aria-hidden>·</span>
                                <span>{where}</span>
                            </>
                        )}
                        {status && status !== 'paid' && (
                            <PaymentStatusBadge
                                status={status}
                                isIncome={isIncome}
                            />
                        )}
                        {t.installment_number && t.installment && (
                            <Tag>
                                {t.installment_number}/
                                {t.installment.installments}
                            </Tag>
                        )}
                        {t.recurring && <Tag>Recorrente</Tag>}
                        <TagChips tags={t.tags} />
                        {t.mirrored_from_id && <Tag>Compartilhada</Tag>}
                        {isThirdParty(t) ? (
                            <>
                                <Tag>
                                    Para{' '}
                                    {receivableSplits(t)
                                        .map((s) => s.contact?.name)
                                        .filter(Boolean)
                                        .join(', ')}
                                </Tag>
                                <ReceivableTag
                                    received={isFullyReimbursed(t)}
                                />
                            </>
                        ) : (
                            t.total_amount != null && (
                                <Tag>
                                    Dividido · {formatCurrency(t.total_amount)}
                                </Tag>
                            )
                        )}
                    </div>
                </div>

                <span
                    className={cn(
                        'shrink-0 text-sm font-bold whitespace-nowrap',
                        isIncome ? 'text-[#1F5428]' : 'text-[#3D2817]',
                        status === 'overdue' && 'text-[#A65D57]',
                    )}
                >
                    {isIncome ? '+' : '-'} {formatCurrency(displayAmount(t))}
                </span>
            </button>

            {canPay && (
                <button
                    type="button"
                    onClick={pay}
                    disabled={paying}
                    aria-label={`Marcar ${cleanName(t.name)} como ${isIncome ? 'recebida' : 'paga'}`}
                    title={
                        isIncome ? 'Marcar como recebida' : 'Marcar como paga'
                    }
                    className={cn(
                        'mr-3 flex h-9 w-9 shrink-0 items-center justify-center rounded-full border-2 transition-colors disabled:opacity-50 md:mr-4',
                        status === 'overdue'
                            ? 'border-[#A65D57] text-[#A65D57] hover:bg-[#A65D57] hover:text-white'
                            : 'border-[#D4C5A9] text-[#8B7355] hover:border-[#1F5428] hover:bg-[#1F5428] hover:text-white',
                    )}
                >
                    <Check className="h-4 w-4" />
                </button>
            )}
        </li>
    );
}

function SummaryCard({
    label,
    value,
    tone,
    highlight = false,
}: {
    label: string;
    value: number;
    tone: 'income' | 'expense' | 'muted';
    highlight?: boolean;
}) {
    return (
        <div
            className={cn(
                'h-full rounded-2xl border bg-white px-4 py-3 shadow-sm',
                highlight
                    ? 'border-[#A65D57] bg-[#FDF3F2]'
                    : 'border-[#E8DCC4]',
            )}
        >
            <p className="text-xs font-bold tracking-wider text-[#8B7355] uppercase">
                {label}
            </p>
            <p
                className={cn(
                    'text-lg font-bold',
                    tone === 'income' && 'text-[#1F5428]',
                    tone === 'expense' && 'text-[#A65D57]',
                    tone === 'muted' && 'text-[#6B4E3D]',
                )}
            >
                {formatCurrency(value)}
            </p>
        </div>
    );
}

/** Compra para outra pessoa: ainda a receber ou já devolvida. */
function ReceivableTag({ received }: { received: boolean }) {
    return (
        <span
            className={cn(
                'inline-flex items-center rounded-md px-1.5 py-0.5 text-[10px] font-bold tracking-wide uppercase',
                received
                    ? 'bg-[#E3F1E6] text-[#1F5428]'
                    : 'bg-[#FCE7E7] text-[#A65D57]',
            )}
        >
            {received ? 'Recebido' : 'A receber'}
        </span>
    );
}

function Tag({ children }: { children: ReactNode }) {
    return (
        <span className="inline-flex items-center rounded-md bg-[#E8DCC4] px-1.5 py-0.5 text-[10px] font-bold tracking-wide text-[#6B4E3D] uppercase">
            {children}
        </span>
    );
}

function Chip({
    active,
    onClick,
    children,
}: {
    active: boolean;
    onClick: () => void;
    children: ReactNode;
}) {
    return (
        <button
            type="button"
            onClick={onClick}
            aria-pressed={active}
            className={cn(
                'shrink-0 rounded-2xl border px-3 py-2 text-sm font-medium whitespace-nowrap transition-colors',
                active
                    ? 'border-[#3D2817] bg-[#3D2817] text-[#F5EFE6]'
                    : 'border-[#E8DCC4] bg-white text-[#3D2817] hover:bg-[#FBF7F1]',
            )}
        >
            {children}
        </button>
    );
}

interface FilterPillProps {
    label: string;
    active: boolean;
    allLabel: string;
    options: Array<{ value: string; label: string }>;
    onSelect: (value?: string) => void;
}

function FilterPill({
    label,
    active,
    allLabel,
    options,
    onSelect,
}: FilterPillProps) {
    return (
        <DropdownMenu>
            <DropdownMenuTrigger asChild>
                <button
                    type="button"
                    className={cn(
                        'flex shrink-0 items-center gap-2 rounded-2xl border px-4 py-2 text-sm font-medium whitespace-nowrap transition-colors',
                        active
                            ? 'border-[#3D2817] bg-[#3D2817] text-[#F5EFE6]'
                            : 'border-[#E8DCC4] bg-white text-[#3D2817] hover:bg-[#FBF7F1]',
                    )}
                >
                    <span>{label}</span>
                    <ChevronDown
                        className={cn(
                            'h-4 w-4',
                            active ? 'text-[#F5EFE6]' : 'text-[#8B7355]',
                        )}
                    />
                </button>
            </DropdownMenuTrigger>
            <DropdownMenuContent
                align="start"
                className="max-h-80 overflow-y-auto rounded-xl"
            >
                <DropdownMenuItem
                    onSelect={() => onSelect(undefined)}
                    className="cursor-pointer"
                >
                    {allLabel}
                </DropdownMenuItem>
                <DropdownMenuSeparator />
                {options.map((o) => (
                    <DropdownMenuItem
                        key={o.value}
                        onSelect={() => onSelect(o.value)}
                        className="cursor-pointer"
                    >
                        {o.label}
                    </DropdownMenuItem>
                ))}
            </DropdownMenuContent>
        </DropdownMenu>
    );
}
PHAMANI_EOF

write 'resources/js/types/phamani/index.ts' <<'PHAMANI_EOF'
export * from './account';
export * from './category';
export * from './contact';
export * from './dashboard';
export * from './pagination';
export * from './tag';
export * from './transaction';
PHAMANI_EOF

write 'resources/js/types/phamani/tag.ts' <<'PHAMANI_EOF'
/** Tag livre de transação (ex.: "iFood", "Amazon"). Pessoal de cada usuário. */
export interface Tag {
    id: string;
    name: string;
    /** Só na lista de "Gerenciar tags". */
    transactions_count?: number;
}
PHAMANI_EOF

write 'resources/js/types/phamani/transaction.ts' <<'PHAMANI_EOF'
import type { RecurringFrequency } from '@/types/enums';
import type { Account } from './account';
import type { Category } from './category';
import type {
    Contact,
    MirrorSource,
    ShareLinkInfo,
    SplitForm,
    TransactionSplit,
} from './contact';
import type { Tag } from './tag';

export type TransactionType = 'income' | 'expense';

export interface InstallmentInfo {
    id: string;
    name: string;
    installments: number;
    installment_amount: string;
    total_amount: string;
    transactions?: Array<{
        id: string;
        installment_id: string;
        installment_number: number;
        date: string;
        amount: string;
    }>;
    /** Débito automático */
    auto_pay?: boolean;
}

export interface Transaction {
    id: string;
    tags?: Tag[];
    name: string;
    description: string | null;
    /** Sua parte (numa divisão) ou o valor inteiro. */
    amount: string | number;
    type: TransactionType;
    date: string;

    /** Valor cheio quando a transação é dividida. */
    total_amount?: string | number | null;
    /** Quem pagou (null = você). */
    paid_by_contact_id?: string | null;
    paid_by?: Pick<Contact, 'id' | 'name' | 'linked_user_id'> | null;
    /** Pago/recebido em (null = pendente ou atrasado). */
    paid_at?: string | null;
    splits?: TransactionSplit[];

    /** Cópia de uma divisão compartilhada por outra pessoa (somente leitura). */
    mirrored_from_id?: string | null;
    mirrored_from?: MirrorSource | null;
    /** Do lado de quem criou: status de cada pessoa com quem foi compartilhada. */
    share_links?: ShareLinkInfo[];

    category_id: string;
    category?: Pick<Category, 'id' | 'name' | 'color' | 'icon'>;

    /** null quando outra pessoa pagou */
    account_id: string | null;
    account?: Pick<Account, 'id' | 'name' | 'type'>;

    installment_id: string | null;
    installment_number: number | null;
    installment?: InstallmentInfo | null;

    recurring_id: string | null;
    recurring?: {
        id: string;
        frequency: RecurringFrequency;
        end_date: string | null;
        /** Débito automático */
        auto_pay?: boolean;
    } | null;

    /** true quando a data já chegou e o valor entrou no saldo da conta. */
    balance_applied?: boolean;
}

export interface TransactionFormData {
    description: string;
    amount: number | '';
    type: TransactionType;
    category_id: string;
    account_id: string;
    date: string;

    is_installment: boolean;
    installments_count: number;
    /** Primeira parcela a lançar (ex.: 15 num parcelamento já na 15/24). */
    installment_start: number;
    /** O valor digitado é o total ou o de cada parcela. */
    amount_mode: 'total' | 'installment';
    /** Edição de parcela: repetir o valor nas parcelas seguintes. */
    apply_to_following: boolean;
    /** Divisão com contatos (null = sem divisão). */
    split: SplitForm | null;
    /** Débito automático (parcelado/recorrente). */
    auto_pay: boolean;
    is_recurring: boolean;
    frequency: RecurringFrequency;
    /** Tags livres (nomes). */
    tags: string[];
}

export type TransactionKind = 'split' | 'installment' | 'recurring' | 'shared';

export interface TransactionFilters {
    account_id?: string;
    category_id?: string;
    tag_id?: string;
    type?: TransactionType;
    /** YYYY-MM (padrão: mês atual) */
    month?: string;
    /** '1' = todo o período */
    all?: string;
    search?: string;
    kind?: TransactionKind;
    status?: 'paid' | 'pending' | 'overdue';
}

/** Totais do mês exibido na lista de transações. */
export interface TransactionsSummary {
    income: number;
    expense: number;
    balance: number;
    /** Despesas com data futura dentro do mês (agendadas). */
    due: number;
    due_count: number;
    /** Despesas vencidas e não pagas. */
    overdue: number;
    overdue_count: number;
    count: number;
}
PHAMANI_EOF

write 'routes/web.php' <<'PHAMANI_EOF'
<?php

use App\Http\Controllers\AccountController;
use App\Http\Controllers\AutoPayController;
use App\Http\Controllers\Auth\GoogleAuthController;
use App\Http\Controllers\CategoryController;
use App\Http\Controllers\ContactController;
use App\Http\Controllers\CreditCardController;
use App\Http\Controllers\DashboardController;
use App\Http\Controllers\InboxController;
use App\Http\Controllers\InvitationController;
use App\Http\Controllers\RecurringTransactionController;
use App\Http\Controllers\ReimbursementController;
use App\Http\Controllers\ShareController;
use App\Http\Controllers\TagController;
use App\Http\Controllers\TransactionController;
use Illuminate\Support\Facades\Route;

/*
| Autenticação (somente Google)
*/
Route::middleware('guest')->group(function () {
    Route::get('/', [GoogleAuthController::class, 'login'])->name('login');

    Route::get('auth/google/redirect', [GoogleAuthController::class, 'redirect'])->name('auth.google.redirect');
    Route::get('auth/google/callback', [GoogleAuthController::class, 'callback'])->name('auth.google.callback');
});

Route::post('logout', [GoogleAuthController::class, 'logout'])
    ->middleware('auth')
    ->name('logout');

/*
| Aplicação
*/
Route::middleware('auth')->group(function () {
    Route::get('dashboard', DashboardController::class)->name('dashboard');

    // Compra para outra pessoa: "a receber"
    Route::post('receivables/{contact}/receive', [ReimbursementController::class, 'receive'])->name('receivables.receive');
    Route::delete('receivables/{split}', [ReimbursementController::class, 'undo'])->name('receivables.undo');

    Route::get('transactions', [TransactionController::class, 'index'])->name('transactions.index');
    Route::post('transactions', [TransactionController::class, 'store'])->name('transactions.store');
    Route::put('transactions/{transaction}', [TransactionController::class, 'update'])->name('transactions.update');
    Route::delete('transactions/{transaction}', [TransactionController::class, 'destroy'])->name('transactions.destroy');
    Route::post('transactions/{transaction}/pay', [TransactionController::class, 'pay'])->name('transactions.pay');
    Route::delete('transactions/{transaction}/pay', [TransactionController::class, 'unpay'])->name('transactions.unpay');

    Route::post('recurring/{recurring}/end', [RecurringTransactionController::class, 'end'])->name('recurring.end');
    Route::post('recurring/{recurring}/auto-pay', [AutoPayController::class, 'recurring'])->name('recurring.auto-pay');
    Route::post('installments/{installment}/auto-pay', [AutoPayController::class, 'installment'])->name('installments.auto-pay');

    Route::post('accounts', [AccountController::class, 'store'])->name('accounts.store');
    Route::put('accounts/{account}', [AccountController::class, 'update'])->name('accounts.update');

    Route::get('cards/{account}', [CreditCardController::class, 'show'])->name('cards.show');
    Route::post('invoices/{invoice}/pay', [CreditCardController::class, 'pay'])->name('invoices.pay');
    Route::delete('invoices/{invoice}/payment', [CreditCardController::class, 'undo'])->name('invoices.undo');
    Route::post('categories', [CategoryController::class, 'store'])->name('categories.store');
    Route::put('categories/{category}', [CategoryController::class, 'update'])->name('categories.update');

    Route::put('tags/{tag}', [TagController::class, 'update'])->name('tags.update');
    Route::delete('tags/{tag}', [TagController::class, 'destroy'])->name('tags.destroy');

    Route::post('contacts', [ContactController::class, 'store'])->name('contacts.store');
    Route::put('contacts/{contact}', [ContactController::class, 'update'])->name('contacts.update');
    Route::delete('contacts/{contact}', [ContactController::class, 'destroy'])->name('contacts.destroy');
    Route::post('contacts/{contact}/invite', [InvitationController::class, 'store'])->name('contacts.invite');
    Route::post('contacts/{contact}/unlink', [InvitationController::class, 'unlink'])->name('contacts.unlink');

    // Pendências (convites e divisões compartilhadas)
    Route::get('inbox', [InboxController::class, 'index'])->name('inbox');
    Route::post('notifications/read', [InboxController::class, 'markNotificationsRead'])->name('notifications.read');
    Route::post('invitations/{invitation}/accept', [InvitationController::class, 'accept'])->name('invitations.accept');
    Route::post('invitations/{invitation}/decline', [InvitationController::class, 'decline'])->name('invitations.decline');
    Route::post('shares/{share}/accept', [ShareController::class, 'accept'])->name('shares.accept');
    Route::post('shares/{share}/decline', [ShareController::class, 'decline'])->name('shares.decline');
    Route::post('shares/{share}/leave', [ShareController::class, 'leave'])->name('shares.leave');
});
PHAMANI_EOF

write 'tests/Feature/TagTest.php' <<'PHAMANI_EOF'
<?php

namespace Tests\Feature;

use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\ICategoryService;
use App\Models\Account;
use App\Models\Category;
use App\Models\Tag;
use App\Models\Transaction;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Inertia\Testing\AssertableInertia as Assert;
use Tests\TestCase;

/**
 * Tags livres nas transações (ex.: "iFood", "Amazon").
 */
class TagTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    private Account $account;

    private Category $category;

    protected function setUp(): void
    {
        parent::setUp();

        $this->travelTo('2026-11-18 10:00:00');

        $this->user = User::factory()->create();
        app(IAccountService::class)->createDefaultForUser($this->user->id);
        app(ICategoryService::class)->createDefaultsForUser($this->user->id);
        $this->account = Account::create(['user_id' => $this->user->id, 'name' => 'Bradesco', 'type' => 'checking', 'balance' => 1000]);
        $this->category = Category::where('user_id', $this->user->id)->where('name', 'Alimentação')->firstOrFail();
    }

    /**
     * @param  array<string, mixed>  $overrides
     */
    private function store(array $overrides = []): Transaction
    {
        $this->actingAs($this->user)
            ->post(route('transactions.store'), [
                'description' => 'Pedido',
                'amount' => 50,
                'type' => 'expense',
                'category_id' => $this->category->id,
                'account_id' => $this->account->id,
                'date' => '2026-11-18',
                'is_installment' => false,
                'installments_count' => 2,
                'installment_start' => 1,
                'amount_mode' => 'installment',
                'is_recurring' => false,
                'frequency' => 'monthly',
                'tags' => ['iFood'],
                ...$overrides,
            ])
            ->assertSessionHasNoErrors();

        return Transaction::query()->latest('created_at')->firstOrFail();
    }

    /** @return list<string> */
    private function tagNames(Transaction $transaction): array
    {
        return $transaction->tags()->orderBy('name')->pluck('name')->all();
    }

    public function test_tags_are_created_without_duplicates(): void
    {
        $transaction = $this->store(['tags' => ['iFood', 'ifood', ' Amazon ']]);

        $this->assertSame(['Amazon', 'iFood'], $this->tagNames($transaction));
        $this->assertSame(2, Tag::where('user_id', $this->user->id)->count());
    }

    public function test_a_different_spelling_reuses_the_existing_tag(): void
    {
        $this->store(['tags' => ['iFood']]);
        $second = $this->store(['tags' => ['IFOOD']]);

        $this->assertSame(1, Tag::where('user_id', $this->user->id)->count());
        $this->assertSame(['iFood'], $this->tagNames($second));
    }

    public function test_every_parcel_gets_the_tags(): void
    {
        $this->store(['description' => 'Celular', 'is_installment' => true, 'installments_count' => 3, 'tags' => ['Amazon']]);

        $parcels = Transaction::whereNotNull('installment_id')->get();
        $this->assertCount(3, $parcels);
        $parcels->each(fn (Transaction $p) => $this->assertSame(['Amazon'], $this->tagNames($p)));
    }

    public function test_next_recurring_occurrence_copies_the_tags(): void
    {
        $this->store(['description' => 'Spotify', 'is_recurring' => true, 'tags' => ['Assinaturas']]);

        $this->travelTo('2026-12-18 10:00:00');
        $this->artisan('phamani:process-due')->assertSuccessful();

        $occurrences = Transaction::whereNotNull('recurring_id')->orderBy('date')->get();
        $this->assertCount(2, $occurrences);
        $this->assertSame(['Assinaturas'], $this->tagNames($occurrences[1]));
    }

    public function test_editing_replaces_the_tags_and_omitting_them_keeps_them(): void
    {
        $transaction = $this->store(['tags' => ['iFood']]);

        $payload = [
            'description' => 'Pedido',
            'amount' => 50,
            'type' => 'expense',
            'category_id' => $this->category->id,
            'account_id' => $this->account->id,
            'date' => '2026-11-18',
        ];

        $this->actingAs($this->user)->put(route('transactions.update', $transaction), [...$payload, 'tags' => ['Rappi']])
            ->assertSessionHasNoErrors();
        $this->assertSame(['Rappi'], $this->tagNames($transaction));

        $this->actingAs($this->user)->put(route('transactions.update', $transaction), $payload)
            ->assertSessionHasNoErrors();
        $this->assertSame(['Rappi'], $this->tagNames($transaction));
    }

    public function test_list_can_be_filtered_by_tag(): void
    {
        $this->store(['description' => 'Pedido 1', 'tags' => ['iFood']]);
        $this->store(['description' => 'Pedido 2', 'tags' => ['iFood']]);
        $this->store(['description' => 'Livro', 'tags' => ['Amazon']]);

        $ifood = Tag::where('name', 'iFood')->firstOrFail();

        $this->actingAs($this->user)
            ->get(route('transactions.index', ['tag_id' => $ifood->id]))
            ->assertInertia(fn (Assert $page) => $page
                ->has('transactions.data', 2)
                ->where('summary.expense', fn ($v) => (float) $v === 100.0));
    }

    public function test_renaming_to_an_existing_name_merges_the_tags(): void
    {
        $a = $this->store(['tags' => ['Ifood']]);
        $b = $this->store(['tags' => ['Delivery']]);

        $delivery = Tag::where('name', 'Delivery')->firstOrFail();

        $this->actingAs($this->user)->put(route('tags.update', $delivery), ['name' => 'IFOOD'])
            ->assertSessionHasNoErrors();

        $this->assertSame(1, Tag::where('user_id', $this->user->id)->count());
        $this->assertSame(['IFOOD'], $this->tagNames($a));
        $this->assertSame(['IFOOD'], $this->tagNames($b));
    }

    public function test_deleting_a_tag_keeps_the_transactions(): void
    {
        $transaction = $this->store(['tags' => ['iFood']]);
        $tag = Tag::firstOrFail();

        $this->actingAs($this->user)->delete(route('tags.destroy', $tag))->assertSessionHasNoErrors();

        $this->assertNotNull($transaction->fresh());
        $this->assertSame([], $this->tagNames($transaction));
    }

    public function test_tags_are_personal(): void
    {
        $this->store(['tags' => ['iFood']]);
        $tag = Tag::firstOrFail();

        $this->actingAs(User::factory()->create())
            ->put(route('tags.update', $tag), ['name' => 'X'])
            ->assertNotFound();
    }
}
PHAMANI_EOF

cat <<'MSG'

Pronto. Local:
  php artisan migrate
  php artisan wayfinder:generate --with-form
  php artisan test --filter=TagTest
Depois: git add -A && git commit -m "Tags nas transações" && git push
MSG
