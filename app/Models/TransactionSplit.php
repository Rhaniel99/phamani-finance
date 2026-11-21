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
 * @property bool $tracked
 * @property string|null $settlement_id
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
        'tracked',
        'settlement_id',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
        'reimbursed_at' => 'date:Y-m-d',
        'reimbursed_amount' => 'decimal:2',
        'tracked' => 'boolean',
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

    /** @return BelongsTo<Settlement, $this> */
    public function settlement(): BelongsTo
    {
        return $this->belongsTo(Settlement::class);
    }
}
