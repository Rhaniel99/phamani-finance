<?php

namespace App\Interfaces\Services;

use App\DTOs\Transaction\SplitData;
use App\Models\Transaction;

interface ISplitService
{
    /**
     * Valida a divisão em relação ao valor informado (lança ValidationException com chaves "split.*").
     */
    public function validate(?SplitData $split, float $amount, string $type): void;

    /**
     * Calcula os campos da transação para um total.
     * Sem divisão: amount = total. Com divisão: amount = sua parte, total_amount = total.
     * O centavo que sobra fica com quem pagou.
     *
     * @return array{amount: float, total_amount: float|null, paid_by_contact_id: string|null, shares: array<string, float>, tracked: list<string>}
     *   shares: chave "me" para você, ou o id do contato. tracked: contatos cujas partes entram no acerto.
     */
    public function compute(float $total, ?SplitData $split): array;

    /**
     * Regrava as partes (transaction_splits) da transação.
     *
     * @param  array<string, float>  $shares
     * @param  list<string>  $tracked  contatos cujas partes entram no acerto
     */
    public function sync(Transaction $transaction, array $shares, array $tracked = []): void;

    /**
     * Copia as partes de uma transação para outra (usado nas recorrências).
     */
    public function copy(Transaction $from, Transaction $to): void;
}
