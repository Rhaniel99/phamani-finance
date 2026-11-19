<?php

namespace App\Interfaces\Services;

use App\Models\Transaction;
use App\Models\User;

/**
 * Status de pagamento (pago / pendente / atrasado).
 * Quem marca é quem pagou; numa divisão compartilhada o status vale para todos.
 */
interface IPaymentService
{
    /**
     * Marca como paga (hoje). Atualiza o saldo e as cópias compartilhadas.
     * Lança ValidationException se o usuário não for quem pagou.
     */
    public function markPaid(Transaction $transaction, User $user): void;

    /**
     * Volta para pendente/atrasada e desfaz o efeito no saldo.
     */
    public function markUnpaid(Transaction $transaction, User $user): void;

    /**
     * Débito automático: marca como pagas as ocorrências/parcelas vencidas de séries com auto_pay.
     * Retorna quantas foram pagas.
     */
    public function processAutoPay(): int;
}
