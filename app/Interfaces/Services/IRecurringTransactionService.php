<?php

namespace App\Interfaces\Services;

use App\DTOs\Transaction\StoreTransactionData;
use App\Models\RecurringTransaction;

interface IRecurringTransactionService
{
    public function createRecurringTransaction(string $userId, StoreTransactionData $dto): RecurringTransaction;

    /**
     * Lança as ocorrências que já venceram, repetindo o último valor lançado.
     * Retorna quantas ocorrências foram criadas.
     */
    public function generateDue(RecurringTransaction $recurring, bool $markPaid = false): int;

    /**
     * Roda generateDue() para todas as recorrências ativas (usado pela tarefa agendada).
     */
    public function generateAllDue(): int;

    /**
     * Encerra a recorrência a partir de hoje: nenhuma nova ocorrência é lançada.
     */
    public function end(RecurringTransaction $recurring): void;
}
