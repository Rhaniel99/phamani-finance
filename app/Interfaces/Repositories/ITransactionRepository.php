<?php

namespace App\Interfaces\Repositories;

use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Support\Collection;

interface ITransactionRepository extends ICoreRepository
{
    public function getLatestForUser(string $userId, int $limit = 5): Collection;

    public function deleteByInstallment(string $installmentId): void;

    /**
     * @param  array{account_id?: ?string, category_id?: ?string, type?: ?string, month?: ?string, search?: ?string, kind?: ?string}  $filters
     */
    public function paginateForUser(string $userId, array $filters = [], int $perPage = 20): LengthAwarePaginator;

    /**
     * Totais da lista filtrada: receitas, despesas, saldo e o que ainda vence (data futura).
     *
     * @param  array<string, mixed>  $filters
     * @return array{income: float, expense: float, balance: float, due: float, due_count: int, overdue: float, overdue_count: int, count: int}
     */
    public function summaryForUser(string $userId, array $filters): array;
}
