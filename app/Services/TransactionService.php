<?php

namespace App\Services;

use App\DTOs\Transaction\StoreTransactionData;
use App\DTOs\Transaction\UpdateTransactionData;
use App\Interfaces\Repositories\IAccountRepository;
use App\Interfaces\Repositories\ITransactionRepository;
use App\Interfaces\Services\IInstallmentService;
use App\Interfaces\Services\IRecurringTransactionService;
use App\Interfaces\Services\ITransactionService;
use App\Models\Transaction;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

class TransactionService implements ITransactionService
{
    public function __construct(
        protected ITransactionRepository $repository,
        protected IAccountRepository $accountRepository,
        protected IInstallmentService $installmentService,
        protected IRecurringTransactionService $recurringService,
    ) {}

    public function create(string $userId, StoreTransactionData $dto): Model
    {
        if ($dto->is_installment) {
            return $this->installmentService->createInstallment($userId, $dto);
        }

        if ($dto->is_recurring) {
            return $this->recurringService->createRecurringTransaction($userId, $dto);
        }

        return DB::transaction(function () use ($userId, $dto) {
            $transaction = $this->repository->create([
                'user_id' => $userId,
                'account_id' => $dto->account_id,
                'category_id' => $dto->category_id,
                'name' => $dto->description,
                'description' => $dto->description,
                'type' => $dto->type,
                'amount' => $dto->amount,
                'date' => $dto->date,
            ]);

            $this->accountRepository->applyTransaction($dto->account_id, $dto->amount, $dto->type);

            return $transaction;
        });
    }

    public function update(Transaction $transaction, UpdateTransactionData $dto): Transaction
    {
        return DB::transaction(function () use ($transaction, $dto) {
            $affectsBalance = $this->affectsBalance($transaction);

            // Desfaz o valor antigo na conta antiga e aplica o novo na conta nova
            // (cobre troca de valor, de tipo e de conta).
            if ($affectsBalance) {
                $this->accountRepository->revertTransaction(
                    $transaction->account_id,
                    (float) $transaction->amount,
                    $transaction->type,
                );
            }

            // Parcelas mantêm o sufixo "(n/total)" no nome.
            $name = $dto->description;
            if ($transaction->installment_id !== null && $transaction->installment !== null) {
                $name = "{$dto->description} ({$transaction->installment_number}/{$transaction->installment->installments})";
            }

            $this->repository->update($transaction->id, [
                'account_id' => $dto->account_id,
                'category_id' => $dto->category_id,
                'name' => $name,
                'description' => $dto->description,
                'type' => $dto->type,
                'amount' => $dto->amount,
                'date' => $dto->date,
            ]);

            if ($affectsBalance) {
                $this->accountRepository->applyTransaction($dto->account_id, $dto->amount, $dto->type);
            }

            return $transaction->refresh();
        });
    }

    public function delete(Transaction $transaction): void
    {
        if ($transaction->installment_id !== null && $transaction->installment !== null) {
            $this->installmentService->deleteInstallment($transaction->installment);

            return;
        }

        DB::transaction(function () use ($transaction) {
            if ($this->affectsBalance($transaction)) {
                $this->accountRepository->revertTransaction(
                    $transaction->account_id,
                    (float) $transaction->amount,
                    $transaction->type,
                );
            }

            $this->repository->delete($transaction->id);
        });
    }

    /**
     * Mesma regra da criação: transações simples e recorrentes entram no saldo;
     * de um parcelamento, só a 1ª parcela.
     */
    private function affectsBalance(Transaction $transaction): bool
    {
        return $transaction->installment_number === null || $transaction->installment_number === 1;
    }

    public function getRecentForDashboard(string $userId, int $limit = 5): Collection
    {
        return $this->repository->getLatestForUser($userId, $limit);
    }

    public function paginateForUser(string $userId, array $filters = [], int $perPage = 20): LengthAwarePaginator
    {
        return $this->repository->paginateForUser($userId, $filters, $perPage);
    }
}
