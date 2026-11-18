<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Support\Carbon;

/**
 * @property string $id
 * @property string $user_id
 * @property string $account_id
 * @property string $category_id
 * @property string|null $recurring_id
 * @property string|null $installment_id
 * @property int|null $installment_number
 * @property string $name
 * @property string|null $description
 * @property string $type
 * @property string $amount
 * @property Carbon $date
 */
class Transaction extends BaseModel
{
    protected $fillable = [
        'user_id',
        'account_id',
        'category_id',
        'recurring_id',
        'installment_id',
        'installment_number',
        'name',
        'description',
        'type',
        'amount',
        'date',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
        'installment_number' => 'integer',
        'date' => 'date:Y-m-d',
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

    /** @return BelongsTo<Installment, $this> */
    public function installment(): BelongsTo
    {
        return $this->belongsTo(Installment::class);
    }

    /** @return BelongsTo<RecurringTransaction, $this> */
    public function recurring(): BelongsTo
    {
        return $this->belongsTo(RecurringTransaction::class, 'recurring_id');
    }

    /** @return BelongsToMany<Tag, $this> */
    public function tags(): BelongsToMany
    {
        return $this->belongsToMany(Tag::class, 'transaction_tags');
    }
}
