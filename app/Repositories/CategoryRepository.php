<?php

namespace App\Repositories;

use App\Interfaces\Repositories\ICategoryRepository;
use App\Models\Category;
use App\Repositories\Base\CoreRepository;

class CategoryRepository extends CoreRepository implements ICategoryRepository
{
    public function __construct(Category $model)
    {
        parent::__construct($model);
    }
}
