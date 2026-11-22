import { Head, router } from '@inertiajs/react';
import {
    Check,
    ChevronDown,
    ChevronLeft,
    ChevronRight,
    CreditCard,
    Plus,
    Search,
    X,
} from 'lucide-react';
import { useEffect, useState } from 'react';
import type { ReactNode } from 'react';
import { CategoryIcon } from '@/components/phamani/category-icon';
import { DashboardHeader } from '@/components/phamani/dashboard/dashboard-header';
import { ShowTransactionDrawer } from '@/components/phamani/drawer/show-transaction-drawer';
import { NewTransactionModal } from '@/components/phamani/modal/new-transaction-modal';
import { PaymentStatusBadge } from '@/components/phamani/payment-status-badge';
import { TagChips } from '@/components/phamani/tag-input';
import { Button } from '@/components/phamani/ui/button';
import {
    DropdownMenu,
    DropdownMenuContent,
    DropdownMenuItem,
    DropdownMenuSeparator,
    DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { useTags } from '@/hooks/use-tags';
import { formatCurrency, formatMonth, today } from '@/lib/format';
import {
    canMarkPaid,
    invoiceOf,
    paymentDate,
    paymentStatus,
} from '@/lib/payment';
import {
    displayAmount,
    isFullyReimbursed,
    isThirdParty,
    receivableSplits,
} from '@/lib/split';
import { cn } from '@/lib/utils';
import { dashboard } from '@/routes';
import {
    index as transactionsIndex,
    pay as payTransaction,
} from '@/routes/transactions';
import type {
    Account,
    Category,
    Paginated,
    Transaction,
    TransactionFilters,
    TransactionKind,
    TransactionsSummary,
} from '@/types/phamani';

interface TransactionsPageProps {
    transactions: Paginated<Transaction>;
    summary: TransactionsSummary | null;
    filters: TransactionFilters;
    accounts: Account[];
    categories: Category[];
}

const STATUSES: Array<{
    value: NonNullable<TransactionFilters['status']>;
    label: string;
}> = [
    { value: 'overdue', label: 'Atrasadas' },
    { value: 'pending', label: 'Pendentes' },
    { value: 'paid', label: 'Pagas' },
];

const KINDS: Array<{ value: TransactionKind; label: string }> = [
    { value: 'split', label: 'Divididas' },
    { value: 'installment', label: 'Parceladas' },
    { value: 'recurring', label: 'Recorrentes' },
    { value: 'shared', label: 'Compartilhadas comigo' },
];

function currentMonth(): string {
    return today().slice(0, 7);
}

function shiftMonth(month: string, delta: number): string {
    const [y, m] = month.split('-').map(Number);
    const d = new Date(y, m - 1 + delta, 1);

    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
}

/** "Telefone (3/4)" → "Telefone" (a parcela já aparece na etiqueta). */
function cleanName(name: string): string {
    return name.replace(/\s\(\d+\/\d+\)$/, '');
}

/** Cabeçalho do dia: Hoje, Ontem, Amanhã ou "qui, 04 dez" (+ ano se não for o atual). */
function dayLabel(date: string): string {
    const todayStr = today();
    const [y, m, d] = date.split('-').map(Number);
    const value = new Date(y, m - 1, d);
    const base = new Date(`${todayStr}T00:00:00`);
    const diff = Math.round((value.getTime() - base.getTime()) / 86_400_000);

    if (diff === 0) return 'Hoje';
    if (diff === -1) return 'Ontem';
    if (diff === 1) return 'Amanhã';

    const label = value.toLocaleDateString('pt-BR', {
        weekday: 'short',
        day: '2-digit',
        month: 'short',
        ...(y !== base.getFullYear() ? { year: 'numeric' } : {}),
    });

    return label.charAt(0).toUpperCase() + label.slice(1).replace(/\./g, '');
}

type ListEntry =
    | { kind: 'row'; transaction: Transaction }
    | {
          kind: 'invoice';
          key: string;
          label: string;
          items: Transaction[];
          total: number;
      };

/**
 * Agrupa por dia. "Por pagamento": compra no cartão vai para o dia em que a fatura vence
 * e as compras de uma mesma fatura viram um bloco só (que abre para mostrar as compras).
 */
function groupByDay(items: Transaction[], byPayment: boolean) {
    const dateOf = (t: Transaction) =>
        byPayment ? paymentDate(t) : t.date.slice(0, 10);

    // Ordem estável: mais recente primeiro, mantendo a ordem do servidor no empate.
    const sorted = items
        .map((t, i) => ({ t, i }))
        .sort((a, b) =>
            dateOf(a.t) === dateOf(b.t)
                ? a.i - b.i
                : dateOf(a.t) < dateOf(b.t)
                  ? 1
                  : -1,
        )
        .map(({ t }) => t);

    const groups: Array<{ date: string; entries: ListEntry[]; net: number }> =
        [];

    for (const t of sorted) {
        const date = dateOf(t);
        let group = groups.at(-1);

        if (!group || group.date !== date) {
            group = { date, entries: [], net: 0 };
            groups.push(group);
        }

        const signed = (t.type === 'income' ? 1 : -1) * Number(t.amount);
        group.net += signed;

        const invoice = byPayment ? invoiceOf(t) : null;
        if (!invoice) {
            group.entries.push({ kind: 'row', transaction: t });
            continue;
        }

        let block = group.entries.find(
            (e) => e.kind === 'invoice' && e.key === invoice.key,
        );
        if (!block) {
            block = { kind: 'invoice', ...invoice, items: [], total: 0 };
            group.entries.push(block);
        }
        if (block.kind === 'invoice') {
            block.items.push(t);
            block.total += -signed;
        }
    }

    return groups;
}

export default function TransactionsIndex({
    transactions,
    summary,
    filters,
    accounts,
    categories,
}: TransactionsPageProps) {
    const [selected, setSelected] = useState<Transaction | null>(null);
    const [isNewTransactionOpen, setIsNewTransactionOpen] = useState(false);
    const [editing, setEditing] = useState<Transaction | null>(null);
    const [search, setSearch] = useState(filters.search ?? '');
    const [loadingMore, setLoadingMore] = useState(false);

    const isAll = filters.all === '1';
    const month = filters.month ?? currentMonth();
    const todayStr = today();

    // "Carregar mais": páginas seguintes são somadas às já exibidas; a 1ª página
    // (nova busca/filtro ou depois de salvar) recomeça a lista.
    const [list, setList] = useState({
        source: transactions,
        items: transactions.data,
    });
    if (list.source !== transactions) {
        const items =
            transactions.current_page > 1
                ? [
                      ...list.items,
                      ...transactions.data.filter(
                          (t) => !list.items.some((i) => i.id === t.id),
                      ),
                  ]
                : transactions.data;
        setList({ source: transactions, items });
    }

    function visit(next: TransactionFilters) {
        const clean = Object.fromEntries(
            Object.entries(next).filter(([, v]) => v),
        );

        router.get(transactionsIndex.url(), clean, {
            preserveState: true,
            preserveScroll: true,
            replace: true,
            only: ['transactions', 'summary', 'filters'],
        });
    }

    const tags = useTags();

    function applyFilter<K extends keyof TransactionFilters>(
        key: K,
        value?: TransactionFilters[K],
    ) {
        visit({ ...filters, [key]: value });
    }

    function goToMonth(next: string) {
        visit({ ...filters, month: next, all: undefined });
    }

    // Busca com pequeno atraso para não recarregar a cada tecla.
    useEffect(() => {
        if ((filters.search ?? '') === search) return;

        const timer = setTimeout(() => applyFilter('search', search), 350);

        return () => clearTimeout(timer);
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [search]);

    function loadMore() {
        if (!transactions.next_page_url) return;

        router.get(
            transactions.next_page_url,
            {},
            {
                preserveState: true,
                preserveScroll: true,
                only: ['transactions'],
                onStart: () => setLoadingMore(true),
                onFinish: () => setLoadingMore(false),
            },
        );
    }

    const hasFilters = !!(
        filters.account_id ||
        filters.category_id ||
        filters.tag_id ||
        filters.type ||
        filters.search ||
        filters.kind ||
        filters.status
    );
    const byPayment = !isAll && filters.view !== 'purchase';
    const groups = groupByDay(list.items, byPayment);

    return (
        <>
            <Head title="Transações" />

            <div className="mx-auto max-w-5xl p-6 md:p-8">
                <DashboardHeader
                    title="Transações"
                    subtitle={isAll ? 'Todo o período' : 'Mês a mês'}
                    onBack={() => router.visit(dashboard.url())}
                    actions={
                        <Button
                            variant="primary"
                            onClick={() => setIsNewTransactionOpen(true)}
                            className="h-12"
                        >
                            <Plus className="h-5 w-5 md:mr-2" />
                            <span className="hidden md:inline">
                                Nova Transação
                            </span>
                        </Button>
                    }
                />

                {/* Mês */}
                <div className="mb-6 flex flex-wrap items-center justify-between gap-3">
                    <div className="flex items-center gap-2">
                        <button
                            type="button"
                            onClick={() =>
                                goToMonth(
                                    shiftMonth(
                                        isAll ? currentMonth() : month,
                                        -1,
                                    ),
                                )
                            }
                            aria-label="Mês anterior"
                            className="rounded-xl border border-[#E8DCC4] bg-white p-2 text-[#6B4E3D] hover:bg-[#FBF7F1]"
                        >
                            <ChevronLeft className="h-5 w-5" />
                        </button>
                        <h2 className="min-w-48 text-center text-xl font-bold text-[#3D2817] capitalize">
                            {isAll ? 'Todo o período' : formatMonth(month)}
                        </h2>
                        <button
                            type="button"
                            onClick={() =>
                                goToMonth(
                                    shiftMonth(
                                        isAll ? currentMonth() : month,
                                        1,
                                    ),
                                )
                            }
                            aria-label="Próximo mês"
                            className="rounded-xl border border-[#E8DCC4] bg-white p-2 text-[#6B4E3D] hover:bg-[#FBF7F1]"
                        >
                            <ChevronRight className="h-5 w-5" />
                        </button>
                        {(isAll || month !== currentMonth()) && (
                            <button
                                type="button"
                                onClick={() => goToMonth(currentMonth())}
                                className="ml-1 rounded-xl px-3 py-2 text-sm font-medium text-[#6B4F3A] hover:bg-[#E8DCC4]"
                            >
                                Este mês
                            </button>
                        )}
                    </div>

                    <div className="flex flex-wrap items-center gap-2">
                        {!isAll && (
                            <div
                                role="group"
                                aria-label="Ver o mês"
                                className="flex rounded-2xl border border-[#E8DCC4] bg-white p-1 text-sm"
                            >
                                {(
                                    [
                                        ['payment', 'Por pagamento'],
                                        ['purchase', 'Por compra'],
                                    ] as const
                                ).map(([value, label]) => {
                                    const active =
                                        (filters.view ?? 'payment') === value;
                                    return (
                                        <button
                                            key={value}
                                            type="button"
                                            aria-pressed={active}
                                            title={
                                                value === 'payment'
                                                    ? 'Mês em que o dinheiro sai: compras no cartão entram no mês da fatura'
                                                    : 'Pela data da compra'
                                            }
                                            onClick={() =>
                                                visit({
                                                    ...filters,
                                                    view:
                                                        value === 'payment'
                                                            ? undefined
                                                            : value,
                                                })
                                            }
                                            className={cn(
                                                'rounded-xl px-3 py-1.5 font-medium transition-colors',
                                                active
                                                    ? 'bg-[#3D2817] text-[#F5EFE6]'
                                                    : 'text-[#6B4E3D] hover:bg-[#FBF7F1]',
                                            )}
                                        >
                                            {label}
                                        </button>
                                    );
                                })}
                            </div>
                        )}
                        <button
                            type="button"
                            onClick={() =>
                                visit({
                                    ...filters,
                                    all: isAll ? undefined : '1',
                                    month: isAll ? currentMonth() : undefined,
                                })
                            }
                            aria-pressed={isAll}
                            className={cn(
                                'rounded-2xl border px-4 py-2 text-sm font-medium transition-colors',
                                isAll
                                    ? 'border-[#3D2817] bg-[#3D2817] text-[#F5EFE6]'
                                    : 'border-[#E8DCC4] bg-white text-[#3D2817] hover:bg-[#FBF7F1]',
                            )}
                        >
                            Todo o período
                        </button>
                    </div>
                </div>

                {/* Resumo do mês */}
                {summary && (
                    <div
                        className={cn(
                            'mb-6 grid grid-cols-2 gap-3',
                            summary.overdue_count > 0
                                ? 'md:grid-cols-5'
                                : 'md:grid-cols-4',
                        )}
                    >
                        <SummaryCard
                            label="Receitas"
                            value={summary.income}
                            tone="income"
                        />
                        <SummaryCard
                            label="Despesas"
                            value={summary.expense}
                            tone="expense"
                        />
                        <SummaryCard
                            label="Saldo do mês"
                            value={summary.balance}
                            tone={summary.balance >= 0 ? 'income' : 'expense'}
                        />
                        <SummaryCard
                            label={`A vencer${summary.due_count ? ` (${summary.due_count})` : ''}`}
                            value={summary.due}
                            tone="muted"
                        />
                        {summary.overdue_count > 0 && (
                            <button
                                type="button"
                                onClick={() => applyFilter('status', 'overdue')}
                                className="text-left"
                            >
                                <SummaryCard
                                    label={`Atrasadas (${summary.overdue_count})`}
                                    value={summary.overdue}
                                    tone="expense"
                                    highlight
                                />
                            </button>
                        )}
                    </div>
                )}

                {/* Busca e filtros */}
                <div className="sticky top-0 z-10 -mx-6 mb-4 space-y-3 bg-[#F5EFE6]/95 px-6 py-3 backdrop-blur-sm md:-mx-8 md:px-8">
                    <div className="relative">
                        <Search className="absolute top-1/2 left-4 h-4 w-4 -translate-y-1/2 text-[#8B7355]" />
                        <label htmlFor="tx-search" className="sr-only">
                            Buscar transações
                        </label>
                        <input
                            id="tx-search"
                            type="search"
                            value={search}
                            onChange={(e) => setSearch(e.target.value)}
                            placeholder="Buscar por descrição (ex.: Uber, Caixa…)"
                            className="w-full rounded-2xl border-2 border-[#E8DCC4] bg-white py-3 pr-4 pl-11 text-[#3D2817] placeholder:text-[#B8A48A] focus:border-[#6B4E3D] focus:outline-none"
                        />
                    </div>

                    <div className="scrollbar-hide flex items-center gap-2 overflow-x-auto pb-1">
                        <FilterPill
                            label={
                                accounts.find(
                                    (a) => a.id === filters.account_id,
                                )?.name ?? 'Conta'
                            }
                            active={!!filters.account_id}
                            options={accounts.map((a) => ({
                                value: a.id,
                                label: a.name,
                            }))}
                            allLabel="Todas as contas"
                            onSelect={(v) => applyFilter('account_id', v)}
                        />
                        <FilterPill
                            label={
                                categories.find(
                                    (c) => c.id === filters.category_id,
                                )?.name ?? 'Categoria'
                            }
                            active={!!filters.category_id}
                            options={categories.map((c) => ({
                                value: c.id,
                                label: c.name,
                            }))}
                            allLabel="Todas as categorias"
                            onSelect={(v) => applyFilter('category_id', v)}
                        />
                        {tags.length > 0 && (
                            <FilterPill
                                label={
                                    tags.find((t) => t.id === filters.tag_id)
                                        ?.name ?? 'Tag'
                                }
                                active={!!filters.tag_id}
                                options={tags.map((t) => ({
                                    value: t.id,
                                    label: t.name,
                                }))}
                                allLabel="Todas as tags"
                                onSelect={(v) => applyFilter('tag_id', v)}
                            />
                        )}
                        <FilterPill
                            label={
                                filters.type === 'income'
                                    ? 'Receitas'
                                    : filters.type === 'expense'
                                      ? 'Despesas'
                                      : 'Tipo'
                            }
                            active={!!filters.type}
                            options={[
                                { value: 'income', label: 'Receitas' },
                                { value: 'expense', label: 'Despesas' },
                            ]}
                            allLabel="Receitas e despesas"
                            onSelect={(v) =>
                                applyFilter(
                                    'type',
                                    v as TransactionFilters['type'],
                                )
                            }
                        />

                        <span className="mx-1 h-6 w-px shrink-0 bg-[#D4C5A9]" />

                        {STATUSES.map((st) => (
                            <Chip
                                key={st.value}
                                active={filters.status === st.value}
                                onClick={() =>
                                    applyFilter(
                                        'status',
                                        filters.status === st.value
                                            ? undefined
                                            : st.value,
                                    )
                                }
                            >
                                {st.label}
                            </Chip>
                        ))}

                        <span className="mx-1 h-6 w-px shrink-0 bg-[#D4C5A9]" />

                        {KINDS.map((k) => (
                            <Chip
                                key={k.value}
                                active={filters.kind === k.value}
                                onClick={() =>
                                    applyFilter(
                                        'kind',
                                        filters.kind === k.value
                                            ? undefined
                                            : k.value,
                                    )
                                }
                            >
                                {k.label}
                            </Chip>
                        ))}

                        {hasFilters && (
                            <button
                                type="button"
                                onClick={() => {
                                    setSearch('');
                                    visit({
                                        month: filters.month,
                                        all: filters.all,
                                    });
                                }}
                                className="flex shrink-0 items-center gap-1 px-3 py-2 text-sm whitespace-nowrap text-[#8B7355] hover:text-[#3D2817]"
                            >
                                <X className="h-4 w-4" /> Limpar
                            </button>
                        )}
                    </div>
                </div>

                {/* Lista agrupada por dia */}
                {groups.length === 0 ? (
                    <p className="rounded-3xl border border-dashed border-[#D4C5A9] p-12 text-center text-[#8B7355]">
                        {hasFilters
                            ? 'Nenhuma transação com esses filtros.'
                            : isAll
                              ? 'Nenhuma transação ainda.'
                              : 'Nenhuma transação neste mês.'}
                    </p>
                ) : (
                    <div className="space-y-6">
                        {groups.map((group) => (
                            <section key={group.date}>
                                <div className="mb-2 flex items-baseline justify-between px-2">
                                    <h3 className="text-sm font-bold text-[#6B4E3D]">
                                        {dayLabel(group.date)}
                                        {group.date > todayStr && (
                                            <span className="ml-2 text-xs font-medium text-[#8B7355]">
                                                agendado
                                            </span>
                                        )}
                                    </h3>
                                    <span
                                        className={cn(
                                            'text-xs font-bold',
                                            group.net >= 0
                                                ? 'text-[#1F5428]'
                                                : 'text-[#8B7355]',
                                        )}
                                    >
                                        {group.net >= 0 ? '+' : '-'}{' '}
                                        {formatCurrency(Math.abs(group.net))}
                                    </span>
                                </div>
                                <ul className="divide-y divide-[#E8DCC4] overflow-hidden rounded-3xl border border-[#E8DCC4] bg-white shadow-sm">
                                    {group.entries.map((entry) =>
                                        entry.kind === 'row' ? (
                                            <TransactionRow
                                                key={entry.transaction.id}
                                                transaction={entry.transaction}
                                                scheduled={
                                                    group.date > todayStr
                                                }
                                                onClick={() =>
                                                    setSelected(
                                                        entry.transaction,
                                                    )
                                                }
                                            />
                                        ) : (
                                            <InvoiceBlock
                                                key={entry.key}
                                                label={entry.label}
                                                items={entry.items}
                                                total={entry.total}
                                                scheduled={
                                                    group.date > todayStr
                                                }
                                                onSelect={setSelected}
                                            />
                                        ),
                                    )}
                                </ul>
                            </section>
                        ))}
                    </div>
                )}

                {transactions.next_page_url && (
                    <div className="mt-6 flex justify-center">
                        <button
                            type="button"
                            onClick={loadMore}
                            disabled={loadingMore}
                            className="rounded-2xl border-2 border-[#D4C5A9] bg-white px-6 py-3 text-sm font-medium text-[#6B4E3D] hover:bg-[#FBF7F1] disabled:opacity-50"
                        >
                            {loadingMore
                                ? 'Carregando…'
                                : `Carregar mais (${list.items.length} de ${transactions.total})`}
                        </button>
                    </div>
                )}

                <ShowTransactionDrawer
                    transaction={selected}
                    onClose={() => setSelected(null)}
                    onEdit={(t) => {
                        setSelected(null);
                        setEditing(t);
                    }}
                />

                <NewTransactionModal
                    isOpen={!!editing}
                    onClose={() => setEditing(null)}
                    categories={categories}
                    accounts={accounts}
                    transaction={editing}
                />

                <NewTransactionModal
                    isOpen={isNewTransactionOpen}
                    onClose={() => setIsNewTransactionOpen(false)}
                    categories={categories}
                    accounts={accounts}
                />
            </div>
        </>
    );
}

/**
 * Bloco de uma fatura dentro do dia do vencimento ("por pagamento").
 * Fechado mostra o total da fatura; aberto lista as compras.
 */
function InvoiceBlock({
    label,
    items,
    total,
    scheduled,
    onSelect,
}: {
    label: string;
    items: Transaction[];
    total: number;
    scheduled: boolean;
    onSelect: (t: Transaction) => void;
}) {
    const [open, setOpen] = useState(false);

    return (
        <li>
            <button
                type="button"
                onClick={() => setOpen((v) => !v)}
                aria-expanded={open}
                className="flex w-full items-center gap-4 px-6 py-4 text-left transition-colors hover:bg-[#FBF7F1]"
            >
                <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-[#3D2817] text-[#F5EFE6]">
                    <CreditCard className="h-5 w-5" />
                </span>
                <span className="min-w-0 flex-1">
                    <span className="block truncate font-bold text-[#3D2817]">
                        {label}
                    </span>
                    <span className="text-xs text-[#8B7355]">
                        {items.length}{' '}
                        {items.length === 1 ? 'compra' : 'compras'} ·{' '}
                        {(items[0].invoice ?? items[0].mirrored_from?.invoice)
                            ?.paid_at
                            ? 'paga neste dia'
                            : 'vence neste dia'}{' '}
                        · {open ? 'esconder' : 'ver compras'}
                    </span>
                </span>
                <span className="text-sm font-bold text-[#3D2817]">
                    - {formatCurrency(total)}
                </span>
                <ChevronDown
                    className={cn(
                        'h-4 w-4 shrink-0 text-[#8B7355] transition-transform',
                        open && 'rotate-180',
                    )}
                />
            </button>
            {open && (
                <ul className="divide-y divide-[#F0E8D8] border-t border-[#E8DCC4] bg-[#FDFBF7]">
                    {items.map((t) => (
                        <TransactionRow
                            key={t.id}
                            transaction={t}
                            scheduled={scheduled}
                            onClick={() => onSelect(t)}
                        />
                    ))}
                </ul>
            )}
        </li>
    );
}

function TransactionRow({
    transaction: t,
    scheduled,
    onClick,
}: {
    transaction: Transaction;
    scheduled: boolean;
    onClick: () => void;
}) {
    const [paying, setPaying] = useState(false);
    const isIncome = t.type === 'income';
    const status = paymentStatus(t);
    const where = t.account?.name
        ? t.account.name
        : t.paid_by
          ? `Pago por ${t.paid_by.name}`
          : t.mirrored_from?.user
            ? `De ${t.mirrored_from.user.name}`
            : null;

    const canPay = status !== null && status !== 'paid' && canMarkPaid(t);

    function pay() {
        router.post(
            payTransaction.url(t.id),
            {},
            {
                preserveScroll: true,
                preserveState: true,
                onStart: () => setPaying(true),
                onFinish: () => setPaying(false),
            },
        );
    }

    return (
        <li className="flex items-center">
            <button
                type="button"
                onClick={onClick}
                className={cn(
                    'flex min-w-0 flex-1 items-center gap-4 px-4 py-3 text-left transition-colors hover:bg-[#F5EFE6] md:px-6',
                    scheduled &&
                        status !== 'overdue' &&
                        'opacity-60 hover:opacity-100',
                )}
            >
                <CategoryIcon
                    category={t.category}
                    className="h-10 w-10 shrink-0 rounded-xl"
                    iconClassName="h-5 w-5"
                />

                <div className="min-w-0 flex-1">
                    <p className="truncate font-bold text-[#3D2817]">
                        {cleanName(t.name)}
                    </p>
                    <div className="mt-0.5 flex flex-wrap items-center gap-1 text-xs text-[#8B7355]">
                        <span>{t.category?.name}</span>
                        {where && (
                            <>
                                <span aria-hidden>·</span>
                                <span>{where}</span>
                            </>
                        )}
                        {status && status !== 'paid' && (
                            <PaymentStatusBadge
                                status={status}
                                isIncome={isIncome}
                            />
                        )}
                        {t.installment_number && t.installment && (
                            <Tag>
                                {t.installment_number}/
                                {t.installment.installments}
                            </Tag>
                        )}
                        {t.recurring && <Tag>Recorrente</Tag>}
                        <TagChips tags={t.tags} />
                        {t.mirrored_from_id && <Tag>Compartilhada</Tag>}
                        {isThirdParty(t) ? (
                            <>
                                <Tag>
                                    Para{' '}
                                    {receivableSplits(t)
                                        .map((s) => s.contact?.name)
                                        .filter(Boolean)
                                        .join(', ')}
                                </Tag>
                                <ReceivableTag
                                    received={isFullyReimbursed(t)}
                                />
                            </>
                        ) : (
                            t.total_amount != null && (
                                <Tag>
                                    Dividido · {formatCurrency(t.total_amount)}
                                </Tag>
                            )
                        )}
                    </div>
                </div>

                <span
                    className={cn(
                        'shrink-0 text-sm font-bold whitespace-nowrap',
                        isIncome ? 'text-[#1F5428]' : 'text-[#3D2817]',
                        status === 'overdue' && 'text-[#A65D57]',
                    )}
                >
                    {isIncome ? '+' : '-'} {formatCurrency(displayAmount(t))}
                </span>
            </button>

            {canPay && (
                <button
                    type="button"
                    onClick={pay}
                    disabled={paying}
                    aria-label={`Marcar ${cleanName(t.name)} como ${isIncome ? 'recebida' : 'paga'}`}
                    title={
                        isIncome ? 'Marcar como recebida' : 'Marcar como paga'
                    }
                    className={cn(
                        'mr-3 flex h-9 w-9 shrink-0 items-center justify-center rounded-full border-2 transition-colors disabled:opacity-50 md:mr-4',
                        status === 'overdue'
                            ? 'border-[#A65D57] text-[#A65D57] hover:bg-[#A65D57] hover:text-white'
                            : 'border-[#D4C5A9] text-[#8B7355] hover:border-[#1F5428] hover:bg-[#1F5428] hover:text-white',
                    )}
                >
                    <Check className="h-4 w-4" />
                </button>
            )}
        </li>
    );
}

function SummaryCard({
    label,
    value,
    tone,
    highlight = false,
}: {
    label: string;
    value: number;
    tone: 'income' | 'expense' | 'muted';
    highlight?: boolean;
}) {
    return (
        <div
            className={cn(
                'h-full rounded-2xl border bg-white px-4 py-3 shadow-sm',
                highlight
                    ? 'border-[#A65D57] bg-[#FDF3F2]'
                    : 'border-[#E8DCC4]',
            )}
        >
            <p className="text-xs font-bold tracking-wider text-[#8B7355] uppercase">
                {label}
            </p>
            <p
                className={cn(
                    'text-lg font-bold',
                    tone === 'income' && 'text-[#1F5428]',
                    tone === 'expense' && 'text-[#A65D57]',
                    tone === 'muted' && 'text-[#6B4E3D]',
                )}
            >
                {formatCurrency(value)}
            </p>
        </div>
    );
}

/** Compra para outra pessoa: ainda a receber ou já devolvida. */
function ReceivableTag({ received }: { received: boolean }) {
    return (
        <span
            className={cn(
                'inline-flex items-center rounded-md px-1.5 py-0.5 text-[10px] font-bold tracking-wide uppercase',
                received
                    ? 'bg-[#E3F1E6] text-[#1F5428]'
                    : 'bg-[#FCE7E7] text-[#A65D57]',
            )}
        >
            {received ? 'Recebido' : 'A receber'}
        </span>
    );
}

function Tag({ children }: { children: ReactNode }) {
    return (
        <span className="inline-flex items-center rounded-md bg-[#E8DCC4] px-1.5 py-0.5 text-[10px] font-bold tracking-wide text-[#6B4E3D] uppercase">
            {children}
        </span>
    );
}

function Chip({
    active,
    onClick,
    children,
}: {
    active: boolean;
    onClick: () => void;
    children: ReactNode;
}) {
    return (
        <button
            type="button"
            onClick={onClick}
            aria-pressed={active}
            className={cn(
                'shrink-0 rounded-2xl border px-3 py-2 text-sm font-medium whitespace-nowrap transition-colors',
                active
                    ? 'border-[#3D2817] bg-[#3D2817] text-[#F5EFE6]'
                    : 'border-[#E8DCC4] bg-white text-[#3D2817] hover:bg-[#FBF7F1]',
            )}
        >
            {children}
        </button>
    );
}

interface FilterPillProps {
    label: string;
    active: boolean;
    allLabel: string;
    options: Array<{ value: string; label: string }>;
    onSelect: (value?: string) => void;
}

function FilterPill({
    label,
    active,
    allLabel,
    options,
    onSelect,
}: FilterPillProps) {
    return (
        <DropdownMenu>
            <DropdownMenuTrigger asChild>
                <button
                    type="button"
                    className={cn(
                        'flex shrink-0 items-center gap-2 rounded-2xl border px-4 py-2 text-sm font-medium whitespace-nowrap transition-colors',
                        active
                            ? 'border-[#3D2817] bg-[#3D2817] text-[#F5EFE6]'
                            : 'border-[#E8DCC4] bg-white text-[#3D2817] hover:bg-[#FBF7F1]',
                    )}
                >
                    <span>{label}</span>
                    <ChevronDown
                        className={cn(
                            'h-4 w-4',
                            active ? 'text-[#F5EFE6]' : 'text-[#8B7355]',
                        )}
                    />
                </button>
            </DropdownMenuTrigger>
            <DropdownMenuContent
                align="start"
                className="max-h-80 overflow-y-auto rounded-xl"
            >
                <DropdownMenuItem
                    onSelect={() => onSelect(undefined)}
                    className="cursor-pointer"
                >
                    {allLabel}
                </DropdownMenuItem>
                <DropdownMenuSeparator />
                {options.map((o) => (
                    <DropdownMenuItem
                        key={o.value}
                        onSelect={() => onSelect(o.value)}
                        className="cursor-pointer"
                    >
                        {o.label}
                    </DropdownMenuItem>
                ))}
            </DropdownMenuContent>
        </DropdownMenu>
    );
}
