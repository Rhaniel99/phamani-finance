import { Head, Link, router } from '@inertiajs/react';
import {
    CalendarClock,
    Check,
    FileScan,
    HandCoins,
    Pencil,
    Plus,
    Undo2,
    Users,
} from 'lucide-react';
import { useState } from 'react';
import { CategoryIcon } from '@/components/phamani/category-icon';
import { DashboardHeader } from '@/components/phamani/dashboard/dashboard-header';
import { CreateAccountDrawer } from '@/components/phamani/drawer/create-account-drawer';
import { ShowTransactionDrawer } from '@/components/phamani/drawer/show-transaction-drawer';
import { ImportStatementModal } from '@/components/phamani/modal/import-statement-modal';
import { NewTransactionModal } from '@/components/phamani/modal/new-transaction-modal';
import { Button } from '@/components/phamani/ui/button';
import { formatCurrency, formatDate, formatMonth, today } from '@/lib/format';
import { isThirdParty, receivableSplits } from '@/lib/split';
import { cn } from '@/lib/utils';
import { dashboard } from '@/routes';
import { show as cardShow } from '@/routes/cards';
import { show as importShow } from '@/routes/imports';
import { reconcile } from '@/routes/transactions';
import { pay as payInvoice, undo as undoPayment } from '@/routes/invoices';
import { INVOICE_STATUS_LABELS } from '@/types/phamani';
import type {
    Account,
    Category,
    Invoice,
    InvoiceStatus,
    Transaction,
} from '@/types/phamani';

interface CardPageProps {
    card: Account;
    invoices: Invoice[];
    selectedInvoice: Invoice | null;
    transactions: Transaction[];
    accounts: Account[];
    categories: Category[];
    pendingImports?: {
        id: string;
        status: 'queued' | 'processing' | 'ready' | 'failed';
        progress: number;
        statement_date: string | null;
        created_at: string | null;
    }[];
}

const IMPORT_STATUS: Record<string, string> = {
    queued: 'na fila',
    processing: 'lendo',
    ready: 'esperando sua revisão',
    failed: 'não deu para ler',
};

const STATUS_STYLES: Record<InvoiceStatus, string> = {
    open: 'bg-[#E8DCC4] text-[#6B4E3D]',
    closed: 'bg-[#FCE7E7] text-[#A65D57]',
    paid: 'bg-[#E3F9E5] text-[#1F5428]',
};

