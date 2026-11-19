<?php

namespace App\Repositories;

use App\Interfaces\Repositories\IContactRepository;
use App\Models\Contact;
use App\Repositories\Base\CoreRepository;

class ContactRepository extends CoreRepository implements IContactRepository
{
    public function __construct(Contact $model)
    {
        parent::__construct($model);
    }
}
