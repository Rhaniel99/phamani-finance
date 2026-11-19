<?php

namespace App\Models;

use App\Enums\RecurringFrequency;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Support\Carbon;

/**
 * @property string $id
 * @property string $user_id
 * @property string $account_id
 * @property string $category_id
 * @property string $name
 * @property string $amount
 * @property string $type
 * @property RecurringFrequency $frequency
 * @property Carbon|null $anchor_date
 * @property Carbon $next_run
 * @property Carbon|null $end_date
 */
class RecurringTransaction extends BaseModel
{
    protected $fillable = [
        'user_id',
        'account_id',
        'category_id',
        'name',
        'amount',
        'type',
        'frequency',
        'anchor_date',
        'next_run',
        'end_date',
        'auto_pay',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
        'auto_pay' => 'boolean',
        'frequency' => RecurringFrequency::class,
        'anchor_date' => 'date:Y-m-d',
        'next_run' => 'date:Y-m-d',
        'end_date' => 'date:Y-m-d',
    ];

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

    /** @return HasMany<Transaction, $this> */
    public function generatedTransactions(): HasMany
    {
        return $this->hasMany(Transaction::class, 'recurring_id');
    }
}