export default function CardShow({
    card,
    invoices,
    selectedInvoice,
    transactions,
    accounts,
    categories,
    pendingImports = [],
}: CardPageProps) {
    const [editingCard, setEditingCard] = useState(false);
    const [newPurchaseOpen, setNewPurchaseOpen] = useState(false);
    const [importOpen, setImportOpen] = useState(false);
    const [selected, setSelected] = useState<Transaction | null>(null);
    const [editing, setEditing] = useState<Transaction | null>(null);

    const summary = card.card;
    const limit = summary?.limit ?? null;
    const usedPct =
        limit && limit > 0 && summary
            ? Math.min(100, Math.max(0, (summary.used / limit) * 100))
            : 0;

    function selectInvoice(id: string) {
        router.get(
            cardShow.url(card.id),
            { invoice: id },
            {
                preserveState: true,
                preserveScroll: true,
                replace: true,
                only: ['selectedInvoice', 'transactions'],
            },
        );
    }

    return (
        <>
            <Head title={card.name} />

            <div className="p-6 md:p-8">
                <DashboardHeader
                    title={card.name}
                    subtitle={
                        card.closing_day && card.due_day
                            ? `Cartão de crédito · fecha dia ${card.closing_day} · vence dia ${card.due_day}`
                            : 'Cartão de crédito'
                    }
                    onBack={() => router.visit(dashboard.url())}
                    actions={
                        <div className="flex gap-2">
                            <Button
                                variant="secondary"
                                onClick={() => setEditingCard(true)}
                                className="h-12"
                            >
                                <Pencil className="h-5 w-5 md:mr-2" />
                                <span className="hidden md:inline">
                                    Editar cartão
                                </span>
                            </Button>
                            <Button
                                variant="secondary"
                                onClick={() => setImportOpen(true)}
                                className="h-12"
                                title="Importar extrato (PDF ou print)"
                            >
                                <FileScan className="h-5 w-5 md:mr-2" />
                                <span className="hidden md:inline">
                                    Importar extrato
                                </span>
                            </Button>
                            <Button
                                variant="primary"
                                onClick={() => setNewPurchaseOpen(true)}
                                className="h-12"
                            >
                                <Plus className="h-5 w-5 md:mr-2" />
                                <span className="hidden md:inline">
                                    Nova compra
                                </span>
                            </Button>
                        </div>
                    }
                />

                {pendingImports.length > 0 && (
                    <div className="mb-6 space-y-2">
                        {pendingImports.map((imp) => (
                            <Link
                                key={imp.id}
                                href={importShow.url(imp.id)}
                                className="flex items-center gap-3 rounded-2xl border border-[#E8DCC4] bg-[#FBF7F1] px-4 py-3 text-sm text-[#3D2817] hover:border-[#6B4F3A]"
                            >
                                <FileScan className="h-5 w-5 shrink-0 text-[#6B4E3D]" />
                                <span className="flex-1">
                                    Extrato
                                    {imp.statement_date
                                        ? ` de ${formatDate(imp.statement_date)}`
                                        : ''}
                                    :{' '}
                                    <strong>
                                        {IMPORT_STATUS[imp.status]}
                                        {imp.status === 'processing'
                                            ? ` (${imp.progress}%)`
                                            : ''}
                                    </strong>
                                </span>
                                <span className="font-bold underline">
                                    {imp.status === 'ready'
                                        ? 'Revisar'
                                        : 'Abrir'}
                                </span>
                            </Link>
                        ))}
                    </div>
                )}

                {/* Limite */}
                <div className="mb-8 rounded-3xl border-2 border-[#3D2817] bg-[#E8DCC4] p-6">
                    <div className="mb-4 grid grid-cols-3 gap-4">
                        <Stat
                            label="Limite"
                            value={limit != null ? formatCurrency(limit) : '—'}
                        />
                        <Stat
                            label="Usado"
                            value={formatCurrency(summary?.used ?? 0)}
                        />
                        <Stat
                            label="Disponível"
                            value={
                                summary?.available != null
                                    ? formatCurrency(summary.available)
                                    : '—'
                            }
                            strong
                        />
                    </div>
                    {limit != null && limit > 0 && (
                        <div
                            className="h-3 overflow-hidden rounded-full bg-[#F5EFE6]"
                            role="progressbar"
                            aria-label="Limite usado"
                            aria-valuenow={Math.round(usedPct)}
                            aria-valuemin={0}
                            aria-valuemax={100}
                        >
                            <div
                                className={cn(
                                    'h-full rounded-full',
                                    usedPct > 85
                                        ? 'bg-[#A65D57]'
                                        : 'bg-[#3D2817]',
                                )}
                                style={{ width: `${usedPct}%` }}
                            />
                        </div>
                    )}
                    <p className="mt-3 text-xs text-[#6B4E3D]">
                        O usado inclui parcelas futuras: uma compra em 10x ocupa
                        o valor inteiro do limite e vai sendo liberada a cada
                        fatura paga.
                    </p>
                </div>

                {/* Faturas */}
                {invoices.length === 0 ? (
                    <p className="rounded-2xl border border-dashed border-[#D4C5A9] p-8 text-center text-[#8B7355]">
                        Nenhuma compra neste cartão ainda.
                    </p>
                ) : (
                    <>
                        <div className="mb-6 scrollbar-hide flex gap-2 overflow-x-auto pb-2">
                            {[...invoices].reverse().map((inv) => (
                                <button
                                    key={inv.id}
                                    type="button"
                                    onClick={() => selectInvoice(inv.id)}
                                    className={cn(
                                        'flex shrink-0 flex-col items-start rounded-2xl border px-4 py-2 text-left transition-all',
                                        selectedInvoice?.id === inv.id
                                            ? 'border-[#3D2817] bg-[#3D2817] text-[#F5EFE6]'
                                            : 'border-[#E8DCC4] bg-white text-[#3D2817] hover:border-[#6B4F3A]',
                                    )}
                                >
                                    <span className="text-sm font-bold capitalize">
                                        {formatMonth(inv.reference_month)}
                                    </span>
                                    <span className="text-xs opacity-75">
                                        {formatCurrency(inv.total)} ·{' '}
                                        {INVOICE_STATUS_LABELS[inv.status]}
                                    </span>
                                </button>
                            ))}
                        </div>

                        {selectedInvoice && (
                            <InvoicePanel
                                invoice={selectedInvoice}
                                card={card}
                                accounts={accounts}
                            />
                        )}

                        <InvoicePurchases
                            transactions={transactions}
                            onOpen={setSelected}
                        />
                    </>
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
                    isOpen={newPurchaseOpen}
                    onClose={() => setNewPurchaseOpen(false)}
                    categories={categories}
                    accounts={accounts}
                    defaultAccountId={card.id}
                />

                <ImportStatementModal
                    cardId={card.id}
                    isOpen={importOpen}
                    onClose={() => setImportOpen(false)}
                />

                <CreateAccountDrawer
                    isOpen={editingCard}
                    onClose={() => setEditingCard(false)}
                    accounts={accounts}
                    account={card}
                />
            </div>
        </>
    );
}

function Stat({
    label,
    value,
    strong = false,
}: {
    label: string;
    value: string;
    strong?: boolean;
}) {
    return (
        <div>
            <p className="text-xs font-bold tracking-wider text-[#8B7355] uppercase">
                {label}
            </p>
            <p
                className={cn(
                    'font-bold text-[#3D2817]',
                    strong ? 'text-2xl' : 'text-lg',
                )}
            >
                {value}
            </p>
        </div>
    );
}

function InvoicePanel({
    invoice,
    card,
    accounts,
}: {
    invoice: Invoice;
    card: Account;
    accounts: Account[];
}) {
    const paymentAccounts = accounts.filter((a) => a.type !== 'credit');
    const [accountId, setAccountId] = useState(
        card.payment_account_id ?? paymentAccounts[0]?.id ?? '',
    );
    const [date, setDate] = useState(today());
    const [processing, setProcessing] = useState(false);
    const [error, setError] = useState<string | null>(null);

    const difference =
        invoice.paid_amount != null
            ? Math.round((invoice.total - invoice.paid_amount) * 100) / 100
            : 0;

    function handlePay() {
        router.post(
            payInvoice.url(invoice.id),
            { account_id: accountId, date },
            {
                preserveScroll: true,
                onStart: () => {
                    setProcessing(true);
                    setError(null);
                },
                onFinish: () => setProcessing(false),
                onError: (errors) =>
                    setError(Object.values(errors)[0] ?? 'Erro ao pagar.'),
            },
        );
    }

    function handleUndo() {
        router.delete(undoPayment.url(invoice.id), {
            preserveScroll: true,
            onStart: () => setProcessing(true),
            onFinish: () => setProcessing(false),
        });
    }

    return (
        <div className="rounded-3xl border border-[#E8DCC4] bg-[#FBF7F1] p-6">
            <div className="flex flex-wrap items-start justify-between gap-4">
                <div>
                    <div className="mb-1 flex items-center gap-2">
                        <h3 className="text-xl font-bold text-[#3D2817] capitalize">
                            Fatura de {formatMonth(invoice.reference_month)}
                        </h3>
                        <span
                            className={cn(
                                'rounded-md px-2 py-0.5 text-[10px] font-bold tracking-wide uppercase',
                                STATUS_STYLES[invoice.status],
                            )}
                        >
                            {INVOICE_STATUS_LABELS[invoice.status]}
                        </span>
                    </div>
                    <p className="flex items-center gap-1 text-sm text-[#6B4E3D]">
                        <CalendarClock className="h-4 w-4" />
                        Fecha {formatDate(invoice.closing_date)} · vence{' '}
                        {formatDate(invoice.due_date)}
                    </p>
                </div>
                <div className="text-right">
                    <p className="text-xs font-bold tracking-wider text-[#8B7355] uppercase">
                        Total
                    </p>
                    <p className="text-3xl font-bold text-[#3D2817]">
                        {formatCurrency(invoice.total)}
                    </p>
                </div>
            </div>

            <div className="mt-6 border-t border-[#E8DCC4] pt-6">
                {invoice.status === 'paid' ? (
                    <div className="flex flex-wrap items-center justify-between gap-4">
                        <div className="text-sm text-[#3D2817]">
                            <p>
                                Paga em {formatDate(invoice.paid_at)} ·{' '}
                                {formatCurrency(invoice.paid_amount)}
                                {(() => {
                                    const from = accounts.find(
                                        (a) =>
                                            a.id ===
                                            invoice.paid_from_account_id,
                                    );
                                    return from ? ` · ${from.name}` : '';
                                })()}
                            </p>
                            {difference !== 0 && (
                                <p className="mt-1 text-xs text-[#A65D57]">
                                    Diferença de {formatCurrency(difference)} em
                                    compras lançadas depois do pagamento.
                                </p>
                            )}
                        </div>
                        <button
                            type="button"
                            onClick={handleUndo}
                            disabled={processing}
                            className="flex items-center gap-2 rounded-xl border-2 border-[#D4C5A9] px-4 py-2 text-sm font-medium text-[#6B4E3D] hover:bg-[#E8DCC4] disabled:opacity-50"
                        >
                            <Undo2 className="h-4 w-4" />
                            Desfazer pagamento
                        </button>
                    </div>
                ) : invoice.total > 0 ? (
                    <div className="space-y-3">
                        <div className="grid gap-3 md:grid-cols-[1fr_auto_auto]">
                            <label className="sr-only" htmlFor="pay-account">
                                Pagar com
                            </label>
                            <select
                                id="pay-account"
                                value={accountId}
                                onChange={(e) => setAccountId(e.target.value)}
                                className="rounded-xl border-2 border-[#E8DCC4] bg-white px-4 py-3 text-[#3D2817]"
                            >
                                {paymentAccounts.map((a) => (
                                    <option key={a.id} value={a.id}>
                                        Pagar com {a.name} (
                                        {formatCurrency(a.balance)})
                                    </option>
                                ))}
                            </select>
                            <label className="sr-only" htmlFor="pay-date">
                                Data do pagamento
                            </label>
                            <input
                                id="pay-date"
                                type="date"
                                value={date}
                                max={today()}
                                onChange={(e) => setDate(e.target.value)}
                                className="rounded-xl border-2 border-[#E8DCC4] bg-white px-4 py-3 text-[#3D2817]"
                            />
                            <button
                                type="button"
                                onClick={handlePay}
                                disabled={processing || !accountId}
                                className="rounded-xl bg-[#3D2817] px-6 py-3 font-medium text-[#F5EFE6] shadow-lg hover:bg-[#543924] disabled:opacity-50"
                            >
                                {processing
                                    ? 'Pagando...'
                                    : `Pagar ${formatCurrency(invoice.total)}`}
                            </button>
                        </div>
                        {error && (
                            <p className="text-xs text-[#D4183D]">{error}</p>
                        )}
                        <p className="text-xs text-[#8B7355]">
                            O valor sai da conta escolhida e libera o limite.
                            Não conta como despesa: as compras já foram contadas
                            uma a uma.
                        </p>
                    </div>
                ) : (
                    <p className="text-sm text-[#8B7355]">
                        Nada a pagar nesta fatura.
                    </p>
                )}
            </div>
        </div>
    );
}

/** Valor que entrou na fatura (numa divisão, o valor cheio; a sua parte vem embaixo). */
function chargedAmount(t: Transaction): number {
    return Number(t.total_amount ?? t.amount);
}

/**
 * Quanto da fatura é de cada pessoa (as partes das divisões; o resto é seu).
 * É a conta que se faz para saber quanto cada um precisa passar no acerto.
 */
function byPerson(
    transactions: Transaction[],
): Array<{ key: string; name: string; amount: number }> {
    const totals = new Map<string, { name: string; amount: number }>();
    const add = (key: string, name: string, value: number) => {
        const current = totals.get(key) ?? { name, amount: 0 };
        totals.set(key, { name, amount: current.amount + value });
    };

    for (const t of transactions) {
        const sign = t.type === 'income' ? -1 : 1;
        if (t.splits && t.splits.length > 0 && t.total_amount != null) {
            for (const s of t.splits) {
                add(
                    s.contact_id ?? 'me',
                    s.contact_id ? (s.contact?.name ?? '—') : 'Você',
                    sign * Number(s.amount),
                );
            }
        } else {
            add('me', 'Você', sign * chargedAmount(t));
        }
    }

    return [...totals.entries()]
        .map(([key, v]) => ({ key, ...v }))
        .filter((p) => Math.abs(p.amount) >= 0.01)
        .sort((a, b) =>
            a.key === 'me' ? -1 : b.key === 'me' ? 1 : b.amount - a.amount,
        );
}

/**
 * Compras da fatura, com "conferido" (para bater com a fatura do banco)
 * e um aviso discreto quando a compra é dividida ou de outra pessoa.
 */
function InvoicePurchases({
    transactions,
    onOpen,
}: {
    transactions: Transaction[];
    onOpen: (t: Transaction) => void;
}) {
    const [busy, setBusy] = useState<string | null>(null);

    const checked = transactions.filter((t) => !!t.reconciled_at);
    const checkedTotal = checked.reduce((sum, t) => sum + chargedAmount(t), 0);
    const total = transactions.reduce((sum, t) => sum + chargedAmount(t), 0);
    const people = byPerson(transactions);

    function toggle(t: Transaction) {
        router.post(
            reconcile.url(t.id),
            {},
            {
                preserveScroll: true,
                preserveState: true,
                only: ['transactions'],
                onStart: () => setBusy(t.id),
                onFinish: () => setBusy(null),
            },
        );
    }

    return (
        <div className="mt-6 overflow-hidden rounded-3xl border border-[#E8DCC4] bg-white shadow-sm">
            {transactions.length === 0 ? (
                <p className="px-6 py-12 text-center text-[#8B7355]">
                    Nenhuma compra nesta fatura.
                </p>
            ) : (
                <div className="flex flex-wrap items-center justify-between gap-2 border-b border-[#E8DCC4] bg-[#FBF7F1] px-6 py-3 text-xs text-[#6B4E3D]">
                    <span>
                        <strong className="text-[#3D2817]">
                            {checked.length} de {transactions.length}
                        </strong>{' '}
                        conferidas
                    </span>
                    <span>
                        {formatCurrency(checkedTotal)} de{' '}
                        {formatCurrency(total)}
                    </span>
                </div>
            )}
            {people.length > 1 && (
                <div className="flex flex-wrap items-center gap-x-3 gap-y-1 border-b border-[#E8DCC4] px-6 py-3 text-xs text-[#6B4E3D]">
                    <span className="flex items-center gap-1 font-bold tracking-wide text-[#8B7355] uppercase">
                        <Users className="h-3.5 w-3.5" /> Por pessoa
                    </span>
                    {people.map((p) => (
                        <span key={p.key}>
                            {p.name}{' '}
                            <strong className="text-[#3D2817]">
                                {formatCurrency(p.amount)}
                            </strong>
                        </span>
                    ))}
                </div>
            )}

            <ul className="divide-y divide-[#E8DCC4]">
                {transactions.map((t) => {
                    const isChecked = !!t.reconciled_at;
                    const forOthers = isThirdParty(t);
                    const split = !forOthers && t.total_amount != null;

                    return (
                        <li
                            key={t.id}
                            className={cn(
                                'flex items-center gap-1 pl-3 transition-colors',
                                isChecked && 'bg-[#F7FBF7]',
                            )}
                        >
                            <button
                                type="button"
                                role="checkbox"
                                aria-checked={isChecked}
                                aria-label={
                                    isChecked
                                        ? `Desmarcar ${t.name} como conferida`
                                        : `Marcar ${t.name} como conferida`
                                }
                                title={isChecked ? 'Conferida' : 'Conferir'}
                                disabled={busy === t.id}
                                onClick={() => toggle(t)}
                                className={cn(
                                    'flex h-6 w-6 shrink-0 items-center justify-center rounded-md border-2 transition-colors disabled:opacity-50',
                                    isChecked
                                        ? 'border-[#1F5428] bg-[#1F5428] text-white'
                                        : 'border-[#D4C5A9] bg-white hover:border-[#6B4E3D]',
                                )}
                            >
                                {isChecked && <Check className="h-4 w-4" />}
                            </button>

                            <button
                                type="button"
                                onClick={() => onOpen(t)}
                                className="flex min-w-0 flex-1 items-center justify-between gap-4 py-4 pr-6 pl-2 text-left hover:bg-[#F5EFE6]/60"
                            >
                                <div className="flex min-w-0 items-center gap-3">
                                    <CategoryIcon
                                        category={t.category}
                                        className="h-10 w-10 shrink-0 rounded-xl"
                                        iconClassName="h-5 w-5"
                                    />
                                    <div className="min-w-0">
                                        <p
                                            className={cn(
                                                'truncate font-bold',
                                                isChecked
                                                    ? 'text-[#6B4E3D]'
                                                    : 'text-[#3D2817]',
                                            )}
                                        >
                                            {t.name}
                                        </p>
                                        <p className="flex flex-wrap items-center gap-x-1.5 text-xs text-[#8B7355]">
                                            <span>
                                                {formatDate(t.date)} ·{' '}
                                                {t.category?.name}
                                            </span>
                                            {split && (
                                                <span
                                                    className="inline-flex items-center gap-1 text-[#6B4E3D]"
                                                    title="Compra dividida: o valor ao lado é o cheio (o da fatura)"
                                                >
                                                    ·
                                                    <Users className="h-3 w-3" />
                                                    sua parte{' '}
                                                    {formatCurrency(t.amount)}
                                                </span>
                                            )}
                                            {forOthers && (
                                                <span
                                                    className="inline-flex items-center gap-1 text-[#A65D57]"
                                                    title="Compra para outra pessoa: não entra nas suas despesas"
                                                >
                                                    ·
                                                    <HandCoins className="h-3 w-3" />
                                                    para{' '}
                                                    {receivableSplits(t)
                                                        .map(
                                                            (x) =>
                                                                x.contact?.name,
                                                        )
                                                        .filter(Boolean)
                                                        .join(', ')}
                                                </span>
                                            )}
                                        </p>
                                    </div>
                                </div>
                                <span
                                    className={cn(
                                        'shrink-0 text-sm font-bold',
                                        t.type === 'income'
                                            ? 'text-[#1F5428]'
                                            : 'text-[#3D2817]',
                                    )}
                                >
                                    {t.type === 'income' ? '+' : '-'}{' '}
                                    {formatCurrency(chargedAmount(t))}
                                </span>
                            </button>
                        </li>
                    );
                })}
            </ul>
        </div>
    );
}
