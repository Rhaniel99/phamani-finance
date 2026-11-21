#!/usr/bin/env bash
# Phamani — compras no cartão seguem a fatura + fatura mais clara + "conferido"
#  - Bug: compra no cartão nascia "Paga" (e a cópia da divisão também). Agora fica "Na fatura" até a
#    fatura ser paga; pagar a fatura marca todas as compras (e cópias) como pagas; desfazer volta.
#    Não dá para marcar compra de cartão como paga à mão, e ela nunca fica "Atrasada".
#    "Pendentes" inclui o que está em fatura aberta. Migration ajusta os dados existentes.
#  - Fatura: valor cheio (o que está na fatura do banco), com aviso discreto
#    "· 👥 sua parte R$ X" nas divididas e "· para Fulano" nas compras para outra pessoa.
#  - "Conferido": caixinha em cada compra da fatura + "X de Y conferidas · R$ conferido de R$ total".
# Uso: na raiz do projeto ->  bash cartao-status-fatura-e-conferir.sh
set -euo pipefail
[ -f artisan ] && [ -f app/Services/CreditCardService.php ] || { echo "Rode na raiz do projeto Phamani."; exit 1; }
BACKUP=".backup-$(date +%Y%m%d%H%M%S)"
backup() { if [ -f "$1" ]; then mkdir -p "$BACKUP/$(dirname "$1")"; cp "$1" "$BACKUP/$1"; fi; }
write() { backup "$1"; mkdir -p "$(dirname "$1")"; cat > "$1"; echo "  ok  $1"; }
echo "Aplicando arquivos (backup em $BACKUP/):"

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
                'mirroredFrom:id,user_id,account_id,total_amount,paid_by_contact_id',
                'mirroredFrom.account:id,type',
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
    /**
     * "Conferido" na lista da fatura (marcar/desmarcar). Não muda valor nem status.
     */
    public function reconcile(Request $request, Transaction $transaction): RedirectResponse
    {
        $this->ensureOwner($request, $transaction);

        $transaction->forceFill([
            'reconciled_at' => $transaction->reconciled_at === null ? now() : null,
        ])->saveQuietly();

        return back();
    }

    private function ensureOwner(Request $request, Transaction $transaction): void
    {
        abort_unless($transaction->user_id === (string) $request->user()?->getAuthIdentifier(), 404);
    }
}
PHAMANI_EOF

write 'app/Models/Transaction.php' <<'PHAMANI_EOF'
<?php

namespace App\Models;

use App\Observers\TransactionObserver;
use Illuminate\Database\Eloquent\Attributes\ObservedBy;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Support\Carbon;

/**
 * @property \Carbon\CarbonInterface|null $reconciled_at
 * @property string $id
 * @property string $user_id
 * @property string|null $account_id
 * @property string $category_id
 * @property string|null $recurring_id
 * @property string|null $installment_id
 * @property string|null $invoice_id
 * @property int|null $installment_number
 * @property string $name
 * @property string|null $description
 * @property string $type
 * @property string $amount  Parte do usuário (numa divisão) ou o valor inteiro.
 * @property string|null $total_amount  Valor cheio quando a transação é dividida.
 * @property string|null $paid_by_contact_id  Quem pagou (null = o próprio usuário).
 * @property Carbon $date
 * @property bool $balance_applied
 * @property Carbon|null $paid_at  Pago/recebido em (null = pendente ou atrasado).
 * @property string|null $mirrored_from_id  Cópia de uma transação compartilhada por outro usuário.
 */
#[ObservedBy(TransactionObserver::class)]
class Transaction extends BaseModel
{
    protected $fillable = [
        'user_id',
        'account_id',
        'category_id',
        'recurring_id',
        'installment_id',
        'installment_number',
        'invoice_id',
        'total_amount',
        'paid_by_contact_id',
        'mirrored_from_id',
        'paid_at',
        'name',
        'description',
        'type',
        'amount',
        'date',
        'balance_applied',
        'reconciled_at',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
        'installment_number' => 'integer',
        'date' => 'date:Y-m-d',
        'balance_applied' => 'boolean',
        'paid_at' => 'date:Y-m-d',
        'total_amount' => 'decimal:2',
        'reconciled_at' => 'datetime',
    ];

    /**
     * Fora do cartão: nem compra num cartão de crédito, nem cópia de uma.
     * (Compras no cartão não ficam "atrasadas": a dívida está na fatura.)
     *
     * @param  Builder<self>  $query
     */
    public function scopeNotOnCard(Builder $query): void
    {
        $credit = Account::query()->select('id')->where('type', 'credit');

        $query
            ->where(fn (Builder $q) => $q->whereNull('account_id')->orWhereNotIn('account_id', $credit))
            ->where(fn (Builder $q) => $q
                ->whereNull('mirrored_from_id')
                ->orWhereNotIn('mirrored_from_id', self::query()->select('id')->whereIn('account_id', $credit)));
    }

    /**
     * No cartão (a compra ou a original de uma cópia).
     *
     * @param  Builder<self>  $query
     */
    public function scopeOnCard(Builder $query): void
    {
        $credit = Account::query()->select('id')->where('type', 'credit');

        $query->where(fn (Builder $q) => $q
            ->whereIn('account_id', $credit)
            ->orWhereIn('mirrored_from_id', self::query()->select('id')->whereIn('account_id', $credit)));
    }

    /** @return BelongsTo<Account, $this> */
    public function account(): BelongsTo
    {
        return $this->belongsTo(Account::class);
    }

    /** @return BelongsTo<Category, $this> */
    public function category(): BelongsTo
    {
        return $this->belongsTo(Category::class);
    }

    /** @return BelongsTo<Installment, $this> */
    public function installment(): BelongsTo
    {
        return $this->belongsTo(Installment::class);
    }

    /**
     * Quanto sai das contas do usuário: o total se ele pagou, nada se outra pessoa pagou.
     */
    public function cashAmount(): float
    {
        if ($this->paid_by_contact_id !== null || $this->account_id === null) {
            return 0.0;
        }

        return (float) ($this->total_amount ?? $this->amount);
    }

    /**
     * Cópia de uma divisão compartilhada por outra pessoa: só quem criou pode editar.
     */
    public function isMirror(): bool
    {
        return $this->mirrored_from_id !== null;
    }

    /** @return BelongsTo<Transaction, $this> */
    public function mirroredFrom(): BelongsTo
    {
        return $this->belongsTo(Transaction::class, 'mirrored_from_id');
    }

    /** @return BelongsTo<User, $this> */
    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    /** @return HasMany<ShareLink, $this> */
    public function shareLinks(): HasMany
    {
        return $this->hasMany(ShareLink::class, 'source_transaction_id');
    }

    public function isSplit(): bool
    {
        return $this->total_amount !== null;
    }

    /** @return HasMany<TransactionSplit, $this> */
    public function splits(): HasMany
    {
        return $this->hasMany(TransactionSplit::class);
    }

    /** @return BelongsTo<Contact, $this> */
    public function paidBy(): BelongsTo
    {
        return $this->belongsTo(Contact::class, 'paid_by_contact_id');
    }

    /** @return BelongsTo<CreditCardInvoice, $this> */
    public function invoice(): BelongsTo
    {
        return $this->belongsTo(CreditCardInvoice::class, 'invoice_id');
    }

    /** @return BelongsTo<RecurringTransaction, $this> */
    public function recurring(): BelongsTo
    {
        return $this->belongsTo(RecurringTransaction::class, 'recurring_id');
    }

    /** @return BelongsToMany<Tag, $this> */
    public function tags(): BelongsToMany
    {
        return $this->belongsToMany(Tag::class, 'transaction_tags');
    }
}
PHAMANI_EOF

write 'app/Observers/TransactionObserver.php' <<'PHAMANI_EOF'
<?php

namespace App\Observers;

use App\Interfaces\Services\ICreditCardService;
use App\Models\Account;
use App\Models\Transaction;

/**
 * Mantém cada transação na fatura certa, venha de onde vier
 * (lançamento simples, parcela, recorrência, edição).
 */
class TransactionObserver
{
    public function __construct(
        protected ICreditCardService $cards,
    ) {}

    /**
     * Status inicial, quando quem criou não definiu paid_at:
     * data de hoje ou passada → pago; futura → pendente.
     * Cartão: já definido no saving (segue a fatura).
     */
    public function creating(Transaction $transaction): void
    {
        if (array_key_exists('paid_at', $transaction->getAttributes())) {
            return;
        }

        $date = $transaction->date->toDateString();

        $transaction->paid_at = $date <= now()->toDateString() ? $date : null;
    }

    public function saving(Transaction $transaction): void
    {
        if ($transaction->exists && ! $transaction->isDirty(['account_id', 'date'])) {
            return;
        }

        $wasCard = $transaction->exists && $this->isCard($transaction->getOriginal('account_id'));

        // Cartão: fatura certa e status da fatura.
        $this->cards->assignInvoice($transaction);

        // Saiu do cartão para uma conta: volta à regra comum (passada → paga, futura → pendente).
        if ($wasCard && ! $this->isCard($transaction->account_id)) {
            $date = $transaction->date->toDateString();
            $transaction->paid_at = $date <= now()->toDateString() ? $date : null;
        }
    }

