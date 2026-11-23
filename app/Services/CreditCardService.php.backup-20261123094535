<?php

namespace App\Services;

use App\Interfaces\Repositories\IAccountRepository;
use App\Interfaces\Services\ICreditCardService;
use App\Models\Account;
use App\Models\CreditCardInvoice;
use App\Models\Transaction;
use Carbon\CarbonImmutable;
use Carbon\CarbonInterface;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class CreditCardService implements ICreditCardService
{
    public function __construct(
        protected IAccountRepository $accounts,
    ) {}

    /**
     * Calcula o período da fatura em que cai uma compra.
     *
     * Ex.: fechamento dia 25, vencimento dia 5.
     *  - compra 20/11 → fecha 25/11, vence 05/12 (fatura de dezembro)
     *  - compra 26/11 → fecha 25/12, vence 05/01 (fatura de janeiro)
     * Meses curtos: dia 31 vira o último dia do mês.
     *
     * @return array{reference_month: CarbonImmutable, closing_date: CarbonImmutable, due_date: CarbonImmutable}
     */
    public function periodFor(Account $card, CarbonInterface $date): array
    {
        $date = CarbonImmutable::parse($date->toDateString());
        $closingDay = (int) $card->closing_day;
        $dueDay = (int) $card->due_day;

        $closingMonth = $date->startOfMonth();
        if ($date->greaterThan($this->dayIn($closingMonth, $closingDay))) {
            $closingMonth = $closingMonth->addMonthNoOverflow();
        }

        // Vencimento depois do fechamento no mesmo mês (fecha 5, vence 15) ou no mês seguinte (fecha 25, vence 5).
        $dueMonth = $dueDay > $closingDay ? $closingMonth : $closingMonth->addMonthNoOverflow();

        return [
            'reference_month' => $dueMonth,
            'closing_date' => $this->dayIn($closingMonth, $closingDay),
            'due_date' => $this->dayIn($dueMonth, $dueDay),
        ];
    }

    public function invoiceFor(Account $card, CarbonInterface $date): CreditCardInvoice
    {
        $period = $this->periodFor($card, $date);
        $reference = $period['reference_month']->toDateString();

        // whereDate (e não firstOrCreate) para comparar só a data em qualquer banco.
        $invoice = CreditCardInvoice::query()
            ->where('account_id', $card->id)
            ->whereDate('reference_month', $reference)
            ->first();

        /** @var CreditCardInvoice */
        return $invoice ?? CreditCardInvoice::query()->create([
            'user_id' => $card->user_id,
            'account_id' => $card->id,
            'reference_month' => $reference,
            'closing_date' => $period['closing_date']->toDateString(),
            'due_date' => $period['due_date']->toDateString(),
        ]);
    }

    /**
     * Fechamento e vencimento de uma fatura a partir do mês de referência (mês do vencimento).
     *
     * @return array{closing_date: CarbonImmutable, due_date: CarbonImmutable}
     */
    private function periodForReference(Account $card, CarbonInterface $referenceMonth): array
    {
        $dueMonth = CarbonImmutable::parse($referenceMonth->toDateString())->startOfMonth();
        $closingMonth = (int) $card->due_day > (int) $card->closing_day ? $dueMonth : $dueMonth->subMonthNoOverflow();

        return [
            'closing_date' => $this->dayIn($closingMonth, (int) $card->closing_day),
            'due_date' => $this->dayIn($dueMonth, (int) $card->due_day),
        ];
    }

    public function assignInvoice(Transaction $transaction): void
    {
        $card = $transaction->account_id !== null ? Account::query()->find($transaction->account_id) : null;

        if ($card === null || ! $card->isCreditCard()) {
            $transaction->invoice_id = null;

            return;
        }

        if (! $card->isConfiguredCard()) {
            // Cartão sem fechamento/vencimento: sem fatura, fica "na fatura" (não paga).
            $transaction->invoice_id = null;
            $transaction->paid_at = null;

            return;
        }

        $invoice = $this->invoiceFor($card, $transaction->date);

        $transaction->invoice_id = $invoice->id;
        // Status da compra = status da fatura: paga quando a fatura for paga.
        $transaction->paid_at = $invoice->paid_at?->toDateString();
    }

    public function reassignInvoices(Account $card): void
    {
        DB::transaction(function () use ($card) {
            $unpaid = Transaction::query()
                ->where('account_id', $card->id)
                ->where(fn ($q) => $q
                    ->whereNull('invoice_id')
                    ->orWhereIn('invoice_id', CreditCardInvoice::query()
                        ->select('id')
                        ->where('account_id', $card->id)
                        ->whereNull('paid_at')))
                ->get();

            foreach ($unpaid as $transaction) {
                $this->assignInvoice($transaction);
                $transaction->saveQuietly();
            }

            // Faturas abertas que ficaram vazias saem; o período delas mudou.
            CreditCardInvoice::query()
                ->where('account_id', $card->id)
                ->whereNull('paid_at')
                ->whereDoesntHave('transactions')
                ->delete();

            // Faturas abertas que continuam ganham as datas novas.
            CreditCardInvoice::query()
                ->where('account_id', $card->id)
                ->whereNull('paid_at')
                ->get()
                ->each(function (CreditCardInvoice $invoice) use ($card) {
                    $period = $this->periodForReference($card, $invoice->reference_month);
                    $invoice->update([
                        'closing_date' => $period['closing_date']->toDateString(),
                        'due_date' => $period['due_date']->toDateString(),
                    ]);
                });
        });
    }

    public function invoiceTotal(CreditCardInvoice $invoice): float
    {
        return $this->totalsFor([$invoice->id])[$invoice->id] ?? 0.0;
    }

    public function summary(Account $card): array
    {
        $limit = $card->credit_limit !== null ? (float) $card->credit_limit : null;

        if (! $card->isConfiguredCard()) {
            return ['limit' => $limit, 'used' => 0.0, 'available' => $limit, 'current_invoice' => null];
        }

        $unpaid = CreditCardInvoice::query()
            ->where('account_id', $card->id)
            ->whereNull('paid_at')
            ->pluck('id')
            ->all();

        $used = round(array_sum($this->totalsFor($unpaid)), 2);

        $period = $this->periodFor($card, now());
        $current = CreditCardInvoice::query()
            ->where('account_id', $card->id)
            ->whereDate('reference_month', $period['reference_month']->toDateString())
            ->first();

        return [
            'limit' => $limit,
            'used' => $used,
            'available' => $limit !== null ? round($limit - $used, 2) : null,
            'current_invoice' => [
                'id' => $current?->id,
                'reference_month' => $period['reference_month']->toDateString(),
                'closing_date' => $period['closing_date']->toDateString(),
                'due_date' => $period['due_date']->toDateString(),
                'total' => $current !== null ? $this->invoiceTotal($current) : 0.0,
                'status' => $current?->status() ?? 'open',
            ],
        ];
    }

    public function invoicesFor(Account $card): array
    {
        $invoices = CreditCardInvoice::query()
            ->where('account_id', $card->id)
            ->orderByDesc('reference_month')
            ->get();

        $totals = $this->totalsFor($invoices->pluck('id')->all());

        return $invoices
            ->map(fn (CreditCardInvoice $invoice) => [
                'id' => $invoice->id,
                'reference_month' => $invoice->reference_month->toDateString(),
                'closing_date' => $invoice->closing_date->toDateString(),
                'due_date' => $invoice->due_date->toDateString(),
                'total' => $totals[$invoice->id] ?? 0.0,
                'status' => $invoice->status(),
                'paid_at' => $invoice->paid_at?->toDateString(),
                'paid_amount' => $invoice->paid_amount !== null ? (float) $invoice->paid_amount : null,
                'paid_from_account_id' => $invoice->paid_from_account_id,
            ])
            ->values()
            ->all();
    }

    public function openInvoicesTotal(string $userId): float
    {
        $total = 0.0;

        $cards = Account::query()->where('user_id', $userId)->where('type', 'credit')->get();

        foreach ($cards as $card) {
            if (! $card->isConfiguredCard()) {
                continue;
            }

            $currentReference = $this->periodFor($card, now())['reference_month']->toDateString();

            $ids = CreditCardInvoice::query()
                ->where('account_id', $card->id)
                ->whereNull('paid_at')
                ->whereDate('reference_month', '<=', $currentReference)
                ->pluck('id')
                ->all();

            $total += array_sum($this->totalsFor($ids));
        }

        return round($total, 2);
    }

    public function pay(CreditCardInvoice $invoice, string $fromAccountId, string $date): void
    {
        if ($invoice->paid_at !== null) {
            throw ValidationException::withMessages(['invoice' => 'Esta fatura já está paga.']);
        }

        $total = $this->invoiceTotal($invoice);

        if ($total <= 0) {
            throw ValidationException::withMessages(['invoice' => 'Não há valor a pagar nesta fatura.']);
        }

        DB::transaction(function () use ($invoice, $fromAccountId, $date, $total) {
            $invoice->update([
                'paid_at' => $date,
                'paid_amount' => $total,
                'paid_from_account_id' => $fromAccountId,
            ]);

            // Sai dinheiro da conta, mas não é despesa: as compras já foram contadas uma a uma.
            $this->accounts->applyTransaction($fromAccountId, $total, 'expense');

            $this->setPurchasesPaidAt($invoice, $date);
        });
    }

    public function undoPayment(CreditCardInvoice $invoice): void
    {
        if ($invoice->paid_at === null) {
            return;
        }

        DB::transaction(function () use ($invoice) {
            if ($invoice->paid_from_account_id !== null && $invoice->paid_amount !== null) {
                $this->accounts->revertTransaction($invoice->paid_from_account_id, (float) $invoice->paid_amount, 'expense');
            }

            $invoice->update([
                'paid_at' => null,
                'paid_amount' => null,
                'paid_from_account_id' => null,
            ]);

            $this->setPurchasesPaidAt($invoice, null);
        });
    }

    /**
     * As compras da fatura (e as cópias delas, nas divisões) acompanham o pagamento da fatura.
     * Compras no cartão não mexem no saldo, então basta gravar o status.
     */
    private function setPurchasesPaidAt(CreditCardInvoice $invoice, ?string $date): void
    {
        $ids = Transaction::query()->where('invoice_id', $invoice->id)->pluck('id');

        Transaction::query()->whereIn('id', $ids)->update(['paid_at' => $date]);
        Transaction::query()->whereIn('mirrored_from_id', $ids)->update(['paid_at' => $date]);
    }

    /**
     * @param  list<string>  $invoiceIds
     * @return array<string, float>
     */
    private function totalsFor(array $invoiceIds): array
    {
        if ($invoiceIds === []) {
            return [];
        }

        return Transaction::query()
            ->whereIn('invoice_id', $invoiceIds)
            ->groupBy('invoice_id')
            // Numa compra dividida, entra na fatura o valor cheio (coalesce com total_amount).
            ->selectRaw("invoice_id, sum(case when type = 'expense' then coalesce(total_amount, amount) else -coalesce(total_amount, amount) end) as total")
            ->pluck('total', 'invoice_id')
            ->map(fn ($total) => round((float) $total, 2))
            ->all();
    }

    private function dayIn(CarbonImmutable $month, int $day): CarbonImmutable
    {
        return $month->startOfMonth()->day(min($day, $month->daysInMonth));
    }
}
