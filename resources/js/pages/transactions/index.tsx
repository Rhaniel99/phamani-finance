import { Head, router } from '@inertiajs/react';
import {
    Check,
    ChevronDown,
    ChevronLeft,
    ChevronRight,
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
import { Button } from '@/components/phamani/ui/button';
import {
    DropdownMenu,
    DropdownMenuContent,
    DropdownMenuItem,
    DropdownMenuSeparator,
    DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { formatCurrency, formatMonth, today } from '@/lib/format';
import { canMarkPaid, paymentStatus } from '@/lib/payment';
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

function groupByDay(items: Transaction[]) {
    const groups: Array<{ date: string; items: Transaction[]; net: number }> =
        [];

    for (const t of items) {
        const date = t.date.slice(0, 10);
        let group = groups.at(-1);

        if (!group || group.date !== date) {
            group = { date, items: [], net: 0 };
            groups.push(group);
        }

        group.items.push(t);
        group.net += (t.type === 'income' ? 1 : -1) * Number(t.amount);
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
        filters.type ||
        filters.search ||
        filters.kind ||
        filters.status
    );
    const groups = groupByDay(list.items);

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
                                    {group.items.map((t) => (
                                        <TransactionRow
                                            key={t.id}
                                            transaction={t}
                                            scheduled={
                                                t.date.slice(0, 10) > todayStr
                                            }
                                            onClick={() => setSelected(t)}
                                        />
                                    ))}
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
                        {t.mirrored_from_id && <Tag>Compartilhada</Tag>}
                        {t.total_amount != null && (
                            <Tag>
                                Dividido · {formatCurrency(t.total_amount)}
                            </Tag>
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
                    {isIncome ? '+' : '-'} {formatCurrency(t.amount)}
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
