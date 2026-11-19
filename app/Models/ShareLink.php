<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Uma transação da série compartilhada × a cópia no sistema de quem aceitou.
 *
 * @property string $id
 * @property string $share_id
 * @property string $source_transaction_id
 * @property string|null $mirror_transaction_id
 */
class ShareLink extends BaseModel
{
    protected $fillable = [
        'share_id',
        'source_transaction_id',
        'mirror_transaction_id',
    ];

    /** @return BelongsTo<Share, $this> */
    public function share(): BelongsTo
    {
        return $this->belongsTo(Share::class);
    }

    /** @return BelongsTo<Transaction, $this> */
    public function source(): BelongsTo
    {
        return $this->belongsTo(Transaction::class, 'source_transaction_id');
    }

    /** @return BelongsTo<Transaction, $this> */
    public function mirror(): BelongsTo
    {
        return $this->belongsTo(Transaction::class, 'mirror_transaction_id');
    }
}
