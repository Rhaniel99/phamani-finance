<?php

namespace App\Interfaces\Repositories;

interface IAccountRepository extends ICoreRepository
{
    /**
     * Soma (receita) ou subtrai (despesa) o valor do saldo da conta, de forma atômica.
     */
    public function applyTransaction(string $accountId, float $amount, string $type): void;

    /**
     * Desfaz o efeito de uma transação no saldo (usado ao editar/excluir).
     */
    public function revertTransaction(string $accountId, float $amount, string $type): void;
}
