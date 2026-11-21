<?php

namespace App\Services;

use App\Interfaces\Services\IBalanceService;
use App\Interfaces\Services\IPaymentService;
use App\Models\Account;
use App\Models\Contact;
use App\Models\Installment;
use App\Models\RecurringTransaction;
use App\Models\ShareLink;
use App\Models\Transaction;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class PaymentService implements IPaymentService
{
    public function __construct(
        protected IBalanceService $balance,
    ) {}

    public function markPaid(Transaction $transaction, User $user): void
    {
        $source = $this->sourceOf($transaction);
        $this->ensureNotOnCard($source);
        $this->ensurePayer($source, $user);

        $this->setPaid($source, now()->toDateString());
    }

    public function markUnpaid(Transaction $transaction, User $user): void
    {
        $source = $this->sourceOf($transaction);
        $this->ensureNotOnCard($source);
        $this->ensurePayer($source, $user);

        $this->setPaid($source, null);
    }

    public function processAutoPay(): int
    {
        $count = 0;

        Transaction::query()
            ->whereNull('paid_at')
            ->whereNull('mirrored_from_id')
            // No cartão, quem paga é a fatura.
            ->notOnCard()
            ->whereDate('date', '<=', now()->toDateString())
            ->where(fn ($q) => $q
                ->whereIn('recurring_id', RecurringTransaction::query()->select('id')->where('auto_pay', true))
                ->orWhereIn('installment_id', Installment::query()->select('id')->where('auto_pay', true)))
            ->lazyById()
            ->each(function (Transaction $transaction) use (&$count) {
                // Débito automático: considera pago na data do vencimento.
                $this->setPaid($transaction, $transaction->date->toDateString());
                $count++;
            });

        return $count;
    }

    /**
     * Grava o status na original e nas cópias, ajustando o saldo de cada uma.
     */
    private function setPaid(Transaction $source, ?string $paidAt): void
    {
        DB::transaction(function () use ($source, $paidAt) {
            $targets = collect([$source]);

            $mirrorIds = ShareLink::query()
                ->where('source_transaction_id', $source->id)
                ->whereNotNull('mirror_transaction_id')
                ->pluck('mirror_transaction_id');

            if ($mirrorIds->isNotEmpty()) {
                $targets = $targets->merge(Transaction::query()->whereIn('id', $mirrorIds)->get());
            }

            foreach ($targets as $transaction) {
                if ($paidAt === null) {
                    $this->balance->revert($transaction);
                }

                $transaction->forceFill(['paid_at' => $paidAt])->save();

                if ($paidAt !== null) {
                    $this->balance->applyIfDue($transaction);
                }
            }
        });
    }

    /**
     * Numa cópia compartilhada, o status é da transação original.
     */
    private function sourceOf(Transaction $transaction): Transaction
    {
        if (! $transaction->isMirror()) {
            return $transaction;
        }

        return Transaction::query()->findOrFail($transaction->mirrored_from_id);
    }

    /**
     * Quem marca é quem pagou: o dono (se ele pagou ou se pagou alguém que não usa o Phamani)
     * ou o usuário vinculado ao contato que pagou.
     */
    private function ensureNotOnCard(Transaction $source): void
    {
        if ($source->account_id !== null && Account::query()->whereKey($source->account_id)->value('type') === 'credit') {
            throw ValidationException::withMessages([
                'paid' => 'Compra no cartão fica paga quando a fatura é paga.',
            ]);
        }
    }

    private function ensurePayer(Transaction $source, User $user): void
    {
        $payerId = $source->user_id;

        if ($source->paid_by_contact_id !== null) {
            $payerId = Contact::query()->whereKey($source->paid_by_contact_id)->value('linked_user_id') ?? $source->user_id;
        }

        if ($payerId !== $user->id) {
            $name = User::query()->whereKey($payerId)->value('name') ?? 'quem pagou';

            throw ValidationException::withMessages([
                'paid' => "Só {$name} pode marcar esta conta como paga.",
            ]);
        }
    }
}
