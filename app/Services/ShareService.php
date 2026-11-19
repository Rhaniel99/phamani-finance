<?php

namespace App\Services;

use App\Interfaces\Services\IBalanceService;
use App\Interfaces\Services\IShareService;
use App\Models\Contact;
use App\Models\Share;
use App\Models\ShareLink;
use App\Models\Transaction;
use App\Models\TransactionSplit;
use App\Models\User;
use App\Notifications\ActivityNotification;
use Illuminate\Support\Facades\DB;

class ShareService implements IShareService
{
    public function __construct(
        protected IBalanceService $balance,
    ) {}

    public function syncFor(Transaction $source): void
    {
        // Cópias não são compartilhadas de novo.
        if ($source->isMirror()) {
            return;
        }

        $splits = TransactionSplit::query()
            ->with('contact:id,user_id,name,linked_user_id')
            ->where('transaction_id', $source->id)
            ->get();

        $participantContactIds = $splits->pluck('contact_id')->filter()->values()->all();

        // Quem saiu da divisão perde a cópia.
        $links = ShareLink::query()->with('share')->where('source_transaction_id', $source->id)->get();
        foreach ($links as $link) {
            if (! in_array($link->share->owner_contact_id, $participantContactIds, true)) {
                $this->dropLink($link);
            }
        }

        [$sourceType, $sourceId] = $this->seriesKey($source);

        foreach ($splits as $split) {
            $contact = $split->contact;

            if ($contact === null || $contact->linked_user_id === null || $contact->user_id !== $source->user_id) {
                continue;
            }

            /** @var Share $share */
            $share = Share::query()->firstOrCreate(
                [
                    'recipient_user_id' => $contact->linked_user_id,
                    'source_type' => $sourceType,
                    'source_id' => $sourceId,
                ],
                [
                    'owner_user_id' => $source->user_id,
                    'owner_contact_id' => $contact->id,
                    'status' => 'pending',
                ],
            );

            if ($share->wasRecentlyCreated || $share->status === 'removed') {
                if ($share->status === 'removed') {
                    $share->update(['status' => 'pending']);
                }

                $this->notifyRequested($share, $source);
            }

            // Recusou ou saiu: as próximas ocorrências da série também não chegam.
            if (in_array($share->status, ['declined', 'left'], true)) {
                continue;
            }

            /** @var ShareLink $link */
            $link = ShareLink::query()->firstOrCreate([
                'share_id' => $share->id,
                'source_transaction_id' => $source->id,
            ]);

            if ($share->status === 'accepted') {
                $this->upsertMirror($link, $share, $source, (float) $split->amount);
            }
        }
    }

    public function shareUpcomingWith(Contact $contact): int
    {
        if ($contact->linked_user_id === null) {
            return 0;
        }

        $count = 0;

        Transaction::query()
            ->where('user_id', $contact->user_id)
            ->whereNull('mirrored_from_id')
            ->whereDate('date', '>=', now()->startOfMonth()->toDateString())
            ->whereHas('splits', fn ($q) => $q->where('contact_id', $contact->id))
            ->orderBy('date')
            ->get()
            ->each(function (Transaction $transaction) use (&$count) {
                $this->syncFor($transaction);
                $count++;
            });

        return $count;
    }

    public function removeFor(Transaction $source): void
    {
        foreach (ShareLink::query()->with('share')->where('source_transaction_id', $source->id)->get() as $link) {
            $this->dropLink($link);
        }
    }

    public function accept(Share $share, User $user, string $categoryId, ?string $accountId): void
    {
        $this->ensureRecipient($share, $user);

        DB::transaction(function () use ($share, $categoryId, $accountId) {
            $share->update([
                'status' => 'accepted',
                'category_id' => $categoryId,
                'account_id' => $accountId,
                'responded_at' => now(),
            ]);

            foreach ($share->links()->with('source')->get() as $link) {
                $source = $link->source;
                if ($source === null) {
                    continue;
                }

                $amount = TransactionSplit::query()
                    ->where('transaction_id', $source->id)
                    ->where('contact_id', $share->owner_contact_id)
                    ->value('amount');

                if ($amount !== null) {
                    $this->upsertMirror($link, $share, $source, (float) $amount);
                }
            }
        });

        $this->notifyOwner($share, 'share_accepted', 'Divisão aceita', 'aceitou a divisão');
    }

