<?php

namespace App\Interfaces\Repositories;

use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Support\Collection;

interface ITransactionRepository extends ICoreRepository
{
    public function getLatestForUser(string $userId, int $limit = 5): Collection;

    public function deleteByInstallment(string $installmentId): void;

    /**
     * @param  array{account_id?: ?string, category_id?: ?string, type?: ?string, month?: ?string}  $filters
     */
    public function paginateForUser(string $userId, array $filters = [], int $perPage = 20): LengthAwarePaginator;
}
