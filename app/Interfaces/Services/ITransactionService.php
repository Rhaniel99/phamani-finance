<?php

namespace App\Interfaces\Services;

use App\DTOs\Transaction\StoreTransactionData;
use App\DTOs\Transaction\UpdateTransactionData;
use App\Models\Transaction;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Collection;

interface ITransactionService
{
    public function create(string $userId, StoreTransactionData $dto): Model;

    /**
     * Atualiza a transação e corrige o saldo das contas envolvidas.
     */
    public function update(Transaction $transaction, UpdateTransactionData $dto): Transaction;

    /**
     * Exclui a transação e desfaz o efeito no saldo.
     * Se for uma parcela, exclui o parcelamento inteiro.
     */
    public function delete(Transaction $transaction): void;

    public function getRecentForDashboard(string $userId, int $limit = 5): Collection;

    /**
     * @param  array{account_id?: ?string, category_id?: ?string, type?: ?string, month?: ?string, search?: ?string, kind?: ?string}  $filters
     */
    public function paginateForUser(string $userId, array $filters = [], int $perPage = 20): LengthAwarePaginator;

    /**
     * @param  array<string, mixed>  $filters
     * @return array{income: float, expense: float, balance: float, due: float, due_count: int, overdue: float, overdue_count: int, count: int}
     */
    public function summaryForUser(string $userId, array $filters): array;
}
