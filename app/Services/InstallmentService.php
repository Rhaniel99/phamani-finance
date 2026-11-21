<?php

namespace App\Services;

use App\DTOs\Transaction\SplitData;
use App\DTOs\Transaction\StoreTransactionData;
use App\Interfaces\Repositories\IInstallmentRepository;
use App\Interfaces\Repositories\ITransactionRepository;
use App\Interfaces\Services\IBalanceService;
use App\Interfaces\Services\IInstallmentService;
use App\Interfaces\Services\IReimbursementService;
use App\Interfaces\Services\IShareService;
use App\Interfaces\Services\ISplitService;
use App\Models\Installment;
use App\Models\Transaction;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;

class InstallmentService implements IInstallmentService
{
    public function __construct(
        protected IInstallmentRepository $installments,
        protected ITransactionRepository $transactions,
        protected IBalanceService $balance,
        protected ISplitService $splits,
        protected IShareService $shares,
        protected IReimbursementService $reimbursements,
    ) {}

    /**
     * Cria as parcelas de `installment_start` até `installments_count`.
     * Ex.: empréstimo já na 15/24 → cria 15/24 … 24/24, a 15ª na data informada.
     *
     * `amount_mode`:
     *  - installment: o valor informado é o de cada parcela (padrão no formulário);
     *  - total: o valor informado é o da COMPRA INTEIRA, dividido pelo nº de parcelas.
     *    Começando de uma parcela > 1, lança só as que faltam com esse mesmo valor
     *    ("R$ 625 em 4x, já na 3ª" → 3/4 e 4/4 de R$ 156,25).
     */
    public function createInstallment(string $userId, StoreTransactionData $dto): Installment
    {
        return DB::transaction(function () use ($userId, $dto) {
            $count = (int) $dto->installments_count;
            $startNumber = max(1, min($dto->installment_start, $count));
            $remaining = $count - $startNumber + 1;
            $start = CarbonImmutable::parse($dto->date);

            if ($dto->amount_mode === 'installment') {
                $amounts = array_fill(0, $remaining, round($dto->amount, 2));
                $totalAmount = round($dto->amount * $count, 2);
            } else {
                $amounts = array_slice($this->splitAmount($dto->amount, $count), $startNumber - 1);
                $totalAmount = $dto->amount;
            }

            /** @var Installment $installment */
            $installment = $this->installments->create([
                'user_id' => $userId,
                'name' => $dto->description,
                'total_amount' => $totalAmount,
                'installment_amount' => $amounts[0],
                'installments' => $count,
                'start_date' => $start->toDateString(),
                'end_date' => $start->addMonthsNoOverflow($remaining - 1)->toDateString(),
                'status' => 'active',
                'auto_pay' => $dto->auto_pay,
            ]);

            foreach ($amounts as $index => $amount) {
                $number = $startNumber + $index;

                // Divisão: cada parcela é dividida na mesma proporção.
                $parts = $this->splits->compute($amount, $dto->split);

                /** @var Transaction $parcel */
                $parcel = $this->transactions->create([
                    'user_id' => $userId,
                    'account_id' => $parts['paid_by_contact_id'] === null ? $dto->account_id : null,
                    'category_id' => $dto->category_id,
                    'installment_id' => $installment->id,
                    'installment_number' => $number,
                    'name' => "{$installment->name} ({$number}/{$count})",
                    'description' => $installment->name,
                    'type' => $dto->type,
                    'amount' => $parts['amount'],
                    'total_amount' => $parts['total_amount'],
                    'paid_by_contact_id' => $parts['paid_by_contact_id'],
                    'date' => $start->addMonthsNoOverflow($index)->toDateString(),
                ]);

                $this->splits->sync($parcel, $parts['shares'], $parts['tracked']);

                // Cada parcela entra no saldo quando a sua data chega.
                $this->balance->applyIfDue($parcel);
            }

            return $installment;
        });
    }

    public function updateFollowingParcels(Transaction $parcel, float $amount, ?SplitData $split = null): void
    {
        DB::transaction(function () use ($parcel, $amount, $split) {
            $following = Transaction::query()
                ->where('installment_id', $parcel->installment_id)
                ->where('installment_number', '>', $parcel->installment_number)
                ->get();

            foreach ($following as $next) {
                $this->balance->revert($next);

                $parts = $this->splits->compute($amount, $split);
                $next->update([
                    'account_id' => $parts['paid_by_contact_id'] === null ? $parcel->account_id : null,
                    'amount' => $parts['amount'],
                    'total_amount' => $parts['total_amount'],
                    'paid_by_contact_id' => $parts['paid_by_contact_id'],
                ]);
                $this->splits->sync($next, $parts['shares'], $parts['tracked']);

                $this->balance->applyIfDue($next);
            }

            $this->installments->update((string) $parcel->installment_id, [
                'installment_amount' => $amount,
            ]);
        });
    }

    public function deleteInstallment(Installment $installment): void
    {
        DB::transaction(function () use ($installment) {
            foreach ($installment->transactions()->get() as $parcel) {
                $this->shares->removeFor($parcel);
                $this->balance->revert($parcel);
                $this->reimbursements->revertFor($parcel);
            }

            $this->transactions->deleteByInstallment($installment->id);
            $this->installments->delete($installment->id);
        });
    }

    /**
     * Divide o total em parcelas de 2 casas decimais; a diferença de arredondamento
     * vai para a última parcela, de forma que a soma bata exatamente com o total.
     *
     * @return list<float>
     */
    private function splitAmount(float $total, int $count): array
    {
        $totalCents = (int) round($total * 100);
        $baseCents = intdiv($totalCents, $count);

        $amounts = array_fill(0, $count, $baseCents / 100);
        $amounts[$count - 1] = ($totalCents - $baseCents * ($count - 1)) / 100;

        return $amounts;
    }
}