    public function decline(Share $share, User $user): void
    {
        $this->ensureRecipient($share, $user);

        $share->update(['status' => 'declined', 'responded_at' => now()]);

        $this->notifyOwner($share, 'share_declined', 'Divisão recusada', 'recusou a divisão');
    }

    public function leave(Share $share, User $user): void
    {
        $this->ensureRecipient($share, $user);

        DB::transaction(function () use ($share) {
            foreach ($share->links()->get() as $link) {
                $this->deleteMirror($link);
            }

            $share->update(['status' => 'left', 'responded_at' => now()]);
        });

        $this->notifyOwner($share, 'share_left', 'Saiu da divisão', 'saiu da divisão');
    }

    public function pendingFor(User $user): array
    {
        return $this->summaries($user, ['pending']);
    }

    public function acceptedFor(User $user): array
    {
        return $this->summaries($user, ['accepted']);
    }

    /**
     * @param  list<string>  $statuses
     * @return list<array<string, mixed>>
     */
    private function summaries(User $user, array $statuses): array
    {
        $shares = Share::query()
            ->with('owner:id,name,avatar')
            ->where('recipient_user_id', $user->id)
            ->whereIn('status', $statuses)
            ->latest()
            ->get();

        return $shares->map(function (Share $share) {
            $links = $share->links()->with('source:id,name,description,date,total_amount,paid_by_contact_id,type')->get()
                ->filter(fn (ShareLink $l) => $l->source !== null)
                ->sortBy(fn (ShareLink $l) => $l->source->date->toDateString())
                ->values();

            /** @var ShareLink|null $latest */
            $latest = $links->last();
            $source = $latest?->source;

            $myAmount = $source !== null
                ? (float) TransactionSplit::query()
                    ->where('transaction_id', $source->id)
                    ->where('contact_id', $share->owner_contact_id)
                    ->value('amount')
                : 0.0;

            $payerName = null;
            if ($source !== null) {
                $payerName = match (true) {
                    $source->paid_by_contact_id === null => $share->owner->name,
                    $source->paid_by_contact_id === $share->owner_contact_id => 'Você',
                    default => Contact::query()->whereKey($source->paid_by_contact_id)->value('name'),
                };
            }

            return [
                'id' => $share->id,
                'status' => $share->status,
                'source_type' => $share->source_type,
                'owner' => ['id' => $share->owner->id, 'name' => $share->owner->name, 'avatar' => $share->owner->avatar],
                'name' => $source?->description ?? $source?->name,
                'date' => $source?->date->toDateString(),
                'total' => $source?->total_amount !== null ? (float) $source->total_amount : null,
                'my_amount' => $myAmount,
                'paid_by' => $payerName,
                'you_paid' => $source !== null && $source->paid_by_contact_id === $share->owner_contact_id,
                'items' => $links->count(),
                'category_id' => $share->category_id,
                'account_id' => $share->account_id,
            ];
        })->values()->all();
    }

