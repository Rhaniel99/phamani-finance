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
     * cartão → pago (a dívida vai para a fatura); data de hoje ou passada → pago; futura → pendente.
     */
    public function creating(Transaction $transaction): void
    {
        if (array_key_exists('paid_at', $transaction->getAttributes())) {
            return;
        }

        $isCard = $transaction->account_id !== null
            && Account::query()->whereKey($transaction->account_id)->value('type') === 'credit';

        $date = $transaction->date->toDateString();

        $transaction->paid_at = $isCard || $date <= now()->toDateString() ? $date : null;
    }

    public function saving(Transaction $transaction): void
    {
        if (! $transaction->exists || $transaction->isDirty(['account_id', 'date'])) {
            $this->cards->assignInvoice($transaction);
        }
    }
}
