#!/usr/bin/env bash
# Phamani — Compra para outra pessoa ("A receber")
#  - Na divisão, desmarcar "Você" = compra para outra pessoa: o valor cheio vai para a conta/fatura
#    (e consome o limite), mas não entra nas suas despesas; a parte de cada contato fica "a receber".
#  - Card "A receber" no dashboard, por contato. "Registrar recebimento": marca as compras pagas,
#    escolhe a conta onde o Pix caiu; o saldo sobe sem contar como receita. Dá para desfazer no drawer.
#  - Parcelas futuras aparecem como "próximas" (podem ser marcadas se a pessoa adiantou).
#  - Editar a compra mantém o recebimento; apagar a compra tira o reembolso do saldo.
#  - Lista/recentes/drawer mostram o valor cheio com as etiquetas "Para …" e "A receber"/"Recebido".
# Migration nova: transaction_splits.reimbursed_at / reimbursement_account_id / reimbursed_amount.
# Uso: na raiz do projeto ->  bash compra-para-outra-pessoa.sh
set -euo pipefail
[ -f artisan ] && [ -f app/Services/SplitService.php ] || { echo "Rode na raiz do projeto Phamani."; exit 1; }
BACKUP=".backup-$(date +%Y%m%d%H%M%S)"
backup() { if [ -f "$1" ]; then mkdir -p "$BACKUP/$(dirname "$1")"; cp "$1" "$BACKUP/$1"; fi; }
write() { backup "$1"; mkdir -p "$(dirname "$1")"; cat > "$1"; echo "  ok  $1"; }
echo "Aplicando arquivos (backup em $BACKUP/):"

write 'app/DTOs/Transaction/SplitData.php' <<'PHAMANI_EOF'
<?php

namespace App\DTOs\Transaction;

use Illuminate\Support\Facades\Auth;
use Illuminate\Validation\Rule;
use Spatie\LaravelData\Attributes\DataCollectionOf;
use Spatie\LaravelData\Attributes\Validation\In;
use Spatie\LaravelData\Data;

/**
 * Divisão de uma despesa entre você e seus contatos.
 *
 * - mode "equal": partes iguais; "custom": valor de cada um (a soma tem que bater com o valor informado).
 * - paid_by_contact_id: quem pagou (null = você). Se foi outra pessoa, nenhuma conta sua é afetada.
 * - include_me: false = compra para outra pessoa — você pagou, sua parte é zero e o valor fica "a receber".
 */
class SplitData extends Data
{
    public function __construct(
        #[In(['equal', 'custom'])]
        public string $mode = 'equal',

        /** @var array<int, SplitParticipantData> */
        #[DataCollectionOf(SplitParticipantData::class)]
        public array $participants = [],

        public ?string $paid_by_contact_id = null,

        public bool $include_me = true,
    ) {}

    /**
     * @return array<string, array<int, mixed>>
     */
    public static function rules(): array
    {
        return [
            'participants' => ['required', 'array', 'min:1'],
            'paid_by_contact_id' => ['nullable', 'uuid', Rule::exists('contacts', 'id')->where('user_id', Auth::id())],
        ];
    }

