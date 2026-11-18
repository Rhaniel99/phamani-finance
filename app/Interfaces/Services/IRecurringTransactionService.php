<?php

namespace App\Interfaces\Services;

use App\DTOs\Transaction\StoreTransactionData;
use App\Models\RecurringTransaction;

interface IRecurringTransactionService
{
    public function createRecurringTransaction(string $userId, StoreTransactionData $dto): RecurringTransaction;
}
