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

    /**
     * Data em que o dinheiro sai: compra no cartão = dia em que a fatura foi paga ou, se ainda não foi,
     * o vencimento (também para a cópia de quem dividiu); o resto = a própria data.
     * Expressão SQL (SQLite e Postgres).
     */
    public static function paymentDateSql(): string
    {
        return 'date(COALESCE('
            .'(select COALESCE(ci.paid_at, ci.due_date) from credit_card_invoices ci where ci.id = transactions.invoice_id), '
            .'(select COALESCE(si.paid_at, si.due_date) from transactions s inner join credit_card_invoices si on si.id = s.invoice_id where s.id = transactions.mirrored_from_id), '
            .'transactions.date))';
    }

    /**
     * Pela data em que o dinheiro sai (ver paymentDateSql), entre $start e $end (Y-m-d).
     *
     * @param  Builder<self>  $query
     */
    public function scopePaidBetween(Builder $query, string $start, string $end): void
    {
        $query->whereRaw(self::paymentDateSql().' between ? and ?', [$start, $end]);
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
