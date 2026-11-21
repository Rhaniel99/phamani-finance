<?php

namespace App\Services;

use App\DTOs\Transaction\StoreTransactionData;
use App\Interfaces\Repositories\IRecurringTransactionRepository;
use App\Interfaces\Repositories\ITransactionRepository;
use App\Interfaces\Services\IBalanceService;
use App\Interfaces\Services\IRecurringTransactionService;
use App\Interfaces\Services\ISplitService;
use App\Interfaces\Services\ITagService;
use App\Models\RecurringTransaction;
use App\Models\Transaction;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;

class RecurringTransactionService implements IRecurringTransactionService
{
    public function __construct(
        protected IRecurringTransactionRepository $recurrings,
        protected ITransactionRepository $transactions,
        protected IBalanceService $balance,
        protected ISplitService $splits,
        protected ITagService $tags,
    ) {}

    public function createRecurringTransaction(string $userId, StoreTransactionData $dto): RecurringTransaction
    {
        return DB::transaction(function () use ($userId, $dto) {
            $frequency = $dto->frequency;
            $date = CarbonImmutable::parse($dto->date);
            $parts = $this->splits->compute($dto->amount, $dto->split);
            $accountId = $parts['paid_by_contact_id'] === null ? $dto->account_id : null;

            /** @var RecurringTransaction $recurring */
            $recurring = $this->recurrings->create([
                'user_id' => $userId,
                'account_id' => $accountId,
                'category_id' => $dto->category_id,
                'name' => $dto->description,
                'amount' => $parts['amount'],
                'type' => $dto->type,
                'frequency' => $frequency,
                'auto_pay' => $dto->auto_pay,
                'anchor_date' => $date->toDateString(),
                'next_run' => $frequency->nth($date, 1)->toDateString(),
            ]);

            // Primeira ocorrência
            /** @var Transaction $first */
            $first = $this->transactions->create([
                'user_id' => $userId,
                'account_id' => $accountId,
                'category_id' => $dto->category_id,
                'recurring_id' => $recurring->id,
                'name' => $dto->description,
                'description' => $dto->description,
                'type' => $dto->type,
                'amount' => $parts['amount'],
                'total_amount' => $parts['total_amount'],
                'paid_by_contact_id' => $parts['paid_by_contact_id'],
                'date' => $date->toDateString(),
            ]);

            $this->splits->sync($first, $parts['shares']);

            $this->balance->applyIfDue($first);

            // Se a 1ª data ficou no passado, já gera as ocorrências que faltam até hoje
            // (como é histórico que você está lançando agora, entram como pagas).
            $this->generateDue($recurring, markPaid: true);

            return $recurring;
        });
    }

    public function generateDue(RecurringTransaction $recurring, bool $markPaid = false): int
    {
        $today = now()->toDateString();
        $created = 0;

        while ($this->shouldRun($recurring, $today)) {
            DB::transaction(function () use ($recurring, $markPaid) {
                $runDate = $recurring->next_run->toImmutable();

                // "Último valor": conta, categoria, nome, valor, divisão e quem pagou seguem a ocorrência
                // mais recente, então uma correção feita num mês vira a base do mês seguinte.
                $last = Transaction::query()
                    ->where('recurring_id', $recurring->id)
                    ->orderByDesc('date')
                    ->orderByDesc('created_at')
                    ->first();

                $amount = $last !== null ? (float) $last->amount : (float) $recurring->amount;

                /** @var Transaction $occurrence */
                $occurrence = $this->transactions->create([
                    'user_id' => $recurring->user_id,
                    'account_id' => $last !== null ? $last->account_id : $recurring->account_id,
                    'category_id' => $last->category_id ?? $recurring->category_id,
                    'recurring_id' => $recurring->id,
                    'name' => $last->name ?? $recurring->name,
                    'description' => $last->description ?? $recurring->name,
                    'type' => $last->type ?? $recurring->type,
                    'amount' => $amount,
                    'total_amount' => $last?->total_amount,
                    'paid_by_contact_id' => $last?->paid_by_contact_id,
                    'date' => $runDate->toDateString(),
                    // Lançada no vencimento: pendente até alguém pagar (ou paga, com débito automático).
                    'paid_at' => $markPaid || $recurring->auto_pay ? $runDate->toDateString() : null,
                ]);

                if ($last !== null) {
                    $this->splits->copy($last, $occurrence);
                    $this->tags->copy($last, $occurrence);
                }

                $this->balance->applyIfDue($occurrence);

                $anchor = ($recurring->anchor_date ?? $runDate)->toImmutable();

                $recurring->forceFill([
                    'amount' => $amount,
                    'next_run' => $recurring->frequency->nextFromAnchor($anchor, $runDate)->toDateString(),
                ])->save();
            });

            $created++;
        }

        return $created;
    }

    public function generateAllDue(): int
    {
        $created = 0;

        RecurringTransaction::query()
            ->whereDate('next_run', '<=', now()->toDateString())
            ->where(fn ($q) => $q->whereNull('end_date')->orWhereColumn('end_date', '>=', 'next_run'))
            ->lazyById()
            ->each(function (RecurringTransaction $recurring) use (&$created) {
                $created += $this->generateDue($recurring);
            });

        return $created;
    }

    public function end(RecurringTransaction $recurring): void
    {
        $recurring->forceFill(['end_date' => now()->toDateString()])->save();
    }

    private function shouldRun(RecurringTransaction $recurring, string $today): bool
    {
        $next = $recurring->next_run->toDateString();

        if ($next > $today) {
            return false;
        }

        return $recurring->end_date === null || $next <= $recurring->end_date->toDateString();
    }
}