    private function isCard(?string $accountId): bool
    {
        return $accountId !== null
            && Account::query()->whereKey($accountId)->value('type') === 'credit';
    }
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
                    // Pendente: ainda não chegou, ou está numa fatura que não foi paga.
                    'pending' => $q->whereNull('paid_at')->where(fn ($w) => $w
                        ->whereDate('date', '>=', $today)
                        ->orWhere(fn ($c) => $c->onCard())),
                    // Compra no cartão não fica atrasada: quem vence é a fatura.
                    'overdue' => $q->whereNull('paid_at')->whereDate('date', '<', $today)->notOnCard(),
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
            ->whereNull('paid_at')
            ->notOnCard();

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
                'mirroredFrom:id,user_id,account_id,total_amount,paid_by_contact_id',
                'mirroredFrom.account:id,type',
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

write 'app/Services/CreditCardService.php' <<'PHAMANI_EOF'
<?php

namespace App\Services;

use App\Interfaces\Repositories\IAccountRepository;
use App\Interfaces\Services\ICreditCardService;
use App\Models\Account;
use App\Models\CreditCardInvoice;
use App\Models\Transaction;
use Carbon\CarbonImmutable;
use Carbon\CarbonInterface;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class CreditCardService implements ICreditCardService
{
    public function __construct(
        protected IAccountRepository $accounts,
    ) {}

    /**
     * Calcula o período da fatura em que cai uma compra.
     *
     * Ex.: fechamento dia 25, vencimento dia 5.
     *  - compra 20/11 → fecha 25/11, vence 05/12 (fatura de dezembro)
     *  - compra 26/11 → fecha 25/12, vence 05/01 (fatura de janeiro)
     * Meses curtos: dia 31 vira o último dia do mês.
     *
     * @return array{reference_month: CarbonImmutable, closing_date: CarbonImmutable, due_date: CarbonImmutable}
     */
    public function periodFor(Account $card, CarbonInterface $date): array
    {
        $date = CarbonImmutable::parse($date->toDateString());
        $closingDay = (int) $card->closing_day;
        $dueDay = (int) $card->due_day;

        $closingMonth = $date->startOfMonth();
        if ($date->greaterThan($this->dayIn($closingMonth, $closingDay))) {
            $closingMonth = $closingMonth->addMonthNoOverflow();
        }

        // Vencimento depois do fechamento no mesmo mês (fecha 5, vence 15) ou no mês seguinte (fecha 25, vence 5).
        $dueMonth = $dueDay > $closingDay ? $closingMonth : $closingMonth->addMonthNoOverflow();

        return [
            'reference_month' => $dueMonth,
            'closing_date' => $this->dayIn($closingMonth, $closingDay),
            'due_date' => $this->dayIn($dueMonth, $dueDay),
        ];
    }

    public function invoiceFor(Account $card, CarbonInterface $date): CreditCardInvoice
    {
        $period = $this->periodFor($card, $date);
        $reference = $period['reference_month']->toDateString();

        // whereDate (e não firstOrCreate) para comparar só a data em qualquer banco.
        $invoice = CreditCardInvoice::query()
            ->where('account_id', $card->id)
            ->whereDate('reference_month', $reference)
            ->first();

        /** @var CreditCardInvoice */
        return $invoice ?? CreditCardInvoice::query()->create([
            'user_id' => $card->user_id,
            'account_id' => $card->id,
            'reference_month' => $reference,
            'closing_date' => $period['closing_date']->toDateString(),
            'due_date' => $period['due_date']->toDateString(),
        ]);
    }

    /**
     * Fechamento e vencimento de uma fatura a partir do mês de referência (mês do vencimento).
     *
     * @return array{closing_date: CarbonImmutable, due_date: CarbonImmutable}
     */
    private function periodForReference(Account $card, CarbonInterface $referenceMonth): array
    {
        $dueMonth = CarbonImmutable::parse($referenceMonth->toDateString())->startOfMonth();
        $closingMonth = (int) $card->due_day > (int) $card->closing_day ? $dueMonth : $dueMonth->subMonthNoOverflow();

        return [
            'closing_date' => $this->dayIn($closingMonth, (int) $card->closing_day),
            'due_date' => $this->dayIn($dueMonth, (int) $card->due_day),
        ];
    }

    public function assignInvoice(Transaction $transaction): void
    {
        $card = $transaction->account_id !== null ? Account::query()->find($transaction->account_id) : null;

        if ($card === null || ! $card->isCreditCard()) {
            $transaction->invoice_id = null;

            return;
        }

        if (! $card->isConfiguredCard()) {
            // Cartão sem fechamento/vencimento: sem fatura, fica "na fatura" (não paga).
            $transaction->invoice_id = null;
            $transaction->paid_at = null;

            return;
        }

        $invoice = $this->invoiceFor($card, $transaction->date);

        $transaction->invoice_id = $invoice->id;
        // Status da compra = status da fatura: paga quando a fatura for paga.
        $transaction->paid_at = $invoice->paid_at?->toDateString();
    }

    public function reassignInvoices(Account $card): void
    {
        DB::transaction(function () use ($card) {
            $unpaid = Transaction::query()
                ->where('account_id', $card->id)
                ->where(fn ($q) => $q
                    ->whereNull('invoice_id')
                    ->orWhereIn('invoice_id', CreditCardInvoice::query()
                        ->select('id')
                        ->where('account_id', $card->id)
                        ->whereNull('paid_at')))
                ->get();

            foreach ($unpaid as $transaction) {
                $this->assignInvoice($transaction);
                $transaction->saveQuietly();
            }

            // Faturas abertas que ficaram vazias saem; o período delas mudou.
            CreditCardInvoice::query()
                ->where('account_id', $card->id)
                ->whereNull('paid_at')
                ->whereDoesntHave('transactions')
                ->delete();

            // Faturas abertas que continuam ganham as datas novas.
            CreditCardInvoice::query()
                ->where('account_id', $card->id)
                ->whereNull('paid_at')
                ->get()
                ->each(function (CreditCardInvoice $invoice) use ($card) {
                    $period = $this->periodForReference($card, $invoice->reference_month);
                    $invoice->update([
                        'closing_date' => $period['closing_date']->toDateString(),
                        'due_date' => $period['due_date']->toDateString(),
                    ]);
                });
        });
    }

    public function invoiceTotal(CreditCardInvoice $invoice): float
    {
        return $this->totalsFor([$invoice->id])[$invoice->id] ?? 0.0;
    }

    public function summary(Account $card): array
    {
        $limit = $card->credit_limit !== null ? (float) $card->credit_limit : null;

        if (! $card->isConfiguredCard()) {
            return ['limit' => $limit, 'used' => 0.0, 'available' => $limit, 'current_invoice' => null];
        }

        $unpaid = CreditCardInvoice::query()
            ->where('account_id', $card->id)
            ->whereNull('paid_at')
            ->pluck('id')
            ->all();

        $used = round(array_sum($this->totalsFor($unpaid)), 2);

        $period = $this->periodFor($card, now());
        $current = CreditCardInvoice::query()
            ->where('account_id', $card->id)
            ->whereDate('reference_month', $period['reference_month']->toDateString())
            ->first();

        return [
            'limit' => $limit,
            'used' => $used,
            'available' => $limit !== null ? round($limit - $used, 2) : null,
            'current_invoice' => [
                'id' => $current?->id,
                'reference_month' => $period['reference_month']->toDateString(),
                'closing_date' => $period['closing_date']->toDateString(),
                'due_date' => $period['due_date']->toDateString(),
                'total' => $current !== null ? $this->invoiceTotal($current) : 0.0,
                'status' => $current?->status() ?? 'open',
            ],
        ];
    }

    public function invoicesFor(Account $card): array
    {
        $invoices = CreditCardInvoice::query()
            ->where('account_id', $card->id)
            ->orderByDesc('reference_month')
            ->get();

        $totals = $this->totalsFor($invoices->pluck('id')->all());

        return $invoices
            ->map(fn (CreditCardInvoice $invoice) => [
                'id' => $invoice->id,
                'reference_month' => $invoice->reference_month->toDateString(),
                'closing_date' => $invoice->closing_date->toDateString(),
                'due_date' => $invoice->due_date->toDateString(),
                'total' => $totals[$invoice->id] ?? 0.0,
                'status' => $invoice->status(),
                'paid_at' => $invoice->paid_at?->toDateString(),
                'paid_amount' => $invoice->paid_amount !== null ? (float) $invoice->paid_amount : null,
                'paid_from_account_id' => $invoice->paid_from_account_id,
            ])
            ->values()
            ->all();
    }

    public function openInvoicesTotal(string $userId): float
    {
        $total = 0.0;

        $cards = Account::query()->where('user_id', $userId)->where('type', 'credit')->get();

        foreach ($cards as $card) {
            if (! $card->isConfiguredCard()) {
                continue;
            }

            $currentReference = $this->periodFor($card, now())['reference_month']->toDateString();

            $ids = CreditCardInvoice::query()
                ->where('account_id', $card->id)
                ->whereNull('paid_at')
                ->whereDate('reference_month', '<=', $currentReference)
                ->pluck('id')
                ->all();

            $total += array_sum($this->totalsFor($ids));
        }

        return round($total, 2);
    }

    public function pay(CreditCardInvoice $invoice, string $fromAccountId, string $date): void
    {
        if ($invoice->paid_at !== null) {
            throw ValidationException::withMessages(['invoice' => 'Esta fatura já está paga.']);
        }

        $total = $this->invoiceTotal($invoice);

        if ($total <= 0) {
            throw ValidationException::withMessages(['invoice' => 'Não há valor a pagar nesta fatura.']);
        }

        DB::transaction(function () use ($invoice, $fromAccountId, $date, $total) {
            $invoice->update([
                'paid_at' => $date,
                'paid_amount' => $total,
                'paid_from_account_id' => $fromAccountId,
            ]);

            // Sai dinheiro da conta, mas não é despesa: as compras já foram contadas uma a uma.
            $this->accounts->applyTransaction($fromAccountId, $total, 'expense');

            $this->setPurchasesPaidAt($invoice, $date);
        });
    }

    public function undoPayment(CreditCardInvoice $invoice): void
    {
        if ($invoice->paid_at === null) {
            return;
        }

        DB::transaction(function () use ($invoice) {
            if ($invoice->paid_from_account_id !== null && $invoice->paid_amount !== null) {
                $this->accounts->revertTransaction($invoice->paid_from_account_id, (float) $invoice->paid_amount, 'expense');
            }

            $invoice->update([
                'paid_at' => null,
                'paid_amount' => null,
                'paid_from_account_id' => null,
            ]);

            $this->setPurchasesPaidAt($invoice, null);
        });
    }

    /**
     * As compras da fatura (e as cópias delas, nas divisões) acompanham o pagamento da fatura.
     * Compras no cartão não mexem no saldo, então basta gravar o status.
     */
    private function setPurchasesPaidAt(CreditCardInvoice $invoice, ?string $date): void
    {
        $ids = Transaction::query()->where('invoice_id', $invoice->id)->pluck('id');

        Transaction::query()->whereIn('id', $ids)->update(['paid_at' => $date]);
        Transaction::query()->whereIn('mirrored_from_id', $ids)->update(['paid_at' => $date]);
    }

    /**
     * @param  list<string>  $invoiceIds
     * @return array<string, float>
     */
    private function totalsFor(array $invoiceIds): array
    {
        if ($invoiceIds === []) {
            return [];
        }

        return Transaction::query()
            ->whereIn('invoice_id', $invoiceIds)
            ->groupBy('invoice_id')
            // Numa compra dividida, entra na fatura o valor cheio (coalesce com total_amount).
            ->selectRaw("invoice_id, sum(case when type = 'expense' then coalesce(total_amount, amount) else -coalesce(total_amount, amount) end) as total")
            ->pluck('total', 'invoice_id')
            ->map(fn ($total) => round((float) $total, 2))
            ->all();
    }

    private function dayIn(CarbonImmutable $month, int $day): CarbonImmutable
    {
        return $month->startOfMonth()->day(min($day, $month->daysInMonth));
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
            ->notOnCard()
            ->whereDate('date', '<', now()->toDateString());

        return [
            'count' => (clone $query)->count(),
            'amount' => round((float) (clone $query)->sum('amount'), 2),
        ];
    }
}
PHAMANI_EOF

write 'app/Services/PaymentService.php' <<'PHAMANI_EOF'
<?php

namespace App\Services;

use App\Interfaces\Services\IBalanceService;
use App\Interfaces\Services\IPaymentService;
use App\Models\Account;
use App\Models\Contact;
use App\Models\Installment;
use App\Models\RecurringTransaction;
use App\Models\ShareLink;
use App\Models\Transaction;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class PaymentService implements IPaymentService
{
    public function __construct(
        protected IBalanceService $balance,
    ) {}

    public function markPaid(Transaction $transaction, User $user): void
    {
        $source = $this->sourceOf($transaction);
        $this->ensureNotOnCard($source);
        $this->ensurePayer($source, $user);

        $this->setPaid($source, now()->toDateString());
    }

    public function markUnpaid(Transaction $transaction, User $user): void
    {
        $source = $this->sourceOf($transaction);
        $this->ensureNotOnCard($source);
        $this->ensurePayer($source, $user);

        $this->setPaid($source, null);
    }

    public function processAutoPay(): int
    {
        $count = 0;

        Transaction::query()
            ->whereNull('paid_at')
            ->whereNull('mirrored_from_id')
            // No cartão, quem paga é a fatura.
            ->notOnCard()
            ->whereDate('date', '<=', now()->toDateString())
            ->where(fn ($q) => $q
                ->whereIn('recurring_id', RecurringTransaction::query()->select('id')->where('auto_pay', true))
                ->orWhereIn('installment_id', Installment::query()->select('id')->where('auto_pay', true)))
            ->lazyById()
            ->each(function (Transaction $transaction) use (&$count) {
                // Débito automático: considera pago na data do vencimento.
                $this->setPaid($transaction, $transaction->date->toDateString());
                $count++;
            });

        return $count;
    }

    /**
     * Grava o status na original e nas cópias, ajustando o saldo de cada uma.
     */
    private function setPaid(Transaction $source, ?string $paidAt): void
    {
        DB::transaction(function () use ($source, $paidAt) {
            $targets = collect([$source]);

            $mirrorIds = ShareLink::query()
                ->where('source_transaction_id', $source->id)
                ->whereNotNull('mirror_transaction_id')
                ->pluck('mirror_transaction_id');

            if ($mirrorIds->isNotEmpty()) {
                $targets = $targets->merge(Transaction::query()->whereIn('id', $mirrorIds)->get());
            }

            foreach ($targets as $transaction) {
                if ($paidAt === null) {
                    $this->balance->revert($transaction);
                }

                $transaction->forceFill(['paid_at' => $paidAt])->save();

                if ($paidAt !== null) {
                    $this->balance->applyIfDue($transaction);
                }
            }
        });
    }

    /**
     * Numa cópia compartilhada, o status é da transação original.
     */
    private function sourceOf(Transaction $transaction): Transaction
    {
        if (! $transaction->isMirror()) {
            return $transaction;
        }

        return Transaction::query()->findOrFail($transaction->mirrored_from_id);
    }

    /**
     * Quem marca é quem pagou: o dono (se ele pagou ou se pagou alguém que não usa o Phamani)
     * ou o usuário vinculado ao contato que pagou.
     */
    private function ensureNotOnCard(Transaction $source): void
    {
        if ($source->account_id !== null && Account::query()->whereKey($source->account_id)->value('type') === 'credit') {
            throw ValidationException::withMessages([
                'paid' => 'Compra no cartão fica paga quando a fatura é paga.',
            ]);
        }
    }

    private function ensurePayer(Transaction $source, User $user): void
    {
        $payerId = $source->user_id;

        if ($source->paid_by_contact_id !== null) {
            $payerId = Contact::query()->whereKey($source->paid_by_contact_id)->value('linked_user_id') ?? $source->user_id;
        }

        if ($payerId !== $user->id) {
            $name = User::query()->whereKey($payerId)->value('name') ?? 'quem pagou';

            throw ValidationException::withMessages([
                'paid' => "Só {$name} pode marcar esta conta como paga.",
            ]);
        }
    }
}
PHAMANI_EOF

write 'database/migrations/2026_11_21_000200_card_status_follows_invoice.php' <<'PHAMANI_EOF'
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Compras no cartão: o status passa a seguir a fatura ("Na fatura" até a fatura ser paga),
 * em vez de nascerem pagas. As cópias compartilhadas seguem a original.
 * E reconciled_at: "conferido" na lista da fatura.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('transactions', function (Blueprint $table) {
            $table->timestamp('reconciled_at')->nullable();
        });

