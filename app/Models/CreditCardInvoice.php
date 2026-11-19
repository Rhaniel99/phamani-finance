<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Support\Carbon;

/**
 * Fatura de um cartão. Identificada pelo mês de vencimento (reference_month = dia 1).
 *
 * Status (calculado): paga (paid_at), fechada (passou do fechamento) ou aberta.
 *
 * @property string $id
 * @property string $user_id
 * @property string $account_id
 * @property Carbon $reference_month
 * @property Carbon $closing_date
 * @property Carbon $due_date
 * @property Carbon|null $paid_at
 * @property string|null $paid_amount
 * @property string|null $paid_from_account_id
 */
class CreditCardInvoice extends BaseModel
{
    protected $fillable = [
        'user_id',
        'account_id',
        'reference_month',
        'closing_date',
        'due_date',
        'paid_at',
        'paid_amount',
        'paid_from_account_id',
    ];

    protected $casts = [
        'reference_month' => 'date:Y-m-d',
        'closing_date' => 'date:Y-m-d',
        'due_date' => 'date:Y-m-d',
        'paid_at' => 'date:Y-m-d',
        'paid_amount' => 'decimal:2',
    ];

    public function status(): string
    {
        if ($this->paid_at !== null) {
            return 'paid';
        }

        return $this->closing_date->toDateString() < now()->toDateString() ? 'closed' : 'open';
    }

    /** @return BelongsTo<Account, $this> */
    public function account(): BelongsTo
    {
        return $this->belongsTo(Account::class);
    }

    /** @return BelongsTo<Account, $this> */
    public function paidFromAccount(): BelongsTo
    {
        return $this->belongsTo(Account::class, 'paid_from_account_id');
    }

    /** @return HasMany<Transaction, $this> */
    public function transactions(): HasMany
    {
        return $this->hasMany(Transaction::class, 'invoice_id');
    }
}