    /**
     * Cria ou atualiza a cópia da transação no sistema de quem aceitou.
     */
    private function upsertMirror(ShareLink $link, Share $share, Transaction $source, float $amount): void
    {
        DB::transaction(function () use ($link, $share, $source, $amount) {
            // Contato de quem recebe que representa o dono (criado ao aceitar o convite).
            $ownerAsContact = Contact::query()
                ->where('user_id', $share->recipient_user_id)
                ->where('linked_user_id', $share->owner_user_id)
                ->value('id');

            // Se quem recebe foi quem pagou, sai da conta que ele escolheu ao aceitar.
            $recipientPaid = $source->paid_by_contact_id === $share->owner_contact_id;

            $attributes = [
                'user_id' => $share->recipient_user_id,
                'account_id' => $recipientPaid ? $share->account_id : null,
                'category_id' => $share->category_id,
                'name' => $source->name,
                'description' => $source->description,
                'type' => $source->type,
                'amount' => $amount,
                'total_amount' => $source->total_amount,
                'paid_by_contact_id' => $recipientPaid ? null : $ownerAsContact,
                'date' => $source->date->toDateString(),
                // O status é de quem pagou e vale para todos da divisão.
                'paid_at' => $source->paid_at?->toDateString(),
                'mirrored_from_id' => $source->id,
            ];

            $mirror = $link->mirror_transaction_id !== null
                ? Transaction::query()->find($link->mirror_transaction_id)
                : null;

            if ($mirror !== null) {
                $this->balance->revert($mirror);
                $mirror->update($attributes);
                $mirror->refresh();
            } else {
                /** @var Transaction $mirror */
                $mirror = Transaction::query()->create($attributes);
                $link->update(['mirror_transaction_id' => $mirror->id]);
            }

            $this->balance->applyIfDue($mirror);
        });
    }

    private function deleteMirror(ShareLink $link): void
    {
        if ($link->mirror_transaction_id === null) {
            return;
        }

        $mirror = Transaction::query()->find($link->mirror_transaction_id);

        if ($mirror !== null) {
            $this->balance->revert($mirror);
            $mirror->delete();
        }

        $link->update(['mirror_transaction_id' => null]);
    }

    private function dropLink(ShareLink $link): void
    {
        DB::transaction(function () use ($link) {
            $share = $link->share;
            $hadMirror = $link->mirror_transaction_id !== null;

            $this->deleteMirror($link);
            $link->delete();

            // Série sem nenhuma transação: o compartilhamento acabou.
            if (! $share->links()->exists() && $share->status !== 'removed') {
                $wasActive = in_array($share->status, ['pending', 'accepted'], true);
                $share->update(['status' => 'removed']);

                if ($wasActive || $hadMirror) {
                    User::query()->find($share->recipient_user_id)?->notify(new ActivityNotification(
                        'share_removed',
                        'Divisão removida',
                        User::query()->whereKey($share->owner_user_id)->value('name').' removeu uma divisão com você.',
                    ));
                }
            }
        });
    }

    /**
     * Série a que a transação pertence: recorrência, parcelamento ou ela mesma.
     *
     * @return array{0: string, 1: string}
     */
    private function seriesKey(Transaction $source): array
    {
        return match (true) {
            $source->recurring_id !== null => ['recurring', $source->recurring_id],
            $source->installment_id !== null => ['installment', $source->installment_id],
            default => ['transaction', $source->id],
        };
    }

    private function notifyRequested(Share $share, Transaction $source): void
    {
        $owner = User::query()->whereKey($share->owner_user_id)->value('name');
        $what = match ($share->source_type) {
            'recurring' => 'uma despesa recorrente',
            'installment' => 'um parcelamento',
            default => 'uma despesa',
        };

        User::query()->find($share->recipient_user_id)?->notify(new ActivityNotification(
            'share_requested',
            'Nova divisão',
            "{$owner} dividiu {$what} com você: ".($source->description ?? $source->name).'.',
            route('inbox'),
        ));
    }

    private function notifyOwner(Share $share, string $kind, string $title, string $verb): void
    {
        $recipient = User::query()->whereKey($share->recipient_user_id)->value('name');

        User::query()->find($share->owner_user_id)?->notify(new ActivityNotification(
            $kind,
            $title,
            "{$recipient} {$verb}.",
        ));
    }

    private function ensureRecipient(Share $share, User $user): void
    {
        abort_unless($share->recipient_user_id === $user->id, 404);
    }
}
