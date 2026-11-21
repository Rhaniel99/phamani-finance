<?php

namespace App\Services;

use App\DTOs\Transaction\SplitData;
use App\DTOs\Transaction\SplitParticipantData;
use App\Interfaces\Services\IShareService;
use App\Interfaces\Services\ISplitService;
use App\Models\Transaction;
use App\Models\TransactionSplit;
use Illuminate\Validation\ValidationException;

class SplitService implements ISplitService
{
    private const ME = 'me';

    public function __construct(
        protected IShareService $shares,
    ) {}

    public function validate(?SplitData $split, float $amount, string $type): void
    {
        if ($split === null) {
            return;
        }

        if ($type !== 'expense') {
            throw ValidationException::withMessages(['split' => 'Só dá para dividir despesas.']);
        }

        $contacts = $split->contactIds();

        if ($contacts === []) {
            throw ValidationException::withMessages(['split.participants' => 'Escolha pelo menos um contato para dividir.']);
        }

        if (count($contacts) !== count(array_unique($contacts))) {
            throw ValidationException::withMessages(['split.participants' => 'Há um contato repetido na divisão.']);
        }

        if (! $split->include_me && $split->paid_by_contact_id !== null) {
            throw ValidationException::withMessages(['split.paid_by_contact_id' => 'Numa compra para outra pessoa, quem pagou é você.']);
        }

        if ($split->paid_by_contact_id !== null && ! in_array($split->paid_by_contact_id, $contacts, true)) {
            throw ValidationException::withMessages(['split.paid_by_contact_id' => 'Quem pagou precisa estar na divisão.']);
        }

        if ($split->mode === 'custom') {
            $sumCents = array_sum(array_map(
                fn (SplitParticipantData $p) => $p->contact_id === null && ! $split->include_me ? 0 : $this->cents((float) $p->amount),
                $split->participants,
            ));

            if ($sumCents !== $this->cents($amount)) {
                throw ValidationException::withMessages([
                    'split.participants' => 'A soma das partes ('.number_format($sumCents / 100, 2, ',', '.').') precisa ser igual ao valor ('.number_format($amount, 2, ',', '.').').',
                ]);
            }
        }
    }

    public function compute(float $total, ?SplitData $split): array
    {
        if ($split === null || $split->contactIds() === []) {
            return ['amount' => round($total, 2), 'total_amount' => null, 'paid_by_contact_id' => null, 'shares' => []];
        }

        // Pesos: iguais (1 para cada) ou proporcionais aos valores informados.
        // Em parcelas, os valores informados valem para o "valor de referência" e são escalados para cada parcela.
        $weights = [];
        foreach ($this->participantsWithMe($split) as $participant) {
            $key = $participant->contact_id ?? self::ME;
            $weights[$key] = match (true) {
                // Compra para outra pessoa: você não entra na conta.
                $key === self::ME && ! $split->include_me => 0,
                $split->mode === 'custom' => $this->cents((float) $participant->amount),
                default => 1,
            };
        }

        $totalCents = $this->cents($total);
        $sumWeights = array_sum($weights);

        $shares = [];
        foreach ($weights as $key => $weight) {
            $shares[$key] = $sumWeights > 0 ? intdiv($totalCents * $weight, $sumWeights) : 0;
        }

        // Centavo que sobra fica com quem pagou.
        $payer = $split->paid_by_contact_id ?? self::ME;
        $shares[$payer] = ($shares[$payer] ?? 0) + ($totalCents - array_sum($shares));

        $shares = array_map(fn (int $cents) => $cents / 100, $shares);

        return [
            'amount' => $shares[self::ME] ?? 0.0,
            'total_amount' => round($total, 2),
            'paid_by_contact_id' => $split->paid_by_contact_id,
            'shares' => $shares,
        ];
    }

    public function sync(Transaction $transaction, array $shares): void
    {
        $existing = TransactionSplit::query()->where('transaction_id', $transaction->id)->get();

        // Reembolsos já registrados ("recebido") continuam valendo para quem segue na divisão.
        $reimbursed = $existing
            ->filter(fn (TransactionSplit $s) => $s->contact_id !== null && $s->reimbursed_at !== null)
            ->keyBy('contact_id');

        TransactionSplit::query()->where('transaction_id', $transaction->id)->delete();

        foreach ($shares as $key => $amount) {
            $previous = $key === self::ME ? null : $reimbursed->get($key);

            TransactionSplit::query()->create([
                'transaction_id' => $transaction->id,
                'contact_id' => $key === self::ME ? null : $key,
                'amount' => $amount,
                'reimbursed_at' => $previous?->reimbursed_at?->toDateString(),
                'reimbursement_account_id' => $previous?->reimbursement_account_id,
                'reimbursed_amount' => $previous?->reimbursed_amount,
            ]);
        }

        // Contatos vinculados a usuários recebem (ou atualizam) o compartilhamento.
        $this->shares->syncFor($transaction);
    }

    public function copy(Transaction $from, Transaction $to): void
    {
        $shares = [];

        foreach (TransactionSplit::query()->where('transaction_id', $from->id)->get() as $split) {
            $shares[$split->contact_id ?? self::ME] = (float) $split->amount;
        }

        $this->sync($to, $shares);
    }

    /**
     * Você sempre participa da divisão (com peso 0 no modo "valores", se não informar valor).
     *
     * @return list<SplitParticipantData>
     */
    private function participantsWithMe(SplitData $split): array
    {
        $participants = array_values($split->participants);

        $hasMe = array_filter($participants, fn (SplitParticipantData $p) => $p->contact_id === null) !== [];

        if (! $hasMe) {
            array_unshift($participants, new SplitParticipantData(null, $split->mode === 'custom' ? 0.0 : null));
        }

        return $participants;
    }

    private function cents(float $value): int
    {
        return (int) round($value * 100);
    }
}
