<?php

namespace App\Interfaces\Services;

use App\Models\Account;
use App\Models\CreditCardInvoice;
use App\Models\Transaction;
use Carbon\CarbonInterface;

interface ICreditCardService
{
    /**
     * Período da fatura em que cai uma compra feita em $date (não cria nada).
     *
     * @return array{reference_month: \Carbon\CarbonImmutable, closing_date: \Carbon\CarbonImmutable, due_date: \Carbon\CarbonImmutable}
     */
    public function periodFor(Account $card, CarbonInterface $date): array;

    /**
     * Fechamento e vencimento da fatura de um mês de referência (mês do vencimento).
     *
     * @return array{closing_date: \Carbon\CarbonImmutable, due_date: \Carbon\CarbonImmutable}
     */
    public function periodForReference(Account $card, CarbonInterface $referenceMonth): array;

    /**
     * Fatura (criada se ainda não existir) em que cai uma compra feita em $date.
     */
    public function invoiceFor(Account $card, CarbonInterface $date): CreditCardInvoice;

    /**
     * Preenche transaction.invoice_id conforme a conta e a data (null se não for cartão).
     * Não salva: é chamado pelo observer antes do save.
     */
    public function assignInvoice(Transaction $transaction): void;

    /**
     * Recoloca as compras ainda não pagas nas faturas certas (após mudar fechamento/vencimento).
     */
    public function reassignInvoices(Account $card): void;

    /**
     * Total da fatura: despesas − estornos/créditos.
     */
    public function invoiceTotal(CreditCardInvoice $invoice): float;

    /**
     * Limite, usado, disponível e fatura atual do cartão.
     *
     * @return array{limit: float|null, used: float, available: float|null, current_invoice: array<string, mixed>|null}
     */
    public function summary(Account $card): array;

    /**
     * Faturas do cartão (mais recentes primeiro), com total e status.
     *
     * @return list<array<string, mixed>>
     */
    public function invoicesFor(Account $card): array;

    /**
     * Soma das faturas a pagar até a fatura atual de cada cartão (fechadas não pagas + atual).
     */
    public function openInvoicesTotal(string $userId): float;

    /**
     * Paga a fatura inteira a partir de uma conta: o saldo da conta cai, sem contar como despesa.
     */
    public function pay(CreditCardInvoice $invoice, string $fromAccountId, string $date): void;

    /**
     * Desfaz o pagamento: o valor volta para a conta de origem.
     */
    public function undoPayment(CreditCardInvoice $invoice): void;
}
