<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Support\Carbon;

/**
 * @property string $id
 * @property string $user_id
 * @property string $name
 * @property string $total_amount
 * @property string $installment_amount
 * @property int $installments
 * @property Carbon $start_date
 * @property Carbon $end_date
 * @property string $status
 */
class Installment extends BaseModel
{
    protected $fillable = [
        'user_id',
        'name',
        'total_amount',
        'installment_amount',
        'installments',
        'start_date',
        'end_date',
        'status',
    ];

    protected $casts = [
        'total_amount' => 'decimal:2',
        'installment_amount' => 'decimal:2',
        'installments' => 'integer',
        'start_date' => 'date:Y-m-d',
        'end_date' => 'date:Y-m-d',
    ];

    /** @return HasMany<Transaction, $this> */
    public function transactions(): HasMany
    {
        return $this->hasMany(Transaction::class)->orderBy('installment_number');
    }
}
