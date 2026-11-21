<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Pessoa com quem o usuário divide contas. Pode não usar o sistema (ex.: a sogra).
 *
 * @property string $id
 * @property string $user_id
 * @property string $name
 * @property string|null $linked_user_id
 * @property bool $track_debts Cobrar essa pessoa no acerto do mês.
 */
class Contact extends BaseModel
{
    protected $fillable = [
        'user_id',
        'name',
        'linked_user_id',
        'track_debts',
    ];

    protected $casts = [
        'track_debts' => 'boolean',
    ];

    /** @return BelongsTo<User, $this> */
    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    /** @return BelongsTo<User, $this> */
    public function linkedUser(): BelongsTo
    {
        return $this->belongsTo(User::class, 'linked_user_id');
    }

    /** @return HasMany<TransactionSplit, $this> */
    public function splits(): HasMany
    {
        return $this->hasMany(TransactionSplit::class);
    }
}
