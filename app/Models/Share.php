<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Support\Carbon;

/**
 * Compartilhamento de uma série (transação avulsa, parcelamento ou recorrência) com um usuário.
 *
 * @property string $id
 * @property string $owner_user_id
 * @property string $recipient_user_id
 * @property string $owner_contact_id
 * @property string $source_type transaction|installment|recurring
 * @property string $source_id
 * @property string $status pending|accepted|declined|left|removed
 * @property string|null $category_id
 * @property string|null $account_id
 * @property Carbon|null $responded_at
 */
class Share extends BaseModel
{
    protected $fillable = [
        'owner_user_id',
        'recipient_user_id',
        'owner_contact_id',
        'source_type',
        'source_id',
        'status',
        'category_id',
        'account_id',
        'responded_at',
    ];

    protected $casts = [
        'responded_at' => 'datetime',
    ];

    /** @return BelongsTo<User, $this> */
    public function owner(): BelongsTo
    {
        return $this->belongsTo(User::class, 'owner_user_id');
    }

    /** @return BelongsTo<User, $this> */
    public function recipient(): BelongsTo
    {
        return $this->belongsTo(User::class, 'recipient_user_id');
    }

    /** @return BelongsTo<Contact, $this> */
    public function ownerContact(): BelongsTo
    {
        return $this->belongsTo(Contact::class, 'owner_contact_id');
    }

    /** @return HasMany<ShareLink, $this> */
    public function links(): HasMany
    {
        return $this->hasMany(ShareLink::class);
    }
}
