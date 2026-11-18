<?php

namespace App\Interfaces\Services;

use App\DTOs\Transaction\StoreTransactionData;
use App\Models\Installment;

interface IInstallmentService
{
    public function createInstallment(string $userId, StoreTransactionData $dto): Installment;

    /**
     * Exclui o parcelamento com todas as parcelas e desfaz o efeito no saldo.
     */
    public function deleteInstallment(Installment $installment): void;
}