        $credit = DB::table('accounts')->select('id')->where('type', 'credit');

        DB::table('transactions')
            ->whereIn('account_id', $credit)
            ->update([
                'paid_at' => DB::raw('(select i.paid_at from credit_card_invoices i where i.id = transactions.invoice_id)'),
            ]);

        // Cópias de compras no cartão: mesmo status da original.
        $cardSources = DB::table('transactions')->whereIn('account_id', $credit)->get(['id', 'paid_at']);

        foreach ($cardSources as $source) {
            DB::table('transactions')->where('mirrored_from_id', $source->id)->update(['paid_at' => $source->paid_at]);
        }
    }

    public function down(): void
    {
        Schema::table('transactions', function (Blueprint $table) {
            $table->dropColumn('reconciled_at');
        });
    }
};
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
import { canMarkPaid, isOnCard, payerName, paymentStatus } from '@/lib/payment';
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
                {status === 'invoice' ? (
                    <p className="mt-1 text-xs text-[#8B7355]">
                        Compra no cartão
                        {transaction.mirrored_from_id && payerName(transaction)
                            ? ` de ${payerName(transaction)}`
                            : ''}
                        : fica paga quando a fatura for paga.
                    </p>
                ) : transaction.paid_at && isOnCard(transaction) ? (
                    <p className="mt-1 text-xs text-[#8B7355]">
                        A fatura do cartão foi paga.
                    </p>
                ) : (
                    !canMark && (
                        <p className="mt-1 text-xs text-[#8B7355]">
                            Quem marca é quem pagou
                            {payerName(transaction)
                                ? ` (${payerName(transaction)})`
                                : ''}
                            .
                        </p>
                    )
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

write 'resources/js/components/phamani/payment-status-badge.tsx' <<'PHAMANI_EOF'
import { cn } from '@/lib/utils';
import type { PaymentStatus } from '@/lib/payment';

const STYLES: Record<PaymentStatus, string> = {
    paid: 'bg-[#E3F9E5] text-[#1F5428]',
    pending: 'bg-[#E8DCC4] text-[#6B4E3D]',
    overdue: 'bg-[#FCE7E7] text-[#A65D57]',
    invoice: 'bg-[#EDE7F6] text-[#5B4A86]',
};

export function paymentStatusLabel(
    status: PaymentStatus,
    isIncome: boolean,
): string {
    if (status === 'paid') return isIncome ? 'Recebido' : 'Pago';
    if (status === 'overdue') return 'Atrasado';
    if (status === 'invoice') return 'Na fatura';

    return 'Pendente';
}

export function PaymentStatusBadge({
    status,
    isIncome = false,
    className,
}: {
    status: PaymentStatus;
    isIncome?: boolean;
    className?: string;
}) {
    return (
        <span
            className={cn(
                'inline-flex items-center rounded-md px-1.5 py-0.5 text-[10px] font-bold tracking-wide uppercase',
                STYLES[status],
                className,
            )}
        >
            {paymentStatusLabel(status, isIncome)}
        </span>
    );
}
PHAMANI_EOF

write 'resources/js/lib/payment.ts' <<'PHAMANI_EOF'
import { today } from '@/lib/format';
import type { Transaction } from '@/types/phamani';

export type PaymentStatus = 'paid' | 'pending' | 'overdue' | 'invoice';

/** Compra num cartão de crédito (ou cópia de uma): quem paga é a fatura. */
export function isOnCard(t: Transaction): boolean {
    return (
        t.account?.type === 'credit' ||
        t.mirrored_from?.account?.type === 'credit'
    );
}

/**
 * Status de pagamento. No cartão: "na fatura" até a fatura ser paga (nunca "atrasado").
 */
export function paymentStatus(t: Transaction): PaymentStatus | null {
    if (t.paid_at) return 'paid';
    if (isOnCard(t)) return 'invoice';

    return t.date.slice(0, 10) < today() ? 'overdue' : 'pending';
}

/**
 * Quem marca como pago é quem pagou:
 * - na sua transação: você, a não ser que o pagador seja um contato que usa o Phamani;
 * - numa cópia compartilhada com você: só se foi você quem pagou.
 */
export function canMarkPaid(t: Transaction): boolean {
    if (isOnCard(t)) return false;
    if (t.mirrored_from_id) return t.paid_by_contact_id == null;

    return !t.paid_by || !t.paid_by.linked_user_id;
}

/** Nome de quem pode marcar (para explicar quando não é você). */
export function payerName(t: Transaction): string | null {
    if (t.mirrored_from_id) {
        return (
            t.mirrored_from?.paid_by?.name ??
            t.mirrored_from?.user?.name ??
            null
        );
    }

    return t.paid_by?.name ?? null;
}
PHAMANI_EOF

write 'resources/js/pages/cards/show.tsx' <<'PHAMANI_EOF'
import { Head, router } from '@inertiajs/react';
import {
    CalendarClock,
    Check,
    HandCoins,
    Pencil,
    Plus,
    Undo2,
    Users,
} from 'lucide-react';
import { useState } from 'react';
import { CategoryIcon } from '@/components/phamani/category-icon';
import { DashboardHeader } from '@/components/phamani/dashboard/dashboard-header';
import { CreateAccountDrawer } from '@/components/phamani/drawer/create-account-drawer';
import { ShowTransactionDrawer } from '@/components/phamani/drawer/show-transaction-drawer';
import { NewTransactionModal } from '@/components/phamani/modal/new-transaction-modal';
import { Button } from '@/components/phamani/ui/button';
import { formatCurrency, formatDate, formatMonth, today } from '@/lib/format';
import { isThirdParty, receivableSplits } from '@/lib/split';
import { cn } from '@/lib/utils';
import { dashboard } from '@/routes';
import { show as cardShow } from '@/routes/cards';
import { reconcile } from '@/routes/transactions';
import { pay as payInvoice, undo as undoPayment } from '@/routes/invoices';
import { INVOICE_STATUS_LABELS } from '@/types/phamani';
import type {
    Account,
    Category,
    Invoice,
    InvoiceStatus,
    Transaction,
} from '@/types/phamani';

interface CardPageProps {
    card: Account;
    invoices: Invoice[];
    selectedInvoice: Invoice | null;
    transactions: Transaction[];
    accounts: Account[];
    categories: Category[];
}

const STATUS_STYLES: Record<InvoiceStatus, string> = {
    open: 'bg-[#E8DCC4] text-[#6B4E3D]',
    closed: 'bg-[#FCE7E7] text-[#A65D57]',
    paid: 'bg-[#E3F9E5] text-[#1F5428]',
};

export default function CardShow({
    card,
    invoices,
    selectedInvoice,
    transactions,
    accounts,
    categories,
}: CardPageProps) {
    const [editingCard, setEditingCard] = useState(false);
    const [newPurchaseOpen, setNewPurchaseOpen] = useState(false);
    const [selected, setSelected] = useState<Transaction | null>(null);
    const [editing, setEditing] = useState<Transaction | null>(null);

    const summary = card.card;
    const limit = summary?.limit ?? null;
    const usedPct =
        limit && limit > 0 && summary
            ? Math.min(100, Math.max(0, (summary.used / limit) * 100))
            : 0;

    function selectInvoice(id: string) {
        router.get(
            cardShow.url(card.id),
            { invoice: id },
            {
                preserveState: true,
                preserveScroll: true,
                replace: true,
                only: ['selectedInvoice', 'transactions'],
            },
        );
    }

    return (
        <>
            <Head title={card.name} />

            <div className="p-6 md:p-8">
                <DashboardHeader
                    title={card.name}
                    subtitle={
                        card.closing_day && card.due_day
                            ? `Cartão de crédito · fecha dia ${card.closing_day} · vence dia ${card.due_day}`
                            : 'Cartão de crédito'
                    }
                    onBack={() => router.visit(dashboard.url())}
                    actions={
                        <div className="flex gap-2">
                            <Button
                                variant="secondary"
                                onClick={() => setEditingCard(true)}
                                className="h-12"
                            >
                                <Pencil className="h-5 w-5 md:mr-2" />
                                <span className="hidden md:inline">
                                    Editar cartão
                                </span>
                            </Button>
                            <Button
                                variant="primary"
                                onClick={() => setNewPurchaseOpen(true)}
                                className="h-12"
                            >
                                <Plus className="h-5 w-5 md:mr-2" />
                                <span className="hidden md:inline">
                                    Nova compra
                                </span>
                            </Button>
                        </div>
                    }
                />

                {/* Limite */}
                <div className="mb-8 rounded-3xl border-2 border-[#3D2817] bg-[#E8DCC4] p-6">
                    <div className="mb-4 grid grid-cols-3 gap-4">
                        <Stat
                            label="Limite"
                            value={limit != null ? formatCurrency(limit) : '—'}
                        />
                        <Stat
                            label="Usado"
                            value={formatCurrency(summary?.used ?? 0)}
                        />
                        <Stat
                            label="Disponível"
                            value={
                                summary?.available != null
                                    ? formatCurrency(summary.available)
                                    : '—'
                            }
                            strong
                        />
                    </div>
                    {limit != null && limit > 0 && (
                        <div
                            className="h-3 overflow-hidden rounded-full bg-[#F5EFE6]"
                            role="progressbar"
                            aria-label="Limite usado"
                            aria-valuenow={Math.round(usedPct)}
                            aria-valuemin={0}
                            aria-valuemax={100}
                        >
                            <div
                                className={cn(
                                    'h-full rounded-full',
                                    usedPct > 85
                                        ? 'bg-[#A65D57]'
                                        : 'bg-[#3D2817]',
                                )}
                                style={{ width: `${usedPct}%` }}
                            />
                        </div>
                    )}
                    <p className="mt-3 text-xs text-[#6B4E3D]">
                        O usado inclui parcelas futuras: uma compra em 10x ocupa
                        o valor inteiro do limite e vai sendo liberada a cada
                        fatura paga.
                    </p>
                </div>

                {/* Faturas */}
                {invoices.length === 0 ? (
                    <p className="rounded-2xl border border-dashed border-[#D4C5A9] p-8 text-center text-[#8B7355]">
                        Nenhuma compra neste cartão ainda.
                    </p>
                ) : (
                    <>
                        <div className="mb-6 scrollbar-hide flex gap-2 overflow-x-auto pb-2">
                            {[...invoices].reverse().map((inv) => (
                                <button
                                    key={inv.id}
                                    type="button"
                                    onClick={() => selectInvoice(inv.id)}
                                    className={cn(
                                        'flex shrink-0 flex-col items-start rounded-2xl border px-4 py-2 text-left transition-all',
                                        selectedInvoice?.id === inv.id
                                            ? 'border-[#3D2817] bg-[#3D2817] text-[#F5EFE6]'
                                            : 'border-[#E8DCC4] bg-white text-[#3D2817] hover:border-[#6B4F3A]',
                                    )}
                                >
                                    <span className="text-sm font-bold capitalize">
                                        {formatMonth(inv.reference_month)}
                                    </span>
                                    <span className="text-xs opacity-75">
                                        {formatCurrency(inv.total)} ·{' '}
                                        {INVOICE_STATUS_LABELS[inv.status]}
                                    </span>
                                </button>
                            ))}
                        </div>

                        {selectedInvoice && (
                            <InvoicePanel
                                invoice={selectedInvoice}
                                card={card}
                                accounts={accounts}
                            />
                        )}

                        <InvoicePurchases
                            transactions={transactions}
                            onOpen={setSelected}
                        />
                    </>
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
                    isOpen={newPurchaseOpen}
                    onClose={() => setNewPurchaseOpen(false)}
                    categories={categories}
                    accounts={accounts}
                    defaultAccountId={card.id}
                />

                <CreateAccountDrawer
                    isOpen={editingCard}
                    onClose={() => setEditingCard(false)}
                    accounts={accounts}
                    account={card}
                />
            </div>
        </>
    );
}

function Stat({
    label,
    value,
    strong = false,
}: {
    label: string;
    value: string;
    strong?: boolean;
}) {
    return (
        <div>
            <p className="text-xs font-bold tracking-wider text-[#8B7355] uppercase">
                {label}
            </p>
            <p
                className={cn(
                    'font-bold text-[#3D2817]',
                    strong ? 'text-2xl' : 'text-lg',
                )}
            >
                {value}
            </p>
        </div>
    );
}

function InvoicePanel({
    invoice,
    card,
    accounts,
}: {
    invoice: Invoice;
    card: Account;
    accounts: Account[];
}) {
    const paymentAccounts = accounts.filter((a) => a.type !== 'credit');
    const [accountId, setAccountId] = useState(
        card.payment_account_id ?? paymentAccounts[0]?.id ?? '',
    );
    const [date, setDate] = useState(today());
    const [processing, setProcessing] = useState(false);
    const [error, setError] = useState<string | null>(null);

    const difference =
        invoice.paid_amount != null
            ? Math.round((invoice.total - invoice.paid_amount) * 100) / 100
            : 0;

    function handlePay() {
        router.post(
            payInvoice.url(invoice.id),
            { account_id: accountId, date },
            {
                preserveScroll: true,
                onStart: () => {
                    setProcessing(true);
                    setError(null);
                },
                onFinish: () => setProcessing(false),
                onError: (errors) =>
                    setError(Object.values(errors)[0] ?? 'Erro ao pagar.'),
            },
        );
    }

    function handleUndo() {
        router.delete(undoPayment.url(invoice.id), {
            preserveScroll: true,
            onStart: () => setProcessing(true),
            onFinish: () => setProcessing(false),
        });
    }

    return (
        <div className="rounded-3xl border border-[#E8DCC4] bg-[#FBF7F1] p-6">
            <div className="flex flex-wrap items-start justify-between gap-4">
                <div>
                    <div className="mb-1 flex items-center gap-2">
                        <h3 className="text-xl font-bold text-[#3D2817] capitalize">
                            Fatura de {formatMonth(invoice.reference_month)}
                        </h3>
                        <span
                            className={cn(
                                'rounded-md px-2 py-0.5 text-[10px] font-bold tracking-wide uppercase',
                                STATUS_STYLES[invoice.status],
                            )}
                        >
                            {INVOICE_STATUS_LABELS[invoice.status]}
                        </span>
                    </div>
                    <p className="flex items-center gap-1 text-sm text-[#6B4E3D]">
                        <CalendarClock className="h-4 w-4" />
                        Fecha {formatDate(invoice.closing_date)} · vence{' '}
                        {formatDate(invoice.due_date)}
                    </p>
                </div>
                <div className="text-right">
                    <p className="text-xs font-bold tracking-wider text-[#8B7355] uppercase">
                        Total
                    </p>
                    <p className="text-3xl font-bold text-[#3D2817]">
                        {formatCurrency(invoice.total)}
                    </p>
                </div>
            </div>

            <div className="mt-6 border-t border-[#E8DCC4] pt-6">
                {invoice.status === 'paid' ? (
                    <div className="flex flex-wrap items-center justify-between gap-4">
                        <div className="text-sm text-[#3D2817]">
                            <p>
                                Paga em {formatDate(invoice.paid_at)} ·{' '}
                                {formatCurrency(invoice.paid_amount)}
                                {(() => {
                                    const from = accounts.find(
                                        (a) =>
                                            a.id ===
                                            invoice.paid_from_account_id,
                                    );
                                    return from ? ` · ${from.name}` : '';
                                })()}
                            </p>
                            {difference !== 0 && (
                                <p className="mt-1 text-xs text-[#A65D57]">
                                    Diferença de {formatCurrency(difference)} em
                                    compras lançadas depois do pagamento.
                                </p>
                            )}
                        </div>
                        <button
                            type="button"
                            onClick={handleUndo}
                            disabled={processing}
                            className="flex items-center gap-2 rounded-xl border-2 border-[#D4C5A9] px-4 py-2 text-sm font-medium text-[#6B4E3D] hover:bg-[#E8DCC4] disabled:opacity-50"
                        >
                            <Undo2 className="h-4 w-4" />
                            Desfazer pagamento
                        </button>
                    </div>
                ) : invoice.total > 0 ? (
                    <div className="space-y-3">
                        <div className="grid gap-3 md:grid-cols-[1fr_auto_auto]">
                            <label className="sr-only" htmlFor="pay-account">
                                Pagar com
                            </label>
                            <select
                                id="pay-account"
                                value={accountId}
                                onChange={(e) => setAccountId(e.target.value)}
                                className="rounded-xl border-2 border-[#E8DCC4] bg-white px-4 py-3 text-[#3D2817]"
                            >
                                {paymentAccounts.map((a) => (
                                    <option key={a.id} value={a.id}>
                                        Pagar com {a.name} (
                                        {formatCurrency(a.balance)})
                                    </option>
                                ))}
                            </select>
                            <label className="sr-only" htmlFor="pay-date">
                                Data do pagamento
                            </label>
                            <input
                                id="pay-date"
                                type="date"
                                value={date}
                                max={today()}
                                onChange={(e) => setDate(e.target.value)}
                                className="rounded-xl border-2 border-[#E8DCC4] bg-white px-4 py-3 text-[#3D2817]"
                            />
                            <button
                                type="button"
                                onClick={handlePay}
                                disabled={processing || !accountId}
                                className="rounded-xl bg-[#3D2817] px-6 py-3 font-medium text-[#F5EFE6] shadow-lg hover:bg-[#543924] disabled:opacity-50"
                            >
                                {processing
                                    ? 'Pagando...'
                                    : `Pagar ${formatCurrency(invoice.total)}`}
                            </button>
                        </div>
                        {error && (
                            <p className="text-xs text-[#D4183D]">{error}</p>
                        )}
                        <p className="text-xs text-[#8B7355]">
                            O valor sai da conta escolhida e libera o limite.
                            Não conta como despesa: as compras já foram contadas
                            uma a uma.
                        </p>
                    </div>
                ) : (
                    <p className="text-sm text-[#8B7355]">
                        Nada a pagar nesta fatura.
                    </p>
                )}
            </div>
        </div>
    );
}

/** Valor que entrou na fatura (numa divisão, o valor cheio; a sua parte vem embaixo). */
function chargedAmount(t: Transaction): number {
    return Number(t.total_amount ?? t.amount);
}

/**
 * Compras da fatura, com "conferido" (para bater com a fatura do banco)
 * e um aviso discreto quando a compra é dividida ou de outra pessoa.
 */
function InvoicePurchases({
    transactions,
    onOpen,
}: {
    transactions: Transaction[];
    onOpen: (t: Transaction) => void;
}) {
    const [busy, setBusy] = useState<string | null>(null);

    const checked = transactions.filter((t) => !!t.reconciled_at);
    const checkedTotal = checked.reduce((sum, t) => sum + chargedAmount(t), 0);
    const total = transactions.reduce((sum, t) => sum + chargedAmount(t), 0);

    function toggle(t: Transaction) {
        router.post(
            reconcile.url(t.id),
            {},
            {
                preserveScroll: true,
                preserveState: true,
                only: ['transactions'],
                onStart: () => setBusy(t.id),
                onFinish: () => setBusy(null),
            },
        );
    }

    return (
        <div className="mt-6 overflow-hidden rounded-3xl border border-[#E8DCC4] bg-white shadow-sm">
            {transactions.length === 0 ? (
                <p className="px-6 py-12 text-center text-[#8B7355]">
                    Nenhuma compra nesta fatura.
                </p>
            ) : (
                <div className="flex flex-wrap items-center justify-between gap-2 border-b border-[#E8DCC4] bg-[#FBF7F1] px-6 py-3 text-xs text-[#6B4E3D]">
                    <span>
                        <strong className="text-[#3D2817]">
                            {checked.length} de {transactions.length}
                        </strong>{' '}
                        conferidas
                    </span>
                    <span>
                        {formatCurrency(checkedTotal)} de{' '}
                        {formatCurrency(total)}
                    </span>
                </div>
            )}

            <ul className="divide-y divide-[#E8DCC4]">
                {transactions.map((t) => {
                    const isChecked = !!t.reconciled_at;
                    const forOthers = isThirdParty(t);
                    const split = !forOthers && t.total_amount != null;

                    return (
                        <li
                            key={t.id}
                            className={cn(
                                'flex items-center gap-1 pl-3 transition-colors',
                                isChecked && 'bg-[#F7FBF7]',
                            )}
                        >
                            <button
                                type="button"
                                role="checkbox"
                                aria-checked={isChecked}
                                aria-label={
                                    isChecked
                                        ? `Desmarcar ${t.name} como conferida`
                                        : `Marcar ${t.name} como conferida`
                                }
                                title={isChecked ? 'Conferida' : 'Conferir'}
                                disabled={busy === t.id}
                                onClick={() => toggle(t)}
                                className={cn(
                                    'flex h-6 w-6 shrink-0 items-center justify-center rounded-md border-2 transition-colors disabled:opacity-50',
                                    isChecked
                                        ? 'border-[#1F5428] bg-[#1F5428] text-white'
                                        : 'border-[#D4C5A9] bg-white hover:border-[#6B4E3D]',
                                )}
                            >
                                {isChecked && <Check className="h-4 w-4" />}
                            </button>

                            <button
                                type="button"
                                onClick={() => onOpen(t)}
                                className="flex min-w-0 flex-1 items-center justify-between gap-4 py-4 pr-6 pl-2 text-left hover:bg-[#F5EFE6]/60"
                            >
                                <div className="flex min-w-0 items-center gap-3">
                                    <CategoryIcon
                                        category={t.category}
                                        className="h-10 w-10 shrink-0 rounded-xl"
                                        iconClassName="h-5 w-5"
                                    />
                                    <div className="min-w-0">
                                        <p
                                            className={cn(
                                                'truncate font-bold',
                                                isChecked
                                                    ? 'text-[#6B4E3D]'
                                                    : 'text-[#3D2817]',
                                            )}
                                        >
                                            {t.name}
                                        </p>
                                        <p className="flex flex-wrap items-center gap-x-1.5 text-xs text-[#8B7355]">
                                            <span>
                                                {formatDate(t.date)} ·{' '}
                                                {t.category?.name}
                                            </span>
                                            {split && (
                                                <span
                                                    className="inline-flex items-center gap-1 text-[#6B4E3D]"
                                                    title="Compra dividida: o valor ao lado é o cheio (o da fatura)"
                                                >
                                                    ·
                                                    <Users className="h-3 w-3" />
                                                    sua parte{' '}
                                                    {formatCurrency(t.amount)}
                                                </span>
                                            )}
                                            {forOthers && (
                                                <span
                                                    className="inline-flex items-center gap-1 text-[#A65D57]"
                                                    title="Compra para outra pessoa: não entra nas suas despesas"
                                                >
                                                    ·
                                                    <HandCoins className="h-3 w-3" />
                                                    para{' '}
                                                    {receivableSplits(t)
                                                        .map(
                                                            (x) =>
                                                                x.contact?.name,
                                                        )
                                                        .filter(Boolean)
                                                        .join(', ')}
                                                </span>
                                            )}
                                        </p>
                                    </div>
                                </div>
                                <span
                                    className={cn(
                                        'shrink-0 text-sm font-bold',
                                        t.type === 'income'
                                            ? 'text-[#1F5428]'
                                            : 'text-[#3D2817]',
                                    )}
                                >
                                    {t.type === 'income' ? '+' : '-'}{' '}
                                    {formatCurrency(chargedAmount(t))}
                                </span>
                            </button>
                        </li>
                    );
                })}
            </ul>
        </div>
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
    account_id?: string | null;
    /** Só o tipo: diz se a original está num cartão (status "na fatura"). */
    account?: { id: string; type: string } | null;
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
    /** "Conferido" na lista da fatura. */
    reconciled_at?: string | null;
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
    Route::post('transactions/{transaction}/reconcile', [TransactionController::class, 'reconcile'])->name('transactions.reconcile');
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

write 'tests/Feature/CreditCardTest.php' <<'PHAMANI_EOF'
<?php

namespace Tests\Feature;

use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\ICategoryService;
use App\Interfaces\Services\ICreditCardService;
use App\Models\Account;
use App\Models\Category;
use App\Models\CreditCardInvoice;
use App\Models\Transaction;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Inertia\Testing\AssertableInertia as Assert;
use Tests\TestCase;

/**
 * Fase 2: cartão de crédito com limite e fatura.
 */
class CreditCardTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    private Account $checking;

    private Category $category;

    protected function setUp(): void
    {
        parent::setUp();

        $this->travelTo('2026-11-18 10:00:00');

        $this->user = User::factory()->create();
        app(IAccountService::class)->createDefaultForUser($this->user->id);
        app(ICategoryService::class)->createDefaultsForUser($this->user->id);
        $this->category = Category::where('user_id', $this->user->id)->where('name', 'Transporte')->firstOrFail();

        $this->checking = Account::create([
            'user_id' => $this->user->id,
            'name' => 'Bradesco',
            'type' => 'checking',
            'balance' => 5000,
        ]);
    }

    private function createCard(int $closingDay = 25, int $dueDay = 5, float $limit = 5000): Account
    {
        $this->actingAs($this->user)
            ->post(route('accounts.store'), [
                'name' => 'Nubank',
                'type' => 'credit',
                'credit_limit' => $limit,
                'closing_day' => $closingDay,
                'due_day' => $dueDay,
                'payment_account_id' => $this->checking->id,
            ])
            ->assertSessionHasNoErrors();

        return Account::where('type', 'credit')->firstOrFail();
    }

    /**
     * @param  array<string, mixed>  $overrides
     */
    private function purchase(Account $card, array $overrides = []): void
    {
        $this->actingAs($this->user)
            ->post(route('transactions.store'), [
                'description' => 'Uber',
                'amount' => 333.75,
                'type' => 'expense',
                'category_id' => $this->category->id,
                'account_id' => $card->id,
                'date' => '2026-11-18',
                'is_installment' => false,
                'installments_count' => 2,
                'installment_start' => 1,
                'amount_mode' => 'total',
                'is_recurring' => false,
                'frequency' => 'monthly',
                ...$overrides,
            ])
            ->assertSessionHasNoErrors();
    }

    private function summary(Account $card): array
    {
        return app(ICreditCardService::class)->summary($card->fresh());
    }

    public function test_card_requires_limit_and_days(): void
    {
        $this->actingAs($this->user)
            ->post(route('accounts.store'), ['name' => 'Nubank', 'type' => 'credit'])
            ->assertSessionHasErrors(['credit_limit', 'closing_day', 'due_day']);
    }

    public function test_purchase_goes_to_invoice_and_does_not_touch_balances(): void
    {
        $card = $this->createCard();
        $this->purchase($card);

        $transaction = Transaction::firstOrFail();
        $invoice = CreditCardInvoice::firstOrFail();

        $this->assertSame($invoice->id, $transaction->invoice_id);
        $this->assertSame('2026-12-01', $invoice->reference_month->toDateString());
        $this->assertSame('2026-11-25', $invoice->closing_date->toDateString());
        $this->assertSame('2026-12-05', $invoice->due_date->toDateString());

        $this->assertEquals(0.0, (float) $card->fresh()->balance);
        $this->assertEquals(5000.0, (float) $this->checking->fresh()->balance);
        $this->assertFalse($transaction->fresh()->balance_applied);

        $summary = $this->summary($card);
        $this->assertEquals(333.75, $summary['used']);
        $this->assertEquals(4666.25, $summary['available']);
        $this->assertEquals(333.75, $summary['current_invoice']['total']);
    }

    public function test_purchase_after_closing_goes_to_next_invoice(): void
    {
        $card = $this->createCard();
        $this->purchase($card, ['date' => '2026-11-26']);

        $invoice = CreditCardInvoice::firstOrFail();
        $this->assertSame('2027-01-01', $invoice->reference_month->toDateString());
        $this->assertSame('2026-12-25', $invoice->closing_date->toDateString());
        $this->assertSame('2027-01-05', $invoice->due_date->toDateString());
    }

    public function test_due_day_after_closing_day_is_in_the_same_month(): void
    {
        $card = $this->createCard(closingDay: 5, dueDay: 15);
        $this->purchase($card);

        $invoice = CreditCardInvoice::firstOrFail();
        $this->assertSame('2026-12-05', $invoice->closing_date->toDateString());
        $this->assertSame('2026-12-15', $invoice->due_date->toDateString());
    }

    public function test_installments_consume_full_limit_and_spread_over_invoices(): void
    {
        $card = $this->createCard();
        $this->purchase($card, ['amount' => 1200, 'is_installment' => true, 'installments_count' => 3]);

        $this->assertSame(
            ['2026-12-01', '2027-01-01', '2027-02-01'],
            CreditCardInvoice::orderBy('reference_month')->get()->map(fn ($i) => $i->reference_month->toDateString())->all(),
        );

        $summary = $this->summary($card);
        $this->assertEquals(1200.0, $summary['used']);
        $this->assertEquals(3800.0, $summary['available']);
        $this->assertEquals(400.0, $summary['current_invoice']['total']);
    }

    public function test_paying_invoice_moves_money_without_counting_as_expense(): void
    {
        $card = $this->createCard();
        $this->purchase($card);
        $invoice = CreditCardInvoice::firstOrFail();

        $this->actingAs($this->user)
            ->post(route('invoices.pay', $invoice), ['account_id' => $this->checking->id, 'date' => '2026-11-18'])
            ->assertSessionHasNoErrors()
            ->assertRedirect();

        $this->assertEquals(4666.25, (float) $this->checking->fresh()->balance);
        $this->assertSame('2026-11-18', $invoice->fresh()->paid_at->toDateString());
        $this->assertEquals(5000.0, $this->summary($card)['available']);

        // A despesa do mês continua sendo a compra (333,75), não compra + pagamento.
        $this->actingAs($this->user)
            ->get(route('dashboard'))
            ->assertInertia(fn (Assert $page) => $page
                ->where('kpis.expense.value', 333.75)
                ->where('kpis.total_balance', 4666.25)
                ->where('kpis.open_invoices', fn ($v) => (float) $v === 0.0));
    }

    public function test_undo_payment_restores_balance(): void
    {
        $card = $this->createCard();
        $this->purchase($card);
        $invoice = CreditCardInvoice::firstOrFail();

        $this->actingAs($this->user)
            ->post(route('invoices.pay', $invoice), ['account_id' => $this->checking->id, 'date' => '2026-11-18']);

        $this->actingAs($this->user)
            ->delete(route('invoices.undo', $invoice))
            ->assertRedirect();

        $this->assertEquals(5000.0, (float) $this->checking->fresh()->balance);
        $this->assertNull($invoice->fresh()->paid_at);
    }

    public function test_cannot_pay_with_a_card_or_in_the_future(): void
    {
        $card = $this->createCard();
        $this->purchase($card);
        $invoice = CreditCardInvoice::firstOrFail();

        $this->actingAs($this->user)
            ->post(route('invoices.pay', $invoice), ['account_id' => $card->id, 'date' => '2026-11-18'])
            ->assertSessionHasErrors('account_id');

        $this->actingAs($this->user)
            ->post(route('invoices.pay', $invoice), ['account_id' => $this->checking->id, 'date' => '2026-12-01'])
            ->assertSessionHasErrors('date');

        $this->assertNull($invoice->fresh()->paid_at);
    }

    public function test_other_users_cannot_see_or_pay_the_card(): void
    {
        $card = $this->createCard();
        $this->purchase($card);
        $invoice = CreditCardInvoice::firstOrFail();
        $intruder = User::factory()->create();

        $this->actingAs($intruder)->get(route('cards.show', $card))->assertNotFound();
        $this->actingAs($intruder)
            ->post(route('invoices.pay', $invoice), ['account_id' => $this->checking->id, 'date' => '2026-11-18'])
            ->assertSessionHasErrors('account_id');
    }

    public function test_dashboard_balance_excludes_cards_and_shows_open_invoices(): void
    {
        $card = $this->createCard();
        $this->purchase($card);
        $this->purchase($card, ['amount' => 1200, 'is_installment' => true, 'installments_count' => 3]);

        $this->actingAs($this->user)
            ->get(route('dashboard'))
            ->assertInertia(fn (Assert $page) => $page
                ->where('kpis.total_balance', fn ($v) => (float) $v === 5000.0)
                // Só a fatura atual (dez): 333,75 + 1ª parcela 400. Parcelas futuras ficam de fora.
                ->where('kpis.open_invoices', 733.75));
    }

    public function test_changing_closing_day_reassigns_unpaid_purchases(): void
    {
        $card = $this->createCard();
        $this->purchase($card, ['date' => '2026-11-10']);

        $this->actingAs($this->user)
            ->put(route('accounts.update', $card), [
                'name' => 'Nubank',
                'credit_limit' => 5000,
                'closing_day' => 5,
                'due_day' => 12,
                'payment_account_id' => $this->checking->id,
            ])
            ->assertSessionHasNoErrors();

        $invoice = Transaction::firstOrFail()->invoice;

        // 10/11 é depois do fechamento (5) → fecha 05/12, vence 12/12.
        $this->assertSame('2026-12-05', $invoice->closing_date->toDateString());
        $this->assertSame('2026-12-12', $invoice->due_date->toDateString());
        $this->assertSame(1, CreditCardInvoice::count());
    }

    public function test_moving_purchase_from_card_to_checking_hits_balance(): void
    {
        $card = $this->createCard();
        $this->purchase($card);
        $transaction = Transaction::firstOrFail();

        $this->actingAs($this->user)
            ->put(route('transactions.update', $transaction), [
                'description' => 'Uber',
                'amount' => 333.75,
                'type' => 'expense',
                'category_id' => $this->category->id,
                'account_id' => $this->checking->id,
                'date' => '2026-11-18',
            ])
            ->assertSessionHasNoErrors();

        $this->assertNull($transaction->fresh()->invoice_id);
        $this->assertEquals(4666.25, (float) $this->checking->fresh()->balance);
        $this->assertEquals(0.0, $this->summary($card)['used']);
    }

    public function test_card_page_renders_selected_invoice(): void
    {
        $card = $this->createCard();
        $this->purchase($card);

        $this->actingAs($this->user)
            ->get(route('cards.show', $card))
            ->assertOk()
            ->assertInertia(fn (Assert $page) => $page
                ->component('cards/show')
                ->has('invoices', 1)
                ->where('selectedInvoice.total', 333.75)
                ->has('transactions', 1));
    }

    public function test_card_purchases_stay_in_the_invoice_until_it_is_paid(): void
    {
        $card = $this->createCard();
        $this->purchase($card, ['date' => '2026-11-02']);
        $transaction = Transaction::firstOrFail();
        $invoice = CreditCardInvoice::firstOrFail();

        // Não nasce paga e não fica "atrasada".
        $this->assertNull($transaction->paid_at);
        $this->actingAs($this->user)
            ->get(route('transactions.index', ['status' => 'overdue']))
            ->assertInertia(fn (Assert $page) => $page->has('transactions.data', 0));
        $this->actingAs($this->user)
            ->get(route('transactions.index', ['status' => 'pending']))
            ->assertInertia(fn (Assert $page) => $page->has('transactions.data', 1));

        $this->actingAs($this->user)
            ->post(route('invoices.pay', $invoice), ['account_id' => $this->checking->id, 'date' => '2026-11-18']);
        $this->assertSame('2026-11-18', $transaction->fresh()->paid_at?->toDateString());

        $this->actingAs($this->user)->delete(route('invoices.undo', $invoice));
        $this->assertNull($transaction->fresh()->paid_at);
    }

    public function test_card_purchase_cannot_be_marked_paid_by_hand(): void
    {
        $card = $this->createCard();
        $this->purchase($card);
        $transaction = Transaction::firstOrFail();

        $this->actingAs($this->user)
            ->post(route('transactions.pay', $transaction))
            ->assertSessionHasErrors('paid');

        $this->assertNull($transaction->fresh()->paid_at);
    }

    public function test_purchase_moved_into_a_paid_invoice_is_paid(): void
    {
        $card = $this->createCard();
        $this->purchase($card, ['description' => 'Primeira']);
        $invoice = CreditCardInvoice::firstOrFail();
        $this->actingAs($this->user)
            ->post(route('invoices.pay', $invoice), ['account_id' => $this->checking->id, 'date' => '2026-11-18']);

        $this->purchase($card, ['description' => 'Segunda', 'date' => '2026-11-10']);

        $this->assertSame('2026-11-18', Transaction::where('name', 'Segunda')->firstOrFail()->paid_at?->toDateString());
    }

    public function test_purchases_can_be_reconciled_on_the_invoice(): void
    {
        $card = $this->createCard();
        $this->purchase($card);
        $transaction = Transaction::firstOrFail();

        $this->actingAs($this->user)->post(route('transactions.reconcile', $transaction))->assertRedirect();
        $this->assertNotNull($transaction->fresh()->reconciled_at);

        $this->actingAs($this->user)->post(route('transactions.reconcile', $transaction));
        $this->assertNull($transaction->fresh()->reconciled_at);

        $this->actingAs(User::factory()->create())
            ->post(route('transactions.reconcile', $transaction))
            ->assertNotFound();
    }
}
PHAMANI_EOF

write 'tests/Feature/PaymentStatusTest.php' <<'PHAMANI_EOF'
<?php

namespace Tests\Feature;

use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\ICategoryService;
use App\Models\Account;
use App\Models\Category;
use App\Models\Contact;
use App\Models\Share;
use App\Models\Transaction;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Inertia\Testing\AssertableInertia as Assert;
use Tests\TestCase;

/**
 * Status de pagamento: pago / pendente / atrasado, saldo só quando pago, débito automático
 * e "quem marca é quem pagou".
 */
class PaymentStatusTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    private Account $account;

    private Category $category;

    protected function setUp(): void
    {
        parent::setUp();

        $this->travelTo('2026-11-18 10:00:00');

        $this->user = User::factory()->create(['name' => 'Rhaniel']);
        app(IAccountService::class)->createDefaultForUser($this->user->id);
        app(ICategoryService::class)->createDefaultsForUser($this->user->id);
        $this->account = Account::create(['user_id' => $this->user->id, 'name' => 'Bradesco', 'type' => 'checking', 'balance' => 1000]);
        $this->category = Category::where('user_id', $this->user->id)->where('name', 'Outros')->firstOrFail();
    }

    /**
     * @param  array<string, mixed>  $overrides
     */
    private function store(array $overrides = [], ?User $as = null): void
    {
        $this->actingAs($as ?? $this->user)
            ->post(route('transactions.store'), [
                'description' => 'Boleto',
                'amount' => 100,
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
                ...$overrides,
            ])
            ->assertSessionHasNoErrors();
    }

    private function balance(): float
    {
        return (float) $this->account->fresh()->balance;
    }

    public function test_initial_status_follows_the_date_and_cards_wait_for_the_invoice(): void
    {
        $this->store(['description' => 'Hoje']);
        $this->store(['description' => 'Futuro', 'date' => '2026-12-10']);

        $card = Account::create([
            'user_id' => $this->user->id, 'name' => 'Nubank', 'type' => 'credit', 'balance' => 0,
            'credit_limit' => 1000, 'closing_day' => 25, 'due_day' => 5,
        ]);
        $this->store(['description' => 'Cartão', 'account_id' => $card->id, 'date' => '2026-12-10']);

        $this->assertSame('2026-11-18', Transaction::where('name', 'Hoje')->firstOrFail()->paid_at->toDateString());
        $this->assertNull(Transaction::where('name', 'Futuro')->firstOrFail()->paid_at);
        // No cartão: "na fatura" até a fatura ser paga.
        $this->assertNull(Transaction::where('name', 'Cartão')->firstOrFail()->paid_at);
        $this->assertEquals(900.0, $this->balance()); // só "Hoje"
    }

    public function test_overdue_does_not_touch_balance_until_marked_paid(): void
    {
        $this->store(['date' => '2026-11-20']);
        $t = Transaction::firstOrFail();

        $this->travelTo('2026-11-25 10:00:00');
        $this->artisan('phamani:process-due')->assertSuccessful();

        $this->assertNull($t->fresh()->paid_at);
        $this->assertEquals(1000.0, $this->balance());

        $this->actingAs($this->user)
            ->get(route('dashboard'))
            ->assertInertia(fn (Assert $page) => $page->where('kpis.overdue.count', 1));

        $this->actingAs($this->user)
            ->get(route('transactions.index', ['status' => 'overdue']))
            ->assertInertia(fn (Assert $page) => $page
                ->has('transactions.data', 1)
                ->where('summary.overdue_count', 1));

        $this->actingAs($this->user)->post(route('transactions.pay', $t))->assertRedirect();
        $this->assertSame('2026-11-25', $t->fresh()->paid_at->toDateString());
        $this->assertEquals(900.0, $this->balance());

        $this->actingAs($this->user)->delete(route('transactions.unpay', $t))->assertRedirect();
        $this->assertNull($t->fresh()->paid_at);
        $this->assertEquals(1000.0, $this->balance());
    }

    public function test_recurring_without_auto_pay_waits_for_confirmation(): void
    {
        $this->store(['is_recurring' => true]);

        $this->travelTo('2026-12-18 10:00:00');
        $this->artisan('phamani:process-due')->assertSuccessful();

        $next = Transaction::orderByDesc('date')->firstOrFail();
        $this->assertSame('2026-12-18', $next->date->toDateString());
        $this->assertNull($next->paid_at);
        $this->assertEquals(900.0, $this->balance()); // só a 1ª (hoje)
    }

    public function test_auto_pay_marks_due_parcels_as_paid(): void
    {
        $this->store(['is_installment' => true, 'installments_count' => 3, 'auto_pay' => true]);

        $this->travelTo('2026-12-18 01:00:00');
        $this->artisan('phamani:process-due')->assertSuccessful();

        $parcels = Transaction::orderBy('installment_number')->get();
        $this->assertSame('2026-12-18', $parcels[1]->paid_at->toDateString());
        $this->assertNull($parcels[2]->paid_at);
        $this->assertEquals(800.0, $this->balance());
    }

    public function test_only_the_payer_marks_and_it_applies_to_everyone(): void
    {
        $mozi = User::factory()->create(['name' => 'Mozi']);
        app(IAccountService::class)->createDefaultForUser($mozi->id);
        app(ICategoryService::class)->createDefaultsForUser($mozi->id);
        $moziAccount = Account::create(['user_id' => $mozi->id, 'name' => 'Nubank', 'type' => 'checking', 'balance' => 1000]);

        $contact = Contact::create(['user_id' => $this->user->id, 'name' => 'Mozi', 'linked_user_id' => $mozi->id]);
        Contact::create(['user_id' => $mozi->id, 'name' => 'Rhaniel', 'linked_user_id' => $this->user->id]);

        // Boleto de amanhã, dividido, pago pela Mozi.
        $this->store([
            'date' => '2026-11-19',
            'account_id' => null,
            'split' => [
                'mode' => 'equal',
                'participants' => [['contact_id' => null], ['contact_id' => $contact->id]],
                'paid_by_contact_id' => $contact->id,
            ],
        ]);
        $source = Transaction::where('user_id', $this->user->id)->firstOrFail();

        $this->actingAs($mozi)
            ->post(route('shares.accept', Share::firstOrFail()), [
                'category_id' => Category::where('user_id', $mozi->id)->where('name', 'Outros')->value('id'),
                'account_id' => $moziAccount->id,
            ])
            ->assertSessionHasNoErrors();
        $mirror = Transaction::where('user_id', $mozi->id)->firstOrFail();

        // Eu não pago esse boleto: não posso marcar.
        $this->actingAs($this->user)
            ->post(route('transactions.pay', $source))
            ->assertSessionHasErrors('paid');
        $this->assertNull($source->fresh()->paid_at);

        // Ela marca na cópia dela: vale para as duas, e o total sai da conta dela.
        $this->actingAs($mozi)->post(route('transactions.pay', $mirror))->assertSessionHasNoErrors();

        $this->assertNotNull($source->fresh()->paid_at);
        $this->assertNotNull($mirror->fresh()->paid_at);
        $this->assertEquals(900.0, (float) $moziAccount->fresh()->balance);
        $this->assertEquals(1000.0, $this->balance());
    }

    public function test_turning_on_auto_pay_settles_overdue_parcels(): void
    {
        $this->store(['is_installment' => true, 'installments_count' => 3]);
        $installment = \App\Models\Installment::firstOrFail();

        $this->travelTo('2026-12-20 10:00:00');
        $this->artisan('phamani:process-due')->assertSuccessful();
        $this->assertEquals(900.0, $this->balance()); // 2ª parcela atrasada

        $this->actingAs($this->user)
            ->post(route('installments.auto-pay', $installment), ['enabled' => true])
            ->assertRedirect();

        $this->assertTrue($installment->fresh()->auto_pay);
        $this->assertSame('2026-12-18', Transaction::where('installment_number', 2)->firstOrFail()->paid_at->toDateString());
        $this->assertEquals(800.0, $this->balance());

        $this->actingAs(User::factory()->create())
            ->post(route('installments.auto-pay', $installment), ['enabled' => false])
            ->assertNotFound();
    }

    public function test_moving_a_paid_transaction_to_the_future_makes_it_pending_and_restores_the_balance(): void
    {
        $this->store(['description' => 'Telefone', 'amount' => 625]);
        $transaction = Transaction::where('description', 'Telefone')->firstOrFail();

        $this->assertNotNull($transaction->paid_at);
        $this->assertEqualsWithDelta(375.0, $this->balance(), 0.001);

        $this->actingAs($this->user)
            ->put(route('transactions.update', $transaction), [
                'description' => 'Telefone',
                'amount' => 625,
                'type' => 'expense',
                'category_id' => $this->category->id,
                'account_id' => $this->account->id,
                'date' => '2026-12-04',
            ])
            ->assertSessionHasNoErrors();

        $transaction->refresh();
        $this->assertNull($transaction->paid_at);
        $this->assertFalse((bool) $transaction->balance_applied);
        $this->assertEqualsWithDelta(1000.0, $this->balance(), 0.001);
    }

    public function test_editing_without_changing_the_date_keeps_the_status(): void
    {
        $this->store(['description' => 'Futuro', 'date' => '2026-12-10']);
        $transaction = Transaction::where('description', 'Futuro')->firstOrFail();

        $this->actingAs($this->user)->post(route('transactions.pay', $transaction));
        $this->assertNotNull($transaction->fresh()->paid_at);

        $this->actingAs($this->user)
            ->put(route('transactions.update', $transaction), [
                'description' => 'Futuro (editado)',
                'amount' => 100,
                'type' => 'expense',
                'category_id' => $this->category->id,
                'account_id' => $this->account->id,
                'date' => '2026-12-10',
            ])
            ->assertSessionHasNoErrors();

        $this->assertNotNull($transaction->fresh()->paid_at);
        $this->assertEqualsWithDelta(900.0, $this->balance(), 0.001);
    }
}
PHAMANI_EOF

cat <<'MSG'

Pronto. Local:
  php artisan migrate
  php artisan wayfinder:generate --with-form
  php artisan test
Depois: git add -A && git commit -m "Cartão segue a fatura, fatura com valor cheio e conferido" && git push
MSG
