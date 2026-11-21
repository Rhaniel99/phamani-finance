<?php

namespace App\Interfaces\Services;

use App\Models\Contact;
use App\Models\Settlement;
use App\Models\Transaction;
use App\Models\TransactionSplit;
use App\Models\User;

/**
 * Acerto do mês: o que cada pessoa te deve e o que você deve a quem usa o Phamani.
 *
 * Entram as partes "cobradas" (tracked) de despesas pagas por quem criou a transação:
 * compras para outra pessoa sempre; divisões comuns quando a cobrança está ligada no contato e na divisão.
 * Cada parte cai no acerto do mês da fatura (cartão) ou da data (resto), com prazo no 5º dia útil.
 *
 * Quem deve e usa o Phamani informa o pagamento ("paguei", saindo da conta dele) e quem recebe confirma
 * (entrando na conta dele). Para quem não usa, quem recebe registra direto. O dinheiro do acerto mexe
 * no saldo, mas não conta como receita nem como despesa (a despesa já foi lançada).
 */
interface IReimbursementService
{
    /**
     * Quem te deve: por contato, com as partes em aberto e os pagamentos aguardando sua confirmação.
     *
     * @return list<array<string, mixed>>
     */
    public function openForUser(string $userId): array;

    /**
     * Quanto você deve: por pessoa (usuário do Phamani), com as partes em aberto e os pagamentos
     * que você informou e ainda não foram confirmados.
     *
     * @return list<array<string, mixed>>
     */
    public function payablesForUser(string $userId): array;

    /**
     * Quem recebe registra direto que o contato pagou (contatos que não usam o Phamani, ou à mão).
     *
     * @param  list<string>  $splitIds
     */
    public function receive(User $user, Contact $contact, array $splitIds, string $accountId, string $date): void;

    /**
     * Quem deve informa que pagou: sai da conta dele e fica aguardando a confirmação.
     *
     * @param  list<string>  $splitIds
     */
    public function pay(User $debtor, User $creditor, array $splitIds, string $fromAccountId, string $date): Settlement;

    /** Quem recebe confirma: entra na conta escolhida e as partes ficam pagas para os dois. */
    public function confirm(User $creditor, Settlement $settlement, string $toAccountId): void;

    /** Quem recebe recusa (não chegou): o valor volta para a conta de quem pagou e as partes voltam a "a pagar". */
    public function reject(User $creditor, Settlement $settlement): void;

    /** Quem pagou cancela o aviso enquanto não foi confirmado. */
    public function cancel(User $debtor, Settlement $settlement): void;

    /** Desfaz um recebimento (no acerto entre usuários, volta a "aguardando confirmação"). */
    public function undo(User $user, TransactionSplit $split): void;

    /** Antes de apagar uma transação: desfaz nos saldos o que já foi pago/recebido dela. */
    public function revertFor(Transaction $transaction): void;
}
