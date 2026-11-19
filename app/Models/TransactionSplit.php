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
 */
class TransactionSplit extends BaseModel
{
    protected $fillable = [
        'transaction_id',
        'contact_id',
        'amount',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
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
}
