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
            // Mesmas relações da lista: o drawer abre daqui também (cópias, status do cartão…).
            ->with($this->listRelations())
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
            ->when($filters['month'] ?? null, function ($q, string $month) use ($filters) {
                $start = CarbonImmutable::createFromFormat('!Y-m', $month);
                [$from, $to] = [$start->startOfMonth()->toDateString(), $start->endOfMonth()->toDateString()];

                // Padrão "por pagamento": compra no cartão entra no mês em que a fatura vence.
                if (($filters['view'] ?? 'payment') === 'payment') {
                    $q->paidBetween($from, $to);

                    return;
                }

                // "Por compra": pela data. whereDate compara só a data em qualquer banco.
                $q->whereDate('date', '>=', $from)->whereDate('date', '<=', $to);
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
                    // Pendente: ainda não chegou, ou está numa fatura que não foi paga.
                    'pending' => $q->whereNull('paid_at')->where(fn ($w) => $w
                        ->whereDate('date', '>=', $today)
                        ->orWhere(fn ($c) => $c->onCard())),
                    // Compra no cartão não fica atrasada: quem vence é a fatura.
                    'overdue' => $q->whereNull('paid_at')->whereDate('date', '<', $today)->notOnCard(),
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
        $byPayment = ($filters['view'] ?? 'payment') === 'payment';

        $income = (float) $this->filtered($userId, $filters)->where('type', 'income')->sum('amount');
        $expense = (float) $this->filtered($userId, $filters)->where('type', 'expense')->sum('amount');

        // Não pagas. Por pagamento: a compra no cartão vence com a fatura e entra em "a vencer".
        // Por compra: o cartão fica de fora (a dívida está na fatura).
        $unpaid = fn () => $this->filtered($userId, $filters)
            ->where('type', 'expense')
            ->whereNull('paid_at')
            ->when(! $byPayment, fn ($q) => $q->notOnCard());

        $when = $byPayment ? Transaction::paymentDateSql() : 'date(transactions.date)';
        $due = $unpaid()->whereRaw("{$when} >= ?", [$today]);
        $overdue = $unpaid()->whereRaw("{$when} < ?", [$today]);

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
            ->with($this->listRelations())
            ->orderByDesc('date')
            ->orderByDesc('created_at')
            ->paginate($perPage)
            ->withQueryString();
    }

    /**
     * Relações usadas na lista, nos recentes e no drawer.
     *
     * @return list<string>
     */
    private function listRelations(): array
    {
        return [
            'account:id,name,type',
            // Fatura (vencimento): a lista "por pagamento" agrupa as compras do cartão por fatura.
            'invoice:id,account_id,due_date,paid_at',
            'category:id,name,color,icon',
            'splits:id,transaction_id,contact_id,amount,reimbursed_at,reimbursement_account_id,reimbursed_amount,tracked,settlement_id',
            'splits.settlement:id,status',
            'splits.contact:id,name',
            'splits.reimbursementAccount:id,name',
            'tags:id,name',
            'paidBy:id,name,linked_user_id',
            'mirroredFrom:id,user_id,account_id,invoice_id,date,total_amount,paid_by_contact_id',
            'mirroredFrom.account:id,name,type',
            'mirroredFrom.invoice:id,due_date,paid_at',
            'mirroredFrom.user:id,name,avatar',
            'mirroredFrom.paidBy:id,name,linked_user_id',
            'mirroredFrom.splits:id,transaction_id,contact_id,amount,tracked,reimbursed_at,settlement_id',
            'mirroredFrom.splits.settlement:id,status',
            'mirroredFrom.splits.contact:id,name,linked_user_id',
            'shareLinks:id,share_id,source_transaction_id,mirror_transaction_id',
            'shareLinks.share:id,status,owner_contact_id',
            'recurring:id,frequency,end_date,auto_pay',
            'installment:id,name,installments,installment_amount,total_amount,auto_pay',
            'installment.transactions:id,installment_id,installment_number,date,amount',
        ];
    }
}
