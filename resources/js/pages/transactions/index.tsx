import { Head, router } from '@inertiajs/react';
import {
    ArrowDownRight,
    ArrowUpRight,
    ChevronDown,
    ChevronLeft,
    ChevronRight,
    Plus,
    X,
} from 'lucide-react';
import { useState } from 'react';
import { CategoryIcon } from '@/components/phamani/category-icon';
import { DashboardHeader } from '@/components/phamani/dashboard/dashboard-header';
import { ShowTransactionDrawer } from '@/components/phamani/drawer/show-transaction-drawer';
import { NewTransactionModal } from '@/components/phamani/modal/new-transaction-modal';
import { Button } from '@/components/phamani/ui/button';
import {
    DropdownMenu,
    DropdownMenuContent,
    DropdownMenuItem,
    DropdownMenuSeparator,
    DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { formatCurrency, formatDate } from '@/lib/format';
import { cn } from '@/lib/utils';
import { dashboard } from '@/routes';
import { index as transactionsIndex } from '@/routes/transactions';
import type {
    Account,
    Category,
    Paginated,
    Transaction,
    TransactionFilters,
} from '@/types/phamani';

interface TransactionsPageProps {
    transactions: Paginated<Transaction>;
    filters: TransactionFilters;
    accounts: Account[];
    categories: Category[];
}

/** Últimos 12 meses no formato YYYY-MM. */
function lastMonths(count = 12) {
    const now = new Date();

    return Array.from({ length: count }, (_, i) => {
        const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
        const value = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
        const label = d.toLocaleDateString('pt-BR', {
            month: 'long',
            year: 'numeric',
        });

        return { value, label: label.charAt(0).toUpperCase() + label.slice(1) };
    });
}

export default function TransactionsIndex({
    transactions,
    filters,
    accounts,
    categories,
}: TransactionsPageProps) {
    const [selected, setSelected] = useState<Transaction | null>(null);
    const [isNewTransactionOpen, setIsNewTransactionOpen] = useState(false);
    const [editing, setEditing] = useState<Transaction | null>(null);

    const months = lastMonths();

    function applyFilter(key: keyof TransactionFilters, value?: string) {
        const next = { ...filters, [key]: value };

        Object.keys(next).forEach((k) => {
            if (!next[k as keyof TransactionFilters])
                delete next[k as keyof TransactionFilters];
        });

        router.get(transactionsIndex.url(), next, {
            preserveState: true,
            preserveScroll: true,
            replace: true,
            only: ['transactions', 'filters'],
        });
    }

    function goTo(url: string | null) {
        if (url)
            router.get(
                url,
                {},
                { preserveState: true, only: ['transactions', 'filters'] },
            );
    }

    const hasFilters = Object.keys(filters).length > 0;

    return (
        <>
            <Head title="Transações" />

            <div className="p-6 md:p-8">
                <DashboardHeader
                    title="Transações"
                    subtitle="Histórico completo"
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

                {/* Filtros */}
                <div className="sticky top-0 z-10 -mx-6 bg-[#F5EFE6]/95 px-6 py-4 backdrop-blur-sm md:-mx-8 md:px-8">
                    <div className="scrollbar-hide flex h-12 items-center gap-2 overflow-x-auto pb-2">
                        <FilterPill
                            label={
                                accounts.find(
                                    (a) => a.id === filters.account_id,
                                )?.name ?? 'Todas as Contas'
                            }
                            active={!!filters.account_id}
                            options={accounts.map((a) => ({
                                value: a.id,
                                label: a.name,
                            }))}
                            allLabel="Todas as Contas"
                            onSelect={(v) => applyFilter('account_id', v)}
                        />
                        <FilterPill
                            label={
                                categories.find(
                                    (c) => c.id === filters.category_id,
                                )?.name ?? 'Todas as Categorias'
                            }
                            active={!!filters.category_id}
                            options={categories.map((c) => ({
                                value: c.id,
                                label: c.name,
                            }))}
                            allLabel="Todas as Categorias"
                            onSelect={(v) => applyFilter('category_id', v)}
                        />
                        <FilterPill
                            label={
                                filters.type === 'income'
                                    ? 'Receitas'
                                    : filters.type === 'expense'
                                      ? 'Despesas'
                                      : 'Receitas e Despesas'
                            }
                            active={!!filters.type}
                            options={[
                                { value: 'income', label: 'Receitas' },
                                { value: 'expense', label: 'Despesas' },
                            ]}
                            allLabel="Receitas e Despesas"
                            onSelect={(v) => applyFilter('type', v)}
                        />
                        <FilterPill
                            label={
                                months.find((m) => m.value === filters.month)
                                    ?.label ?? 'Todo o período'
                            }
                            active={!!filters.month}
                            options={months}
                            allLabel="Todo o período"
                            onSelect={(v) => applyFilter('month', v)}
                        />

                        {hasFilters && (
                            <button
                                type="button"
                                onClick={() =>
                                    router.get(
                                        transactionsIndex.url(),
                                        {},
                                        { preserveState: true, replace: true },
                                    )
                                }
                                className="flex items-center gap-1 px-3 py-2 text-sm whitespace-nowrap text-[#8B7355] hover:text-[#3D2817]"
                            >
                                <X className="h-4 w-4" /> Limpar
                            </button>
                        )}
                    </div>
                </div>

                {/* Tabela */}
                <div className="overflow-hidden rounded-3xl border border-[#E8DCC4] bg-white shadow-sm">
                    <table className="w-full">
                        <thead>
                            <tr className="border-b border-[#E8DCC4] bg-[#FBF7F1]">
                                <Th className="w-16">Tipo</Th>
                                <Th>Descrição</Th>
                                <Th className="hidden md:table-cell">
                                    Categoria
                                </Th>
                                <Th className="hidden sm:table-cell">Conta</Th>
                                <Th className="text-right">Valor</Th>
                                <Th className="hidden text-right sm:table-cell">
                                    Data
                                </Th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-[#E8DCC4]">
                            {transactions.data.length === 0 && (
                                <tr>
                                    <td
                                        colSpan={6}
                                        className="px-6 py-16 text-center text-[#8B7355]"
                                    >
                                        Nenhuma transação encontrada.
                                    </td>
                                </tr>
                            )}

                            {transactions.data.map((t, index) => (
                                <tr
                                    key={t.id}
                                    onClick={() => setSelected(t)}
                                    className={cn(
                                        'group cursor-pointer transition-colors hover:bg-[#F5EFE6]',
                                        index % 2 === 0
                                            ? 'bg-white'
                                            : 'bg-[#FBF7F1]',
                                    )}
                                >
                                    <td className="px-6 py-4">
                                        <div
                                            className={cn(
                                                'flex h-10 w-10 items-center justify-center rounded-xl',
                                                t.type === 'income'
                                                    ? 'bg-[#E3F9E5] text-[#1F5428]'
                                                    : 'bg-[#FCE7E7] text-[#D4183D]',
                                            )}
                                        >
                                            {t.type === 'income' ? (
                                                <ArrowDownRight className="h-5 w-5" />
                                            ) : (
                                                <ArrowUpRight className="h-5 w-5" />
                                            )}
                                        </div>
                                    </td>
                                    <td className="px-6 py-4">
                                        <p className="font-bold text-[#3D2817] transition-colors group-hover:text-[#6B4F3A]">
                                            {t.name}
                                        </p>
                                        <div className="mt-1 flex gap-1">
                                            {t.installment_number &&
                                                t.installment && (
                                                    <Tag>
                                                        {t.installment_number}/
                                                        {
                                                            t.installment
                                                                .installments
                                                        }
                                                    </Tag>
                                                )}
                                            {t.recurring && (
                                                <Tag>Recorrente</Tag>
                                            )}
                                        </div>
                                    </td>
                                    <td className="hidden px-6 py-4 md:table-cell">
                                        <span className="inline-flex items-center gap-2 rounded-full border border-[#E8DCC4] bg-[#FBF7F1] py-1 pr-3 pl-1 text-xs font-medium text-[#6B4F3A]">
                                            <CategoryIcon
                                                category={t.category}
                                                className="h-5 w-5 rounded-full"
                                                iconClassName="h-3 w-3"
                                            />
                                            {t.category?.name}
                                        </span>
                                    </td>
                                    <td className="hidden px-6 py-4 sm:table-cell">
                                        <div className="flex items-center gap-2">
                                            <div className="flex h-6 w-6 items-center justify-center rounded-full bg-[#3D2817] text-[10px] text-[#F5EFE6]">
                                                {t.account?.name.charAt(0)}
                                            </div>
                                            <span className="text-sm text-[#3D2817]">
                                                {t.account?.name}
                                            </span>
                                        </div>
                                    </td>
                                    <td className="px-6 py-4 text-right">
                                        <span
                                            className={cn(
                                                'text-sm font-bold',
                                                t.type === 'income'
                                                    ? 'text-[#1F5428]'
                                                    : 'text-[#3D2817]',
                                            )}
                                        >
                                            {t.type === 'income' ? '+' : '-'}{' '}
                                            {formatCurrency(t.amount)}
                                        </span>
                                    </td>
                                    <td className="hidden px-6 py-4 text-right sm:table-cell">
                                        <span className="text-sm text-[#8B7355]">
                                            {formatDate(t.date)}
                                        </span>
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>

                {/* Paginação */}
                {transactions.last_page > 1 && (
                    <div className="mt-6 flex items-center justify-between text-sm text-[#8B7355]">
                        <span>
                            {transactions.from}–{transactions.to} de{' '}
                            {transactions.total}
                        </span>
                        <div className="flex gap-2">
                            <PageButton
                                disabled={!transactions.prev_page_url}
                                onClick={() => goTo(transactions.prev_page_url)}
                                label="Anterior"
                            >
                                <ChevronLeft className="h-4 w-4" />
                            </PageButton>
                            <span className="flex items-center px-2">
                                {transactions.current_page} /{' '}
                                {transactions.last_page}
                            </span>
                            <PageButton
                                disabled={!transactions.next_page_url}
                                onClick={() => goTo(transactions.next_page_url)}
                                label="Próxima"
                            >
                                <ChevronRight className="h-4 w-4" />
                            </PageButton>
                        </div>
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

function Th({
    children,
    className,
}: {
    children: React.ReactNode;
    className?: string;
}) {
    return (
        <th
            className={cn(
                'px-6 py-4 text-left text-xs font-bold tracking-wider text-[#8B7355] uppercase',
                className,
            )}
        >
            {children}
        </th>
    );
}

function Tag({ children }: { children: React.ReactNode }) {
    return (
        <span className="inline-flex items-center rounded-md bg-[#E8DCC4] px-2 py-0.5 text-[10px] font-bold tracking-wide text-[#6B4E3D] uppercase">
            {children}
        </span>
    );
}

function PageButton({
    disabled,
    onClick,
    label,
    children,
}: {
    disabled: boolean;
    onClick: () => void;
    label: string;
    children: React.ReactNode;
}) {
    return (
        <button
            type="button"
            aria-label={label}
            disabled={disabled}
            onClick={onClick}
            className="rounded-xl border border-[#E8DCC4] bg-white p-2 text-[#3D2817] transition-colors hover:border-[#6B4F3A] disabled:opacity-40"
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
                        'flex items-center gap-2 rounded-2xl border px-4 py-2 text-sm font-medium whitespace-nowrap shadow-sm transition-all hover:-translate-y-0.5 hover:border-[#6B4F3A]',
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
