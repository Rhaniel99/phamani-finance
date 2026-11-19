<?php

namespace App\Interfaces\Services;

use App\DTOs\Transaction\SplitData;
use App\DTOs\Transaction\StoreTransactionData;
use App\Models\Installment;
use App\Models\Transaction;

interface IInstallmentService
{
    public function createInstallment(string $userId, StoreTransactionData $dto): Installment;

    /**
     * Repete o valor (e a divisão) de uma parcela em todas as parcelas seguintes
     * (ex.: correção mensal da entrada da MRV).
     */
    public function updateFollowingParcels(Transaction $parcel, float $amount, ?SplitData $split = null): void;

    /**
     * Exclui o parcelamento com todas as parcelas e desfaz o efeito no saldo.
     */
    public function deleteInstallment(Installment $installment): void;
}
