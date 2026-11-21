<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Pagamento do acerto entre dois usuários: quem deve informa ("paguei") e quem recebe confirma.
 *
 * @property string $id
 * @property string $creditor_user_id
 * @property string $debtor_user_id
 * @property string $contact_id
 * @property string $amount
 * @property \Carbon\CarbonInterface $paid_on
 * @property string|null $from_account_id
 * @property string|null $to_account_id
 * @property string $status pending|confirmed|rejected
 * @property \Carbon\CarbonInterface|null $confirmed_at
 */
class Settlement extends BaseModel
{
    protected $fillable = [
        'creditor_user_id',
        'debtor_user_id',
        'contact_id',
        'amount',
        'paid_on',
        'from_account_id',
        'to_account_id',
        'status',
        'confirmed_at',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
        'paid_on' => 'date:Y-m-d',
        'confirmed_at' => 'datetime',
    ];

    /** @return HasMany<TransactionSplit, $this> */
    public function splits(): HasMany
    {
        return $this->hasMany(TransactionSplit::class);
    }

    /** @return BelongsTo<User, $this> */
    public function creditor(): BelongsTo
    {
        return $this->belongsTo(User::class, 'creditor_user_id');
    }

    /** @return BelongsTo<User, $this> */
    public function debtor(): BelongsTo
    {
        return $this->belongsTo(User::class, 'debtor_user_id');
    }

    /** @return BelongsTo<Account, $this> */
    public function fromAccount(): BelongsTo
    {
        return $this->belongsTo(Account::class, 'from_account_id');
    }
}
