<?php

namespace App\Repositories;

use App\Interfaces\Repositories\IInstallmentRepository;
use App\Models\Installment;
use App\Repositories\Base\CoreRepository;

class InstallmentRepository extends CoreRepository implements IInstallmentRepository
{
    public function __construct(Installment $model)
    {
        parent::__construct($model);
    }
}
