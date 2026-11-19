<?php

namespace App\Interfaces\Services;

use App\Models\Transaction;

/**
 * Único lugar que decide quando uma transação entra ou sai do saldo da conta.
 * Regra: só entra quando a transação está paga (paid_at preenchido).
 */
interface IBalanceService
{
    /**
     * Aplica no saldo se estiver paga e ainda não foi aplicada.
     */
    public function applyIfDue(Transaction $transaction): void;

    /**
     * Desfaz o efeito no saldo, se tiver sido aplicada.
     */
    public function revert(Transaction $transaction): void;

    /**
     * Aplica todas as transações pagas que ainda não entraram no saldo. Retorna quantas foram verificadas.
     */
    public function applyAllDue(): int;
}
