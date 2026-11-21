<?php

namespace App\Services;

use App\Interfaces\Repositories\IAccountRepository;
use App\Interfaces\Services\IReimbursementService;
use App\Models\Account;
use App\Models\Contact;
use App\Models\Transaction;
use App\Models\TransactionSplit;
use App\Models\User;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class ReimbursementService implements IReimbursementService
{
    public function __construct(
        protected IAccountRepository $accounts,
    ) {}

    public function openForUser(string $userId): array
    {
        $today = now()->toDateString();

        return $this->openQuery($userId)
            ->with([
                'transaction:id,name,date',
                'contact:id,name,linked_user_id',
                'contact.linkedUser:id,avatar',
            ])
            ->get()
            ->groupBy('contact_id')
            ->map(function ($splits) use ($today) {
                /** @var TransactionSplit $first */
                $first = $splits->first();

                $items = $splits->map(fn (TransactionSplit $s) => [
                    'id' => $s->id,
                    'transaction_id' => $s->transaction_id,
                    'name' => $s->transaction->name,
                    'date' => $s->transaction->date->toDateString(),
                    'amount' => (float) $s->amount,
                    'due' => $s->transaction->date->toDateString() <= $today,
                ])->values();

                $due = $items->where('due', true);

                return [
                    'contact' => [
                        'id' => $first->contact->id,
                        'name' => $first->contact->name,
                        'avatar' => $first->contact->linkedUser?->avatar,
                    ],
                    'due_total' => round((float) $due->sum('amount'), 2),
                    'due_count' => $due->count(),
                    'items' => $items->all(),
                ];
            })
            ->sortByDesc('due_total')
            ->values()
            ->all();
    }

    public function receive(User $user, Contact $contact, array $splitIds, string $accountId, string $date): void
    {
        if ($contact->user_id !== $user->id) {
            abort(404);
        }

        $account = Account::query()->where('user_id', $user->id)->whereKey($accountId)->first();

        if ($account === null || $account->type === 'credit') {
            throw ValidationException::withMessages(['account_id' => 'Escolha a conta onde o dinheiro caiu (cartão não serve).']);
        }

        $splits = $this->openQuery($user->id)
            ->where('transaction_splits.contact_id', $contact->id)
            ->whereIn('transaction_splits.id', $splitIds)
            ->get();

        if ($splits->isEmpty() || $splits->count() !== count(array_unique($splitIds))) {
            throw ValidationException::withMessages(['split_ids' => 'Escolha as compras que foram pagas.']);
        }

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

    public function undo(User $user, TransactionSplit $split): void
    {
        $ownerId = Transaction::query()->whereKey($split->transaction_id)->value('user_id');

        if ($ownerId !== $user->id) {
            abort(404);
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
        TransactionSplit::query()
            ->where('transaction_id', $transaction->id)
            ->whereNotNull('reimbursed_at')
            ->get()
            ->each(fn (TransactionSplit $split) => $this->revertBalance($split));
    }

    private function revertBalance(TransactionSplit $split): void
    {
        if ($split->reimbursement_account_id !== null && $split->reimbursed_amount !== null) {
            $this->accounts->revertTransaction($split->reimbursement_account_id, (float) $split->reimbursed_amount, 'income');
        }
    }

    /**
     * Partes em aberto de compras feitas por você para outras pessoas (sua parte = 0).
     *
     * @return Builder<TransactionSplit>
     */
    private function openQuery(string $userId): Builder
    {
        return TransactionSplit::query()
            ->select('transaction_splits.*')
            ->join('transactions', 'transactions.id', '=', 'transaction_splits.transaction_id')
            ->where('transactions.user_id', $userId)
            ->where('transactions.type', 'expense')
            ->whereNull('transactions.paid_by_contact_id')
            ->whereNull('transactions.mirrored_from_id')
            ->whereNotNull('transactions.total_amount')
            ->where('transactions.amount', 0)
            ->whereNotNull('transaction_splits.contact_id')
            ->where('transaction_splits.amount', '>', 0)
            ->whereNull('transaction_splits.reimbursed_at')
            ->orderBy('transactions.date')
            ->orderBy('transactions.created_at');
    }
}
