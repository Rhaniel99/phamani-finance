<?php

namespace App\Interfaces\Services;

use App\Models\Contact;
use App\Models\Transaction;
use App\Models\TransactionSplit;
use App\Models\User;

/**
 * Compra para outra pessoa: o que cada contato te deve e o registro do reembolso (Pix).
 *
 * Entra aqui toda despesa paga por você em que a sua parte é zero; a parte de cada contato
 * fica "a receber" até você registrar o recebimento. O dinheiro que volta aumenta o saldo da
 * conta escolhida, mas não conta como receita.
 */
interface IReimbursementService
{
    /**
     * Contatos com valores em aberto, cada um com as compras pendentes (vencidas e futuras).
     *
     * @return list<array{
     *     contact: array{id: string, name: string, avatar: string|null},
     *     due_total: float,
     *     due_count: int,
     *     items: list<array{id: string, transaction_id: string, name: string, date: string, amount: float, due: bool}>
     * }>
     */
    public function openForUser(string $userId): array;

    /**
     * Registra que o contato devolveu as partes escolhidas, com o dinheiro caindo em $accountId.
     *
     * @param  list<string>  $splitIds
     */
    public function receive(User $user, Contact $contact, array $splitIds, string $accountId, string $date): void;

    /** Desfaz um recebimento (o valor sai de novo da conta onde tinha entrado). */
    public function undo(User $user, TransactionSplit $split): void;

    /** Antes de apagar uma transação: tira dos saldos os reembolsos já registrados nela. */
    public function revertFor(Transaction $transaction): void;
}
