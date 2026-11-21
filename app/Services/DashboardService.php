<?php

namespace App\Services;

use App\Enums\Category\Color;
use App\Interfaces\Services\ICreditCardService;
use App\Interfaces\Services\IDashboardService;
use App\Models\Account;
use App\Models\Installment;
use App\Models\Transaction;
use Carbon\CarbonImmutable;
use Carbon\CarbonInterface;
use Illuminate\Support\Collection;

class DashboardService implements IDashboardService
{
    public function __construct(
        protected ICreditCardService $cards,
    ) {}

    public function kpis(string $userId): array
    {
        $now = CarbonImmutable::now();
        $lastMonth = $now->subMonthNoOverflow();

        $currentIncome = $this->monthlyTotal($userId, 'income', $now);
        $previousIncome = $this->monthlyTotal($userId, 'income', $lastMonth);

        $currentExpense = $this->monthlyTotal($userId, 'expense', $now);
        $previousExpense = $this->monthlyTotal($userId, 'expense', $lastMonth);

        return [
            // Só dinheiro em contas; cartão é dívida e aparece em "faturas em aberto".
            'total_balance' => $this->totalBalance($userId),
            'open_invoices' => $this->cards->openInvoicesTotal($userId),
            'overdue' => $this->overdue($userId),
            'income' => [
                'value' => $currentIncome,
                'trend' => $this->trend($currentIncome, $previousIncome),
            ],
            'expense' => [
                'value' => $currentExpense,
                'trend' => $this->trend($currentExpense, $previousExpense),
            ],
            'installments' => [
                'value' => $this->activeInstallments($userId),
                'trend' => null,
            ],
        ];
    }

    public function cashFlow(string $userId, string $period = 'yearly'): array
    {
        $now = CarbonImmutable::now();

        return $period === 'monthly'
            ? $this->cashFlowByDay($userId, $now)
            : $this->cashFlowByMonth($userId, $now);
    }

    public function categoryPie(string $userId, string $period = 'monthly'): array
    {
        [$start, $end] = $this->periodRange(CarbonImmutable::now(), $period);

        return Transaction::query()
            ->join('categories', 'categories.id', '=', 'transactions.category_id')
            ->where('transactions.user_id', $userId)
            ->where('transactions.type', 'expense')
            ->whereBetween('transactions.date', [$start, $end])
            ->groupBy('categories.id', 'categories.name', 'categories.color')
            ->selectRaw('categories.name as name, categories.color as color, SUM(transactions.amount) as value')
            // Compras para outras pessoas têm a sua parte = 0 e não aparecem no gráfico.
            ->havingRaw('SUM(transactions.amount) > 0')
            ->orderByDesc('value')
            ->toBase()
            ->get()
            ->map(fn (object $row) => [
                'name' => (string) $row->name,
                'value' => (float) $row->value,
                'color' => Color::tryFrom((string) $row->color)?->hex() ?? Color::CHARCOAL->hex(),
            ])
            ->values()
            ->all();
    }

    /**
     * Fluxo diário do mês corrente.
     *
     * @return list<array{label: string, income: float, expense: float}>
     */
    protected function cashFlowByDay(string $userId, CarbonImmutable $date): array
    {
        $totals = $this->totalsByDate($userId, $date->startOfMonth(), $date->endOfMonth())
            ->groupBy(fn (object $row) => (int) substr((string) $row->date, 8, 2));

        return collect(range(1, $date->daysInMonth))
            ->map(fn (int $day) => [
                'label' => (string) $day,
                ...$this->sumByType($totals->get($day, collect())),
            ])
            ->all();
    }

    /**
     * Fluxo mensal do ano corrente.
     *
     * @return list<array{label: string, income: float, expense: float}>
     */
    protected function cashFlowByMonth(string $userId, CarbonImmutable $date): array
    {
        $totals = $this->totalsByDate($userId, $date->startOfYear(), $date->endOfYear())
            ->groupBy(fn (object $row) => (int) substr((string) $row->date, 5, 2));

        return collect(range(1, 12))
            ->map(fn (int $month) => [
                'label' => ucfirst(rtrim(CarbonImmutable::create($date->year, $month, 1)->locale('pt_BR')->translatedFormat('M'), '.')),
                ...$this->sumByType($totals->get($month, collect())),
            ])
            ->all();
    }

    /**
     * Totais agrupados por data e tipo. A agregação por dia/mês é feita em PHP para
     * manter a consulta portável entre PostgreSQL e SQLite (testes).
     *
     * @return Collection<int, object{date: string, type: string, total: string}>
     */
    protected function totalsByDate(string $userId, CarbonInterface $start, CarbonInterface $end): Collection
    {
        return Transaction::query()
            ->where('user_id', $userId)
            ->whereBetween('date', [$start->toDateString(), $end->toDateString()])
            ->groupBy('date', 'type')
            ->selectRaw('date, type, SUM(amount) as total')
            ->toBase()
            ->get();
    }

    /**
     * @param  Collection<int, object>  $rows
     * @return array{income: float, expense: float}
     */
    protected function sumByType(Collection $rows): array
    {
        return [
            'income' => round((float) $rows->where('type', 'income')->sum('total'), 2),
            'expense' => round((float) $rows->where('type', 'expense')->sum('total'), 2),
        ];
    }

    /**
     * @return array{0: string, 1: string}
     */
    protected function periodRange(CarbonImmutable $now, string $period): array
    {
        return $period === 'monthly'
            ? [$now->startOfMonth()->toDateString(), $now->endOfMonth()->toDateString()]
            : [$now->startOfYear()->toDateString(), $now->endOfYear()->toDateString()];
    }

    protected function totalBalance(string $userId): float
    {
        return (float) Account::query()
            ->where('user_id', $userId)
            ->where('type', '!=', 'credit')
            ->sum('balance');
    }

    protected function monthlyTotal(string $userId, string $type, CarbonImmutable $month): float
    {
        return (float) Transaction::query()
            ->where('user_id', $userId)
            ->where('type', $type)
            ->whereBetween('date', [$month->startOfMonth()->toDateString(), $month->endOfMonth()->toDateString()])
            ->sum('amount');
    }

    protected function activeInstallments(string $userId): float
    {
        return (float) Installment::query()
            ->where('user_id', $userId)
            ->where('status', 'active')
            ->sum('installment_amount');
    }

    /**
     * @return array{value: float, direction: 'up'|'down'}|null
     */
    protected function trend(float $current, float $previous): ?array
    {
        if ($previous <= 0) {
            return null;
        }

        $diff = (($current - $previous) / $previous) * 100;

        return [
            'value' => round($diff, 1),
            'direction' => $diff >= 0 ? 'up' : 'down',
        ];
    }

    /**
     * Despesas vencidas e ainda não pagas (de qualquer mês).
     *
     * @return array{count: int, amount: float}
     */
    private function overdue(string $userId): array
    {
        $query = Transaction::query()
            ->where('user_id', $userId)
            ->where('type', 'expense')
            ->whereNull('paid_at')
            ->notOnCard()
            ->whereDate('date', '<', now()->toDateString());

        return [
            'count' => (clone $query)->count(),
            'amount' => round((float) (clone $query)->sum('amount'), 2),
        ];
    }
}
