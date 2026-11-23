<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Carbon;

/**
 * @property string $id
 * @property string $user_id
 * @property string $account_id
 * @property string $bank
 * @property string $status  queued | processing | ready | done | failed
 * @property int $progress  0–100
 * @property string|null $stage
 * @property string|null $error
 * @property Carbon|null $statement_date
 * @property list<string>|null $files
 * @property array<string, mixed>|null $result
 * @property int $created_count
 * @property Carbon|null $finished_at
 */
class StatementImport extends BaseModel
{
    protected $fillable = [
        'user_id',
        'account_id',
        'bank',
        'status',
        'progress',
        'stage',
        'error',
        'statement_date',
        'files',
        'result',
        'created_count',
        'finished_at',
    ];

    protected $casts = [
        'progress' => 'integer',
        'statement_date' => 'date:Y-m-d',
        'files' => 'array',
        'result' => 'array',
        'created_count' => 'integer',
        'finished_at' => 'datetime',
    ];

    /** @return BelongsTo<Account, $this> */
    public function account(): BelongsTo
    {
        return $this->belongsTo(Account::class);
    }

    public function isRunning(): bool
    {
        return in_array($this->status, ['queued', 'processing'], true);
    }
}
