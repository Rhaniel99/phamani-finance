<?php

namespace App\Services;

use App\DTOs\Transaction\StoreTransactionData;
use App\DTOs\Transaction\UpdateTransactionData;
use App\Interfaces\Repositories\ITransactionRepository;
use App\Interfaces\Services\IBalanceService;
use App\Interfaces\Services\IInstallmentService;
use App\Interfaces\Services\IRecurringTransactionService;
use App\Interfaces\Services\IShareService;
use App\Interfaces\Services\ISplitService;
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
        protected IBalanceService $balance,
        protected IInstallmentService $installmentService,
        protected IRecurringTransactionService $recurringService,
        protected ISplitService $splits,
        protected IShareService $shares,
    ) {}

    public function create(string $userId, StoreTransactionData $dto): Model
    {
        $this->splits->validate($dto->split, $dto->amount, $dto->type);

        if ($dto->is_installment) {
            return $this->installmentService->createInstallment($userId, $dto);
        }

        if ($dto->is_recurring) {
            return $this->recurringService->createRecurringTransaction($userId, $dto);
        }

        return DB::transaction(function () use ($userId, $dto) {
            $parts = $this->splits->compute($dto->amount, $dto->split);

            /** @var Transaction $transaction */
            $transaction = $this->repository->create([
                'user_id' => $userId,
                // Se outra pessoa pagou, nenhuma conta sua é afetada.
                'account_id' => $parts['paid_by_contact_id'] === null ? $dto->account_id : null,
                'category_id' => $dto->category_id,
                'name' => $dto->description,
                'description' => $dto->description,
                'type' => $dto->type,
                'amount' => $parts['amount'],
                'total_amount' => $parts['total_amount'],
                'paid_by_contact_id' => $parts['paid_by_contact_id'],
                'date' => $dto->date,
            ]);

            $this->splits->sync($transaction, $parts['shares']);

            // Data futura: fica "agendada" e só entra no saldo quando a data chegar.
            $this->balance->applyIfDue($transaction);

            return $transaction;
        });
    }

    public function update(Transaction $transaction, UpdateTransactionData $dto): Transaction
    {
        $this->splits->validate($dto->split, $dto->amount, $dto->type);

        return DB::transaction(function () use ($transaction, $dto) {
            // Tira o efeito antigo (se havia) e reaplica com os dados novos, se a data já chegou.
            // Cobre troca de valor, de tipo, de conta e de data.
            $this->balance->revert($transaction);

            // Parcelas mantêm o sufixo "(n/total)" no nome.
            $name = $dto->description;
            if ($transaction->installment_id !== null && $transaction->installment !== null) {
                $name = "{$dto->description} ({$transaction->installment_number}/{$transaction->installment->installments})";
            }

            $parts = $this->splits->compute($dto->amount, $dto->split);

            $this->repository->update($transaction->id, [
                'account_id' => $parts['paid_by_contact_id'] === null ? $dto->account_id : null,
                'category_id' => $dto->category_id,
                'name' => $name,
                'description' => $dto->description,
                'type' => $dto->type,
                'amount' => $parts['amount'],
                'total_amount' => $parts['total_amount'],
                'paid_by_contact_id' => $parts['paid_by_contact_id'],
                'date' => $dto->date,
            ]);

            $transaction->refresh();
            $this->splits->sync($transaction, $parts['shares']);
            $this->balance->applyIfDue($transaction);

            if ($dto->apply_to_following && $transaction->installment_id !== null) {
                $this->installmentService->updateFollowingParcels($transaction, $dto->amount, $dto->split);
            }

            return $transaction;
        });
    }

    public function delete(Transaction $transaction): void
    {
        if ($transaction->installment_id !== null && $transaction->installment !== null) {
            $this->installmentService->deleteInstallment($transaction->installment);

            return;
        }

        DB::transaction(function () use ($transaction) {
            // Quem aceitou a divisão perde a cópia.
            $this->shares->removeFor($transaction);
            $this->balance->revert($transaction);
            $this->repository->delete($transaction->id);
        });
    }

    public function getRecentForDashboard(string $userId, int $limit = 5): Collection
    {
        return $this->repository->getLatestForUser($userId, $limit);
    }

    public function paginateForUser(string $userId, array $filters = [], int $perPage = 20): LengthAwarePaginator
    {
        return $this->repository->paginateForUser($userId, $filters, $perPage);
    }

    public function summaryForUser(string $userId, array $filters): array
    {
        return $this->repository->summaryForUser($userId, $filters);
    }
}