    /**
     * IDs dos contatos participantes (sem você).
     *
     * @return list<string>
     */
    public function contactIds(): array
    {
        return array_values(array_filter(array_map(
            fn (SplitParticipantData $p) => $p->contact_id,
            $this->participants,
        )));
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

write 'app/Http/Controllers/DashboardController.php' <<'PHAMANI_EOF'
<?php

namespace App\Http\Controllers;

use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\ICategoryService;
use App\Interfaces\Services\IDashboardService;
use App\Interfaces\Services\IReimbursementService;
use App\Interfaces\Services\ITransactionService;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Inertia\Inertia;
use Inertia\Response;

class DashboardController extends Controller
{
    public function __construct(
        protected IAccountService $accountService,
        protected ICategoryService $categoryService,
        protected IDashboardService $dashboardService,
        protected ITransactionService $transactionService,
        protected IReimbursementService $reimbursements,
    ) {}

    public function __invoke(Request $request): Response
    {
        $userId = (string) $request->user()?->getAuthIdentifier();

        $period = $request->validate([
            'period' => ['nullable', Rule::in(['monthly', 'yearly'])],
        ])['period'] ?? 'yearly';

        return Inertia::render('dashboard', [
            'period' => $period,
            'kpis' => fn () => $this->dashboardService->kpis($userId),
            'cashFlow' => fn () => $this->dashboardService->cashFlow($userId, $period),
            'categoryPie' => fn () => $this->dashboardService->categoryPie($userId, $period),
            'recentTransactions' => fn () => $this->transactionService->getRecentForDashboard($userId),
            'accounts' => fn () => $this->accountService->listForUser($userId),
            'receivables' => fn () => $this->reimbursements->openForUser($userId),
            'categories' => fn () => $this->categoryService->listForUser($userId),
        ]);
    }
}
PHAMANI_EOF

write 'app/Http/Controllers/ReimbursementController.php' <<'PHAMANI_EOF'
<?php

namespace App\Http\Controllers;

use App\Interfaces\Services\IReimbursementService;
use App\Models\Contact;
use App\Models\TransactionSplit;
use App\Models\User;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;

/**
 * Compra para outra pessoa: registrar (ou desfazer) o reembolso.
 */
class ReimbursementController extends Controller
{
    public function __construct(
        protected IReimbursementService $reimbursements,
    ) {}

    public function receive(Request $request, Contact $contact): RedirectResponse
    {
        $data = $request->validate([
            'split_ids' => ['required', 'array', 'min:1'],
            'split_ids.*' => ['uuid'],
            'account_id' => ['required', 'uuid'],
            'date' => ['required', 'date'],
        ]);

        /** @var User $user */
        $user = $request->user();

        $this->reimbursements->receive($user, $contact, array_values($data['split_ids']), $data['account_id'], $data['date']);

        Inertia::flash('toast', ['type' => 'success', 'message' => "Recebimento de {$contact->name} registrado."]);

        return back();
    }

    public function undo(Request $request, TransactionSplit $split): RedirectResponse
    {
        /** @var User $user */
        $user = $request->user();

        $this->reimbursements->undo($user, $split);

        Inertia::flash('toast', ['type' => 'success', 'message' => 'Recebimento desfeito.']);

        return back();
    }
}
PHAMANI_EOF

write 'app/Interfaces/Services/IReimbursementService.php' <<'PHAMANI_EOF'
<?php

namespace App\Interfaces\Services;

use App\Models\Contact;
use App\Models\Transaction;
use App\Models\TransactionSplit;
use App\Models\User;

/**
 * Compra para outra pessoa: o que cada contato te deve e o registro do reembolso (Pix).
 *
 * Entra aqui toda despesa paga por você em que a sua parte é zero; a parte de cada contato
 * fica "a receber" até você registrar o recebimento. O dinheiro que volta aumenta o saldo da
 * conta escolhida, mas não conta como receita.
 */
interface IReimbursementService
{
    /**
     * Contatos com valores em aberto, cada um com as compras pendentes (vencidas e futuras).
     *
     * @return list<array{
     *     contact: array{id: string, name: string, avatar: string|null},
     *     due_total: float,
     *     due_count: int,
     *     items: list<array{id: string, transaction_id: string, name: string, date: string, amount: float, due: bool}>
     * }>
     */
    public function openForUser(string $userId): array;

    /**
     * Registra que o contato devolveu as partes escolhidas, com o dinheiro caindo em $accountId.
     *
     * @param  list<string>  $splitIds
     */
    public function receive(User $user, Contact $contact, array $splitIds, string $accountId, string $date): void;

    /** Desfaz um recebimento (o valor sai de novo da conta onde tinha entrado). */
    public function undo(User $user, TransactionSplit $split): void;

    /** Antes de apagar uma transação: tira dos saldos os reembolsos já registrados nela. */
    public function revertFor(Transaction $transaction): void;
}
PHAMANI_EOF

write 'app/Models/TransactionSplit.php' <<'PHAMANI_EOF'
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Parte de um participante numa transação dividida. contact_id null = o dono da transação.
 *
 * @property string $id
 * @property string $transaction_id
 * @property string|null $contact_id
 * @property string $amount
 * @property \Carbon\CarbonInterface|null $reimbursed_at
 * @property string|null $reimbursement_account_id
 * @property string|null $reimbursed_amount
 */
class TransactionSplit extends BaseModel
{
    protected $fillable = [
        'transaction_id',
        'contact_id',
        'amount',
        'reimbursed_at',
        'reimbursement_account_id',
        'reimbursed_amount',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
        'reimbursed_at' => 'date:Y-m-d',
        'reimbursed_amount' => 'decimal:2',
    ];

    /** @return BelongsTo<Transaction, $this> */
    public function transaction(): BelongsTo
    {
        return $this->belongsTo(Transaction::class);
    }

    /** @return BelongsTo<Contact, $this> */
    public function contact(): BelongsTo
    {
        return $this->belongsTo(Contact::class);
    }

    /**
     * Conta onde caiu o reembolso (compra para outra pessoa).
     *
     * @return BelongsTo<Account, $this>
     */
    public function reimbursementAccount(): BelongsTo
    {
        return $this->belongsTo(Account::class, 'reimbursement_account_id');
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
     * @param  array{account_id?: ?string, category_id?: ?string, type?: ?string, month?: ?string, search?: ?string, kind?: ?string}  $filters
     */
    private function filtered(string $userId, array $filters): Builder
    {
        return $this->query()
            ->where('user_id', $userId)
            ->when($filters['account_id'] ?? null, fn ($q, $id) => $q->where('account_id', $id))
            ->when($filters['category_id'] ?? null, fn ($q, $id) => $q->where('category_id', $id))
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

write 'app/Services/DashboardService.php' <<'PHAMANI_EOF'
<?php

namespace App\Services;

use App\Enums\Category\Color;
use App\Interfaces\Services\ICreditCardService;
use App\Interfaces\Services\IDashboardService;
use App\Models\Account;
use App\Models\Installment;
use App\Models\Transaction;
use Carbon\CarbonImmutable;
use Carbon\CarbonInterface;
use Illuminate\Support\Collection;

class DashboardService implements IDashboardService
{
    public function __construct(
        protected ICreditCardService $cards,
    ) {}

    public function kpis(string $userId): array
    {
        $now = CarbonImmutable::now();
        $lastMonth = $now->subMonthNoOverflow();

        $currentIncome = $this->monthlyTotal($userId, 'income', $now);
        $previousIncome = $this->monthlyTotal($userId, 'income', $lastMonth);

        $currentExpense = $this->monthlyTotal($userId, 'expense', $now);
        $previousExpense = $this->monthlyTotal($userId, 'expense', $lastMonth);

        return [
            // Só dinheiro em contas; cartão é dívida e aparece em "faturas em aberto".
            'total_balance' => $this->totalBalance($userId),
            'open_invoices' => $this->cards->openInvoicesTotal($userId),
            'overdue' => $this->overdue($userId),
            'income' => [
                'value' => $currentIncome,
                'trend' => $this->trend($currentIncome, $previousIncome),
            ],
            'expense' => [
                'value' => $currentExpense,
                'trend' => $this->trend($currentExpense, $previousExpense),
            ],
            'installments' => [
                'value' => $this->activeInstallments($userId),
                'trend' => null,
            ],
        ];
    }

    public function cashFlow(string $userId, string $period = 'yearly'): array
    {
        $now = CarbonImmutable::now();

        return $period === 'monthly'
            ? $this->cashFlowByDay($userId, $now)
            : $this->cashFlowByMonth($userId, $now);
    }

    public function categoryPie(string $userId, string $period = 'monthly'): array
    {
        [$start, $end] = $this->periodRange(CarbonImmutable::now(), $period);

        return Transaction::query()
            ->join('categories', 'categories.id', '=', 'transactions.category_id')
            ->where('transactions.user_id', $userId)
            ->where('transactions.type', 'expense')
            ->whereBetween('transactions.date', [$start, $end])
            ->groupBy('categories.id', 'categories.name', 'categories.color')
            ->selectRaw('categories.name as name, categories.color as color, SUM(transactions.amount) as value')
            // Compras para outras pessoas têm a sua parte = 0 e não aparecem no gráfico.
            ->havingRaw('SUM(transactions.amount) > 0')
            ->orderByDesc('value')
            ->toBase()
            ->get()
            ->map(fn (object $row) => [
                'name' => (string) $row->name,
                'value' => (float) $row->value,
                'color' => Color::tryFrom((string) $row->color)?->hex() ?? Color::CHARCOAL->hex(),
            ])
            ->values()
            ->all();
    }

    /**
     * Fluxo diário do mês corrente.
     *
     * @return list<array{label: string, income: float, expense: float}>
     */
    protected function cashFlowByDay(string $userId, CarbonImmutable $date): array
    {
        $totals = $this->totalsByDate($userId, $date->startOfMonth(), $date->endOfMonth())
            ->groupBy(fn (object $row) => (int) substr((string) $row->date, 8, 2));

        return collect(range(1, $date->daysInMonth))
            ->map(fn (int $day) => [
                'label' => (string) $day,
                ...$this->sumByType($totals->get($day, collect())),
            ])
            ->all();
    }

    /**
     * Fluxo mensal do ano corrente.
     *
     * @return list<array{label: string, income: float, expense: float}>
     */
    protected function cashFlowByMonth(string $userId, CarbonImmutable $date): array
    {
        $totals = $this->totalsByDate($userId, $date->startOfYear(), $date->endOfYear())
            ->groupBy(fn (object $row) => (int) substr((string) $row->date, 5, 2));

        return collect(range(1, 12))
            ->map(fn (int $month) => [
                'label' => ucfirst(rtrim(CarbonImmutable::create($date->year, $month, 1)->locale('pt_BR')->translatedFormat('M'), '.')),
                ...$this->sumByType($totals->get($month, collect())),
            ])
            ->all();
    }

    /**
     * Totais agrupados por data e tipo. A agregação por dia/mês é feita em PHP para
     * manter a consulta portável entre PostgreSQL e SQLite (testes).
     *
     * @return Collection<int, object{date: string, type: string, total: string}>
     */
    protected function totalsByDate(string $userId, CarbonInterface $start, CarbonInterface $end): Collection
    {
        return Transaction::query()
            ->where('user_id', $userId)
            ->whereBetween('date', [$start->toDateString(), $end->toDateString()])
            ->groupBy('date', 'type')
            ->selectRaw('date, type, SUM(amount) as total')
            ->toBase()
            ->get();
    }

    /**
     * @param  Collection<int, object>  $rows
     * @return array{income: float, expense: float}
     */
    protected function sumByType(Collection $rows): array
    {
        return [
            'income' => round((float) $rows->where('type', 'income')->sum('total'), 2),
            'expense' => round((float) $rows->where('type', 'expense')->sum('total'), 2),
        ];
    }

    /**
     * @return array{0: string, 1: string}
     */
    protected function periodRange(CarbonImmutable $now, string $period): array
    {
        return $period === 'monthly'
            ? [$now->startOfMonth()->toDateString(), $now->endOfMonth()->toDateString()]
            : [$now->startOfYear()->toDateString(), $now->endOfYear()->toDateString()];
    }

    protected function totalBalance(string $userId): float
    {
        return (float) Account::query()
            ->where('user_id', $userId)
            ->where('type', '!=', 'credit')
            ->sum('balance');
    }

    protected function monthlyTotal(string $userId, string $type, CarbonImmutable $month): float
    {
        return (float) Transaction::query()
            ->where('user_id', $userId)
            ->where('type', $type)
            ->whereBetween('date', [$month->startOfMonth()->toDateString(), $month->endOfMonth()->toDateString()])
            ->sum('amount');
    }

    protected function activeInstallments(string $userId): float
    {
        return (float) Installment::query()
            ->where('user_id', $userId)
            ->where('status', 'active')
            ->sum('installment_amount');
    }

    /**
     * @return array{value: float, direction: 'up'|'down'}|null
     */
    protected function trend(float $current, float $previous): ?array
    {
        if ($previous <= 0) {
            return null;
        }

        $diff = (($current - $previous) / $previous) * 100;

        return [
            'value' => round($diff, 1),
            'direction' => $diff >= 0 ? 'up' : 'down',
        ];
    }

    /**
     * Despesas vencidas e ainda não pagas (de qualquer mês).
     *
     * @return array{count: int, amount: float}
     */
    private function overdue(string $userId): array
    {
        $query = Transaction::query()
            ->where('user_id', $userId)
            ->where('type', 'expense')
            ->whereNull('paid_at')
            ->whereDate('date', '<', now()->toDateString());

        return [
            'count' => (clone $query)->count(),
            'amount' => round((float) (clone $query)->sum('amount'), 2),
        ];
    }
}
PHAMANI_EOF

write 'app/Services/InstallmentService.php' <<'PHAMANI_EOF'
<?php

namespace App\Services;

use App\DTOs\Transaction\SplitData;
use App\DTOs\Transaction\StoreTransactionData;
use App\Interfaces\Repositories\IInstallmentRepository;
use App\Interfaces\Repositories\ITransactionRepository;
use App\Interfaces\Services\IBalanceService;
use App\Interfaces\Services\IInstallmentService;
use App\Interfaces\Services\IReimbursementService;
use App\Interfaces\Services\IShareService;
use App\Interfaces\Services\ISplitService;
use App\Models\Installment;
use App\Models\Transaction;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;

class InstallmentService implements IInstallmentService
{
    public function __construct(
        protected IInstallmentRepository $installments,
        protected ITransactionRepository $transactions,
        protected IBalanceService $balance,
        protected ISplitService $splits,
        protected IShareService $shares,
        protected IReimbursementService $reimbursements,
    ) {}

    /**
     * Cria as parcelas de `installment_start` até `installments_count`.
     * Ex.: empréstimo já na 15/24 → cria 15/24 … 24/24, a 15ª na data informada.
     *
     * `amount_mode`:
     *  - installment: o valor informado é o de cada parcela (padrão no formulário);
     *  - total: o valor informado é o da COMPRA INTEIRA, dividido pelo nº de parcelas.
     *    Começando de uma parcela > 1, lança só as que faltam com esse mesmo valor
     *    ("R$ 625 em 4x, já na 3ª" → 3/4 e 4/4 de R$ 156,25).
     */
    public function createInstallment(string $userId, StoreTransactionData $dto): Installment
    {
        return DB::transaction(function () use ($userId, $dto) {
            $count = (int) $dto->installments_count;
            $startNumber = max(1, min($dto->installment_start, $count));
            $remaining = $count - $startNumber + 1;
            $start = CarbonImmutable::parse($dto->date);

            if ($dto->amount_mode === 'installment') {
                $amounts = array_fill(0, $remaining, round($dto->amount, 2));
                $totalAmount = round($dto->amount * $count, 2);
            } else {
                $amounts = array_slice($this->splitAmount($dto->amount, $count), $startNumber - 1);
                $totalAmount = $dto->amount;
            }

            /** @var Installment $installment */
            $installment = $this->installments->create([
                'user_id' => $userId,
                'name' => $dto->description,
                'total_amount' => $totalAmount,
                'installment_amount' => $amounts[0],
                'installments' => $count,
                'start_date' => $start->toDateString(),
                'end_date' => $start->addMonthsNoOverflow($remaining - 1)->toDateString(),
                'status' => 'active',
                'auto_pay' => $dto->auto_pay,
            ]);

            foreach ($amounts as $index => $amount) {
                $number = $startNumber + $index;

                // Divisão: cada parcela é dividida na mesma proporção.
                $parts = $this->splits->compute($amount, $dto->split);

                /** @var Transaction $parcel */
                $parcel = $this->transactions->create([
                    'user_id' => $userId,
                    'account_id' => $parts['paid_by_contact_id'] === null ? $dto->account_id : null,
                    'category_id' => $dto->category_id,
                    'installment_id' => $installment->id,
                    'installment_number' => $number,
                    'name' => "{$installment->name} ({$number}/{$count})",
                    'description' => $installment->name,
                    'type' => $dto->type,
                    'amount' => $parts['amount'],
                    'total_amount' => $parts['total_amount'],
                    'paid_by_contact_id' => $parts['paid_by_contact_id'],
                    'date' => $start->addMonthsNoOverflow($index)->toDateString(),
                ]);

                $this->splits->sync($parcel, $parts['shares']);

                // Cada parcela entra no saldo quando a sua data chega.
                $this->balance->applyIfDue($parcel);
            }

            return $installment;
        });
    }

    public function updateFollowingParcels(Transaction $parcel, float $amount, ?SplitData $split = null): void
    {
        DB::transaction(function () use ($parcel, $amount, $split) {
            $following = Transaction::query()
                ->where('installment_id', $parcel->installment_id)
                ->where('installment_number', '>', $parcel->installment_number)
                ->get();

            foreach ($following as $next) {
                $this->balance->revert($next);

                $parts = $this->splits->compute($amount, $split);
                $next->update([
                    'account_id' => $parts['paid_by_contact_id'] === null ? $parcel->account_id : null,
                    'amount' => $parts['amount'],
                    'total_amount' => $parts['total_amount'],
                    'paid_by_contact_id' => $parts['paid_by_contact_id'],
                ]);
                $this->splits->sync($next, $parts['shares']);

                $this->balance->applyIfDue($next);
            }

            $this->installments->update((string) $parcel->installment_id, [
                'installment_amount' => $amount,
            ]);
        });
    }

    public function deleteInstallment(Installment $installment): void
    {
        DB::transaction(function () use ($installment) {
            foreach ($installment->transactions()->get() as $parcel) {
                $this->shares->removeFor($parcel);
                $this->balance->revert($parcel);
                $this->reimbursements->revertFor($parcel);
            }

            $this->transactions->deleteByInstallment($installment->id);
            $this->installments->delete($installment->id);
        });
    }

    /**
     * Divide o total em parcelas de 2 casas decimais; a diferença de arredondamento
     * vai para a última parcela, de forma que a soma bata exatamente com o total.
     *
     * @return list<float>
     */
    private function splitAmount(float $total, int $count): array
    {
        $totalCents = (int) round($total * 100);
        $baseCents = intdiv($totalCents, $count);

        $amounts = array_fill(0, $count, $baseCents / 100);
        $amounts[$count - 1] = ($totalCents - $baseCents * ($count - 1)) / 100;

        return $amounts;
    }
}
PHAMANI_EOF

write 'app/Services/ReimbursementService.php' <<'PHAMANI_EOF'
<?php

namespace App\Services;

use App\Interfaces\Repositories\IAccountRepository;
use App\Interfaces\Services\IReimbursementService;
use App\Models\Account;
use App\Models\Contact;
use App\Models\Transaction;
use App\Models\TransactionSplit;
use App\Models\User;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class ReimbursementService implements IReimbursementService
{
    public function __construct(
        protected IAccountRepository $accounts,
    ) {}

    public function openForUser(string $userId): array
    {
        $today = now()->toDateString();

        return $this->openQuery($userId)
            ->with([
                'transaction:id,name,date',
                'contact:id,name,linked_user_id',
                'contact.linkedUser:id,avatar',
            ])
            ->get()
            ->groupBy('contact_id')
            ->map(function ($splits) use ($today) {
                /** @var TransactionSplit $first */
                $first = $splits->first();

                $items = $splits->map(fn (TransactionSplit $s) => [
                    'id' => $s->id,
                    'transaction_id' => $s->transaction_id,
                    'name' => $s->transaction->name,
                    'date' => $s->transaction->date->toDateString(),
                    'amount' => (float) $s->amount,
                    'due' => $s->transaction->date->toDateString() <= $today,
                ])->values();

                $due = $items->where('due', true);

                return [
                    'contact' => [
                        'id' => $first->contact->id,
                        'name' => $first->contact->name,
                        'avatar' => $first->contact->linkedUser?->avatar,
                    ],
                    'due_total' => round((float) $due->sum('amount'), 2),
                    'due_count' => $due->count(),
                    'items' => $items->all(),
                ];
            })
            ->sortByDesc('due_total')
            ->values()
            ->all();
    }

    public function receive(User $user, Contact $contact, array $splitIds, string $accountId, string $date): void
    {
        if ($contact->user_id !== $user->id) {
            abort(404);
        }

        $account = Account::query()->where('user_id', $user->id)->whereKey($accountId)->first();

        if ($account === null || $account->type === 'credit') {
            throw ValidationException::withMessages(['account_id' => 'Escolha a conta onde o dinheiro caiu (cartão não serve).']);
        }

        $splits = $this->openQuery($user->id)
            ->where('transaction_splits.contact_id', $contact->id)
            ->whereIn('transaction_splits.id', $splitIds)
            ->get();

        if ($splits->isEmpty() || $splits->count() !== count(array_unique($splitIds))) {
            throw ValidationException::withMessages(['split_ids' => 'Escolha as compras que foram pagas.']);
        }

        DB::transaction(function () use ($splits, $account, $date) {
            foreach ($splits as $split) {
                $split->forceFill([
                    'reimbursed_at' => $date,
                    'reimbursement_account_id' => $account->id,
                    'reimbursed_amount' => $split->amount,
                ])->save();
            }

            // Entra na conta, mas não é receita: é dinheiro seu voltando.
            $this->accounts->applyTransaction($account->id, (float) $splits->sum('amount'), 'income');
        });
    }

    public function undo(User $user, TransactionSplit $split): void
    {
        $ownerId = Transaction::query()->whereKey($split->transaction_id)->value('user_id');

        if ($ownerId !== $user->id) {
            abort(404);
        }

        if ($split->reimbursed_at === null) {
            return;
        }

        DB::transaction(function () use ($split) {
            $this->revertBalance($split);

            $split->forceFill([
                'reimbursed_at' => null,
                'reimbursement_account_id' => null,
                'reimbursed_amount' => null,
            ])->save();
        });
    }

    public function revertFor(Transaction $transaction): void
    {
        TransactionSplit::query()
            ->where('transaction_id', $transaction->id)
            ->whereNotNull('reimbursed_at')
            ->get()
            ->each(fn (TransactionSplit $split) => $this->revertBalance($split));
    }

    private function revertBalance(TransactionSplit $split): void
    {
        if ($split->reimbursement_account_id !== null && $split->reimbursed_amount !== null) {
            $this->accounts->revertTransaction($split->reimbursement_account_id, (float) $split->reimbursed_amount, 'income');
        }
    }

    /**
     * Partes em aberto de compras feitas por você para outras pessoas (sua parte = 0).
     *
     * @return Builder<TransactionSplit>
     */
    private function openQuery(string $userId): Builder
    {
        return TransactionSplit::query()
            ->select('transaction_splits.*')
            ->join('transactions', 'transactions.id', '=', 'transaction_splits.transaction_id')
            ->where('transactions.user_id', $userId)
            ->where('transactions.type', 'expense')
            ->whereNull('transactions.paid_by_contact_id')
            ->whereNull('transactions.mirrored_from_id')
            ->whereNotNull('transactions.total_amount')
            ->where('transactions.amount', 0)
            ->whereNotNull('transaction_splits.contact_id')
            ->where('transaction_splits.amount', '>', 0)
            ->whereNull('transaction_splits.reimbursed_at')
            ->orderBy('transactions.date')
            ->orderBy('transactions.created_at');
    }
}
PHAMANI_EOF

write 'app/Services/SplitService.php' <<'PHAMANI_EOF'
<?php

namespace App\Services;

use App\DTOs\Transaction\SplitData;
use App\DTOs\Transaction\SplitParticipantData;
use App\Interfaces\Services\IShareService;
use App\Interfaces\Services\ISplitService;
use App\Models\Transaction;
use App\Models\TransactionSplit;
use Illuminate\Validation\ValidationException;

class SplitService implements ISplitService
{
    private const ME = 'me';

    public function __construct(
        protected IShareService $shares,
    ) {}

    public function validate(?SplitData $split, float $amount, string $type): void
    {
        if ($split === null) {
            return;
        }

        if ($type !== 'expense') {
            throw ValidationException::withMessages(['split' => 'Só dá para dividir despesas.']);
        }

        $contacts = $split->contactIds();

        if ($contacts === []) {
            throw ValidationException::withMessages(['split.participants' => 'Escolha pelo menos um contato para dividir.']);
        }

        if (count($contacts) !== count(array_unique($contacts))) {
            throw ValidationException::withMessages(['split.participants' => 'Há um contato repetido na divisão.']);
        }

        if (! $split->include_me && $split->paid_by_contact_id !== null) {
            throw ValidationException::withMessages(['split.paid_by_contact_id' => 'Numa compra para outra pessoa, quem pagou é você.']);
        }

        if ($split->paid_by_contact_id !== null && ! in_array($split->paid_by_contact_id, $contacts, true)) {
            throw ValidationException::withMessages(['split.paid_by_contact_id' => 'Quem pagou precisa estar na divisão.']);
        }

        if ($split->mode === 'custom') {
            $sumCents = array_sum(array_map(
                fn (SplitParticipantData $p) => $p->contact_id === null && ! $split->include_me ? 0 : $this->cents((float) $p->amount),
                $split->participants,
            ));

            if ($sumCents !== $this->cents($amount)) {
                throw ValidationException::withMessages([
                    'split.participants' => 'A soma das partes ('.number_format($sumCents / 100, 2, ',', '.').') precisa ser igual ao valor ('.number_format($amount, 2, ',', '.').').',
                ]);
            }
        }
    }

    public function compute(float $total, ?SplitData $split): array
    {
        if ($split === null || $split->contactIds() === []) {
            return ['amount' => round($total, 2), 'total_amount' => null, 'paid_by_contact_id' => null, 'shares' => []];
        }

        // Pesos: iguais (1 para cada) ou proporcionais aos valores informados.
        // Em parcelas, os valores informados valem para o "valor de referência" e são escalados para cada parcela.
        $weights = [];
        foreach ($this->participantsWithMe($split) as $participant) {
            $key = $participant->contact_id ?? self::ME;
            $weights[$key] = match (true) {
                // Compra para outra pessoa: você não entra na conta.
                $key === self::ME && ! $split->include_me => 0,
                $split->mode === 'custom' => $this->cents((float) $participant->amount),
                default => 1,
            };
        }

        $totalCents = $this->cents($total);
        $sumWeights = array_sum($weights);

        $shares = [];
        foreach ($weights as $key => $weight) {
            $shares[$key] = $sumWeights > 0 ? intdiv($totalCents * $weight, $sumWeights) : 0;
        }

        // Centavo que sobra fica com quem pagou.
        $payer = $split->paid_by_contact_id ?? self::ME;
        $shares[$payer] = ($shares[$payer] ?? 0) + ($totalCents - array_sum($shares));

        $shares = array_map(fn (int $cents) => $cents / 100, $shares);

        return [
            'amount' => $shares[self::ME] ?? 0.0,
            'total_amount' => round($total, 2),
            'paid_by_contact_id' => $split->paid_by_contact_id,
            'shares' => $shares,
        ];
    }

    public function sync(Transaction $transaction, array $shares): void
    {
        $existing = TransactionSplit::query()->where('transaction_id', $transaction->id)->get();

        // Reembolsos já registrados ("recebido") continuam valendo para quem segue na divisão.
        $reimbursed = $existing
            ->filter(fn (TransactionSplit $s) => $s->contact_id !== null && $s->reimbursed_at !== null)
            ->keyBy('contact_id');

        TransactionSplit::query()->where('transaction_id', $transaction->id)->delete();

        foreach ($shares as $key => $amount) {
            $previous = $key === self::ME ? null : $reimbursed->get($key);

            TransactionSplit::query()->create([
                'transaction_id' => $transaction->id,
                'contact_id' => $key === self::ME ? null : $key,
                'amount' => $amount,
                'reimbursed_at' => $previous?->reimbursed_at?->toDateString(),
                'reimbursement_account_id' => $previous?->reimbursement_account_id,
                'reimbursed_amount' => $previous?->reimbursed_amount,
            ]);
        }

        // Contatos vinculados a usuários recebem (ou atualizam) o compartilhamento.
        $this->shares->syncFor($transaction);
    }

    public function copy(Transaction $from, Transaction $to): void
    {
        $shares = [];

        foreach (TransactionSplit::query()->where('transaction_id', $from->id)->get() as $split) {
            $shares[$split->contact_id ?? self::ME] = (float) $split->amount;
        }

        $this->sync($to, $shares);
    }

    /**
     * Você sempre participa da divisão (com peso 0 no modo "valores", se não informar valor).
     *
     * @return list<SplitParticipantData>
     */
    private function participantsWithMe(SplitData $split): array
    {
        $participants = array_values($split->participants);

        $hasMe = array_filter($participants, fn (SplitParticipantData $p) => $p->contact_id === null) !== [];

        if (! $hasMe) {
            array_unshift($participants, new SplitParticipantData(null, $split->mode === 'custom' ? 0.0 : null));
        }

        return $participants;
    }

    private function cents(float $value): int
    {
        return (int) round($value * 100);
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
use App\Interfaces\Services\ITransactionService;
use App\Models\Account;
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
    ) {}

    public function create(string $userId, StoreTransactionData $dto): Model
    {
        $this->splits->validate($dto->split, $dto->amount, $dto->type);

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

            if ($dto->apply_to_following && $transaction->installment_id !== null) {
                $this->installmentService->updateFollowingParcels($transaction, $dto->amount, $dto->split);
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

write 'database/migrations/2026_11_20_000100_add_reimbursements_to_splits.php' <<'PHAMANI_EOF'
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Compra para outra pessoa ("A receber").
 *
 * Uma compra feita por você em que a sua parte é zero (ex.: o irmão usa o cartão) fica "a receber"
 * de cada contato da divisão. Quando ele devolve (Pix), a parte dele é marcada como recebida:
 * - reimbursed_at: data em que o dinheiro chegou;
 * - reimbursement_account_id: conta onde caiu (o saldo dela sobe, sem contar como receita);
 * - reimbursed_amount: quanto entrou (para desfazer exatamente o mesmo valor).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('transaction_splits', function (Blueprint $table) {
            $table->date('reimbursed_at')->nullable();
            $table->foreignUuid('reimbursement_account_id')->nullable()->constrained('accounts')->nullOnDelete();
            $table->decimal('reimbursed_amount', 12, 2)->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('transaction_splits', function (Blueprint $table) {
            $table->dropConstrainedForeignId('reimbursement_account_id');
            $table->dropColumn(['reimbursed_at', 'reimbursed_amount']);
        });
    }
};
PHAMANI_EOF

write 'resources/js/components/phamani/dashboard/dashboard-sidebar.tsx' <<'PHAMANI_EOF'
import { Link } from '@inertiajs/react';
import { Plus } from 'lucide-react';
import { useState } from 'react';
import { CategoryIcon } from '@/components/phamani/category-icon';
import { ReceivablesCard } from '@/components/phamani/dashboard/receivables-card';
import { AccountsList } from '@/components/phamani/list/accounts-list';
import { AccountsListModal } from '@/components/phamani/modal/accounts-list-modal';
import { Button } from '@/components/phamani/ui/button';
import { Card } from '@/components/phamani/ui/card';
import { PaymentStatusBadge } from '@/components/phamani/payment-status-badge';
import { formatCurrency, formatDate, today } from '@/lib/format';
import { paymentStatus } from '@/lib/payment';
import { displayAmount, isFullyReimbursed, isThirdParty } from '@/lib/split';
import { index as transactionsIndex } from '@/routes/transactions';
import type { Account, Receivable, Transaction } from '@/types/phamani';

interface DashboardSidebarProps {
    recentTransactions: Transaction[];
    accounts: Account[];
    receivables: Receivable[];
    onNewTransaction: () => void;
}

export function DashboardSidebar({
    recentTransactions,
    accounts,
    receivables,
    onNewTransaction,
}: DashboardSidebarProps) {
    const [accountsModalOpen, setAccountsModalOpen] = useState(false);
    const todayStr = today();

    return (
        <>
            <Button
                variant="primary"
                size="lg"
                className="flex w-full flex-col gap-2 rounded-2xl py-8 text-lg shadow-xl"
                onClick={onNewTransaction}
            >
                <Plus className="h-8 w-8" />
                Nova Transação
            </Button>

            <div className="space-y-4">
                <div className="flex items-center justify-between">
                    <h3 className="font-bold text-[#3D2817]">Recentes</h3>
                    <Link
                        href={transactionsIndex()}
                        prefetch
                        className="text-sm text-[#6B4F3A] hover:underline"
                    >
                        Ver tudo
                    </Link>
                </div>

                <div className="space-y-3">
                    {recentTransactions.length === 0 && (
                        <p className="rounded-2xl border border-dashed border-[#D4C5A9] p-4 text-center text-sm text-[#8B7355]">
                            Nenhuma transação ainda.
                        </p>
                    )}

                    {recentTransactions.map((t) => (
                        <Card
                            key={t.id}
                            variant="interactive"
                            className="flex items-center justify-between !border-0 p-4 !shadow-sm transition-colors hover:bg-[#E8DCC4]/30"
                        >
                            <div className="flex min-w-0 items-center gap-3">
                                <CategoryIcon
                                    category={t.category}
                                    className="h-10 w-10 shrink-0 rounded-xl shadow-sm"
                                    iconClassName="h-5 w-5"
                                />
                                <div className="min-w-0">
                                    <p className="truncate text-sm font-bold text-[#3D2817]">
                                        {t.name}
                                    </p>
                                    <p className="flex items-center gap-2 text-xs text-[#8B7355]">
                                        {formatDate(t.date)}
                                        {isThirdParty(t) &&
                                            !isFullyReimbursed(t) && (
                                                <span className="rounded-md bg-[#FCE7E7] px-1.5 py-0.5 text-[10px] font-bold tracking-wide text-[#A65D57] uppercase">
                                                    A receber
                                                </span>
                                            )}
                                        {t.date.slice(0, 10) > todayStr ? (
                                            <span className="rounded-md bg-[#E8DCC4] px-1.5 py-0.5 text-[10px] font-bold tracking-wide text-[#6B4E3D] uppercase">
                                                Agendada
                                            </span>
                                        ) : (
                                            paymentStatus(t) === 'overdue' && (
                                                <PaymentStatusBadge status="overdue" />
                                            )
                                        )}
                                    </p>
                                </div>
                            </div>

                            <span
                                className={`shrink-0 text-sm font-bold ${t.type === 'income' ? 'text-[#4A7A5E]' : 'text-[#3D2817]'}`}
                            >
                                {t.type === 'income' ? '+' : '-'}{' '}
                                {formatCurrency(displayAmount(t))}
                            </span>
                        </Card>
                    ))}
                </div>
            </div>

            <ReceivablesCard receivables={receivables} accounts={accounts} />

            <AccountsList
                accounts={accounts}
                onViewAll={() => setAccountsModalOpen(true)}
            />

            <AccountsListModal
                open={accountsModalOpen}
                onOpenChange={setAccountsModalOpen}
                accounts={accounts}
            />
        </>
    );
}
PHAMANI_EOF

write 'resources/js/components/phamani/dashboard/receivables-card.tsx' <<'PHAMANI_EOF'
import { HandCoins } from 'lucide-react';
import { useState } from 'react';
import { ContactAvatar } from '@/components/phamani/contact-avatar';
import { ReceiveModal } from '@/components/phamani/modal/receive-modal';
import { formatCurrency } from '@/lib/format';
import type { Account, Receivable } from '@/types/phamani';

interface ReceivablesCardProps {
    receivables: Receivable[];
    accounts: Account[];
}

/**
 * Compra para outra pessoa: quanto cada contato ainda te deve.
 * Clicar abre o registro do recebimento (ex.: chegou o Pix do irmão).
 */
export function ReceivablesCard({
    receivables,
    accounts,
}: ReceivablesCardProps) {
    const [selected, setSelected] = useState<Receivable | null>(null);

    if (receivables.length === 0) return null;

    return (
        <div className="space-y-4">
            <h3 className="flex items-center gap-2 font-bold text-[#3D2817]">
                <HandCoins className="h-4 w-4 text-[#6B4E3D]" />A receber
            </h3>

            <div className="space-y-3">
                {receivables.map((r) => {
                    const upcoming = r.items.length - r.due_count;
                    return (
                        <button
                            key={r.contact.id}
                            type="button"
                            onClick={() => setSelected(r)}
                            className="flex w-full items-center justify-between gap-3 rounded-2xl border border-[#E8DCC4] bg-white p-4 text-left shadow-sm transition-colors hover:bg-[#E8DCC4]/30"
                        >
                            <span className="flex min-w-0 items-center gap-3">
                                <ContactAvatar
                                    name={r.contact.name}
                                    avatar={r.contact.avatar}
                                    className="h-10 w-10 text-sm"
                                />
                                <span className="min-w-0">
                                    <span className="block truncate text-sm font-bold text-[#3D2817]">
                                        {r.contact.name}
                                    </span>
                                    <span className="block text-xs text-[#8B7355]">
                                        {r.due_count > 0
                                            ? `${r.due_count} ${r.due_count === 1 ? 'compra' : 'compras'}`
                                            : 'Nada vencido'}
                                        {upcoming > 0 &&
                                            ` · ${upcoming} ${upcoming === 1 ? 'próxima' : 'próximas'}`}
                                    </span>
                                </span>
                            </span>
                            <span className="shrink-0 text-right">
                                <span className="block text-[10px] font-bold tracking-wide text-[#8B7355] uppercase">
                                    Te deve
                                </span>
                                <span className="text-sm font-bold text-[#A65D57]">
                                    {formatCurrency(r.due_total)}
                                </span>
                            </span>
                        </button>
                    );
                })}
            </div>

            <ReceiveModal
                receivable={selected}
                accounts={accounts}
                onClose={() => setSelected(null)}
            />
        </div>
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

write 'resources/js/components/phamani/drawer/split-details.tsx' <<'PHAMANI_EOF'
import { router, usePage } from '@inertiajs/react';
import { HandCoins, Users } from 'lucide-react';
import { ContactAvatar } from '@/components/phamani/contact-avatar';
import { useContactAvatar } from '@/hooks/use-contacts';
import { formatCurrency, formatDate } from '@/lib/format';
import { isThirdParty } from '@/lib/split';
import { cn } from '@/lib/utils';
import { undo as undoReimbursement } from '@/routes/receivables';
import { SHARE_STATUS_LABELS } from '@/types/phamani';
import type {
    ShareStatus,
    Transaction,
    TransactionSplit,
} from '@/types/phamani';

const STATUS_STYLES: Record<ShareStatus, string> = {
    pending: 'bg-[#E8DCC4] text-[#6B4E3D]',
    accepted: 'bg-[#E3F9E5] text-[#1F5428]',
    declined: 'bg-[#FCE7E7] text-[#A65D57]',
    left: 'bg-[#FCE7E7] text-[#A65D57]',
    removed: 'bg-[#E8DCC4] text-[#8B7355]',
};

/**
 * Bloco "Divisão" do drawer.
 * - Transação sua: mostra as partes e o status de quem é usuário do Phamani (aceitou, aguardando…).
 * - Cópia compartilhada com você: mostra a divisão original, com "Você" no lugar do seu nome.
 */
export function SplitDetails({ transaction }: { transaction: Transaction }) {
    const authUser = usePage().props.auth.user;
    const me = authUser?.id;
    const contactAvatar = useContactAvatar();
    const source = transaction.mirrored_from;
    const isMirror = !!transaction.mirrored_from_id && !!source;

    const splits = isMirror
        ? (source.splits ?? [])
        : (transaction.splits ?? []);
    if (splits.length === 0) return null;

    const ownerName = isMirror ? (source.user?.name ?? 'Quem criou') : 'Você';
    // Compra para outra pessoa: mostra só quem te deve e se já devolveu.
    const forOthers = !isMirror && isThirdParty(transaction);
    const total = isMirror ? source.total_amount : transaction.total_amount;

    const labelOf = (s: (typeof splits)[number]) => {
        if (s.contact_id === null) return ownerName;
        if (
            isMirror &&
            s.contact &&
            'linked_user_id' in s.contact &&
            s.contact.linked_user_id === me
        )
            return 'Você';
        return s.contact?.name ?? '—';
    };

    const avatarOf = (s: (typeof splits)[number]): string | null => {
        if (isMirror) {
            if (s.contact_id === null) return source.user?.avatar ?? null;
            if (
                s.contact &&
                'linked_user_id' in s.contact &&
                s.contact.linked_user_id === me
            )
                return authUser?.avatar ?? null;
            return null;
        }
        return s.contact_id === null
            ? (authUser?.avatar ?? null)
            : contactAvatar(s.contact_id);
    };

    let payer: string;
    if (isMirror) {
        payer = !source.paid_by
            ? ownerName
            : source.paid_by.linked_user_id === me
              ? 'você'
              : source.paid_by.name;
    } else {
        payer = transaction.paid_by?.name ?? 'você';
    }

    const statusOf = (contactId: string | null): ShareStatus | null => {
        if (isMirror || !contactId) return null;
        const link = transaction.share_links?.find(
            (l) => l.share?.owner_contact_id === contactId,
        );
        return link?.share?.status ?? null;
    };

    // Dono primeiro
    const ordered = [...splits]
        .filter((s) => !forOthers || s.contact_id !== null)
        .sort(
            (a, b) =>
                Number(a.contact_id !== null) - Number(b.contact_id !== null),
        );

    function undo(splitId: string) {
        router.delete(undoReimbursement.url(splitId), {
            preserveScroll: true,
            preserveState: true,
        });
    }

    return (
        <div className="rounded-3xl border border-[#D4C5A9] bg-white p-6">
            <div className="mb-4 flex items-center justify-between">
                <h4 className="flex items-center gap-2 font-bold text-[#3D2817]">
                    {forOthers ? (
                        <HandCoins className="h-4 w-4" />
                    ) : (
                        <Users className="h-4 w-4" />
                    )}
                    {forOthers ? 'Compra para outra pessoa' : 'Divisão'}
                </h4>
                <span className="text-xs text-[#8B7355]">
                    Pago por <strong>{payer}</strong>
                </span>
            </div>
            <ul className="space-y-2">
                {ordered.map((s) => {
                    const status = statusOf(s.contact_id);
                    return (
                        <li
                            key={s.id}
                            className="flex flex-wrap items-center justify-between gap-2 text-sm"
                        >
                            <span className="flex items-center gap-2 text-[#3D2817]">
                                <ContactAvatar
                                    name={labelOf(s)}
                                    avatar={avatarOf(s)}
                                    className="h-6 w-6 text-[10px]"
                                />
                                {labelOf(s)}
                                {status && (
                                    <span
                                        className={cn(
                                            'rounded-md px-1.5 py-0.5 text-[10px] font-bold uppercase',
                                            STATUS_STYLES[status],
                                        )}
                                    >
                                        {SHARE_STATUS_LABELS[status]}
                                    </span>
                                )}
                            </span>
                            <span className="font-bold text-[#3D2817]">
                                {formatCurrency(s.amount)}
                            </span>
                            {forOthers && (
                                <ReimbursementStatus
                                    split={s as TransactionSplit}
                                    onUndo={() => undo(s.id)}
                                />
                            )}
                        </li>
                    );
                })}
            </ul>
            <div className="mt-3 flex items-center justify-between border-t border-[#E8DCC4] pt-3 text-sm">
                <span className="text-[#8B7355]">Total</span>
                <span className="font-bold text-[#3D2817]">
                    {formatCurrency(total)}
                </span>
            </div>
        </div>
    );
}

/** "A receber" ou "Recebido em … na conta …" (com opção de desfazer). */
function ReimbursementStatus({
    split,
    onUndo,
}: {
    split: TransactionSplit;
    onUndo: () => void;
}) {
    if (!split.reimbursed_at) {
        return (
            <p className="w-full text-xs text-[#A65D57]">
                A receber · registre quando o dinheiro chegar (card “A receber”
                no início).
            </p>
        );
    }

    return (
        <p className="flex w-full items-center justify-between text-xs text-[#1F5428]">
            <span>
                Recebido em {formatDate(split.reimbursed_at)}
                {split.reimbursement_account &&
                    ` · ${split.reimbursement_account.name}`}
            </span>
            <button
                type="button"
                onClick={onUndo}
                className="font-semibold text-[#8B7355] underline-offset-2 hover:underline"
            >
                Desfazer
            </button>
        </p>
    );
}
PHAMANI_EOF

write 'resources/js/components/phamani/modal/receive-modal.tsx' <<'PHAMANI_EOF'
import { router } from '@inertiajs/react';
import { useEffect, useMemo, useState } from 'react';
import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogHeader,
    DialogTitle,
} from '@/components/ui/dialog';
import { formatCurrency, formatDate, today } from '@/lib/format';
import { cn } from '@/lib/utils';
import { receive } from '@/routes/receivables';
import { isCreditCard } from '@/types/phamani';
import type { Account, Receivable } from '@/types/phamani';

interface ReceiveModalProps {
    receivable: Receivable | null;
    accounts: Account[];
    onClose: () => void;
}

const inputClass =
    'w-full rounded-xl border-2 border-[#E8DCC4] bg-white px-3 py-2 text-[#3D2817] focus:border-[#6B4E3D] focus:outline-none';

/**
 * Registrar recebimento: o contato devolveu (Pix). As compras vencidas já vêm marcadas;
 * as próximas (parcelas futuras) podem ser marcadas se ele adiantou.
 * O valor entra na conta escolhida, sem contar como receita.
 */
export function ReceiveModal({
    receivable,
    accounts,
    onClose,
}: ReceiveModalProps) {
    const moneyAccounts = useMemo(
        () => accounts.filter((a) => !isCreditCard(a)),
        [accounts],
    );

    const [selected, setSelected] = useState<string[]>([]);
    const [accountId, setAccountId] = useState('');
    const [date, setDate] = useState(today());
    const [errors, setErrors] = useState<Record<string, string>>({});
    const [processing, setProcessing] = useState(false);

    // Ao abrir: marca o que já venceu.
    useEffect(() => {
        if (!receivable) return;
        setSelected(receivable.items.filter((i) => i.due).map((i) => i.id));
        setAccountId((current) => current || moneyAccounts[0]?.id || '');
        setDate(today());
        setErrors({});
    }, [receivable, moneyAccounts]);

    if (!receivable) return null;

    const total = receivable.items
        .filter((i) => selected.includes(i.id))
        .reduce((sum, i) => sum + i.amount, 0);

    function toggle(id: string) {
        setSelected((current) =>
            current.includes(id)
                ? current.filter((x) => x !== id)
                : [...current, id],
        );
    }

    function submit() {
        if (!receivable) return;

        router.post(
            receive.url(receivable.contact.id),
            { split_ids: selected, account_id: accountId, date },
            {
                preserveScroll: true,
                onStart: () => setProcessing(true),
                onFinish: () => setProcessing(false),
                onError: (e) => setErrors(e),
                onSuccess: () => onClose(),
            },
        );
    }

    const due = receivable.items.filter((i) => i.due);
    const upcoming = receivable.items.filter((i) => !i.due);

    return (
        <Dialog open={!!receivable} onOpenChange={(open) => !open && onClose()}>
            <DialogContent
                onOpenAutoFocus={(e) => e.preventDefault()}
                className="max-w-lg overflow-hidden border-[#E8DCC4] bg-[#F5EFE6] p-0"
            >
                <DialogHeader className="border-b border-[#E8DCC4] px-6 pt-6 pb-4">
                    <DialogTitle className="text-xl text-[#3D2817]">
                        Recebimento de {receivable.contact.name}
                    </DialogTitle>
                    <DialogDescription className="mt-1 text-sm text-[#8B7355]">
                        Marque o que foi pago. O valor entra na conta escolhida,
                        sem contar como receita.
                    </DialogDescription>
                </DialogHeader>

                <div className="max-h-[55vh] space-y-4 overflow-y-auto px-6 py-4">
                    <ItemGroup
                        title="Vencidas"
                        items={due}
                        selected={selected}
                        onToggle={toggle}
                    />
                    <ItemGroup
                        title="Próximas (se ele adiantou)"
                        items={upcoming}
                        selected={selected}
                        onToggle={toggle}
                    />
                    {errors.split_ids && (
                        <p className="text-xs text-[#D4183D]">
                            {errors.split_ids}
                        </p>
                    )}

                    <div className="grid grid-cols-2 gap-3">
                        <div>
                            <label
                                htmlFor="receive-account"
                                className="mb-1 ml-1 block text-xs text-[#6B4E3D]"
                            >
                                Caiu na conta
                            </label>
                            <select
                                id="receive-account"
                                value={accountId}
                                onChange={(e) => setAccountId(e.target.value)}
                                className={inputClass}
                            >
                                {moneyAccounts.map((a) => (
                                    <option key={a.id} value={a.id}>
                                        {a.name}
                                    </option>
                                ))}
                            </select>
                            {errors.account_id && (
                                <p className="mt-1 text-xs text-[#D4183D]">
                                    {errors.account_id}
                                </p>
                            )}
                        </div>
                        <div>
                            <label
                                htmlFor="receive-date"
                                className="mb-1 ml-1 block text-xs text-[#6B4E3D]"
                            >
                                Em
                            </label>
                            <input
                                id="receive-date"
                                type="date"
                                value={date}
                                onChange={(e) => setDate(e.target.value)}
                                className={inputClass}
                            />
                        </div>
                    </div>
                </div>

                <div className="flex items-center justify-between border-t border-[#E8DCC4] px-6 py-4">
                    <span className="text-sm text-[#6B4E3D]">
                        Total{' '}
                        <strong className="text-[#3D2817]">
                            {formatCurrency(total)}
                        </strong>
                    </span>
                    <div className="flex gap-2">
                        <button
                            type="button"
                            onClick={onClose}
                            className="rounded-xl px-4 py-2 text-sm font-semibold text-[#6B4E3D] hover:bg-[#E8DCC4]"
                        >
                            Cancelar
                        </button>
                        <button
                            type="button"
                            onClick={submit}
                            disabled={
                                processing ||
                                selected.length === 0 ||
                                !accountId
                            }
                            className="rounded-xl bg-[#3D2817] px-4 py-2 text-sm font-bold text-[#F5EFE6] hover:bg-[#6B4E3D] disabled:opacity-40"
                        >
                            Registrar
                        </button>
                    </div>
                </div>
            </DialogContent>
        </Dialog>
    );
}

function ItemGroup({
    title,
    items,
    selected,
    onToggle,
}: {
    title: string;
    items: Receivable['items'];
    selected: string[];
    onToggle: (id: string) => void;
}) {
    if (items.length === 0) return null;

    return (
        <div>
            <p className="mb-2 text-xs font-bold tracking-wide text-[#8B7355] uppercase">
                {title}
            </p>
            <ul className="space-y-2">
                {items.map((item) => {
                    const checked = selected.includes(item.id);
                    return (
                        <li key={item.id}>
                            <label
                                className={cn(
                                    'flex cursor-pointer items-center gap-3 rounded-xl border bg-white p-3 transition-colors',
                                    checked
                                        ? 'border-[#6B4E3D]'
                                        : 'border-[#E8DCC4] opacity-70',
                                )}
                            >
                                <input
                                    type="checkbox"
                                    checked={checked}
                                    onChange={() => onToggle(item.id)}
                                    className="h-4 w-4 accent-[#3D2817]"
                                />
                                <span className="min-w-0 flex-1">
                                    <span className="block truncate text-sm font-semibold text-[#3D2817]">
                                        {item.name}
                                    </span>
                                    <span className="text-xs text-[#8B7355]">
                                        {formatDate(item.date)}
                                    </span>
                                </span>
                                <span className="text-sm font-bold text-[#3D2817]">
                                    {formatCurrency(item.amount)}
                                </span>
                            </label>
                        </li>
                    );
                })}
            </ul>
        </div>
    );
}
PHAMANI_EOF

write 'resources/js/components/phamani/modal/split-section.tsx' <<'PHAMANI_EOF'
import { router } from '@inertiajs/react';
import { Check, HandCoins, Plus, Users } from 'lucide-react';
import { useState } from 'react';
import { ContactAvatar } from '@/components/phamani/contact-avatar';
import { ToggleField } from '@/components/toggle-field';
import { useContacts } from '@/hooks/use-contacts';
import { formatCurrency } from '@/lib/format';
import { cn } from '@/lib/utils';
import { store as storeContact } from '@/routes/contacts';
import type { Contact, SplitForm, SplitParticipantForm } from '@/types/phamani';

interface SplitSectionProps {
    split: SplitForm | null;
    onChange: (split: SplitForm | null) => void;
    /** Valor digitado no formulário (total, ou da parcela). */
    amount: number;
    errors: Partial<Record<string, string>>;
}

const labelClass = 'mb-2 ml-1 block font-serif text-sm text-[#6B4E3D]';
const smallInput =
    'w-full rounded-xl border-2 border-[#E8DCC4] bg-white px-3 py-2 text-[#3D2817] focus:border-[#6B4E3D] focus:outline-none';

const EMPTY_SPLIT: SplitForm = {
    mode: 'equal',
    participants: [{ contact_id: null, amount: '' }],
    paid_by_contact_id: null,
};

export function SplitSection({
    split,
    onChange,
    amount,
    errors,
}: SplitSectionProps) {
    const contacts = useContacts();
    const [newName, setNewName] = useState('');
    const [adding, setAdding] = useState(false);

    const selectedIds = (split?.participants ?? [])
        .map((p) => p.contact_id)
        .filter((id): id is string => id !== null);
    // Desmarcar "Você" = compra para outra pessoa (sua parte é zero, o resto fica a receber).
    const includeMe = split?.include_me !== false;
    const people = selectedIds.length + (includeMe ? 1 : 0);
    const nameOf = (id: string | null) =>
        id === null ? 'Você' : (contacts.find((c) => c.id === id)?.name ?? '—');

    function update(patch: Partial<SplitForm>) {
        if (split) onChange({ ...split, ...patch });
    }

    function toggleMe() {
        if (!split) return;

        onChange(
            includeMe
                ? {
                      ...split,
                      include_me: false,
                      participants: split.participants.filter(
                          (p) => p.contact_id !== null,
                      ),
                      // Numa compra para outra pessoa, quem pagou é você.
                      paid_by_contact_id: null,
                  }
                : {
                      ...split,
                      include_me: true,
                      participants: [
                          { contact_id: null, amount: '' },
                          ...split.participants,
                      ],
                  },
        );
    }

    function toggleContact(contact: Contact) {
        if (!split) return;

        const isIn = selectedIds.includes(contact.id);
        const participants: SplitParticipantForm[] = isIn
            ? split.participants.filter((p) => p.contact_id !== contact.id)
            : [...split.participants, { contact_id: contact.id, amount: '' }];

        onChange({
            ...split,
            participants,
            // Quem pagou precisa estar na divisão.
            paid_by_contact_id:
                isIn && split.paid_by_contact_id === contact.id
                    ? null
                    : split.paid_by_contact_id,
        });
    }

    function setParticipantAmount(
        contactId: string | null,
        value: number | '',
    ) {
        if (!split) return;

        update({
            participants: split.participants.map((p) =>
                p.contact_id === contactId ? { ...p, amount: value } : p,
            ),
        });
    }

    function addContact() {
        const name = newName.trim();
        if (!name) return;

        router.post(
            storeContact.url(),
            { name },
            {
                preserveState: true,
                preserveScroll: true,
                only: ['contacts', 'errors'],
                onStart: () => setAdding(true),
                onFinish: () => setAdding(false),
                onSuccess: (page) => {
                    setNewName('');
                    const created = (
                        page.props.contacts as Contact[] | undefined
                    )?.find((c) => c.name === name);
                    if (created && split) {
                        onChange({
                            ...split,
                            participants: [
                                ...split.participants,
                                { contact_id: created.id, amount: '' },
                            ],
                        });
                    }
                },
            },
        );
    }

    const customSum = (split?.participants ?? []).reduce(
        (sum, p) => sum + Number(p.amount || 0),
        0,
    );
    const customDiff = Math.round((amount - customSum) * 100) / 100;

    return (
        <div className="space-y-4">
            <ToggleField
                label="Dividir com alguém?"
                icon={<Users className="h-5 w-5" />}
                active={!!split}
                onToggle={() => onChange(split ? null : { ...EMPTY_SPLIT })}
            />

            {split && (
                <div className="space-y-5 border-l-2 border-[#6B4E3D] pl-4">
                    {/* Participantes */}
                    <div>
                        <span className={labelClass}>Dividir entre</span>
                        <div className="flex flex-wrap gap-2">
                            <button
                                type="button"
                                onClick={toggleMe}
                                aria-pressed={includeMe}
                                title={
                                    includeMe
                                        ? 'Desmarque se a compra foi só para outra pessoa'
                                        : 'Incluir você na divisão'
                                }
                                className={cn(
                                    'inline-flex items-center gap-1 rounded-full border px-3 py-1.5 text-sm font-medium transition-colors',
                                    includeMe
                                        ? 'border-[#3D2817] bg-[#3D2817] text-[#F5EFE6]'
                                        : 'border-[#D4C5A9] bg-white text-[#6B4E3D] hover:border-[#6B4E3D]',
                                )}
                            >
                                {includeMe && <Check className="h-3.5 w-3.5" />}
                                Você
                            </button>
                            {contacts.map((c) => {
                                const active = selectedIds.includes(c.id);
                                return (
                                    <button
                                        key={c.id}
                                        type="button"
                                        onClick={() => toggleContact(c)}
                                        aria-pressed={active}
                                        className={cn(
                                            'inline-flex items-center gap-1 rounded-full border px-3 py-1.5 text-sm font-medium transition-colors',
                                            active
                                                ? 'border-[#3D2817] bg-[#3D2817] text-[#F5EFE6]'
                                                : 'border-[#D4C5A9] bg-white text-[#6B4E3D] hover:border-[#6B4E3D]',
                                        )}
                                    >
                                        {active ? (
                                            <Check className="h-3.5 w-3.5" />
                                        ) : (
                                            <ContactAvatar
                                                name={c.name}
                                                avatar={c.linked_user?.avatar}
                                                className="h-5 w-5 text-[10px]"
                                            />
                                        )}
                                        {c.name}
                                    </button>
                                );
                            })}
                        </div>

                        <div className="mt-3 flex gap-2">
                            <label htmlFor="new-contact" className="sr-only">
                                Novo contato
                            </label>
                            <input
                                id="new-contact"
                                value={newName}
                                onChange={(e) => setNewName(e.target.value)}
                                onKeyDown={(e) => {
                                    if (e.key === 'Enter') {
                                        e.preventDefault();
                                        addContact();
                                    }
                                }}
                                placeholder="Novo contato (ex.: Mãe da Mozi)"
                                className={smallInput}
                            />
                            <button
                                type="button"
                                onClick={addContact}
                                disabled={adding || !newName.trim()}
                                aria-label="Adicionar contato"
                                className="shrink-0 rounded-xl bg-[#6B4E3D] px-3 text-[#F5EFE6] hover:bg-[#3D2817] disabled:opacity-40"
                            >
                                <Plus className="h-5 w-5" />
                            </button>
                        </div>
                        {errors['split.participants'] && (
                            <p className="mt-1 ml-1 text-xs text-[#D4183D]">
                                {errors['split.participants']}
                            </p>
                        )}
                        {errors.split && (
                            <p className="mt-1 ml-1 text-xs text-[#D4183D]">
                                {errors.split}
                            </p>
                        )}
                    </div>

                    {!includeMe && (
                        <div className="flex items-start gap-3 rounded-xl bg-[#FBF7F1] p-3 text-xs text-[#6B4E3D]">
                            <HandCoins className="mt-0.5 h-4 w-4 shrink-0 text-[#8B7355]" />
                            <span>
                                <strong className="text-[#3D2817]">
                                    Compra para outra pessoa.
                                </strong>{' '}
                                Você paga (o valor cheio sai da conta ou vai
                                para a fatura), mas não entra nas suas despesas:
                                fica <strong>a receber</strong> até a pessoa te
                                devolver.
                                {selectedIds.length === 0 &&
                                    ' Escolha para quem foi a compra.'}
                            </span>
                        </div>
                    )}

                    {selectedIds.length > 0 && (
                        <>
                            {/* Modo */}
                            <div className="flex rounded-xl bg-[#E8DCC4] p-1">
                                {(
                                    [
                                        ['equal', 'Partes iguais'],
                                        ['custom', 'Valores'],
                                    ] as const
                                ).map(([mode, label]) => (
                                    <button
                                        key={mode}
                                        type="button"
                                        onClick={() => update({ mode })}
                                        className={cn(
                                            'flex-1 rounded-lg py-2 text-sm font-bold transition-all',
                                            split.mode === mode
                                                ? 'bg-white text-[#3D2817] shadow-sm'
                                                : 'text-[#6B4E3D] hover:bg-[#D4C5A9]/50',
                                        )}
                                    >
                                        {label}
                                    </button>
                                ))}
                            </div>

                            {split.mode === 'equal' ? (
                                <div className="space-y-2">
                                    <p className="ml-1 text-sm text-[#6B4E3D]">
                                        {people === 1
                                            ? nameOf(selectedIds[0])
                                            : `${people} pessoas`}{' '}
                                        ·{' '}
                                        <strong>
                                            {formatCurrency(
                                                amount && people
                                                    ? amount / people
                                                    : 0,
                                            )}
                                        </strong>{' '}
                                        {people === 1
                                            ? 'a receber'
                                            : 'para cada'}
                                    </p>
                                    {includeMe && (
                                        <p className="ml-1 text-xs text-[#8B7355]">
                                            Só sabe a sua parte? Escolha “Minha
                                            parte” embaixo do campo Valor.
                                        </p>
                                    )}
                                </div>
                            ) : (
                                <div className="space-y-2">
                                    {split.participants.map((p) => (
                                        <div
                                            key={p.contact_id ?? 'me'}
                                            className="flex items-center gap-3"
                                        >
                                            <label
                                                htmlFor={`share-${p.contact_id ?? 'me'}`}
                                                className="w-28 shrink-0 truncate text-sm text-[#3D2817]"
                                            >
                                                {nameOf(p.contact_id)}
                                            </label>
                                            <input
                                                id={`share-${p.contact_id ?? 'me'}`}
                                                type="number"
                                                inputMode="decimal"
                                                step="0.01"
                                                min="0"
                                                value={p.amount}
                                                onChange={(e) =>
                                                    setParticipantAmount(
                                                        p.contact_id,
                                                        e.target.value === ''
                                                            ? ''
                                                            : Number(
                                                                  e.target
                                                                      .value,
                                                              ),
                                                    )
                                                }
                                                placeholder="0,00"
                                                className={smallInput}
                                            />
                                        </div>
                                    ))}
                                    <p
                                        className={cn(
                                            'ml-1 text-xs',
                                            customDiff === 0
                                                ? 'text-[#1F5428]'
                                                : 'text-[#A65D57]',
                                        )}
                                    >
                                        Soma {formatCurrency(customSum)} de{' '}
                                        {formatCurrency(amount)}
                                        {customDiff !== 0 &&
                                            ` · faltam ${formatCurrency(customDiff)}`}
                                    </p>
                                </div>
                            )}

                            {/* Quem pagou (numa compra para outra pessoa, é você) */}
                            {includeMe && (
                                <div>
                                    <label
                                        htmlFor="paid-by"
                                        className={labelClass}
                                    >
                                        Quem pagou?
                                    </label>
                                    <select
                                        id="paid-by"
                                        value={split.paid_by_contact_id ?? ''}
                                        onChange={(e) =>
                                            update({
                                                paid_by_contact_id:
                                                    e.target.value || null,
                                            })
                                        }
                                        className={smallInput}
                                    >
                                        <option value="">Você</option>
                                        {selectedIds.map((id) => (
                                            <option key={id} value={id}>
                                                {nameOf(id)}
                                            </option>
                                        ))}
                                    </select>
                                    {split.paid_by_contact_id && (
                                        <p className="mt-1 ml-1 text-xs text-[#8B7355]">
                                            Nenhuma conta sua é afetada: só a
                                            sua parte entra como despesa.
                                        </p>
                                    )}
                                    {errors['split.paid_by_contact_id'] && (
                                        <p className="mt-1 ml-1 text-xs text-[#D4183D]">
                                            {errors['split.paid_by_contact_id']}
                                        </p>
                                    )}
                                </div>
                            )}
                        </>
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
            className="w-full overflow-y-auto bg-[#F5EFE6] p-8 md:w-1/2 md:p-12"
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
import { useAuth } from '@/hooks/use-auth';
import { useContacts } from '@/hooks/use-contacts';
import { splitBreakdown } from '@/lib/split';
import { getInstallmentValue } from '@/lib/transaction-math';
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
        <div className="relative hidden w-1/2 flex-col items-center justify-center overflow-hidden border-l-2 border-[#D4C5A9] bg-[#E8DCC4]/50 p-12 md:flex">
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
                            Conta
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

write 'resources/js/lib/split.ts' <<'PHAMANI_EOF'
import type { SplitForm, Transaction, TransactionSplit } from '@/types/phamani';

/**
 * Compra para outra pessoa: você pagou e a sua parte é zero.
 * O valor cheio vai para a conta/fatura e a parte de cada contato fica "a receber".
 */
export function isThirdParty(t: Transaction): boolean {
    return (
        t.type === 'expense' &&
        t.total_amount != null &&
        Number(t.amount) === 0 &&
        !t.paid_by_contact_id &&
        !t.mirrored_from_id
    );
}

/** Partes dos contatos numa compra para outra pessoa. */
export function receivableSplits(t: Transaction): TransactionSplit[] {
    return (t.splits ?? []).filter(
        (s) => s.contact_id !== null && Number(s.amount) > 0,
    );
}

/** Tudo devolvido? */
export function isFullyReimbursed(t: Transaction): boolean {
    const parts = receivableSplits(t);
    return parts.length > 0 && parts.every((s) => !!s.reimbursed_at);
}

/** Valor a mostrar nas listas: numa compra para outra pessoa, o valor cheio. */
export function displayAmount(t: Transaction): number {
    return isThirdParty(t) ? Number(t.total_amount) : Number(t.amount);
}

/** Sua parte numa divisão (prévia no front; o back-end faz o cálculo final). */
export function myShare(amount: number, split: SplitForm | null): number {
    if (!split || !amount) return amount || 0;
    if (split.include_me === false) return 0;

    const contacts = split.participants.filter((p) => p.contact_id !== null);
    if (contacts.length === 0) return amount;

    if (split.mode === 'custom') {
        const me = split.participants.find((p) => p.contact_id === null);
        return Number(me?.amount || 0);
    }

    return Math.floor((amount / (contacts.length + 1)) * 100) / 100;
}

/** Monta o formulário de divisão a partir de uma transação já salva (edição). */
export function splitFromTransaction(t: Transaction): SplitForm | null {
    if (t.total_amount == null || !t.splits?.length) return null;

    if (isThirdParty(t)) {
        const parts = receivableSplits(t);
        const amounts = parts.map((s) => Number(s.amount));
        const equal =
            amounts.length > 0 &&
            Math.max(...amounts) - Math.min(...amounts) <= 0.01;

        return {
            mode: equal ? 'equal' : 'custom',
            participants: parts.map((s) => ({
                contact_id: s.contact_id,
                amount: equal ? '' : Number(s.amount),
            })),
            paid_by_contact_id: null,
            include_me: false,
        };
    }

    const amounts = t.splits.map((s) => Number(s.amount));
    const equal = Math.max(...amounts) - Math.min(...amounts) <= 0.01;

    // Você sempre primeiro
    const ordered = [
        ...t.splits.filter((s) => s.contact_id === null),
        ...t.splits.filter((s) => s.contact_id !== null),
    ];

    return {
        mode: equal ? 'equal' : 'custom',
        participants: ordered.map((s) => ({
            contact_id: s.contact_id,
            amount: equal ? '' : Number(s.amount),
        })),
        paid_by_contact_id: t.paid_by_contact_id ?? null,
    };
}

/**
 * Parte de cada participante para um valor (prévia).
 * Mesma regra do back-end: partes iguais ou proporcionais aos valores, em centavos,
 * e o centavo que sobra fica com quem pagou.
 */
export function splitBreakdown(
    amount: number,
    split: SplitForm | null,
): Array<{ contact_id: string | null; amount: number }> {
    if (!split || !amount) return [];

    const participants = split.participants.some((p) => p.contact_id === null)
        ? split.participants
        : [
              { contact_id: null, amount: 0 as number | '' },
              ...split.participants,
          ];

    if (!participants.some((p) => p.contact_id !== null)) return [];

    const weights = participants.map((p) => {
        if (p.contact_id === null && split.include_me === false) return 0;
        return split.mode === 'custom'
            ? Math.round(Number(p.amount || 0) * 100)
            : 1;
    });
    const sumWeights = weights.reduce((a, b) => a + b, 0);
    const totalCents = Math.round(amount * 100);

    const cents = weights.map((w) =>
        sumWeights > 0 ? Math.floor((totalCents * w) / sumWeights) : 0,
    );
    const payerIndex = Math.max(
        0,
        participants.findIndex(
            (p) => p.contact_id === (split.paid_by_contact_id ?? null),
        ),
    );
    cents[payerIndex] += totalCents - cents.reduce((a, b) => a + b, 0);

    return participants.map((p, i) => ({
        contact_id: p.contact_id,
        amount: cents[i] / 100,
    }));
}
PHAMANI_EOF

write 'resources/js/pages/dashboard.tsx' <<'PHAMANI_EOF'
import { Head } from '@inertiajs/react';
import { useState } from 'react';
import { DashboardContent } from '@/components/phamani/dashboard/dashboard-content';
import { DashboardHeader } from '@/components/phamani/dashboard/dashboard-header';
import { DashboardMain } from '@/components/phamani/dashboard/dashboard-main';
import { DashboardSidebar } from '@/components/phamani/dashboard/dashboard-sidebar';
import { NewTransactionModal } from '@/components/phamani/modal/new-transaction-modal';
import type {
    Account,
    CashFlowPoint,
    Category,
    CategoryPiePoint,
    DashboardPeriod,
    Kpis,
    Receivable,
    Transaction,
} from '@/types/phamani';

interface DashboardProps {
    period: DashboardPeriod;
    kpis: Kpis;
    cashFlow: CashFlowPoint[];
    categoryPie: CategoryPiePoint[];
    recentTransactions: Transaction[];
    accounts: Account[];
    receivables: Receivable[];
    categories: Category[];
}

export default function Dashboard({
    period,
    kpis,
    cashFlow,
    categoryPie,
    recentTransactions,
    accounts,
    receivables,
    categories,
}: DashboardProps) {
    const [isNewTransactionOpen, setIsNewTransactionOpen] = useState(false);

    return (
        <>
            <Head title="Dashboard" />

            <div className="p-6 md:p-8">
                <DashboardHeader
                    title="Phamani"
                    subtitle="Gestão Financeira Pessoal"
                />

                <DashboardMain
                    left={
                        <DashboardContent
                            kpis={kpis}
                            period={period}
                            cashFlow={cashFlow}
                            categoryPie={categoryPie}
                        />
                    }
                    right={
                        <DashboardSidebar
                            recentTransactions={recentTransactions}
                            accounts={accounts}
                            receivables={receivables}
                            onNewTransaction={() =>
                                setIsNewTransactionOpen(true)
                            }
                        />
                    }
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
import { Button } from '@/components/phamani/ui/button';
import {
    DropdownMenu,
    DropdownMenuContent,
    DropdownMenuItem,
    DropdownMenuSeparator,
    DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
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

write 'resources/js/types/phamani/contact.ts' <<'PHAMANI_EOF'
export interface Contact {
    id: string;
    name: string;
    /** Contato vinculado a um usuário do Phamani (convite aceito). */
    linked_user_id: string | null;
    linked_user?: {
        id: string;
        name: string;
        email: string;
        avatar: string | null;
    } | null;
    /** E-mail do convite ainda não respondido. */
    pending_invite_email?: string | null;
}

export type SplitMode = 'equal' | 'custom';

export interface SplitParticipantForm {
    /** null = você */
    contact_id: string | null;
    /** Só no modo "valores" */
    amount: number | '';
}

export interface SplitForm {
    mode: SplitMode;
    participants: SplitParticipantForm[];
    /** null = você pagou */
    paid_by_contact_id: string | null;
    /**
     * false = compra para outra pessoa: você pagou, sua parte é zero e o valor fica "a receber".
     * Ausente = true.
     */
    include_me?: boolean;
}

export interface TransactionSplit {
    id: string;
    contact_id: string | null;
    amount: string | number;
    contact?: Pick<Contact, 'id' | 'name'> | null;
    /** Compra para outra pessoa: quando ela devolveu (null = ainda a receber). */
    reimbursed_at?: string | null;
    reimbursement_account_id?: string | null;
    reimbursed_amount?: string | number | null;
    reimbursement_account?: { id: string; name: string } | null;
}

export type ShareStatus =
    | 'pending'
    | 'accepted'
    | 'declined'
    | 'left'
    | 'removed';

/** Origem de uma cópia (transação de outra pessoa dividida com você). */
export interface MirrorSource {
    id: string;
    user_id: string;
    total_amount: string | number | null;
    paid_by_contact_id: string | null;
    user?: { id: string; name: string; avatar?: string | null } | null;
    paid_by?: Pick<Contact, 'id' | 'name' | 'linked_user_id'> | null;
    splits?: Array<{
        id: string;
        contact_id: string | null;
        amount: string | number;
        contact?: Pick<Contact, 'id' | 'name' | 'linked_user_id'> | null;
    }>;
}

export interface ShareLinkInfo {
    id: string;
    share?: {
        id: string;
        status: ShareStatus;
        owner_contact_id: string;
    } | null;
}

export interface PendingInvitation {
    id: string;
    created_at: string | null;
    inviter: {
        id: string;
        name: string;
        email: string;
        avatar: string | null;
    } | null;
}

export interface ShareSummary {
    id: string;
    status: ShareStatus;
    source_type: 'transaction' | 'installment' | 'recurring';
    owner: { id: string; name: string; avatar: string | null };
    name: string | null;
    date: string | null;
    total: number | null;
    my_amount: number;
    paid_by: string | null;
    you_paid: boolean;
    items: number;
    category_id: string | null;
    account_id: string | null;
}

export interface AppNotification {
    id: string;
    read_at: string | null;
    created_at: string;
    data: { kind: string; title: string; body: string; url: string | null };
}

export interface NotificationsProp {
    unread: number;
    pending: number;
    latest: AppNotification[];
}

export const SHARE_STATUS_LABELS: Record<ShareStatus, string> = {
    pending: 'aguardando',
    accepted: 'aceitou',
    declined: 'recusou',
    left: 'saiu',
    removed: 'removida',
};
PHAMANI_EOF

write 'resources/js/types/phamani/dashboard.ts' <<'PHAMANI_EOF'
export interface KPITrend {
    value: number;
    direction: 'up' | 'down';
}

export interface KPIValue {
    value: number;
    trend: KPITrend | null;
}

export interface Kpis {
    /** Só dinheiro em contas (cartões ficam de fora). */
    total_balance: number;
    /** Faturas a pagar até a fatura atual de cada cartão. */
    open_invoices: number;
    /** Despesas vencidas e não pagas. */
    overdue: { count: number; amount: number };
    income: KPIValue;
    expense: KPIValue;
    installments: KPIValue;
}

export interface CashFlowPoint {
    label: string;
    income: number;
    expense: number;
}

export interface CategoryPiePoint {
    name: string;
    value: number;
    color: string;
}

export type DashboardPeriod = 'monthly' | 'yearly';

/** Compra para outra pessoa: o que um contato ainda te deve. */
export interface ReceivableItem {
    /** id da parte (transaction_split) */
    id: string;
    transaction_id: string;
    name: string;
    date: string;
    amount: number;
    /** A data da compra já chegou (as futuras são parcelas ainda por vir). */
    due: boolean;
}

export interface Receivable {
    contact: { id: string; name: string; avatar: string | null };
    /** Só o que já venceu. */
    due_total: number;
    due_count: number;
    items: ReceivableItem[];
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

write 'tests/Feature/ReceivableTest.php' <<'PHAMANI_EOF'
<?php

namespace Tests\Feature;

use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\ICategoryService;
use App\Interfaces\Services\ICreditCardService;
use App\Interfaces\Services\IDashboardService;
use App\Interfaces\Services\IReimbursementService;
use App\Models\Account;
use App\Models\Category;
use App\Models\Contact;
use App\Models\Transaction;
use App\Models\TransactionSplit;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Compra para outra pessoa (ex.: o irmão usa o cartão e devolve por Pix).
 */
class ReceivableTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    private Account $checking;

    private Account $card;

    private Category $category;

    private Contact $irmao;

    protected function setUp(): void
    {
        parent::setUp();

        $this->travelTo('2026-11-18 10:00:00');

        $this->user = User::factory()->create();
        app(IAccountService::class)->createDefaultForUser($this->user->id);
        app(ICategoryService::class)->createDefaultsForUser($this->user->id);
        $this->category = Category::where('user_id', $this->user->id)->where('name', 'Outros')->firstOrFail();

        $this->checking = Account::create(['user_id' => $this->user->id, 'name' => 'Bradesco', 'type' => 'checking', 'balance' => 1000]);
        $this->card = Account::create([
            'user_id' => $this->user->id, 'name' => 'Elo', 'type' => 'credit', 'balance' => 0,
            'credit_limit' => 5000, 'closing_day' => 25, 'due_day' => 5,
        ]);

        $this->actingAs($this->user)->post(route('contacts.store'), ['name' => 'Irmão'])->assertSessionHasNoErrors();
        $this->irmao = Contact::where('name', 'Irmão')->firstOrFail();
    }

    /**
     * @param  array<string, mixed>  $overrides
     */
    private function storeForBrother(array $overrides = []): Transaction
    {
        $this->actingAs($this->user)
            ->post(route('transactions.store'), [
                'description' => 'Tênis do irmão',
                'amount' => 300,
                'type' => 'expense',
                'category_id' => $this->category->id,
                'account_id' => $this->card->id,
                'date' => '2026-11-18',
                'is_installment' => false,
                'installments_count' => 2,
                'installment_start' => 1,
                'amount_mode' => 'installment',
                'is_recurring' => false,
                'frequency' => 'monthly',
                'split' => [
                    'mode' => 'equal',
                    'participants' => [['contact_id' => $this->irmao->id]],
                    'paid_by_contact_id' => null,
                    'include_me' => false,
                ],
                ...$overrides,
            ])
            ->assertSessionHasNoErrors();

        return Transaction::query()->latest('created_at')->firstOrFail();
    }

    private function brotherSplit(Transaction $transaction): TransactionSplit
    {
        return TransactionSplit::where('transaction_id', $transaction->id)->where('contact_id', $this->irmao->id)->firstOrFail();
    }

    public function test_purchase_for_someone_else_goes_to_the_invoice_but_not_to_my_expenses(): void
    {
        $transaction = $this->storeForBrother();

        $this->assertEquals(0.0, (float) $transaction->amount);
        $this->assertEquals(300.0, (float) $transaction->total_amount);
        $this->assertEquals(300.0, (float) $this->brotherSplit($transaction)->amount);

        $summary = app(ICreditCardService::class)->summary($this->card->fresh());
        $this->assertEquals(300.0, $summary['used']);

        $kpis = app(IDashboardService::class)->kpis($this->user->id);
        $this->assertEquals(0.0, (float) $kpis['expense']['value']);

        $open = app(IReimbursementService::class)->openForUser($this->user->id);
        $this->assertCount(1, $open);
        $this->assertSame('Irmão', $open[0]['contact']['name']);
        $this->assertEquals(300.0, $open[0]['due_total']);
    }

    public function test_receiving_raises_the_account_balance_without_counting_as_income(): void
    {
        $split = $this->brotherSplit($this->storeForBrother());

        $this->actingAs($this->user)
            ->post(route('receivables.receive', $this->irmao), [
                'split_ids' => [$split->id],
                'account_id' => $this->checking->id,
                'date' => '2026-11-20',
            ])
            ->assertSessionHasNoErrors();

        $this->assertEquals(1300.0, (float) $this->checking->fresh()->balance);
        $this->assertSame('2026-11-20', $split->fresh()->reimbursed_at?->toDateString());

        $kpis = app(IDashboardService::class)->kpis($this->user->id);
        $this->assertEquals(0.0, (float) $kpis['income']['value']);
        $this->assertSame([], app(IReimbursementService::class)->openForUser($this->user->id));
    }

    public function test_undo_takes_the_money_back_out(): void
    {
        $split = $this->brotherSplit($this->storeForBrother());

        $this->actingAs($this->user)->post(route('receivables.receive', $this->irmao), [
            'split_ids' => [$split->id], 'account_id' => $this->checking->id, 'date' => '2026-11-20',
        ]);

        $this->actingAs($this->user)->delete(route('receivables.undo', $split))->assertSessionHasNoErrors();

        $this->assertEquals(1000.0, (float) $this->checking->fresh()->balance);
        $this->assertNull($split->fresh()->reimbursed_at);
    }

    public function test_editing_the_purchase_keeps_the_reimbursement(): void
    {
        $transaction = $this->storeForBrother();
        $split = $this->brotherSplit($transaction);

        $this->actingAs($this->user)->post(route('receivables.receive', $this->irmao), [
            'split_ids' => [$split->id], 'account_id' => $this->checking->id, 'date' => '2026-11-20',
        ]);

        $this->actingAs($this->user)
            ->put(route('transactions.update', $transaction), [
                'description' => 'Tênis (editado)',
                'amount' => 300,
                'type' => 'expense',
                'category_id' => $this->category->id,
                'account_id' => $this->card->id,
                'date' => '2026-11-18',
                'split' => [
                    'mode' => 'equal',
                    'participants' => [['contact_id' => $this->irmao->id]],
                    'paid_by_contact_id' => null,
                    'include_me' => false,
                ],
            ])
            ->assertSessionHasNoErrors();

        $this->assertNotNull($this->brotherSplit($transaction)->reimbursed_at);
        $this->assertEquals(1300.0, (float) $this->checking->fresh()->balance);
    }

    public function test_deleting_the_purchase_reverts_the_reimbursement(): void
    {
        $transaction = $this->storeForBrother();
        $split = $this->brotherSplit($transaction);

        $this->actingAs($this->user)->post(route('receivables.receive', $this->irmao), [
            'split_ids' => [$split->id], 'account_id' => $this->checking->id, 'date' => '2026-11-20',
        ]);

        $this->actingAs($this->user)->delete(route('transactions.destroy', $transaction))->assertSessionHasNoErrors();

        $this->assertEquals(1000.0, (float) $this->checking->fresh()->balance);
    }

    public function test_someone_else_cannot_be_the_payer_of_a_purchase_for_others(): void
    {
        $this->actingAs($this->user)
            ->post(route('transactions.store'), [
                'description' => 'X',
                'amount' => 100,
                'type' => 'expense',
                'category_id' => $this->category->id,
                'account_id' => null,
                'date' => '2026-11-18',
                'is_installment' => false,
                'installments_count' => 2,
                'installment_start' => 1,
                'amount_mode' => 'installment',
                'is_recurring' => false,
                'frequency' => 'monthly',
                'split' => [
                    'mode' => 'equal',
                    'participants' => [['contact_id' => $this->irmao->id]],
                    'paid_by_contact_id' => $this->irmao->id,
                    'include_me' => false,
                ],
            ])
            ->assertSessionHasErrors('split.paid_by_contact_id');
    }

    public function test_money_cannot_go_to_a_credit_card_or_to_another_users_contact(): void
    {
        $split = $this->brotherSplit($this->storeForBrother());

        $this->actingAs($this->user)
            ->post(route('receivables.receive', $this->irmao), [
                'split_ids' => [$split->id], 'account_id' => $this->card->id, 'date' => '2026-11-20',
            ])
            ->assertSessionHasErrors('account_id');

        $other = User::factory()->create();
        $this->actingAs($other)
            ->post(route('receivables.receive', $this->irmao), [
                'split_ids' => [$split->id], 'account_id' => $this->checking->id, 'date' => '2026-11-20',
            ])
            ->assertNotFound();
    }

    public function test_installments_for_someone_else_list_future_parcels_as_upcoming(): void
    {
        $this->storeForBrother([
            'description' => 'Celular do irmão',
            'amount' => 100,
            'is_installment' => true,
            'installments_count' => 3,
        ]);

        $open = app(IReimbursementService::class)->openForUser($this->user->id);

        $this->assertCount(3, $open[0]['items']);
        $this->assertSame(1, $open[0]['due_count']);
        $this->assertEquals(100.0, $open[0]['due_total']);
    }
}
PHAMANI_EOF


cat <<'MSG'

Pronto. Local:
  php artisan migrate
  php artisan wayfinder:generate --with-form
  php artisan test --filter=Receivable
Depois: git add -A && git commit -m "Compra para outra pessoa (a receber)" && git push
(o deploy roda a migration sozinho)
MSG
