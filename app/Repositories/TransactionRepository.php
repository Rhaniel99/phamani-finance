<?php

namespace App\Repositories;

use App\Interfaces\Repositories\ITransactionRepository;
use App\Models\Transaction;
use App\Repositories\Base\CoreRepository;
use Carbon\CarbonImmutable;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Collection;

class TransactionRepository extends CoreRepository implements ITransactionRepository
{
    public function __construct(Transaction $model)
    {
        parent::__construct($model);
    }

    public function getLatestForUser(string $userId, int $limit = 5): Collection
    {
        // "Recentes" = últimas lançadas, inclusive com data futura (agendadas).
        // De um parcelamento entra só a 1ª parcela lançada (que pode ser a 15/24),
        // para não lotar a lista com as futuras.
        return $this->query()
            ->where('user_id', $userId)
            ->where(fn ($q) => $q
                ->whereNull('installment_id')
                ->orWhere('installment_number', '=', fn ($sub) => $sub
                    ->selectRaw('min(t2.installment_number)')
                    ->from('transactions as t2')
                    ->whereColumn('t2.installment_id', 'transactions.installment_id')))
            ->with([
                'account:id,name,type',
                'category:id,name,color,icon',
                'splits:id,transaction_id,contact_id,amount,reimbursed_at,reimbursement_account_id,reimbursed_amount',
                'splits.contact:id,name',
                'splits.reimbursementAccount:id,name',
                'tags:id,name',
                'paidBy:id,name,linked_user_id',
            ])
            ->orderByDesc('created_at')
            ->orderByDesc('date')
            ->limit($limit)
            ->get();
    }

    public function deleteByInstallment(string $installmentId): void
    {
        $this->query()->where('installment_id', $installmentId)->delete();
    }

    /**
     * Filtros da tela de transações, compartilhados pela lista e pelo resumo do mês.
     *
     * @param  array{account_id?: ?string, category_id?: ?string, tag_id?: ?string, type?: ?string, month?: ?string, search?: ?string, kind?: ?string}  $filters
     */
    private function filtered(string $userId, array $filters): Builder
    {
        return $this->query()
            ->where('user_id', $userId)
            ->when($filters['account_id'] ?? null, fn ($q, $id) => $q->where('account_id', $id))
            ->when($filters['category_id'] ?? null, fn ($q, $id) => $q->where('category_id', $id))
            ->when($filters['tag_id'] ?? null, fn ($q, $id) => $q->whereHas('tags', fn ($t) => $t->whereKey($id)))
            ->when($filters['type'] ?? null, fn ($q, $type) => $q->where('type', $type))
            ->when($filters['month'] ?? null, function ($q, string $month) {
                $start = CarbonImmutable::createFromFormat('!Y-m', $month);

                // whereDate: compara só a data em qualquer banco (inclui o último dia do mês).
                $q->whereDate('date', '>=', $start->startOfMonth()->toDateString())
                    ->whereDate('date', '<=', $start->endOfMonth()->toDateString());
            })
            ->when($filters['search'] ?? null, function ($q, string $search) {
                $term = '%'.mb_strtolower(trim($search)).'%';

                $q->where(fn ($w) => $w
                    ->whereRaw('lower(name) like ?', [$term])
                    ->orWhereRaw('lower(description) like ?', [$term]));
            })
            ->when($filters['status'] ?? null, function ($q, string $status) {
                $today = now()->toDateString();

                match ($status) {
                    'paid' => $q->whereNotNull('paid_at'),
                    'pending' => $q->whereNull('paid_at')->whereDate('date', '>=', $today),
                    'overdue' => $q->whereNull('paid_at')->whereDate('date', '<', $today),
                    default => null,
                };
            })
            ->when($filters['kind'] ?? null, fn ($q, string $kind) => match ($kind) {
                'split' => $q->whereNotNull('total_amount'),
                'installment' => $q->whereNotNull('installment_id'),
                'recurring' => $q->whereNotNull('recurring_id'),
                'shared' => $q->whereNotNull('mirrored_from_id'),
                default => $q,
            });
    }

    public function summaryForUser(string $userId, array $filters): array
    {
        $today = now()->toDateString();

        $income = (float) $this->filtered($userId, $filters)->where('type', 'income')->sum('amount');
        $expense = (float) $this->filtered($userId, $filters)->where('type', 'expense')->sum('amount');
        // Não pagas (cartão fica de fora: a dívida está na fatura).
        $unpaid = fn () => $this->filtered($userId, $filters)
            ->where('type', 'expense')
            ->whereNull('paid_at');

        $due = $unpaid()->whereDate('date', '>=', $today);
        $overdue = $unpaid()->whereDate('date', '<', $today);

        return [
            'income' => round($income, 2),
            'expense' => round($expense, 2),
            'balance' => round($income - $expense, 2),
            'due' => round((float) (clone $due)->sum('amount'), 2),
            'due_count' => (clone $due)->count(),
            'overdue' => round((float) (clone $overdue)->sum('amount'), 2),
            'overdue_count' => (clone $overdue)->count(),
            'count' => $this->filtered($userId, $filters)->count(),
        ];
    }

    public function paginateForUser(string $userId, array $filters = [], int $perPage = 20): LengthAwarePaginator
    {
        return $this->filtered($userId, $filters)
            ->with([
                'account:id,name,type',
                'category:id,name,color,icon',
                'splits:id,transaction_id,contact_id,amount,reimbursed_at,reimbursement_account_id,reimbursed_amount',
                'splits.contact:id,name',
                'splits.reimbursementAccount:id,name',
                'tags:id,name',
                'paidBy:id,name,linked_user_id',
                'mirroredFrom:id,user_id,total_amount,paid_by_contact_id',
                'mirroredFrom.user:id,name,avatar',
                'mirroredFrom.paidBy:id,name,linked_user_id',
                'mirroredFrom.splits:id,transaction_id,contact_id,amount',
                'mirroredFrom.splits.contact:id,name,linked_user_id',
                'shareLinks:id,share_id,source_transaction_id,mirror_transaction_id',
                'shareLinks.share:id,status,owner_contact_id',
                'recurring:id,frequency,end_date,auto_pay',
                'installment:id,name,installments,installment_amount,total_amount,auto_pay',
                'installment.transactions:id,installment_id,installment_number,date,amount',
            ])
            ->orderByDesc('date')
            ->orderByDesc('created_at')
            ->paginate($perPage)
            ->withQueryString();
    }
}
