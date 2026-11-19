<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * @property string $id
 * @property string $user_id
 * @property string $name
 * @property string $type
 * @property string $balance
 * @property string|null $credit_limit
 * @property int|null $closing_day
 * @property int|null $due_day
 * @property string|null $payment_account_id
 */
class Account extends BaseModel
{
    protected $fillable = [
        'user_id',
        'name',
        'type',
        'balance',
        'credit_limit',
        'closing_day',
        'due_day',
        'payment_account_id',
    ];

    protected $casts = [
        'balance' => 'decimal:2',
        'credit_limit' => 'decimal:2',
        'closing_day' => 'integer',
        'due_day' => 'integer',
    ];

    /**
     * Cartão de crédito: compras não mexem em saldo, vão para a fatura.
     */
    public function isCreditCard(): bool
    {
        return $this->type === 'credit';
    }

    /**
     * Cartão com fechamento e vencimento configurados (necessário para montar faturas).
     */
    public function isConfiguredCard(): bool
    {
        return $this->isCreditCard() && $this->closing_day !== null && $this->due_day !== null;
    }

    /** @return HasMany<CreditCardInvoice, $this> */
    public function invoices(): HasMany
    {
        return $this->hasMany(CreditCardInvoice::class);
    }

    /** @return BelongsTo<Account, $this> */
    public function paymentAccount(): BelongsTo
    {
        return $this->belongsTo(Account::class, 'payment_account_id');
    }

    /** @return BelongsTo<User, $this> */
    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    /** @return HasMany<Transaction, $this> */
    public function transactions(): HasMany
    {
        return $this->hasMany(Transaction::class);
    }

    /** @return HasMany<RecurringTransaction, $this> */
    public function recurringTransactions(): HasMany
    {
        return $this->hasMany(RecurringTransaction::class);
    }
}
