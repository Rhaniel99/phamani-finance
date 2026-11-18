<?php

namespace App\Repositories;

use App\Interfaces\Repositories\IAccountRepository;
use App\Models\Account;
use App\Repositories\Base\CoreRepository;

class AccountRepository extends CoreRepository implements IAccountRepository
{
    public function __construct(Account $model)
    {
        parent::__construct($model);
    }

    public function applyTransaction(string $accountId, float $amount, string $type): void
    {
        $delta = $type === 'income' ? $amount : -$amount;

        // increment() gera um UPDATE atômico (balance = balance + ?), evitando condição de corrida.
        $this->query()->whereKey($accountId)->increment('balance', $delta);
    }

    public function revertTransaction(string $accountId, float $amount, string $type): void
    {
        $this->applyTransaction($accountId, -$amount, $type);
    }
}
