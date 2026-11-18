<?php

namespace App\Services;

use App\DTOs\Transaction\StoreTransactionData;
use App\Interfaces\Repositories\IAccountRepository;
use App\Interfaces\Repositories\IInstallmentRepository;
use App\Interfaces\Repositories\ITransactionRepository;
use App\Interfaces\Services\IInstallmentService;
use App\Models\Installment;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;

class InstallmentService implements IInstallmentService
{
    public function __construct(
        protected IInstallmentRepository $installments,
        protected ITransactionRepository $transactions,
        protected IAccountRepository $accounts,
    ) {}

    public function createInstallment(string $userId, StoreTransactionData $dto): Installment
    {
        return DB::transaction(function () use ($userId, $dto) {
            $count = (int) $dto->installments_count;
            $start = CarbonImmutable::parse($dto->date);
            $amounts = $this->splitAmount($dto->amount, $count);

            /** @var Installment $installment */
            $installment = $this->installments->create([
                'user_id' => $userId,
                'name' => $dto->description,
                'total_amount' => $dto->amount,
                'installment_amount' => $amounts[0],
                'installments' => $count,
                'start_date' => $start->toDateString(),
                'end_date' => $start->addMonthsNoOverflow($count - 1)->toDateString(),
                'status' => 'active',
            ]);

            foreach ($amounts as $index => $amount) {
                $number = $index + 1;

                $this->transactions->create([
                    'user_id' => $userId,
                    'account_id' => $dto->account_id,
                    'category_id' => $dto->category_id,
                    'installment_id' => $installment->id,
                    'installment_number' => $number,
                    'name' => "{$installment->name} ({$number}/{$count})",
                    'description' => $installment->name,
                    'type' => $dto->type,
                    'amount' => $amount,
                    'date' => $start->addMonthsNoOverflow($index)->toDateString(),
                ]);
            }

            // Assim como no Lukisa: apenas a primeira parcela afeta o saldo na criação.
            $this->accounts->applyTransaction($dto->account_id, $amounts[0], $dto->type);

            return $installment;
        });
    }

    public function deleteInstallment(Installment $installment): void
    {
        DB::transaction(function () use ($installment) {
            // Só a 1ª parcela entrou no saldo (ver createInstallment).
            $first = $installment->transactions()->where('installment_number', 1)->first();

            if ($first !== null) {
                $this->accounts->revertTransaction($first->account_id, (float) $first->amount, $first->type);
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
