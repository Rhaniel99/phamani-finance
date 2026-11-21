<?php

namespace App\Observers;

use App\Interfaces\Services\ICreditCardService;
use App\Models\Account;
use App\Models\Transaction;

/**
 * Mantém cada transação na fatura certa, venha de onde vier
 * (lançamento simples, parcela, recorrência, edição).
 */
class TransactionObserver
{
    public function __construct(
        protected ICreditCardService $cards,
    ) {}

    /**
     * Status inicial, quando quem criou não definiu paid_at:
     * data de hoje ou passada → pago; futura → pendente.
     * Cartão: já definido no saving (segue a fatura).
     */
    public function creating(Transaction $transaction): void
    {
        if (array_key_exists('paid_at', $transaction->getAttributes())) {
            return;
        }

        $date = $transaction->date->toDateString();

        $transaction->paid_at = $date <= now()->toDateString() ? $date : null;
    }

    public function saving(Transaction $transaction): void
    {
        if ($transaction->exists && ! $transaction->isDirty(['account_id', 'date'])) {
            return;
        }

        $wasCard = $transaction->exists && $this->isCard($transaction->getOriginal('account_id'));

        // Cartão: fatura certa e status da fatura.
        $this->cards->assignInvoice($transaction);

        // Saiu do cartão para uma conta: volta à regra comum (passada → paga, futura → pendente).
        if ($wasCard && ! $this->isCard($transaction->account_id)) {
            $date = $transaction->date->toDateString();
            $transaction->paid_at = $date <= now()->toDateString() ? $date : null;
        }
    }

    private function isCard(?string $accountId): bool
    {
        return $accountId !== null
            && Account::query()->whereKey($accountId)->value('type') === 'credit';
    }
}
