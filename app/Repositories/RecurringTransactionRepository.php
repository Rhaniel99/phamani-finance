<?php

namespace App\Repositories;

use App\Interfaces\Repositories\IRecurringTransactionRepository;
use App\Models\RecurringTransaction;
use App\Repositories\Base\CoreRepository;

class RecurringTransactionRepository extends CoreRepository implements IRecurringTransactionRepository
{
    public function __construct(RecurringTransaction $model)
    {
        parent::__construct($model);
    }
}
