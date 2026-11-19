<?php

namespace App\Services;

use App\Interfaces\Repositories\IAccountRepository;
use App\Interfaces\Services\IBalanceService;
use App\Models\Account;
use App\Models\Transaction;
use Illuminate\Support\Facades\DB;

class BalanceService implements IBalanceService
{
    public function __construct(
        protected IAccountRepository $accounts,
    ) {}

    public function applyIfDue(Transaction $transaction): void
    {
        // O saldo muda quando a transação está PAGA (pendente/atrasada ainda não saiu da conta).
        if ($transaction->balance_applied || $transaction->paid_at === null) {
            return;
        }

        // Outra pessoa pagou (divisão): nenhuma conta sua é afetada.
        if ($transaction->cashAmount() <= 0 || $transaction->account_id === null) {
            return;
        }

        // Compra no cartão não mexe em saldo: vai para a fatura e só sai dinheiro ao pagá-la.
        if ($this->isCreditCard($transaction->account_id)) {
            return;
        }

        DB::transaction(function () use ($transaction) {
            // Numa divisão paga por você, sai o total da conta (não só a sua parte).
            $this->accounts->applyTransaction($transaction->account_id, $transaction->cashAmount(), $transaction->type);
            $transaction->forceFill(['balance_applied' => true])->save();
        });
    }

    public function revert(Transaction $transaction): void
    {
        if (! $transaction->balance_applied || $transaction->account_id === null) {
            return;
        }

        DB::transaction(function () use ($transaction) {
            $this->accounts->revertTransaction($transaction->account_id, $transaction->cashAmount(), $transaction->type);
            $transaction->forceFill(['balance_applied' => false])->save();
        });
    }

    public function applyAllDue(): int
    {
        $count = 0;

        Transaction::query()
            ->where('balance_applied', false)
            ->whereNotNull('paid_at')
            ->whereNotNull('account_id')
            ->whereNull('paid_by_contact_id')
            ->whereNotIn('account_id', Account::query()->select('id')->where('type', 'credit'))
            ->lazyById()
            ->each(function (Transaction $transaction) use (&$count) {
                $this->applyIfDue($transaction);
                $count++;
            });

        return $count;
    }

    private function isCreditCard(string $accountId): bool
    {
        return Account::query()->whereKey($accountId)->value('type') === 'credit';
    }
}
