<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Relations\BelongsToMany;

/**
 * Tag livre de uma transação (pessoal: não vai junto nas divisões compartilhadas).
 * slug = nome normalizado, usado para não duplicar "iFood"/"ifood".
 *
 * @property string $id
 * @property string $user_id
 * @property string $name
 * @property string|null $slug
 * @property string|null $color
 */
class Tag extends BaseModel
{
    protected $fillable = [
        'user_id',
        'name',
        'slug',
        'color',
    ];

    protected $hidden = ['pivot'];

    /** @return BelongsToMany<Transaction, $this> */
    public function transactions(): BelongsToMany
    {
        return $this->belongsToMany(Transaction::class, 'transaction_tags');
    }
}
