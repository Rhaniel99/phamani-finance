<?php

namespace App\Services;

use App\Interfaces\Repositories\IAccountRepository;
use App\Interfaces\Services\IReimbursementService;
use App\Models\Account;
use App\Models\Contact;
use App\Models\Settlement;
use App\Models\Transaction;
use App\Models\TransactionSplit;
use App\Models\User;
use App\Notifications\ActivityNotification;
use App\Support\Acerto;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class ReimbursementService implements IReimbursementService
{
    public function __construct(
        protected IAccountRepository $accounts,
    ) {}

    public function openForUser(string $userId): array
    {
        $current = Acerto::current();

        $open = $this->openQuery()
            ->where('transactions.user_id', $userId)
            ->whereNull('transaction_splits.settlement_id')
            ->with($this->itemRelations())
            ->get();

        $pending = Settlement::query()
            ->where('creditor_user_id', $userId)
            ->where('status', 'pending')
            ->withCount('splits')
            ->orderBy('paid_on')
            ->get();

        $contactIds = $open->pluck('contact_id')->merge($pending->pluck('contact_id'))->unique()->values();

        $contacts = Contact::query()
            ->with('linkedUser:id,avatar')
            ->whereIn('id', $contactIds)
            ->get(['id', 'name', 'linked_user_id'])
            ->keyBy('id');

        return $contactIds
            ->map(function (string $contactId) use ($open, $pending, $contacts, $current) {
                /** @var Contact $contact */
                $contact = $contacts[$contactId];

                return [
                    'contact' => [
                        'id' => $contact->id,
                        'name' => $contact->name,
                        'avatar' => $contact->linkedUser?->avatar,
                        'linked' => $contact->linked_user_id !== null,
                    ],
                    ...$this->summary($open->where('contact_id', $contactId)->values(), $current),
                    'pending' => $pending->where('contact_id', $contactId)->map(fn (Settlement $s) => $this->settlementData($s))->values()->all(),
                ];
            })
            ->sortByDesc(fn (array $r) => $r['overdue_total'] + $r['current_total'] + ($r['pending'] === [] ? 0 : 1_000_000))
            ->values()
            ->all();
    }

    public function payablesForUser(string $userId): array
    {
        $current = Acerto::current();

        $open = $this->payableQuery($userId)
            ->whereNull('transaction_splits.settlement_id')
            ->with($this->itemRelations())
            ->get();

        $pending = Settlement::query()
            ->where('debtor_user_id', $userId)
            ->where('status', 'pending')
            ->withCount('splits')
            ->orderBy('paid_on')
            ->get();

        $creditorIds = $open->pluck('transaction.user_id')->merge($pending->pluck('creditor_user_id'))->unique()->values();
        $creditors = User::query()->whereIn('id', $creditorIds)->get(['id', 'name', 'avatar'])->keyBy('id');

        return $creditorIds
            ->map(function (string $creditorId) use ($open, $pending, $creditors, $current) {
                $creditor = $creditors[$creditorId];

                return [
                    'creditor' => ['id' => $creditor->id, 'name' => $creditor->name, 'avatar' => $creditor->avatar],
                    ...$this->summary($open->where('transaction.user_id', $creditorId)->values(), $current),
                    'pending' => $pending->where('creditor_user_id', $creditorId)->map(fn (Settlement $s) => $this->settlementData($s))->values()->all(),
                ];
            })
            ->values()
            ->all();
    }

    public function receive(User $user, Contact $contact, array $splitIds, string $accountId, string $date): void
    {
        if ($contact->user_id !== $user->id) {
            abort(404);
        }

        $account = $this->moneyAccount($user, $accountId, 'account_id');

        $splits = $this->openQuery()
            ->where('transactions.user_id', $user->id)
            ->where('transaction_splits.contact_id', $contact->id)
            ->whereNull('transaction_splits.settlement_id')
            ->whereIn('transaction_splits.id', $splitIds)
            ->get();

        $this->ensureAll($splits, $splitIds);

        DB::transaction(function () use ($splits, $account, $date) {
            foreach ($splits as $split) {
                $split->forceFill([
                    'reimbursed_at' => $date,
                    'reimbursement_account_id' => $account->id,
                    'reimbursed_amount' => $split->amount,
                ])->save();
            }

            // Entra na conta, mas não é receita: é dinheiro seu voltando.
            $this->accounts->applyTransaction($account->id, (float) $splits->sum('amount'), 'income');
        });
    }

    public function pay(User $debtor, User $creditor, array $splitIds, string $fromAccountId, string $date): Settlement
    {
        $account = $this->moneyAccount($debtor, $fromAccountId, 'account_id');

        $splits = $this->payableQuery($debtor->id)
            ->where('transactions.user_id', $creditor->id)
            ->whereNull('transaction_splits.settlement_id')
            ->whereIn('transaction_splits.id', $splitIds)
            ->get();

        $this->ensureAll($splits, $splitIds);

        $amount = round((float) $splits->sum('amount'), 2);

        $settlement = DB::transaction(function () use ($debtor, $creditor, $splits, $account, $date, $amount) {
            /** @var Settlement $settlement */
            $settlement = Settlement::query()->create([
                'creditor_user_id' => $creditor->id,
                'debtor_user_id' => $debtor->id,
                'contact_id' => $splits->first()->contact_id,
                'amount' => $amount,
                'paid_on' => $date,
                'from_account_id' => $account->id,
                'status' => 'pending',
            ]);

            TransactionSplit::query()->whereIn('id', $splits->pluck('id'))->update(['settlement_id' => $settlement->id]);

            // Sai da conta de quem pagou (não é despesa: a despesa já está lançada).
            $this->accounts->applyTransaction($account->id, $amount, 'expense');

            return $settlement;
        });

        $creditor->notify(new ActivityNotification(
            'settlement',
            "{$debtor->name} pagou ".$this->money($amount),
            'Confirme o recebimento do acerto no card "A receber".',
            route('dashboard'),
        ));

        return $settlement;
    }

    public function confirm(User $creditor, Settlement $settlement, string $toAccountId): void
    {
        $this->ensureCreditor($creditor, $settlement);
        $this->ensurePending($settlement);

        $account = $this->moneyAccount($creditor, $toAccountId, 'to_account_id');

        DB::transaction(function () use ($settlement, $account) {
            foreach ($settlement->splits()->get() as $split) {
                $split->forceFill([
                    'reimbursed_at' => $settlement->paid_on->toDateString(),
                    'reimbursement_account_id' => $account->id,
                    'reimbursed_amount' => $split->amount,
                ])->save();
            }

            $this->accounts->applyTransaction($account->id, (float) $settlement->amount, 'income');

            $settlement->forceFill([
                'status' => 'confirmed',
                'to_account_id' => $account->id,
                'confirmed_at' => now(),
            ])->save();
        });

        User::query()->find($settlement->debtor_user_id)?->notify(new ActivityNotification(
            'settlement',
            "{$creditor->name} confirmou seu pagamento",
            'Acerto de '.$this->money((float) $settlement->amount).' confirmado.',
            route('dashboard'),
        ));
    }

    public function reject(User $creditor, Settlement $settlement): void
    {
        $this->ensureCreditor($creditor, $settlement);
        $this->ensurePending($settlement);

        $this->undoPayment($settlement, 'rejected');

        User::query()->find($settlement->debtor_user_id)?->notify(new ActivityNotification(
            'settlement',
            "{$creditor->name} não confirmou o pagamento",
            'O acerto de '.$this->money((float) $settlement->amount).' voltou para "a pagar" e o valor voltou para a sua conta.',
            route('dashboard'),
        ));
    }

    public function cancel(User $debtor, Settlement $settlement): void
    {
        if ($settlement->debtor_user_id !== $debtor->id) {
            abort(404);
        }
        $this->ensurePending($settlement);

        $this->undoPayment($settlement, 'rejected');
    }

    public function undo(User $user, TransactionSplit $split): void
    {
        $ownerId = Transaction::query()->whereKey($split->transaction_id)->value('user_id');

        if ($ownerId !== $user->id) {
            abort(404);
        }

        // Acerto entre usuários: desfaz a confirmação (o pagamento de quem deve continua informado).
        if ($split->settlement_id !== null) {
            $settlement = Settlement::query()->find($split->settlement_id);

            if ($settlement !== null && $settlement->status === 'confirmed') {
                DB::transaction(function () use ($settlement) {
                    foreach ($settlement->splits()->get() as $s) {
                        $this->revertBalance($s);
                        $s->forceFill(['reimbursed_at' => null, 'reimbursement_account_id' => null, 'reimbursed_amount' => null])->save();
                    }

                    $settlement->forceFill(['status' => 'pending', 'to_account_id' => null, 'confirmed_at' => null])->save();
                });
            }

            return;
        }

        if ($split->reimbursed_at === null) {
            return;
        }

        DB::transaction(function () use ($split) {
            $this->revertBalance($split);

            $split->forceFill([
                'reimbursed_at' => null,
                'reimbursement_account_id' => null,
                'reimbursed_amount' => null,
            ])->save();
        });
    }

    public function revertFor(Transaction $transaction): void
    {
        $splits = TransactionSplit::query()
            ->where('transaction_id', $transaction->id)
            ->where(fn ($q) => $q->whereNotNull('reimbursed_at')->orWhereNotNull('settlement_id'))
            ->get();

        foreach ($splits as $split) {
            // O que entrou na conta de quem recebe sai.
            $this->revertBalance($split);

            if ($split->settlement_id === null) {
                continue;
            }

            // O que saiu da conta de quem pagou volta, e o acerto diminui.
            $settlement = Settlement::query()->find($split->settlement_id);
            if ($settlement === null) {
                continue;
            }

            $amount = (float) ($split->reimbursed_amount ?? $split->amount);

            if ($settlement->from_account_id !== null) {
                $this->accounts->revertTransaction($settlement->from_account_id, $amount, 'expense');
            }

            $remaining = round((float) $settlement->amount - $amount, 2);
            $remaining > 0
                ? $settlement->forceFill(['amount' => $remaining])->save()
                : $settlement->delete();
        }
    }

    /**
     * Totais e itens de um grupo de partes em aberto.
     *
     * @param  Collection<int, TransactionSplit>  $splits
     * @return array<string, mixed>
     */
    private function summary(Collection $splits, string $current): array
    {
        $items = $splits
            ->map(function (TransactionSplit $s) use ($current) {
                $t = $s->transaction;
                $month = Acerto::monthOf($t->date, $t->invoice?->due_date);

                return [
                    'id' => $s->id,
                    'transaction_id' => $t->id,
                    'name' => $t->name,
                    'date' => $t->date->toDateString(),
                    'amount' => (float) $s->amount,
                    'month' => $month,
                    'group' => Acerto::group($month, $current),
                    'on_card' => $t->invoice_id !== null,
                ];
            })
            ->sortBy([['month', 'asc'], ['date', 'asc']])
            ->values();

        return [
            'overdue_total' => round((float) $items->where('group', 'overdue')->sum('amount'), 2),
            'current_total' => round((float) $items->where('group', 'current')->sum('amount'), 2),
            'current_month' => $current,
            'current_deadline' => Acerto::deadline($current)->toDateString(),
            'items' => $items->all(),
        ];
    }

    /** @return array<string, mixed> */
    private function settlementData(Settlement $s): array
    {
        return [
            'id' => $s->id,
            'amount' => (float) $s->amount,
            'paid_on' => $s->paid_on->toDateString(),
            'count' => (int) $s->getAttribute('splits_count'),
        ];
    }

    /** @return list<string> */
    private function itemRelations(): array
    {
        return [
            'transaction:id,user_id,name,date,invoice_id',
            'transaction.invoice:id,due_date',
        ];
    }

    private function undoPayment(Settlement $settlement, string $status): void
    {
        DB::transaction(function () use ($settlement, $status) {
            if ($settlement->from_account_id !== null) {
                $this->accounts->revertTransaction($settlement->from_account_id, (float) $settlement->amount, 'expense');
            }

            TransactionSplit::query()->where('settlement_id', $settlement->id)->update(['settlement_id' => null]);

            $settlement->forceFill(['status' => $status])->save();
        });
    }

    private function revertBalance(TransactionSplit $split): void
    {
        if ($split->reimbursement_account_id !== null && $split->reimbursed_amount !== null) {
            $this->accounts->revertTransaction($split->reimbursement_account_id, (float) $split->reimbursed_amount, 'income');
        }
    }

    private function moneyAccount(User $user, string $accountId, string $field): Account
    {
        $account = Account::query()->where('user_id', $user->id)->whereKey($accountId)->first();

        if ($account === null || $account->type === 'credit') {
            throw ValidationException::withMessages([$field => 'Escolha uma conta (cartão de crédito não serve).']);
        }

        return $account;
    }

    /**
     * @param  Collection<int, TransactionSplit>  $splits
     * @param  list<string>  $splitIds
     */
    private function ensureAll(Collection $splits, array $splitIds): void
    {
        if ($splits->isEmpty() || $splits->count() !== count(array_unique($splitIds))) {
            throw ValidationException::withMessages(['split_ids' => 'Escolha os itens do acerto que foram pagos.']);
        }
    }

    private function ensureCreditor(User $user, Settlement $settlement): void
    {
        if ($settlement->creditor_user_id !== $user->id) {
            abort(404);
        }
    }

    private function ensurePending(Settlement $settlement): void
    {
        if ($settlement->status !== 'pending') {
            throw ValidationException::withMessages(['settlement' => 'Este pagamento já foi resolvido.']);
        }
    }

    private function money(float $value): string
    {
        return 'R$ '.number_format($value, 2, ',', '.');
    }

    /**
     * Partes em aberto cobradas no acerto (despesas pagas por quem criou).
     *
     * @return Builder<TransactionSplit>
     */
    private function openQuery(): Builder
    {
        return TransactionSplit::query()
            ->select('transaction_splits.*')
            ->join('transactions', 'transactions.id', '=', 'transaction_splits.transaction_id')
            ->where('transactions.type', 'expense')
            ->whereNull('transactions.paid_by_contact_id')
            ->whereNull('transactions.mirrored_from_id')
            ->whereNotNull('transaction_splits.contact_id')
            ->where('transaction_splits.tracked', true)
            ->where('transaction_splits.amount', '>', 0)
            ->whereNull('transaction_splits.reimbursed_at')
            ->orderBy('transactions.date');
    }

    /**
     * Partes em aberto que você (usuário vinculado) deve, de divisões que você aceitou.
     *
     * @return Builder<TransactionSplit>
     */
    private function payableQuery(string $debtorId): Builder
    {
        return $this->openQuery()
            ->join('contacts', 'contacts.id', '=', 'transaction_splits.contact_id')
            ->where('contacts.linked_user_id', $debtorId)
            ->whereExists(fn ($q) => $q
                ->selectRaw('1')
                ->from('share_links')
                ->join('shares', 'shares.id', '=', 'share_links.share_id')
                ->whereColumn('share_links.source_transaction_id', 'transactions.id')
                ->where('shares.recipient_user_id', $debtorId)
                ->where('shares.status', 'accepted'));
    }
}
