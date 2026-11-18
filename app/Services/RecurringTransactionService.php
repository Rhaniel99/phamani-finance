<?php

namespace App\Services;

use App\DTOs\Transaction\StoreTransactionData;
use App\Interfaces\Repositories\IAccountRepository;
use App\Interfaces\Repositories\IRecurringTransactionRepository;
use App\Interfaces\Repositories\ITransactionRepository;
use App\Interfaces\Services\IRecurringTransactionService;
use App\Models\RecurringTransaction;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;

class RecurringTransactionService implements IRecurringTransactionService
{
    public function __construct(
        protected IRecurringTransactionRepository $recurrings,
        protected ITransactionRepository $transactions,
        protected IAccountRepository $accounts,
    ) {}

    public function createRecurringTransaction(string $userId, StoreTransactionData $dto): RecurringTransaction
    {
        return DB::transaction(function () use ($userId, $dto) {
            $frequency = $dto->frequency;
            $date = CarbonImmutable::parse($dto->date);

            /** @var RecurringTransaction $recurring */
            $recurring = $this->recurrings->create([
                'user_id' => $userId,
                'account_id' => $dto->account_id,
                'category_id' => $dto->category_id,
                'name' => $dto->description,
                'amount' => $dto->amount,
                'type' => $dto->type,
                'frequency' => $frequency,
                'next_run' => $frequency->nextAfter($date)->toDateString(),
            ]);

            // Primeira ocorrência
            $this->transactions->create([
                'user_id' => $userId,
                'account_id' => $dto->account_id,
                'category_id' => $dto->category_id,
                'recurring_id' => $recurring->id,
                'name' => $dto->description,
                'description' => $dto->description,
                'type' => $dto->type,
                'amount' => $dto->amount,
                'date' => $date->toDateString(),
            ]);

            $this->accounts->applyTransaction($dto->account_id, $dto->amount, $dto->type);

            return $recurring;
        });
    }
}
