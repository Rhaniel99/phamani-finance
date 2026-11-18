<?php

namespace App\Interfaces\Services;

use App\DTOs\Category\StoreCategoryData;
use App\Models\Category;
use Illuminate\Support\Collection;

interface ICategoryService
{
    public function listForUser(string $userId): Collection;

    public function create(string $userId, StoreCategoryData $dto): Category;

    /**
     * Cria as categorias padrão de um usuário recém-cadastrado (idempotente).
     */
    public function createDefaultsForUser(string $userId): void;
}
